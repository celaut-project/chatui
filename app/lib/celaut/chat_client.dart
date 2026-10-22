import 'dart:convert';
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
    return ChatAttachment(kind: kind, mime: mime, size: size, name: name as String?);
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
}

/// A file that the user sends with a message.
class OutgoingAttachment {
  const OutgoingAttachment({required this.mime, required this.bytes, this.name});

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
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final seq = json['seq'];
    final role = json['role'];
    final text = json['text'];
    final attachments = json['attachments'];
    if (seq is! int ||
        seq < 0 ||
        role is! String ||
        text is! String ||
        (attachments != null && attachments is! List)) {
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
    );
  }

  final int seq;
  final String role;
  final String text;
  final List<ChatAttachment> attachments;

  bool get fromUser => role == 'user';
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

  /// 503: the service makes an answer already. Try again later.
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
/// client knows: the `expect` of the next send.
class ChatClient {
  ChatClient({required this.port, required TunnelHttp http}) : _http = http;

  final int port;
  final TunnelHttp _http;
  final List<ChatMessage> _messages = [];
  final Map<(int, int), Uint8List> _files = {};
  Set<String> _accepts = const {};

  /// Calls run one after the other: the service allows one send at a time.
  Future<void> _tail = Future.value();

  static const _path = '/chat/messages';

  /// The most files in one send, and the most bytes in one file
  /// (`docs/celaut/chat.md`, section 7).
  static const maxAttachments = 4;
  static const maxAttachmentBytes = 4 * 1024 * 1024;

  /// The wait for a send that has files: the body is larger.
  static const attachmentTimeout = Duration(minutes: 2);

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// The kinds of attachment (`image`, `audio`) that the service said it accepts, in the
  /// last read of the history. Empty: the service accepts text only.
  Set<String> get accepts => _accepts;
  int get count => _messages.length;

  /// Read the history that the client does not have, and add it to [messages].
  /// Use it when the screen opens a running instance and to repair a lost answer.
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

  /// Send [text] and add the user message and the answer to [messages].
  ///
  /// If the service says that the client is out of sync (409), or the connection
  /// breaks, the client reads the history first. If the message is in it, the send
  /// worked. If not, the client does not send it again by itself: it throws, and the
  /// user decides to try again (`docs/celaut/chat.md`, section 6.3).
  ///
  /// [attachments] are sent only if the service accepts their kinds ([accepts]). A send
  /// with files and no text is valid.
  Future<void> send(String text, {List<OutgoingAttachment> attachments = const []}) =>
      _serial(() => _send(text, attachments));

  /// The bytes of attachment [index] of message [seq]. A file that this client sent is
  /// already in memory; the others are read from the service
  /// (`docs/celaut/chat.md`, section 6.4) once. They are kept in memory only.
  Future<Uint8List> readAttachment(int seq, int index) => _serial(() async {
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
        return _files[(seq, index)] = answer.bytes;
      });

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
    final expect = count;
    TunnelAnswer answer;
    try {
      answer = await _http.postJson(
        port,
        _path,
        {
          'expect': expect,
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
        timeout: attachments.isEmpty ? const Duration(seconds: 30) : attachmentTimeout,
      );
    } on ChatException {
      rethrow;
    } on Exception {
      // The client does not know if the service got the message.
      await _recover(expect, text, attachments);
      return;
    }
    switch (answer.status) {
      case 200:
        _add(_readMessages(answer.body).messages);
        _keepFiles(expect, attachments);
      case 409:
        await _recover(expect, text, attachments);
      default:
        throw _error(answer);
    }
  }

  /// The user message of a send is at [seq]: keep the bytes that the client has, so that
  /// the screen does not read them back.
  void _keepFiles(int seq, List<OutgoingAttachment> attachments) {
    for (var i = 0; i < attachments.length; i++) {
      _files[(seq, i)] = attachments[i].bytes;
    }
  }

  /// Read the history, then check that the message with [expect] is the one that the
  /// client sent. If it is not, the send did not happen: throw `unreachable`.
  Future<void> _recover(int expect, String text, List<OutgoingAttachment> attachments) async {
    try {
      await _sync();
    } on Exception {
      throw const ChatException(ChatErrorKind.unreachable);
    }
    final sent = _messages.length > expect &&
        _messages[expect].fromUser &&
        _messages[expect].text == text &&
        _messages[expect].attachments.length == attachments.length;
    if (!sent) throw const ChatException(ChatErrorKind.unreachable);
    _keepFiles(expect, attachments);
  }

  Future<void> _sync() async {
    final TunnelAnswer answer;
    try {
      answer = await _http.get(port, '$_path?from=$count');
    } on Exception {
      throw const ChatException(ChatErrorKind.unreachable);
    }
    if (answer.status != 200) throw _error(answer);
    final read = _readMessages(answer.body);
    _accepts = read.accepts;
    _add(read.messages);
  }

  /// Add the messages that follow the ones that the client has. A message that the
  /// client has is skipped; a gap is an answer that does not follow the convention.
  void _add(List<ChatMessage> incoming) {
    for (final message in incoming) {
      if (message.seq < _messages.length) continue;
      if (message.seq != _messages.length) {
        throw const ChatException(ChatErrorKind.badAnswer);
      }
      _messages.add(message);
    }
  }

  ({int count, Set<String> accepts, List<ChatMessage> messages}) _readMessages(String body) {
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
