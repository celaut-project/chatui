import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:argus_wallet/celaut/chat/gen/chat.pbgrpc.dart';
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/sha3.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';

/// The `chat-reason` trailer of `docs/celaut/chat.md`, section 9.
GrpcError chatError(int code, String reason, [String message = 'error']) =>
    GrpcError.custom(code, message, null, null, {'chat-reason': reason});

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A chat service in memory that follows `docs/celaut/chat.md` (revision 6), with switches
/// to break it. It serves `ChatService` and `FileService` of `chat.proto` over h2c.
class FakeChatService {
  Capabilities caps = Capabilities(acceptedMimeTypes: ['image/jpeg', 'image/png', 'audio/wav']);

  final msgs = <Message>[];
  int _clock = 1000;

  /// What the service got.
  final unarySends = <SendMessageRequest>[];
  final streamEvents = <ClientEvent>[];
  final reads = <int>[];
  final subscribes = <int>[];
  int capabilityCalls = 0;
  int connects = 0;
  int pinCalls = 0;

  /// The next calls to `SetMessagePinned` fail with these errors, in order.
  final pinErrors = <GrpcError>[];

  /// Each user message gets a whole answer `echo: <text>` at once.
  bool autoAnswer = false;

  /// The most messages in the answer to one read, or null for all.
  int? readLimit;

  /// The next calls to `SendMessage` fail with these errors, in order, and add nothing.
  final sendErrors = <GrpcError>[];

  /// The next call to `SendMessage` adds the message and then fails with this error.
  GrpcError? failAfterApply;

  /// The next `Connect` calls end with this status.
  GrpcError? connectError;

  /// Runs when a `send_message` event came over `Connect` and the message was added.
  void Function()? onStreamSend;

  /// `GetMessages` gives a gap: the first message has this `sequence` plus one.
  bool gapInReads = false;

  /// A `SendMessage` of this kind fails with `file_missing` while the file is not uploaded.
  bool requireFiles = true;
  int fileMissingTimes = 0;

  final files = <String, Uint8List>{};
  final uploads = <FileReference>[];
  final queries = <List<String>>[];
  final chunkSizes = <int>[];
  int downloads = 0;

  /// [DownloadFile] gives these bytes instead of the file.
  Uint8List? downloadOverride;
  GrpcError? uploadError;

  final _streams = <StreamController<ServerEvent>>[];

  Message user(String text, {String? key, List<ContentPart> extra = const []}) {
    final m = Message(
      messageId: 'm${msgs.length + 1}',
      sequence: Int64(msgs.length + 1),
      content: [if (text.isNotEmpty) ContentPart(text: TextContent(text: text)), ...extra],
      status: MessageStatus.MESSAGE_STATUS_COMPLETED,
      createdAt: Int64(_clock),
      updatedAt: Int64(_clock++),
      idempotencyKey: key,
    );
    msgs.add(m);
    return m;
  }

  Message assistant(
    String text, {
    String? replyTo,
    MessageStatus status = MessageStatus.MESSAGE_STATUS_COMPLETED,
    String reasoning = '',
    bool pinned = false,
  }) {
    final m = Message(
      messageId: 'm${msgs.length + 1}',
      sequence: Int64(msgs.length + 1),
      content: [if (text.isNotEmpty) ContentPart(text: TextContent(text: text))],
      status: status,
      createdAt: Int64(_clock),
      updatedAt: Int64(_clock++),
      fromService: true,
      reasoning: reasoning,
      pinned: pinned,
      replyToMessageId: replyTo,
    );
    msgs.add(m);
    return m;
  }

  Message byId(String id) => msgs.firstWhere((m) => m.messageId == id);

  void emit(ServerEvent e) {
    for (final s in List.of(_streams)) {
      s.add(e);
    }
  }

  void emitCreated(Message m) => emit(ServerEvent(messageCreated: MessageCreated(message: m)));

  void emitDelta(String id, {String text = '', String reasoning = ''}) {
    final m = byId(id);
    if (text.isNotEmpty) {
      if (m.content.isNotEmpty && m.content.last.hasText()) {
        m.content.last.text.text += text;
      } else {
        m.content.add(ContentPart(text: TextContent(text: text)));
      }
    }
    m.reasoning += reasoning;
    emit(ServerEvent(
      messageDelta: MessageDelta(messageId: id, textAppend: text, reasoningAppend: reasoning),
    ));
  }

  void setStatus(String id, MessageStatus status) {
    final m = byId(id)
      ..status = status
      ..updatedAt = Int64(_clock++);
    emit(ServerEvent(
      messageStatusChanged:
          MessageStatusChanged(messageId: id, status: status, updatedAt: m.updatedAt),
    ));
  }

  void setPinned(String id, bool pinned) {
    final m = byId(id);
    if (m.pinned == pinned) return;
    m
      ..pinned = pinned
      ..updatedAt = Int64(_clock++);
    emit(ServerEvent(
      messagePinnedChanged:
          MessagePinnedChanged(messageId: id, pinned: pinned, updatedAt: m.updatedAt),
    ));
  }

  /// The number of streams that are open.
  int get openStreams => _streams.length;

  String? _text(SendMessageRequest r) =>
      r.content.where((p) => p.hasText()).map((p) => p.text.text).join();

  /// The checks of section 6.1 that the fake does. The reason, or null.
  String? check(SendMessageRequest r) {
    final text = _text(r);
    if (text == 'bad') return 'bad_request';
    if (text == 'busy') return 'busy';
    if (text == 'full') return 'history_full';
    if (text == 'media') return 'unsupported_media';
    if (requireFiles) {
      for (final p in r.content) {
        final f = p.hasImage() ? p.image.file : p.hasAudio() ? p.audio.file : null;
        if (f != null && !files.containsKey(hex(f.hashes.first.value))) return 'file_missing';
      }
    }
    return null;
  }

  static GrpcError errorFor(String reason) => switch (reason) {
        'busy' => chatError(StatusCode.unavailable, reason),
        'history_full' => chatError(StatusCode.resourceExhausted, reason),
        'file_missing' => chatError(StatusCode.failedPrecondition, reason),
        'unsupported_media' => chatError(StatusCode.invalidArgument, reason),
        _ => chatError(StatusCode.invalidArgument, reason),
      };

  Message _accept(SendMessageRequest r) {
    if (r.hasIdempotencyKey()) {
      for (final m in msgs) {
        if (m.hasIdempotencyKey() && m.idempotencyKey == r.idempotencyKey) return m;
      }
    }
    final m = user('', key: r.hasIdempotencyKey() ? r.idempotencyKey : null)
      ..content.addAll(r.content);
    emitCreated(m);
    if (autoAnswer) {
      final a = assistant('echo: ${_text(r)}', replyTo: m.messageId);
      emitCreated(a);
    }
    return m;
  }

  late final ChatServiceBase chat = _Chat(this);
  late final FileServiceBase file = _Files(this);

  Server? server;
  Future<int> start([int port = 0]) async {
    server = Server.create(services: [chat, file]);
    await server!.serve(address: InternetAddress.loopbackIPv4, port: port);
    return server!.port!;
  }

  Future<void> stop() async {
    for (final s in List.of(_streams)) {
      unawaited(s.close());
    }
    // A handler of a call that the client cancelled can stay open: do not wait for it.
    await server?.shutdown().timeout(const Duration(seconds: 2), onTimeout: () {});
    server = null;
  }
}

class _Chat extends ChatServiceBase {
  _Chat(this.f);
  final FakeChatService f;

  @override
  Future<Capabilities> getCapabilities(ServiceCall call, GetCapabilitiesRequest request) async {
    f.capabilityCalls++;
    return f.caps;
  }

  @override
  Future<Message> sendMessage(ServiceCall call, SendMessageRequest request) async {
    f.unarySends.add(request);
    if (f.sendErrors.isNotEmpty) throw f.sendErrors.removeAt(0);
    if (f.fileMissingTimes > 0) {
      f.fileMissingTimes--;
      throw FakeChatService.errorFor('file_missing');
    }
    final reason = f.check(request);
    if (reason != null) throw FakeChatService.errorFor(reason);
    final m = f._accept(request);
    final fail = f.failAfterApply;
    if (fail != null) {
      f.failAfterApply = null;
      throw fail;
    }
    return m;
  }

  @override
  Stream<Message> getMessages(ServiceCall call, GetMessagesRequest request) async* {
    final after = request.afterSequence.toInt();
    f.reads.add(after);
    if (after > f.msgs.length) throw FakeChatService.errorFor('bad_request');
    var list = f.msgs.skip(after).toList();
    final limit = f.readLimit;
    if (limit != null && list.length > limit) list = list.take(limit).toList();
    for (final m in list) {
      if (f.gapInReads) {
        yield m.deepCopy()..sequence = m.sequence + 1;
      } else {
        yield m.deepCopy();
      }
    }
  }

  @override
  Stream<ServerEvent> connect(ServiceCall call, Stream<ClientEvent> request) async* {
    f.connects++;
    final error = f.connectError;
    if (error != null) throw error;
    final out = StreamController<ServerEvent>();
    final seen = <String>{};
    var subscribed = false;
    request.listen(
      (e) {
        f.streamEvents.add(e);
        if (e.hasEventId() && !seen.add(e.eventId)) {
          out.add(ServerEvent(
            error: ProtocolError(code: 'bad_request', message: 'event_id', eventId: e.eventId),
          ));
          return;
        }
        if (e.hasSubscribe()) {
          if (subscribed) return;
          subscribed = true;
          final after = e.subscribe.afterSequence.toInt();
          f.subscribes.add(after);
          for (final m in f.msgs.skip(after)) {
            out.add(ServerEvent(messageCreated: MessageCreated(message: m.deepCopy())));
          }
          out.add(ServerEvent(
            subscriptionReady: SubscriptionReady(latestSequence: Int64(f.msgs.length)),
          ));
          f._streams.add(out);
        } else if (e.hasSendMessage()) {
          final reason = f.check(e.sendMessage);
          if (reason != null) {
            out.add(ServerEvent(
              error: ProtocolError(code: reason, message: 'no', eventId: e.eventId),
            ));
            return;
          }
          f._accept(e.sendMessage);
          f.onStreamSend?.call();
        } else if (e.hasAcknowledge()) {
          if (e.acknowledge.lastSequence.toInt() > f.msgs.length) {
            out.add(ServerEvent(
              error: ProtocolError(code: 'bad_request', message: 'ack', eventId: e.eventId),
            ));
          }
        }
      },
      onDone: out.close,
      onError: (_) {},
    );
    try {
      yield* out.stream;
    } finally {
      f._streams.remove(out);
    }
  }

  @override
  Future<Conversation> forkConversation(ServiceCall call, ForkConversationRequest request) =>
      throw GrpcError.unimplemented();

  @override
  Future<Conversation> getConversation(ServiceCall call, GetConversationRequest request) async =>
      Conversation();

  @override
  Future<Message> setMessagePinned(ServiceCall call, SetMessagePinnedRequest request) async {
    f.pinCalls++;
    if (f.pinErrors.isNotEmpty) throw f.pinErrors.removeAt(0);
    final m = f.msgs.where((m) => m.messageId == request.messageId).firstOrNull;
    if (m == null) throw chatError(StatusCode.notFound, 'not_found');
    f.setPinned(m.messageId, request.pinned);
    return m.deepCopy();
  }
}

class _Files extends FileServiceBase {
  _Files(this.f);
  final FakeChatService f;

  @override
  Stream<QueryFilesResponse> queryFiles(ServiceCall call, Stream<QueryFilesRequest> request) async* {
    final asked = <String>[];
    await for (final r in request) {
      final h = hex(r.hash.value);
      asked.add(h);
      yield QueryFilesResponse(hash: r.hash, available: f.files.containsKey(h));
    }
    f.queries.add(asked);
  }

  @override
  Future<UploadFileResponse> uploadFile(ServiceCall call, Stream<UploadFileRequest> request) async {
    final error = f.uploadError;
    if (error != null) throw error;
    FileReference? ref;
    final data = BytesBuilder();
    await for (final r in request) {
      if (r.hasFile()) {
        ref = r.file;
      } else {
        f.chunkSizes.add(r.chunk.length);
        data.add(r.chunk);
      }
    }
    if (ref == null) throw chatError(StatusCode.invalidArgument, 'bad_request');
    final bytes = data.takeBytes();
    final digest = sha3_256(bytes);
    if (hex(digest) != hex(ref.hashes.first.value) || bytes.length != ref.sizeBytes.toInt()) {
      throw chatError(StatusCode.invalidArgument, 'hash_mismatch');
    }
    f.files[hex(digest)] = bytes;
    f.uploads.add(ref);
    return UploadFileResponse(file: ref);
  }

  @override
  Stream<DownloadFileResponse> downloadFile(
    ServiceCall call,
    DownloadFileRequest request,
  ) async* {
    f.downloads++;
    final bytes = f.downloadOverride ?? f.files[hex(request.hash.value)];
    if (bytes == null) throw chatError(StatusCode.notFound, 'not_found');
    for (var i = 0; i < bytes.length; i += ChatClient.chunkBytes) {
      yield DownloadFileResponse(
        chunk: Uint8List.sublistView(bytes, i, (i + ChatClient.chunkBytes).clamp(0, bytes.length)),
      );
    }
  }
}

/// A TCP forwarder like the tunnel: it counts the connections and it can drop them all.
class TcpProxy {
  TcpProxy(this.targetPort);

  final int targetPort;
  late ServerSocket _listen;
  final _sockets = <Socket>[];
  int connections = 0;
  int get port => _listen.port;

  Future<void> start() async {
    _listen = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _listen.listen((client) async {
      connections++;
      final Socket up;
      try {
        up = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
      } on Object {
        client.destroy();
        return;
      }
      _sockets
        ..add(client)
        ..add(up);
      client.listen(up.add, onDone: () => up.destroy(), onError: (_) => up.destroy());
      up.listen(client.add, onDone: () => client.destroy(), onError: (_) => client.destroy());
    });
  }

  void drop() {
    for (final s in _sockets) {
      s.destroy();
    }
    _sockets.clear();
  }

  Future<void> stop() async {
    drop();
    await _listen.close();
  }
}
