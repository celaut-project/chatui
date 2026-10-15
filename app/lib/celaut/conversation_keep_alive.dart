import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the app alive in the background while a conversation with a service is open,
/// so that the tunnel to the node stays up (`docs/celaut-plan.md`, section 3). The
/// instance runs on the node and is not affected: only the phone side is kept.
///
/// Both calls never throw: the conversation works without the keep-alive.
abstract class ConversationKeepAlive {
  /// Ask for the notification permission (Android 13+), then start the foreground
  /// service. The service runs also if the user refuses the permission.
  Future<void> start();

  /// Stop the foreground service. It is safe to call it more than once.
  Future<void> stop();
}

/// The Android half lives in `ConversationHandler.kt` and `ConversationService.kt`. On
/// other platforms, and when the channel is missing, it does nothing.
class ChannelConversationKeepAlive implements ConversationKeepAlive {
  ChannelConversationKeepAlive({MethodChannel? channel, bool? isAndroid})
      : _channel = channel ?? const MethodChannel(channelName),
        _isAndroid = isAndroid ?? Platform.isAndroid;

  static const channelName = 'org.celaut.chatui/conversation';

  final MethodChannel _channel;
  final bool _isAndroid;

  @override
  Future<void> start() async {
    if (!_isAndroid) return;
    // The answer does not matter: with no permission the service has no notification.
    await _call('requestNotificationPermission');
    await _call('start');
  }

  @override
  Future<void> stop() async {
    if (!_isAndroid) return;
    await _call('stop');
  }

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<Object?>(method);
    } on Object {
      // PlatformException, MissingPluginException: nothing to keep alive.
    }
  }
}
