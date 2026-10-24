import 'package:flutter_test/flutter_test.dart';

import 'package:argus_wallet/celaut/chat_notifier.dart';

void main() {
  test('shows one notification per chat with a chat payload', () async {
    final shown = <List<Object>>[];
    final n = ChatNotifier(isMuted: (_) => false, show: (id, t, b, p) async => shown.add([id, t, b, p]));
    expect(await n.notifyDone(instanceId: 'a', title: 'T', body: 'B'), isTrue);
    expect(await n.notifyDone(instanceId: 'a', title: 'T2', body: 'B2'), isTrue);
    expect(shown[0][0], shown[1][0]);
    expect(shown[0][3], 'chat/a');
  });

  test('a muted instance shows nothing', () async {
    var calls = 0;
    final n = ChatNotifier(isMuted: (id) => id == 'm', show: (_, __, ___, ____) async => calls++);
    expect(await n.notifyDone(instanceId: 'm', title: 'T', body: 'B'), isFalse);
    expect(calls, 0);
  });

  test('a platform failure is swallowed', () async {
    final n = ChatNotifier(isMuted: (_) => false, show: (_, __, ___, ____) async => throw Exception('x'));
    expect(await n.notifyDone(instanceId: 'a', title: 'T', body: 'B'), isFalse);
  });
}
