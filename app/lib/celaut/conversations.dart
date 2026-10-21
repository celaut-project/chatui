import 'package:flutter/foundation.dart';

import '../bridge/api/celaut_service.dart';
import '../format.dart';
import 'chat_client.dart';

/// The name of an instance for the user: the name of its skill or service file, or a
/// short service id when the app does not know the name.
String instanceTitle(InstanceListView i) =>
    i.name.trim().isNotEmpty ? i.name.trim() : shorten(i.serviceId, head: 8, tail: 6);

/// An instance that stopped while the app was open. The database forgets an instance
/// when it stops, so the list of conversations keeps it here until the user removes it
/// or the app closes.
class StoppedInstance {
  const StoppedInstance({required this.instance, required this.refundMu});

  final InstanceListView instance;

  /// What the node gave back at the stop, in MU (empty if unknown).
  final String refundMu;
}

/// What the list of conversations knows in memory, for this run of the app only
/// (`docs/celaut/ui-chat-first.md`): the last message of each conversation, the
/// instances that start, and the instances that stopped. Nothing here goes to the
/// Celaut database: the history of a conversation stays with the service
/// (`docs/celaut/chat.md`).
class ConversationNotes extends ChangeNotifier {
  final Map<String, ChatMessage> _last = {};
  final Set<String> _starting = {};
  final Map<String, StoppedInstance> _stopped = {};

  /// The last message of the conversation, if the app saw one in this run.
  ChatMessage? lastMessage(String instanceId) => _last[instanceId];

  /// The instance started in this run, and its service did not answer yet.
  bool isStarting(String instanceId) => _starting.contains(instanceId);

  /// The instances that stopped in this run, the last stop first.
  List<StoppedInstance> get stopped => _stopped.values.toList().reversed.toList();

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

  void markStopped(InstanceListView instance, String refundMu) {
    _starting.remove(instance.instanceId);
    _stopped.remove(instance.instanceId);
    _stopped[instance.instanceId] = StoppedInstance(instance: instance, refundMu: refundMu);
    notifyListeners();
  }

  /// Forget what the list knows of the instance.
  void remove(String instanceId) {
    final stopped = _stopped.remove(instanceId) != null;
    final last = _last.remove(instanceId) != null;
    final starting = _starting.remove(instanceId);
    if (stopped || last || starting) notifyListeners();
  }
}

/// The notes of the app.
final conversationNotes = ConversationNotes();
