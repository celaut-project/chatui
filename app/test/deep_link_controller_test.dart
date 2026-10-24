import 'package:argus_wallet/services/deep_link_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push parks a link and notifies; take hands it over once', () {
    final c = DeepLinkController();
    var notified = 0;
    c.addListener(() => notified++);

    c.push('ergopay://x/y');

    expect(notified, 1);
    expect(c.pending, 'ergopay://x/y');
    expect(c.take(), 'ergopay://x/y');
    expect(c.take(), isNull);
    expect(c.pending, isNull);
  });

  test('ignores blank links', () {
    final c = DeepLinkController();
    c.push('   ');
    expect(c.pending, isNull);
  });

  test('a notification tap becomes an argus link with a home route', () {
    expect(argusLinkRoute('argus://activity'), '/transactions');
    expect(argusLinkRoute('argus://nothing'), isNull);
    expect(argusLinkRoute('ergopay://x'), isNull);
  });

  test('a chat link names the instance, and no other link does', () {
    expect(argusChatInstance('argus://chat/AbC-12_x'), 'AbC-12_x');
    expect(argusChatInstance('  argus://chat/abc  '), 'abc');
    expect(argusChatInstance('argus://chat/'), isNull);
    expect(argusChatInstance('argus://chat/a/b'), isNull);
    expect(argusChatInstance('argus://chat/a b'), isNull);
    expect(argusChatInstance('argus://activity'), isNull);
    expect(argusChatInstance('argus://chat/${'a' * 129}'), isNull);
    expect(argusLinkRoute('argus://chat/abc'), isNull);
  });
}
