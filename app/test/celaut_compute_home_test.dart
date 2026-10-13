import 'package:argus_wallet/bridge/api/celaut_home.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/celaut_strings.dart';
import 'package:argus_wallet/celaut/compute_home_flag.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/compute_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _a = 'aa' * 32;
final _b = 'bb' * 32;

ComputeOverviewView _overview() => ComputeOverviewView(
  nodesCounted: 1,
  nodesUnreachable: 1,
  // The reachable node gives no CPU: the sum is unknown, not 0.
  cpuCores: const CoresTotalView(total: null, known: 0, unknownNodes: 1),
  memBytes: const BytesTotalView(total: 8589934592, known: 8589934592, unknownNodes: 0),
  diskBytes: const BytesTotalView(total: 1073741824, known: 1073741824, unknownNodes: 0),
  // The unreachable node has an unknown credit: the total is unknown.
  creditNanoErg: const NanoErgTotalView(total: null, known: '10000000', unknownNodes: 1),
  nodes: [
    NodeComputeView(
      peerId: _a,
      address: 'a:1',
      reachable: true,
      memBytes: 8589934592,
      diskBytes: 1073741824,
      creditMu: '10000000',
      muPerNanoErg: '1',
      creditNanoErg: '10000000',
    ),
    NodeComputeView(peerId: _b, address: 'b:1', reachable: false, error: 'refused'),
  ],
  instances: [
    RunningInstanceView(
      instanceId: 'i1',
      peerId: _a,
      serviceId: 'cc' * 32,
      startedAt: 1,
      balanceMu: '900000',
      costSoFarMu: '100000',
      costSoFarNanoErg: '100000',
    ),
    RunningInstanceView(instanceId: 'i2', peerId: _b, serviceId: 'dd' * 32, startedAt: 2),
  ],
);

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    bool fullWallet = true,
    int? walletsNano = 250000000,
  }) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stops = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ComputeHomeScreen(
          walletsTotalNano: walletsNano,
          hasFullWallet: fullWallet,
          onWallets: () {},
          load: () async => _overview(),
          stop: (id) async {
            stops.add(id);
            return const StopView(refundMu: '900000', clientBalanceMu: '');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return stops;
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('compute first: offered sums, unknown parts and the unreachable nodes', (
    tester,
  ) async {
    await pump(tester);
    final l = appL10n;
    expect(text(tester, 'compute-home-nodes'), l.celautHomeNodes('1', '1'));
    expect(text(tester, 'compute-home-cpu'), '${CelautStrings.cpuLabel}: ${l.celautUnknown}');
    expect(
      text(tester, 'compute-home-memory'),
      '${CelautStrings.memoryLabel}: ${CelautStrings.bytes(8589934592)}',
    );
    expect(find.text(l.celautHomeOfferedNote), findsOneWidget);
    // The order: compute, money, instances.
    final compute = tester.getTopLeft(find.byKey(const Key('compute-home-offered'))).dy;
    final money = tester.getTopLeft(find.byKey(const Key('compute-home-money'))).dy;
    final instance = tester.getTopLeft(find.byKey(const Key('compute-home-instance-i1'))).dy;
    expect(compute, lessThan(money));
    expect(money, lessThan(instance));
  });

  testWidgets('money for compute: ERG of all wallets and credit in MU and ERG', (tester) async {
    await pump(tester);
    final l = appL10n;
    expect(
      text(tester, 'compute-home-wallets-total'),
      l.celautHomeWalletsTotal(formatErg(250000000)),
    );
    expect(text(tester, 'compute-home-credit'), l.celautHomeCredit(l.celautUnknown));
    expect(
      text(tester, 'compute-home-credit-$_a'),
      l.celautHomeCreditNode(
        shorten(_a, head: 8, tail: 6),
        '10,000,000 MU',
        '1 MU',
        formatErg(10000000),
      ),
    );
    expect(
      text(tester, 'compute-home-credit-$_b'),
      l.celautHomeCreditNode(
        shorten(_b, head: 8, tail: 6),
        l.celautUnknown,
        l.celautUnknown,
        l.celautUnknown,
      ),
    );
  });

  testWidgets('an unknown wallet total is unknown, not 0', (tester) async {
    await pump(tester, walletsNano: null);
    expect(
      text(tester, 'compute-home-wallets-total'),
      appL10n.celautHomeWalletsTotal(appL10n.celautUnknown),
    );
  });

  testWidgets('running instances show the cost so far and stop', (tester) async {
    final stops = await pump(tester);
    final l = appL10n;
    expect(
      text(tester, 'compute-home-cost-i1'),
      l.celautHomeCostSoFar('100,000 MU', formatErg(100000)),
    );
    expect(
      text(tester, 'compute-home-cost-i2'),
      l.celautHomeCostSoFar(l.celautUnknown, l.celautUnknown),
    );
    await tester.tap(find.byKey(const Key('compute-home-stop-i1')));
    await tester.pumpAndSettle();
    expect(stops, ['i1']);
    expect(text(tester, 'compute-home-note'), l.celautHomeStopped('900,000 MU'));
  });

  testWidgets('with no full wallet the stop is off, with the message', (tester) async {
    final stops = await pump(tester, fullWallet: false);
    expect(find.byKey(const Key('compute-home-no-full-wallet')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('compute-home-stop-i1'))).onPressed,
      isNull,
    );
    expect(stops, isEmpty);
  });

  test('the compute home is off until the developer setting turns it on', () async {
    SharedPreferences.setMockInitialValues({});
    final flag = ComputeHomeFlag();
    await flag.load();
    expect(flag.value, isFalse);
    await flag.set(true);
    final again = ComputeHomeFlag();
    await again.load();
    expect(again.value, isTrue);
  });
}
