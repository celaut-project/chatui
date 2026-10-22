import 'dart:convert';

import 'tunnel_http.dart';

/// One message of a conversation (`docs/celaut/chat.md`, section 5).
class ChatMessage {
  const ChatMessage({required this.seq, required this.role, required this.text});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final seq = json['seq'];
    final role = json['role'];
    final text = json['text'];
    if (seq is! int || seq < 0 || role is! String || text is! String) {
      throw const ChatException(ChatErrorKind.badAnswer);
    }
    return ChatMessage(seq: seq, role: role, text: text);
  }

  final int seq;
  final String role;
  final String text;

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

  /// Calls run one after the other: the service allows one send at a time.
  Future<void> _tail = Future.value();

  static const _path = '/chat/messages';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
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
  Future<void> send(String text) => _serial(() => _send(text));

  Future<void> _serial(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _send(String text) async {
    final expect = count;
    TunnelAnswer answer;
    try {
      answer = await _http.postJson(port, _path, {'expect': expect, 'text': text});
    } on ChatException {
      rethrow;
    } on Exception {
      // The client does not know if the service got the message.
      await _recover(expect, text);
      return;
    }
    switch (answer.status) {
      case 200:
        _add(_readMessages(answer.body).messages);
      case 409:
        await _recover(expect, text);
      default:
        throw _error(answer);
    }
  }

  /// Read the history, then check that the message with [expect] is the one that the
  /// client sent. If it is not, the send did not happen: throw `unreachable`.
  Future<void> _recover(int expect, String text) async {
    try {
      await _sync();
    } on Exception {
      throw const ChatException(ChatErrorKind.unreachable);
    }
    final sent = _messages.length > expect &&
        _messages[expect].fromUser &&
        _messages[expect].text == text;
    if (!sent) throw const ChatException(ChatErrorKind.unreachable);
  }

  Future<void> _sync() async {
    final TunnelAnswer answer;
    try {
      answer = await _http.get(port, '$_path?from=$count');
    } on Exception {
      throw const ChatException(ChatErrorKind.unreachable);
    }
    if (answer.status != 200) throw _error(answer);
    _add(_readMessages(answer.body).messages);
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

  ({int count, List<ChatMessage> messages}) _readMessages(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) throw const FormatException();
      final count = json['count'];
      final list = json['messages'];
      if (count is! int || list is! List) throw const FormatException();
      return (
        count: count,
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
      503 => ChatErrorKind.busy,
      _ => ChatErrorKind.other,
    };
    return ChatException(kind, status: answer.status, message: message);
  }
}
