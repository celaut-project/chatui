import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/l10n.dart';
import 'chat_prefs.dart';

/// Shows a local notification when an assistant message reaches status
/// `done`. The notice has no text of the answer: only the name of the chat. The caller decides whether the user is looking at that chat;
/// this class only honours the mute switch of the instance. Nothing leaves
/// the device.
class ChatNotifier {
  ChatNotifier({
    bool Function(String instanceId)? isMuted,
    Future<void> Function(int id, String title, String body, String payload)? show,
  })  : _isMuted = isMuted ?? chatPrefs.isMuted,
        _show = show ?? _showNative;

  final bool Function(String) _isMuted;
  final Future<void> Function(int, String, String, String) _show;

  static const channelId = 'chat_done';

  static AndroidNotificationChannel get _channel => AndroidNotificationChannel(
        channelId,
        appL10n.notifyChatDoneChannelName,
        description: appL10n.notifyChatDoneChannelDescription,
        importance: Importance.defaultImportance,
      );

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Returns true when a notification was shown. A muted instance and a
  /// platform failure both return false.
  Future<bool> notifyDone({
    required String instanceId,
    required String title,
    required String body,
  }) async {
    if (_isMuted(instanceId)) return false;
    try {
      // One notification per chat: a newer answer replaces the older one.
      await _show(instanceId.hashCode & 0x7fffffff, title, body, 'chat/$instanceId');
      return true;
    } catch (e) {
      debugPrint('argus: chat notification failed: $e');
      return false;
    }
  }

  // The shared plugin is initialised by NotificationService at start-up.
  static Future<void> _showNative(int id, String title, String body, String payload) async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          // The lock screen hides the notice until the user unlocks the phone.
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  }
}

final chatNotifier = ChatNotifier();
