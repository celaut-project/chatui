import 'package:argus_wallet/bridge/api/celaut_home.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/celaut_format.dart';
import 'package:argus_wallet/celaut/celaut_strings.dart';
import 'package:argus_wallet/celaut/compute_home_flag.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/wallet_money.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/compute_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _a = 'aa' * 32;
final _b = 'bb' * 32;
final _c = 'cc' * 32;

ComputeOverviewView _overview() => ComputeOverviewView(
  nodesCounted: 2,
  nodesUnreachable: 1,
  // One counted node gives no CPU: "at least 6 cores (1 node unknown)".
  cpuCores: const CoresTotalView(total: null, known: 6, unknownNodes: 1, atLeast: true),
  memBytes: const BytesTotalView(
    total: 8589934592,
    known: 8589934592,
    unknownNodes: 0,
    atLeast: false,
  ),
  // No node gives the disk: unknown, not "at least 0".
  diskBytes: const BytesTotalView(total: null, known: 0, unknownNodes: 2, atLeast: false),
  creditNanoErg: const NanoErgTotalView(
    total: null,
    known: '14500000',
    unknownNodes: 1,
    atLeast: true,
  ),
  paidNanoErg: const NanoErgTotalView(
    total: null,
    known: '10000000',
    unknownNodes: 1,
    atLeast: true,
  ),
  freeNanoErg: const NanoErgTotalView(
    total: null,
    known: '4500000',
    unknownNodes: 1,
    atLeast: true,
  ),
  nodes: [
    NodeComputeView(
      peerId: _a,
      address: 'a.example:1',
      reachable: true,
      cpuCores: 6,
      memBytes: 8589934592,
      creditMu: '14500000',
      muPerNanoErg: '1',
      creditNanoErg: '14500000',
      paidMu: '10000000',
      paidNanoErg: '10000000',
      freeMu: '4500000',
      freeNanoErg: '4500000',
      clientUnknown: false,
    ),
    NodeComputeView(
      peerId: _b,
      address: 'b.example:2',
      reachable: false,
      error: 'This RPC requires a client_id minted by GenerateClient first.',
      clientUnknown: true,
    ),
    NodeComputeView(
      peerId: _c,
      address: 'c.example:3',
      reachable: false,
      error: 'refused',
      clientUnknown: false,
    ),
  ],
  instances: [
    RunningInstanceView(
      instanceId: 'i1',
      peerId: _a,
      serviceId: 'dd' * 32,
      startedAt: 1,
      balanceMu: '900000',
      costSoFarMu: '100000',
      costSoFarNanoErg: '100000',
    ),
    RunningInstanceView(instanceId: 'i2', peerId: _c, serviceId: 'ee' * 32, startedAt: 2),
  ],
);

const _full = WalletSum(count: 2, unknown: 0, knownNano: 250000000);
const _watched = WalletSum(count: 1, unknown: 0, knownNano: 3000000000);

class _Wallets implements FullWallets {
  _Wallets({this.open = true, this.unlocks = true});

  bool open;
  final bool unlocks;
  final unlocked = <String>[];

  @override
  Future<List<PayerWallet>> payers() async => [
    PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 250000000, open: open),
  ];

  @override
  Future<String?> loadDefault() async => null;

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async {
    unlocked.add(wallet.walletId);
    if (unlocks) open = true;
    return unlocks;
  }
}

class _Run {
  final stops = <String>[];
  final newClients = <String>[];
  var loads = 0;
}

void main() {
  Future<_Run> pump(
    WidgetTester tester, {
    WalletMoney? money,
    double? usdPerErg = 2.0,
    FullWallets? wallets,
  }) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final run = _Run();
    await tester.pumpWidget(
      MaterialApp(
        home: ComputeHomeScreen(
          money:
              money ??
              const WalletMoney(full: _full, watched: _watched, gate: FullWalletGate.open),
          usdPerErg: usdPerErg,
          onWallets: () {},
          onNodes: () {},
          wallets: wallets ?? _Wallets(),
          load: () async {
            run.loads++;
            return _overview();
          },
          stop: (id) async {
            run.stops.add(id);
            return const StopView(refundMu: '900000', clientBalanceMu: '');
          },
          newClient: (node) async {
            run.newClients.add('${node.host}:${node.port}');
            return NewClientView(peerId: _b, freeCreditMu: '4500000', earlierClients: 1);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return run;
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  String rowTexts(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)))
      .map((t) => t.data)
      .join(' | ');

  testWidgets('compute first: a partial sum is "at least", a missing one is unknown', (
    tester,
  ) async {
    await pump(tester);
    final l = appL10n;
    expect(text(tester, 'compute-home-nodes'), l.celautHomeNodes('2', '1'));
    expect(text(tester, 'compute-home-cpu'), l.celautAtLeast(CelautStrings.cores(6), 1));
    expect(text(tester, 'compute-home-cpu'), contains('1 node unknown'));
    expect(rowTexts(tester, 'compute-home-memory'), contains(CelautStrings.bytes(8589934592)));
    expect(rowTexts(tester, 'compute-home-disk'), contains(l.celautUnknown));
    expect(find.text(l.celautHomeOfferedNote), findsOneWidget);
    // The order: compute, money, instances.
    final compute = tester.getTopLeft(find.byKey(const Key('compute-home-cpu'))).dy;
    final money = tester.getTopLeft(find.byKey(const Key('compute-home-full'))).dy;
    final instance = tester.getTopLeft(find.byKey(const Key('compute-home-instance-i1'))).dy;
    expect(compute, lessThan(money));
    expect(money, lessThan(instance));
    // The Celaut header.
    expect(find.text('CELAUT'), findsOneWidget);
  });

  testWidgets('full wallets and watched wallets are two figures with USD', (tester) async {
    await pump(tester);
    final l = appL10n;
    final full = rowTexts(tester, 'compute-home-full');
    expect(full, contains(l.celautHomeFullWallets));
    expect(full, contains(formatErg(250000000)));
    expect(full, contains(l.celautHomeUsd('\$0.50')));
    final watched = rowTexts(tester, 'compute-home-watched');
    expect(watched, contains(l.celautHomeWatched));
    expect(watched, contains(formatErg(3000000000)));
    expect(watched, contains(l.celautHomeUsd('\$6.00')));
    // Never one sum of the two.
    expect(find.textContaining(formatErg(3250000000)), findsNothing);
    expect(find.byKey(const Key('compute-home-usd-source')), findsOneWidget);
  });

  testWidgets('without the oracle price the USD is unknown, not \$0', (tester) async {
    await pump(tester, usdPerErg: null);
    final l = appL10n;
    expect(rowTexts(tester, 'compute-home-full'), contains(l.celautHomeUsdUnknown));
    expect(rowTexts(tester, 'compute-home-watched'), contains(l.celautHomeUsdUnknown));
    expect(find.textContaining('\$0'), findsNothing);
  });

  testWidgets('a wallet with an unknown balance makes "at least"', (tester) async {
    await pump(
      tester,
      money: const WalletMoney(
        full: WalletSum(count: 2, unknown: 1, knownNano: 250000000),
        watched: WalletSum(count: 1, unknown: 1, knownNano: 0),
        gate: FullWalletGate.open,
      ),
    );
    final l = appL10n;
    expect(
      rowTexts(tester, 'compute-home-full'),
      contains(l.celautAtLeastWallets(formatErg(250000000), 1)),
    );
    expect(rowTexts(tester, 'compute-home-full'), contains(l.celautHomeUsdUnknown));
    expect(rowTexts(tester, 'compute-home-watched'), contains(l.celautUnknown));
  });

  testWidgets('the free credit is apart from the paid credit', (tester) async {
    await pump(tester);
    final l = appL10n;
    final paid = rowTexts(tester, 'compute-home-paid');
    expect(paid, contains(l.celautHomePaidCredit));
    expect(paid, contains(l.celautAtLeast(formatNanoErg(BigInt.from(10000000)), 1)));
    final free = rowTexts(tester, 'compute-home-free');
    expect(free, contains(l.celautHomeFreeCredit));
    expect(free, contains(l.celautAtLeast(formatNanoErg(BigInt.from(4500000)), 1)));
    expect(
      rowTexts(tester, 'compute-home-credit-$_a'),
      contains(l.celautHomeNodeCredit('10,000,000 MU', '4,500,000 MU', '1')),
    );
    expect(rowTexts(tester, 'compute-home-credit-$_c'), contains(l.celautHomeNodeUnreachable));
  });

  testWidgets('a forgotten client: the user chooses a new client', (tester) async {
    final run = await pump(tester);
    expect(find.byKey(Key('compute-home-client-unknown-$_c')), findsNothing);
    await tester.tap(find.byKey(Key('compute-home-client-unknown-$_b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-unknown-dialog')), findsOneWidget);
    expect(find.byKey(const Key('client-unknown-warning')), findsOneWidget);
    expect(run.newClients, isEmpty);
    await tester.tap(find.byKey(const Key('client-unknown-new')));
    await tester.pumpAndSettle();
    expect(run.newClients, ['b.example:2']);
    expect(run.loads, 2);
  });

  testWidgets('a forgotten client: "Retry later" changes nothing', (tester) async {
    final run = await pump(tester);
    await tester.tap(find.byKey(Key('compute-home-client-unknown-$_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-unknown-retry')));
    await tester.pumpAndSettle();
    expect(run.newClients, isEmpty);
    expect(run.loads, 1);
  });

  testWidgets('running instances show the cost so far and stop', (tester) async {
    final run = await pump(tester);
    final l = appL10n;
    expect(text(tester, 'compute-home-cost-i1'), l.celautHomeCostSoFar('100,000 MU', formatErg(100000)));
    expect(
      text(tester, 'compute-home-cost-i2'),
      l.celautHomeCostSoFar(l.celautUnknown, l.celautUnknown),
    );
    await tester.tap(find.byKey(const Key('compute-home-stop-i1')));
    await tester.pumpAndSettle();
    expect(run.stops, ['i1']);
    expect(text(tester, 'compute-home-note'), l.celautHomeStopped('900,000 MU'));
  });

  testWidgets('a stop with only locked full wallets asks to open one first', (tester) async {
    final wallets = _Wallets(open: false);
    final run = await pump(
      tester,
      wallets: wallets,
      money: const WalletMoney(full: _full, watched: _watched, gate: FullWalletGate.locked),
    );
    expect(find.byKey(const Key('compute-home-wallet-locked')), findsOneWidget);
    await tester.tap(find.byKey(const Key('compute-home-stop-i1')));
    await tester.pumpAndSettle();
    expect(wallets.unlocked, ['w1']);
    expect(run.stops, ['i1']);
  });

  testWidgets('a stop is not sent when the user does not open a wallet', (tester) async {
    final wallets = _Wallets(open: false, unlocks: false);
    final run = await pump(
      tester,
      wallets: wallets,
      money: const WalletMoney(full: _full, watched: _watched, gate: FullWalletGate.locked),
    );
    await tester.tap(find.byKey(const Key('compute-home-stop-i1')));
    await tester.pumpAndSettle();
    expect(wallets.unlocked, ['w1']);
    expect(run.stops, isEmpty);
  });

  testWidgets('with no full wallet the stop is off, with the message', (tester) async {
    final run = await pump(
      tester,
      money: const WalletMoney(
        full: WalletSum.empty,
        watched: _watched,
        gate: FullWalletGate.none,
      ),
    );
    expect(find.byKey(const Key('compute-home-no-full-wallet')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('compute-home-stop-i1'))).onPressed,
      isNull,
    );
    expect(run.stops, isEmpty);
  });

  test('the compute home is the default home screen; the setting turns it off', () async {
    SharedPreferences.setMockInitialValues({});
    final flag = ComputeHomeFlag();
    expect(flag.value, isTrue);
    await flag.load();
    expect(flag.value, isTrue);
    await flag.set(false);
    final again = ComputeHomeFlag();
    await again.load();
    expect(again.value, isFalse);
  });

  group('sums and USD', () {
    test('a sum over nodes is exact, "at least", or unknown', () {
      final l = appL10n;
      String cores(double? total, double known, int unknown, bool atLeast) => partialSum<double>(
        total: total,
        known: known,
        unknownNodes: unknown,
        atLeast: atLeast,
        format: CelautStrings.cores,
      );
      expect(cores(6, 6, 0, false), CelautStrings.cores(6));
      expect(cores(null, 6, 2, true), l.celautAtLeast(CelautStrings.cores(6), 2));
      expect(cores(null, 6, 2, true), contains('2 nodes unknown'));
      expect(cores(null, 0, 3, false), l.celautUnknown);
    });

    test('USD from the oracle price, unknown without it', () {
      expect(usdOf(BigInt.from(1000000000), 1.5), '\$1.50');
      expect(usdOf(BigInt.from(1234567000000000), 1.0), '\$1,234,567.00');
      expect(usdOf(BigInt.from(1000), 1.0), '< \$0.01');
      expect(usdOf(BigInt.zero, 1.0), '\$0.00');
      expect(usdOf(BigInt.from(1000000000), null), isNull);
      expect(usdOf(BigInt.from(1000000000), 0), isNull);
      expect(usdOf(BigInt.from(1000000000), double.nan), isNull);
      expect(usdOf(null, 1.0), isNull);
      expect(usdTextOf(null, 1.0), appL10n.celautHomeUsdUnknown);
      expect(usdTextOf(BigInt.from(2000000000), 0.5), appL10n.celautHomeUsd('\$1.00'));
    });
  });
}
