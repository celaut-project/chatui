import 'package:argus_wallet/celaut/conversation_keep_alive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(ChannelConversationKeepAlive.channelName);
  final calls = <String>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    calls.clear();
    answer((call) async {
      calls.add(call.method);
      return call.method == 'start' ? true : null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start asks for the notification permission, then starts the service', () async {
    await ChannelConversationKeepAlive(isAndroid: true).start();
    expect(calls, ['requestNotificationPermission', 'start']);
  });

  test('stop stops the service', () async {
    await ChannelConversationKeepAlive(isAndroid: true).stop();
    expect(calls, ['stop']);
  });

  test('a refused permission does not stop the start', () async {
    answer((call) async {
      calls.add(call.method);
      return false;
    });
    await ChannelConversationKeepAlive(isAndroid: true).start();
    expect(calls, ['requestNotificationPermission', 'start']);
  });

  test('on a platform that is not Android it does nothing', () async {
    final keepAlive = ChannelConversationKeepAlive(isAndroid: false);
    await keepAlive.start();
    await keepAlive.stop();
    expect(calls, isEmpty);
  });

  test('a platform error or a missing channel never throws', () async {
    answer((call) async => throw PlatformException(code: 'x'));
    final keepAlive = ChannelConversationKeepAlive(isAndroid: true);
    await keepAlive.start();
    await keepAlive.stop();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await keepAlive.start();
    await keepAlive.stop();
  });

  test('a permission error does not stop the start call', () async {
    answer((call) async {
      calls.add(call.method);
      if (call.method == 'requestNotificationPermission') {
        throw PlatformException(code: 'permission');
      }
      return true;
    });
    await ChannelConversationKeepAlive(isAndroid: true).start();
    expect(calls, ['requestNotificationPermission', 'start']);
  });
}
