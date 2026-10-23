import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/auto_top_up.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/celaut/auto_top_up_screen.dart';
import 'package:argus_wallet/ui/celaut/chats_screen.dart';
import 'package:argus_wallet/ui/celaut/instance_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The automatic top-up (Josemi, 2026-10-23): off by default; it moves credit that the app
// already has on a node to an instance (ModifyDeposit), and never pays a node by itself.

InstanceListView _instance(String id, {int? stoppedAt}) => InstanceListView(
      instanceId: id,
      peerId: 'aa' * 32,
      address: 'node.example:53460',
      serviceId: '65' * 32,
      slots: Uint16List.fromList([8080]),
      chatSlots: Uint16List.fromList([8080]),
      startedAt: 1,
      startChargeMu: '1000',
      name: 'Echo chat',
      alias: '',
      stoppedAt: stoppedAt,
      refundMu: '',
    );

InstanceStatusView _balance(String mu) =>
    InstanceStatusView(instanceBalanceMu: mu, costSoFarMu: '1', streamsOpened: BigInt.zero);

class _Wallets implements FullWallets {
  _Wallets({required this.unlocks});

  final bool unlocks;
  int asked = 0;

  @override
  Future<List<PayerWallet>> payers() async =>
      [const PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 1, open: false)];

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async {
    asked++;
    return unlocks;
  }
}

void main() {
  late List<String> topUps;
  late List<InstanceListView> db;
  late Map<String, String> balances;
  late Object? topUpError;
  late DateTime clock;

  AutoTopUp engine() => AutoTopUp(
        topUp: (id, mu) async {
          topUps.add('$id $mu');
          final e = topUpError;
          if (e != null) throw e;
          return const TopUpView(instanceBalanceMu: '1200000', clientBalanceMu: '3000000');
        },
        instances: () => db,
        status: (id) async => _balance(balances[id]!),
        now: () => clock,
        periodic: false,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    topUps = [];
    db = [];
    balances = {};
    topUpError = null;
    clock = DateTime(2026, 10, 23, 12);
  });

  group('the engine', () {
    test('is off by default, and then moves nothing', () async {
      final e = engine();
      await e.load();
      expect(e.on, isFalse);
      expect(e.threshold, BigInt.from(200000));
      expect(e.amount, BigInt.from(1000000));
      db = [_instance('i1')];
      balances['i1'] = '10';
      await e.check();
      expect(topUps, isEmpty);
    });

    test('on, it tops up a running instance under the threshold, once a minute at most', () async {
      final e = engine();
      await e.save(on: true, threshold: BigInt.from(300000), amount: BigInt.from(500000));
      db = [_instance('low'), _instance('high'), _instance('old', stoppedAt: 5)];
      balances.addAll({'low': '299999', 'high': '300000', 'old': '0'});
      await e.check();
      expect(topUps, ['low 500000']);
      // Still low a moment later: it waits.
      await e.check();
      expect(topUps, ['low 500000']);
      clock = clock.add(const Duration(minutes: 1, seconds: 1));
      await e.check();
      expect(topUps, ['low 500000', 'low 500000']);
      e.dispose();
    });

    test('with too little credit on the node it pays nothing and asks the user', () async {
      final e = engine();
      await e.save(on: true, threshold: BigInt.from(300000), amount: BigInt.from(500000));
      topUpError = const CelautError(
        kind: CelautErrorKind.insufficientCredit,
        message: 'credit 100 MU, top-up 500000 MU',
      );
      db = [_instance('low')];
      balances['low'] = '5';
      await e.check();
      expect(e.need?.instanceId, 'low');
      expect(e.need?.address, 'node.example:53460');
      // It waits ten minutes before it tries again.
      clock = clock.add(const Duration(minutes: 5));
      await e.check();
      expect(topUps, hasLength(1));
      e.dismissNeed();
      expect(e.need, isNull);
      e.dispose();
    });

    test('the settings are kept, and bad kept values give the defaults', () async {
      final e = engine();
      await e.save(on: true, threshold: BigInt.from(250000), amount: BigInt.from(750000));
      e.dispose();
      final again = engine();
      await again.load();
      expect((again.on, again.threshold, again.amount), (true, BigInt.from(250000), BigInt.from(750000)));
      again.dispose();
      SharedPreferences.setMockInitialValues({
        AutoTopUp.keyOn: true,
        AutoTopUp.keyThreshold: '1',
        AutoTopUp.keyAmount: '999999999999',
      });
      final bad = engine();
      await bad.load();
      expect((bad.threshold, bad.amount), (AutoTopUp.defaultThreshold, AutoTopUp.defaultAmount));
      bad.dispose();
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester, AutoTopUp e, _Wallets wallets) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: argusTheme(watchful: false),
          home: AutoTopUpScreen(topUp: e, wallets: wallets),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('turning it on needs the wallet; off it moves nothing', (tester) async {
      final e = engine();
      addTearDown(e.dispose);
      final refused = _Wallets(unlocks: false);
      await pump(tester, e, refused);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('top-up-switch'))).value, isFalse);
      expect(find.text(appL10n.celautTopUpNote), findsOneWidget);
      await tester.tap(find.byKey(const Key('top-up-switch')));
      await tester.pumpAndSettle();
      expect(refused.asked, 1);
      expect(e.on, isFalse);
      expect(find.text(appL10n.celautOpenFullWalletNeeded), findsOneWidget);
    });

    testWidgets('with the wallet open it turns on with the threshold and the amount', (tester) async {
      final e = engine();
      addTearDown(e.dispose);
      await pump(tester, e, _Wallets(unlocks: true));
      await tester.enterText(find.byKey(const Key('top-up-threshold')), '400000');
      await tester.enterText(find.byKey(const Key('top-up-amount')), '2000000');
      await tester.tap(find.byKey(const Key('top-up-switch')));
      await tester.pumpAndSettle();
      expect((e.on, e.threshold, e.amount), (true, BigInt.from(400000), BigInt.from(2000000)));
      // A value out of its limits is refused and kept out.
      await tester.enterText(find.byKey(const Key('top-up-amount')), '99999999');
      await tester.pump();
      expect(find.text(appL10n.celautTopUpRange('10,000 MU', '10,000,000 MU')), findsOneWidget);
      await tester.tap(find.byKey(const Key('top-up-save')));
      await tester.pumpAndSettle();
      expect(e.amount, BigInt.from(2000000));
    });
  });

  testWidgets('a top-up that needs a deposit shows on the list, and Deposit opens the deposit', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.argus.wallet/secure_storage'),
      (call) async => null,
    );
    final e = engine();
    addTearDown(e.dispose);
    await e.save(on: true, threshold: BigInt.from(300000), amount: BigInt.from(500000));
    topUpError = const CelautError(kind: CelautErrorKind.insufficientCredit, message: 'credit 1 MU');
    db = [_instance('low')];
    balances['low'] = '5';
    var deposits = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: argusTheme(watchful: false),
        home: ChatsScreen(
          topUp: e,
          openDeposit: () => deposits++,
          list: (key, empty) => InstanceList(
            key: key,
            chats: true,
            load: () => db,
            loadStatus: (id) async => _balance(balances[id]!),
            topUp: e,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The list read the balance: under the threshold, and the credit is too low.
    expect(topUps, ['low 500000']);
    expect(find.byKey(const Key('top-up-need')), findsOneWidget);
    expect(find.text(appL10n.celautTopUpNeed('node.example:53460', '500,000 MU')), findsOneWidget);
    await tester.tap(find.byKey(const Key('top-up-need-deposit')));
    await tester.pumpAndSettle();
    expect(deposits, 1);
    expect(find.byKey(const Key('top-up-need')), findsNothing);
  });
}
