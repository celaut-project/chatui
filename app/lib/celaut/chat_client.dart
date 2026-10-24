import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'tunnel_http.dart';

/// The description of one file of a message (`docs/celaut/chat.md`, section 5.1). The
/// bytes are not here: [ChatClient.readAttachment] reads them.
class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.mime,
    required this.size,
    this.name,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final mime = json['mime'];
    final size = json['size'];
    final name = json['name'];
    if (kind is! String ||
        !attachmentKinds.contains(kind) ||
        mime is! String ||
        size is! int ||
        size < 0 ||
        (name != null && name is! String)) {
      throw const ChatException(ChatErrorKind.badAnswer);
    }
    return ChatAttachment(
      kind: kind,
      mime: mime,
      size: size,
      name: name as String?,
    );
  }

  /// The kinds of attachment that the convention defines.
  static const attachmentKinds = {'image', 'audio'};

  /// `image` or `audio`.
  final String kind;
  final String mime;
  final int size;
  final String? name;

  bool get isImage => kind == 'image';
  bool get isAudio => kind == 'audio';

  /// [name] as a safe name for a file on this device, or null. The name comes from the
  /// service: only its last path segment stays, without control characters or `..`, and
  /// a name that is empty or longer than 100 characters is dropped.
  String? get safeName {
    final last = name?.split(RegExp(r'[\\/]')).last ?? '';
    final clean = last.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').replaceAll('..', '').trim();
    return clean.isEmpty || clean.length > 100 ? null : clean;
  }
}

/// A file that the user sends with a message.
class OutgoingAttachment {
  const OutgoingAttachment({
    required this.mime,
    required this.bytes,
    this.name,
  });

  final String mime;
  final Uint8List bytes;
  final String? name;

  /// `image`, `audio`, or null for a media type that the convention does not define.
  String? get kind {
    final top = mime.split('/').first.toLowerCase();
    return ChatAttachment.attachmentKinds.contains(top) ? top : null;
  }
}

/// One message of a conversation (`docs/celaut/chat.md`, section 5).
class ChatMessage {
  const ChatMessage({
    required this.seq,
    required this.role,
    required this.text,
    this.attachments = const [],
    this.status = statusDone,
    this.reasoning = '',
    this.replyTo,
    this.cid,
    this.pinned = false,
  });

  /// The values of [status] (`docs/celaut/chat.md`, section 5.2).
  static const statusStreaming = 'streaming';
  static const statusDone = 'done';
  static const statusFailed = 'failed';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final seq = json['seq'];
    final role = json['role'];
    final text = json['text'];
    final attachments = json['attachments'];
    final status = json['status'] ?? statusDone;
    final reasoning = json['reasoning'] ?? '';
    final replyTo = json['reply_to'];
    final cid = json['cid'];
    final pinned = json['pinned'] ?? false;
    if (seq is! int ||
        seq < 0 ||
        role is! String ||
        text is! String ||
        (attachments != null && attachments is! List) ||
        status is! String ||
        !const {statusStreaming, statusDone, statusFailed}.contains(status) ||
        reasoning is! String ||
        (replyTo != null && replyTo is! int) ||
        (cid != null && cid is! String) ||
        pinned is! bool ||
        (pinned && role != 'assistant')) {
      throw const ChatException(ChatErrorKind.badAnswer);
    }
    return ChatMessage(
      seq: seq,
      role: role,
      text: text,
      attachments: [
        for (final item in (attachments as List?) ?? const [])
          if (item is Map<String, dynamic>)
            ChatAttachment.fromJson(item)
          else
            throw const ChatException(ChatErrorKind.badAnswer),
      ],
      status: status,
      reasoning: reasoning,
      replyTo: replyTo as int?,
      cid: cid as String?,
      pinned: pinned,
    );
  }

  final int seq;
  final String role;
  final String text;
  final List<ChatAttachment> attachments;

  /// `streaming` while the service still makes the answer, then `done` or `failed`.
  final String status;

  /// The reasoning of the model, apart from [text]. Empty if the service gives none.
  final String reasoning;

  /// The `seq` of the user message that this message answers, if the service says it.
  final int? replyTo;

  /// The `cid` of the send of a user message, if the service gives it.
  final String? cid;

  /// An assistant message that the client keeps at the top of the chat once the conversation
  /// grows past it. The service sets it when it makes the message and never changes it.
  final bool pinned;

  bool get fromUser => role == 'user';

  /// An answer that grows: its [text] and [reasoning] are not final yet.
  bool get isOpen => status == statusStreaming;
  bool get isFailed => status == statusFailed;
}

enum ChatErrorKind {
  /// The service did not answer, or the connection broke.
  unreachable,

  /// The answer of the service does not follow the convention.
  badAnswer,

  /// 400: the service refused the request.
  badRequest,

  /// 413: the service cannot keep more messages.
  historyFull,

  /// 503: the service cannot keep one more message that waits. Try again later.
  busy,

  /// 415, or the service does not accept the kind of file: no attachment is sent.
  unsupportedMedia,

  /// Another status that the convention does not define.
  other,
}

class ChatException implements Exception {
  const ChatException(this.kind, {this.status, this.message});

  final ChatErrorKind kind;
  final int? status;

  /// The `message` of the service, for the user, if it sent one.
  final String? message;

  @override
  String toString() => 'ChatException($kind, status: $status, message: $message)';
}

/// The client of the chat convention for one instance (`docs/celaut/chat.md`).
///
/// The service keeps the history. This object keeps a copy in memory only, and it
/// writes nothing to the Celaut database. [count] is the number of messages that the
/// client knows.
///
/// A send only gives the message to the service, so the user can send many messages at
/// once. The answers come with [sync], which the screen calls every few seconds: an
/// answer that the service still makes is an open message ([ChatMessage.isOpen]) that
/// grows from one read to the next.
class ChatClient {
  ChatClient({
    required this.port,
    required TunnelHttp http,
    this.sendTimeout = defaultSendTimeout,
  }) : _http = http;

  final int port;
  final TunnelHttp _http;

  /// The wait for the reply of a send. Tests make it short.
  final Duration sendTimeout;
  final List<ChatMessage> _messages = [];
  final Map<(int, int), Uint8List> _files = {};
  Set<String> _accepts = const {};

  /// Sends that are queued or running: the reads of files wait while there is one.
  int _sends = 0;

  /// Calls run one after the other: they share one connection.
  Future<void> _tail = Future.value();

  /// The reads of files, one after the other, before they join [_tail].
  Future<void> _readTail = Future.value();

  static const _path = '/chat/messages';

  /// The most files in one send, and the most bytes in one file
  /// (`docs/celaut/chat.md`, section 7).
  static const maxAttachments = 4;
  static const maxAttachmentBytes = 4 * 1024 * 1024;

  /// The wait for the reply of every send, with files or not. The service replies at once
  /// (it does not wait for the answer), but a send with files is a large upload, so the
  /// client waits longer than the 30 seconds of a read ([TunnelHttp.get]).
  static const defaultSendTimeout = Duration(minutes: 2);

  /// How often the client reads the conversation (`docs/celaut/chat.md`, section 9): while
  /// it waits for an answer, and otherwise.
  static const pollWaiting = Duration(seconds: 2);
  static const pollIdle = Duration(seconds: 10);

  /// The most bytes of files that stay in memory. Past it, the files of the other
  /// messages are dropped: the service gives them again.
  static const maxCachedBytes = 24 * 1024 * 1024;

  /// The most bytes of one read of the history.
  static const maxHistoryBytes = 1024 * 1024;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// The kinds of attachment (`image`, `audio`) that the service said it accepts, in the
  /// last read of the history. Empty: the service accepts text only.
  Set<String> get accepts => _accepts;
  int get count => _messages.length;

  /// The client waits for an answer: a message is open, or there are more user messages
  /// than assistant messages (`docs/celaut/chat.md`, section 9).
  bool get awaitingAnswer {
    var users = 0;
    var replies = 0;
    for (final message in _messages) {
      if (message.isOpen) return true;
      message.fromUser ? users++ : replies++;
    }
    return users > replies;
  }

  /// Read what is new in the conversation, and the growth of the open messages, and put
  /// it in [messages]. Use it when the screen opens a running instance, and again every
  /// [pollWaiting] or [pollIdle].
  Future<void> sync() => _serial(_sync);

  /// The waits between the reads of [syncWhenStarted]: they get longer, then stay at
  /// 10 seconds.
  static const startWaits = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ];

  /// [sync] for an instance that has just started. The service starts to listen some
  /// seconds after `StartService` (the echo service of M4: 18 to 60 seconds), and until
  /// then the node cannot connect the tunnel. So the client reads again while the
  /// service is not reachable, with longer waits ([startWaits]), until it has waited
  /// [limit]. Then it throws `unreachable`. Each read opens one tunnel stream, and the
  /// node charges each one (`TUNNEL_OPEN_MU`): about 14 reads in the 2 minutes.
  Future<void> syncWhenStarted({
    Duration limit = const Duration(minutes: 2),
    Future<void> Function(Duration wait)? wait,
  }) =>
      _serial(() async {
        final pause = wait ?? (d) => Future<void>.delayed(d);
        var waited = Duration.zero;
        for (var i = 0;; i++) {
          try {
            await _sync();
            return;
          } on ChatException catch (e) {
            if (e.kind != ChatErrorKind.unreachable || waited >= limit) rethrow;
          }
          final next = startWaits[i < startWaits.length ? i : startWaits.length - 1];
          await pause(next);
          waited += next;
        }
      });

  /// Send [text] and add the user message to [messages]. It does not wait for the answer:
  /// the answer comes with [sync].
  ///
  /// Each send has its own `cid`. If the connection breaks, the client reads the history
  /// first. If the message is in it, the send worked. If not, the client sends the same
  /// request again once, with the same `cid`, so the service cannot add it twice
  /// (`docs/celaut/chat.md`, section 6.3).
  ///
  /// [attachments] are sent only if the service accepts their kinds ([accepts]). A send
  /// with files and no text is valid.
  Future<void> send(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) {
    _sends++;
    return _serial(() => _send(text, attachments)).whenComplete(() => _sends--);
  }

  /// The bytes of attachment [index] of message [seq]. A file that this client sent is
  /// already in memory; the others are read from the service
  /// (`docs/celaut/chat.md`, section 6.4) once. They are kept in memory only.
  ///
  /// A send goes first: a read waits while a send is queued or running. The reads queue
  /// among themselves, so at most one of them is ahead of a new send.
  Future<Uint8List> readAttachment(int seq, int index) {
    final run = _readTail.then((_) => _read(seq, index));
    _readTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Uint8List> _read(int seq, int index) async {
    final early = _files[(seq, index)];
    if (early != null) return early;
    while (_sends > 0) {
      await _tail;
    }
    return _serial(() async {
      final kept = _files[(seq, index)];
      if (kept != null) return kept;
      final TunnelBytes answer;
      try {
        answer = await _http.getBytes(
          port,
          '$_path/$seq/attachments/$index',
          maxBytes: maxAttachmentBytes,
        );
      } on Exception {
        throw const ChatException(ChatErrorKind.unreachable);
      }
      if (answer.status != 200) {
        throw ChatException(ChatErrorKind.other, status: answer.status);
      }
      if (answer.truncated) throw const ChatException(ChatErrorKind.badAnswer);
      _remember(seq, index, answer.bytes);
      return answer.bytes;
    });
  }

  void _remember(int seq, int index, Uint8List bytes) {
    _files[(seq, index)] = bytes;
    var total = 0;
    for (final file in _files.values) {
      total += file.length;
    }
    if (total > maxCachedBytes) _files.removeWhere((key, _) => key.$1 != seq);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Check the limits of `docs/celaut/chat.md` (sections 6.1 and 7) before anything goes
  /// to the service.
  void _checkAttachments(String text, List<OutgoingAttachment> attachments) {
    if (text.isEmpty && attachments.isEmpty) {
      throw const ChatException(ChatErrorKind.badRequest);
    }
    if (attachments.isEmpty) return;
    if (attachments.length > maxAttachments) {
      throw const ChatException(ChatErrorKind.badRequest);
    }
    for (final file in attachments) {
      final kind = file.kind;
      if (kind == null || !_accepts.contains(kind)) {
        throw const ChatException(ChatErrorKind.unsupportedMedia);
      }
      if (file.bytes.isEmpty || file.bytes.length > maxAttachmentBytes) {
        throw const ChatException(ChatErrorKind.badRequest);
      }
    }
  }

  Future<void> _send(String text, List<OutgoingAttachment> attachments) async {
    _checkAttachments(text, attachments);
    final cid = _newCid();
    TunnelAnswer answer;
    try {
      answer = await _post(cid, text, attachments);
    } on ChatException {
      rethrow;
    } on Exception {
      // The client does not know if the service got the message: read the history.
      if (await _recovered(cid, attachments)) return;
      try {
        answer = await _post(cid, text, attachments);
      } on Exception {
        throw const ChatException(ChatErrorKind.unreachable);
      }
    }
    if (answer.status != 200) throw _error(answer);
    final sent = _readSent(answer.body);
    await _addSent(sent);
    _keepFiles(sent.seq, attachments);
  }

  Future<TunnelAnswer> _post(String cid, String text, List<OutgoingAttachment> attachments) =>
      _http.postJson(
        port,
        _path,
        {
          'cid': cid,
          'text': text,
          if (attachments.isNotEmpty)
            'attachments': [
              for (final file in attachments)
                {
                  'mime': file.mime,
                  if (file.name != null) 'name': file.name,
                  'data': base64Encode(file.bytes),
                },
            ],
        },
        timeout: sendTimeout,
      );

  /// A name for a send: 22 characters from the set that the convention allows.
  static String _newCid() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 22; i++) chars.codeUnitAt(random.nextInt(chars.length)),
    ]);
  }

  /// The user message of a send is at [seq]: keep the bytes that the client has, so that
  /// the screen does not read them back.
  void _keepFiles(int seq, List<OutgoingAttachment> attachments) {
    for (var i = 0; i < attachments.length; i++) {
      _remember(seq, i, attachments[i].bytes);
    }
  }

  /// Read the history, and say if it has the user message with [cid]. A read that fails
  /// counts as "no": the caller sends again, and that fails too if the service is gone.
  Future<bool> _recovered(String cid, List<OutgoingAttachment> attachments) async {
    try {
      await _sync();
    } on Exception {
      return false;
    }
    for (final message in _messages) {
      if (message.fromUser && message.cid == cid) {
        _keepFiles(message.seq, attachments);
        return true;
      }
    }
    return false;
  }

  /// The user message of the reply to a send (`docs/celaut/chat.md`, section 6.1).
  ChatMessage _readSent(String body) {
    try {
      final json = jsonDecode(body);
      final message = json is Map<String, dynamic> ? json['message'] : null;
      if (message is! Map<String, dynamic>) throw const FormatException();
      return ChatMessage.fromJson(message);
    } on ChatException {
      rethrow;
    } on Object {
      throw const ChatException(ChatErrorKind.badAnswer);
    }
  }

  /// Add the user message of a send. The service can have added answers to earlier
  /// messages since the last read, so the message can be past the end: read the gap.
  Future<void> _addSent(ChatMessage message) async {
    if (message.seq <= _messages.length) return _add([message]);
    await _sync();
  }

  /// The `seq` from which the next read starts: the first open message, or the end.
  int get _readFrom {
    final open = _messages.indexWhere((m) => m.isOpen);
    return open < 0 ? _messages.length : open;
  }

  /// Read from [_readFrom] until the client has all the messages (a read can be shorter
  /// than the history: section 6.2).
  Future<void> _sync() async {
    while (true) {
      final TunnelAnswer answer;
      try {
        answer = await _http.get(
          port,
          '$_path?from=$_readFrom',
          maxBytes: maxHistoryBytes,
        );
      } on Exception {
        throw const ChatException(ChatErrorKind.unreachable);
      }
      if (answer.status != 200) throw _error(answer);
      final read = _readMessages(answer.body);
      _accepts = read.accepts;
      _add(read.messages);
      if (_messages.length >= read.count) return;
      // The service has more, but this read gave nothing new: do not loop.
      if (read.messages.isEmpty) throw const ChatException(ChatErrorKind.badAnswer);
    }
  }

  /// Add the messages that follow the ones that the client has. A message that the
  /// client has as open is replaced by its new state; a final one is skipped. A gap is an
  /// answer that does not follow the convention.
  void _add(List<ChatMessage> incoming) {
    for (final message in incoming) {
      if (message.seq < _messages.length) {
        if (_messages[message.seq].isOpen) _messages[message.seq] = message;
        continue;
      }
      if (message.seq != _messages.length) {
        throw const ChatException(ChatErrorKind.badAnswer);
      }
      _messages.add(message);
    }
  }

  ({int count, Set<String> accepts, List<ChatMessage> messages}) _readMessages(
    String body,
  ) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) throw const FormatException();
      final count = json['count'];
      final list = json['messages'];
      final accepts = json['accepts'];
      if (count is! int || list is! List || (accepts != null && accepts is! List)) {
        throw const FormatException();
      }
      return (
        count: count,
        // A kind that this client does not know is ignored.
        accepts: {
          for (final kind in (accepts as List?) ?? const [])
            if (kind is String && ChatAttachment.attachmentKinds.contains(kind)) kind,
        },
        messages: [
          for (final item in list) ChatMessage.fromJson(item as Map<String, dynamic>),
        ],
      );
    } on ChatException {
      rethrow;
    } on Object {
      throw const ChatException(ChatErrorKind.badAnswer);
    }
  }

  ChatException _error(TunnelAnswer answer) {
    String? message;
    try {
      final json = jsonDecode(answer.body);
      if (json is Map<String, dynamic> && json['message'] is String) {
        message = json['message'] as String;
      }
    } on Object {
      // The body is not JSON: there is no message.
    }
    final kind = switch (answer.status) {
      400 => ChatErrorKind.badRequest,
      413 => ChatErrorKind.historyFull,
      415 => ChatErrorKind.unsupportedMedia,
      503 => ChatErrorKind.busy,
      _ => ChatErrorKind.other,
    };
    return ChatException(kind, status: answer.status, message: message);
  }
}
