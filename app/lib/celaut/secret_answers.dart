import 'package:shared_preferences/shared_preferences.dart';

/// How the user answered a secret request of the service (`docs/celaut/chat.md`, section
/// 5.6).
enum SecretAnswer { sent, skipped }

/// The answers to the secret requests of one conversation. The service does not send the
/// state of a request, so the client keeps it: the `request_id` and "sent" or "skipped",
/// never the value. Stored in SharedPreferences; a failed read or write keeps the answers in
/// memory only.
class SecretAnswers {
  SecretAnswers(this.instanceId);

  final String instanceId;
  final _answers = <String, SecretAnswer>{};

  String get _key => 'chat_secret_answers_$instanceId';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final row in p.getStringList(_key) ?? const <String>[]) {
        final at = row.lastIndexOf('=');
        if (at <= 0) continue;
        final answer = SecretAnswer.values.where((a) => a.name == row.substring(at + 1)).firstOrNull;
        if (answer != null) _answers[row.substring(0, at)] = answer;
      }
    } catch (_) {
      // Memory only.
    }
  }

  /// The answer to [requestId], or null if the user did not answer it yet.
  SecretAnswer? of(String requestId) => _answers[requestId];

  Future<void> set(String requestId, SecretAnswer answer) async {
    _answers[requestId] = answer;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, [for (final e in _answers.entries) '${e.key}=${e.value.name}']);
    } catch (_) {
      // Memory only for this run.
    }
  }
}
