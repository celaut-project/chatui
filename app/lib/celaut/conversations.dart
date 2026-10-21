import 'package:flutter/foundation.dart';

import '../bridge/api/celaut_service.dart';
import '../format.dart';
import 'chat_client.dart';

/// The name of an instance for the user: the name of its skill or service file, or a
/// short service id when the app does not know the name.
String instanceTitle(InstanceListView i) =>
    i.name.trim().isNotEmpty ? i.name.trim() : shorten(i.serviceId, head: 8, tail: 6);

/// What the list of conversations knows in memory, for this run of the app only
/// (`docs/celaut/ui-chat-first.md`): the last message of each conversation, and the
/// instances that start. Nothing here goes to the Celaut database: the history of a
/// conversation stays with the service (`docs/celaut/chat.md`). The database keeps
/// the instances, stopped or not, until the user deletes them.
class ConversationNotes extends ChangeNotifier {
  final Map<String, ChatMessage> _last = {};
  final Set<String> _starting = {};

  /// The last message of the conversation, if the app saw one in this run.
  ChatMessage? lastMessage(String instanceId) => _last[instanceId];

  /// The instance started in this run, and its service did not answer yet.
  bool isStarting(String instanceId) => _starting.contains(instanceId);

  void markStarting(String instanceId) {
    if (_starting.add(instanceId)) notifyListeners();
  }

  /// The service answered: the instance runs.
  void answered(String instanceId) {
    if (_starting.remove(instanceId)) notifyListeners();
  }

  /// Keep the last of [messages] as the preview of the conversation.
  void saw(String instanceId, List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    final last = messages.last;
    final before = _last[instanceId];
    if (before != null && before.seq == last.seq && before.text == last.text) return;
    _last[instanceId] = last;
    notifyListeners();
  }

  /// The instance stopped: the lists read the database again.
  void stopped(String instanceId) {
    _starting.remove(instanceId);
    notifyListeners();
  }

  /// Forget what the list knows of a deleted instance.
  void remove(String instanceId) {
    final last = _last.remove(instanceId) != null;
    final starting = _starting.remove(instanceId);
    if (last || starting) notifyListeners();
  }
}

/// The notes of the app.
final conversationNotes = ConversationNotes();
