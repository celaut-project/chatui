import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_network.dart';
import 'package:argus_wallet/celaut/network_route.dart';
import 'package:argus_wallet/celaut/network_strings.dart';
import 'package:argus_wallet/ui/celaut/network_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

NetworkStatusView _status(NetworkState state, {NetworkChoice? choice, int percent = 0, String error = ''}) =>
    NetworkStatusView(
      choice: choice ?? NetworkChoice.off,
      state: state,
      percent: percent,
      error: error,
    );

void main() {
  late NetworkStatusView current;
  late List<({NetworkChoice choice, String? socks})> pushed;
  Object? pushError;

  NetworkRoute make() => NetworkRoute(
    push: (choice, socks, dir) async {
      pushed.add((choice: choice, socks: socks));
      if (pushError != null) throw pushError!;
    },
    readStatus: () => current,
    privateDir: () async => '/private',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    current = _status(NetworkState.off);
    pushed = [];
    pushError = null;
  });

  Future<void> open(WidgetTester tester, NetworkRoute route) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: NetworkScreen(route: route)));
    await tester.pumpAndSettle();
  }

  testWidgets('it starts with Tor off and says that the connections are direct', (tester) async {
    await open(tester, make());
    expect(find.text(NetworkStrings.status(current)), findsOneWidget);
    expect(tester.widget<RadioListTile<NetworkMode>>(find.byKey(const Key('network-off'))).groupValue, NetworkMode.off);
    expect(find.byKey(const Key('network-socks-address')), findsNothing);
  });

  testWidgets('choosing the embedded Tor and applying keeps it and gives it to the core', (tester) async {
    final route = make();
    await open(tester, route);
    await tester.tap(find.byKey(const Key('network-embedded')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('network-apply')));
    await tester.pumpAndSettle();
    expect(pushed.single, (choice: NetworkChoice.embedded, socks: null));
    expect(route.mode, NetworkMode.embedded);
  });

  testWidgets('the proxy option shows the address, and a bad address is not sent', (tester) async {
    await open(tester, make());
    await tester.tap(find.byKey(const Key('network-socks')));
    await tester.pump();
    expect(find.byKey(const Key('network-socks-address')), findsOneWidget);
    for (final bad in ['', 'localhost:9050', '127.0.0.1', '127.0.0.1:0', '127.0.0.1:70000']) {
      await tester.enterText(find.byKey(const Key('network-socks-address')), bad);
      await tester.tap(find.byKey(const Key('network-apply')));
      await tester.pumpAndSettle();
      expect(find.text(NetworkStrings.socksInvalid), findsOneWidget, reason: bad);
    }
    expect(pushed, isEmpty);

    await tester.enterText(find.byKey(const Key('network-socks-address')), '127.0.0.1:9050');
    await tester.tap(find.byKey(const Key('network-apply')));
    await tester.pumpAndSettle();
    expect(pushed.single, (choice: NetworkChoice.socks, socks: '127.0.0.1:9050'));
  });

  testWidgets('an ipv6 proxy address is accepted', (tester) async {
    await open(tester, make());
    await tester.tap(find.byKey(const Key('network-socks')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('network-socks-address')), '[::1]:9050');
    await tester.tap(find.byKey(const Key('network-apply')));
    await tester.pumpAndSettle();
    expect(pushed.single.socks, '[::1]:9050');
  });

  testWidgets('the state is read again every second: starting, ready, failed', (tester) async {
    current = _status(NetworkState.starting, choice: NetworkChoice.embedded, percent: 37);
    await open(tester, make());
    expect(find.text('Starting Tor… 37%'), findsOneWidget);

    current = _status(NetworkState.ready, choice: NetworkChoice.embedded);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('The connections go through Tor.'), findsOneWidget);

    current = _status(NetworkState.failed, choice: NetworkChoice.socks, error: 'no answer');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('no answer'), findsOneWidget);
    expect(find.textContaining('fail until'), findsOneWidget);
  });

  testWidgets('an error of the core is shown, and the choice stays kept', (tester) async {
    pushError = const CelautError(kind: CelautErrorKind.invalidInput, message: 'not an IP address and port');
    final route = make();
    await open(tester, route);
    await tester.tap(find.byKey(const Key('network-embedded')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('network-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('network-error')), findsOneWidget);
    expect(find.text('not an IP address and port'), findsOneWidget);
    expect(route.mode, NetworkMode.embedded);
  });

  testWidgets('a saved choice is shown when the screen opens', (tester) async {
    SharedPreferences.setMockInitialValues({
      NetworkRoute.modeKey: 'socks',
      NetworkRoute.socksKey: '10.1.1.1:1080',
    });
    await open(tester, make());
    expect(tester.widget<RadioListTile<NetworkMode>>(find.byKey(const Key('network-socks'))).groupValue, NetworkMode.socks);
    expect(tester.widget<TextField>(find.byKey(const Key('network-socks-address'))).controller!.text, '10.1.1.1:1080');
  });
}
