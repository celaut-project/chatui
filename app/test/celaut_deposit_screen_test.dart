import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_deposit.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/celaut/deposit_strings.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/ui/celaut/deposit_confirm.dart';
import 'package:argus_wallet/ui/celaut/deposit_screen.dart';
import 'package:argus_wallet/ui/confirm_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _peer = 'ab' * 32;
const _address = '9fRAWhdxEsTcdb8PhGNrZfwqa65zfkuYHAMmkQLcic1gdLSV5vA';
final _tx = '7c' * 32;

DepositPreparedView _prepared({int amount = 10000000, String mu = '10000000'}) =>
    DepositPreparedView(
      depositId: 'dep-1',
      preparationId: BigInt.from(42),
      peerId: _peer,
      payToAddress: _address,
      amountNanoErg: BigInt.from(amount),
      amountMu: mu,
      muPerNanoErg: '1',
      minerFeeNanoErg: 1100000,
      changeNanoErg: 88900000,
      inputCount: 1,
      boxId: 'b0' * 32,
      limitNanoErg: BigInt.from(50000000),
      depositedNanoErg: BigInt.from(amount),
      tokenSeconds: 3600,
    );

class DepositApi extends RustLibApi {
  final nodeCalls = <NodeAddress>[];
  final limits = <({String peer, BigInt limit})>[];
  final cancels = <String>[];
  final notifies = <({String deposit, String tx})>[];
  final notifyAnswers = <Object>[];
  String balance = '4500000';

  @override
  Future<DepositNodeView> crateApiCelautDepositCelautDepositNode({
    required NodeAddress node,
  }) async {
    nodeCalls.add(node);
    return DepositNodeView(
      peerId: _peer,
      payToAddress: _address,
      muPerNanoErg: '1',
      clientBalanceMu: balance,
      limitNanoErg: limits.isEmpty ? BigInt.from(50000000) : limits.last.limit,
      depositedNanoErg: BigInt.zero,
    );
  }

  @override
  Future<void> crateApiCelautDepositCelautSetDepositLimit({
    required String peerId,
    required BigInt limitNanoErg,
  }) async =>
      limits.add((peer: peerId, limit: limitNanoErg));

  @override
  Future<void> crateApiCelautDepositCelautDepositCancel({required String depositId}) async =>
      cancels.add(depositId);

  @override
  Future<DepositDoneView> crateApiCelautDepositCelautDepositNotify({
    required String depositId,
    required String txId,
    String? explorerUrl,
  }) async {
    notifies.add((deposit: depositId, tx: txId));
    final a = notifyAnswers.removeAt(0);
    if (a is CelautError) throw a;
    return a as DepositDoneView;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWallet implements DepositWallet {
  String? cannot;
  final prepares = <({NodeAddress node, int amount})>[];
  final sends = <int>[];

  @override
  String? cannotSign(BuildContext context) => cannot;

  @override
  Future<DepositPreparedView> prepare(
    BuildContext context,
    NodeAddress node,
    int amountNanoErg,
  ) async {
    prepares.add((node: node, amount: amountNanoErg));
    return _prepared(amount: amountNanoErg, mu: '$amountNanoErg');
  }

  @override
  Future<String> send(int preparationId) async {
    sends.add(preparationId);
    return _tx;
  }
}

DepositDoneView _done({bool accepted = true}) => DepositDoneView(
      depositId: 'dep-1',
      txId: _tx,
      boxId: 'b0' * 32,
      accepted: accepted,
      nodeMessage: accepted ? null : 'Error: payment not valid.',
      clientBalanceMu: accepted ? '14500000' : '4500000',
    );

void main() {
  final api = DepositApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.nodeCalls.clear();
    api.limits.clear();
    api.cancels.clear();
    api.notifies.clear();
    api.notifyAnswers.clear();
  });

  group('confirmation sheet', () {
    Widget host(void Function(ConfirmChoice) onResult) => MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => onResult(await showDepositConfirmation(ctx, _prepared())),
              child: const Text('open'),
            ),
          ),
        );

    testWidgets('shows the ERG, the MU that it buys, the fee and the limit', (tester) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ConfirmChoice? result;
      await tester.pumpWidget(host((r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(DepositStrings.confirmTitle), findsOneWidget);
      expect(find.text(formatErg(10000000)), findsOneWidget);
      expect(find.text('10,000,000 MU'), findsOneWidget);
      expect(find.text(DepositStrings.rate('1')), findsOneWidget);
      expect(find.text(formatErg(1100000)), findsOneWidget);
      expect(find.text(formatErg(11100000)), findsOneWidget);
      expect(
        find.text(DepositStrings.used(formatErg(10000000), formatErg(50000000))),
        findsOneWidget,
      );
      expect(find.text(_address), findsOneWidget);
      expect(find.text(DepositStrings.confirmDetail(60)), findsOneWidget);
      // No "sign only": the app must follow the transaction to tell the node.
      expect(find.text('Sign only'), findsNothing);

      await tester.tap(find.text(DepositStrings.confirmLabel));
      await tester.pumpAndSettle();
      expect(result, ConfirmChoice.broadcast);
    });

    test('MU are grouped like token amounts', () {
      expect(groupMu('0'), '0');
      expect(groupMu('999'), '999');
      expect(groupMu('1000'), '1,000');
      expect(groupMu('14500000'), '14,500,000');
      expect(groupMu('n/a'), 'n/a');
    });
  });

  group('deposit screen', () {
    late FakeWallet wallet;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      wallet = FakeWallet();
      await tester.pumpWidget(MaterialApp(home: DepositScreen(wallet: wallet)));
    }

    Future<void> check(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('deposit-node')), '127.0.0.1:18460');
      await tester.tap(find.byKey(const Key('deposit-check')));
      await tester.pumpAndSettle();
    }

    testWidgets('checks the node, deposits, waits for the box and shows the balance',
        (tester) async {
      await pump(tester);
      await check(tester);
      expect(api.nodeCalls.single, const NodeAddress(host: '127.0.0.1', port: 18460));
      expect(find.text(DepositStrings.payTo(_address)), findsOneWidget);
      expect(find.text(DepositStrings.balance('4,500,000')), findsOneWidget);

      api.notifyAnswers.add(_done());
      await tester.tap(find.byKey(const Key('deposit-prepare')));
      await tester.pumpAndSettle();
      expect(wallet.prepares.single.amount, 10000000);
      expect(find.text('10,000,000 MU'), findsOneWidget);

      await tester.tap(find.text(DepositStrings.confirmLabel));
      await tester.pumpAndSettle();
      expect(wallet.sends.single, 42);
      expect(api.notifies.single, (deposit: 'dep-1', tx: _tx));
      expect(api.cancels, isEmpty);
      expect(find.text(DepositStrings.accepted('14,500,000')), findsOneWidget);
      expect(find.text(DepositStrings.tx(_tx)), findsOneWidget);
    });

    testWidgets('a cancelled confirmation gives the deposit back', (tester) async {
      await pump(tester);
      await check(tester);
      await tester.enterText(find.byKey(const Key('deposit-amount')), '0.002');
      await tester.tap(find.byKey(const Key('deposit-prepare')));
      await tester.pumpAndSettle();
      expect(wallet.prepares.single.amount, 2000000);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.cancels.single, 'dep-1');
      expect(wallet.sends, isEmpty);
      expect(api.notifies, isEmpty);
      expect(find.text(DepositStrings.cancelled), findsOneWidget);
    });

    testWidgets('a box that is late can be waited for again; a refusal is shown',
        (tester) async {
      await pump(tester);
      await check(tester);
      api.notifyAnswers.addAll([
        CelautError(kind: CelautErrorKind.timeout, message: 'the explorer does not show it'),
        _done(accepted: false),
      ]);
      await tester.tap(find.byKey(const Key('deposit-prepare')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DepositStrings.confirmLabel));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposit-error')), findsOneWidget);
      expect(find.byKey(const Key('deposit-wait-again')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deposit-wait-again')));
      await tester.pumpAndSettle();
      expect(api.notifies.length, 2);
      expect(api.notifies.last, (deposit: 'dep-1', tx: _tx));
      expect(wallet.sends.length, 1);
      expect(find.text(DepositStrings.refused('Error: payment not valid.')), findsOneWidget);
      expect(find.byKey(const Key('deposit-wait-again')), findsNothing);
    });

    testWidgets('bad amounts and a wallet that cannot sign prepare nothing', (tester) async {
      await pump(tester);
      await check(tester);
      for (final bad in ['', '0.0005', 'lots']) {
        await tester.enterText(find.byKey(const Key('deposit-amount')), bad);
        await tester.tap(find.byKey(const Key('deposit-prepare')));
        await tester.pumpAndSettle();
        expect(find.text(DepositStrings.amountInvalid), findsOneWidget, reason: bad);
      }
      await tester.enterText(find.byKey(const Key('deposit-amount')), '0.01');
      wallet.cannot = DepositStrings.watchOnly;
      await tester.tap(find.byKey(const Key('deposit-prepare')));
      await tester.pumpAndSettle();
      expect(find.text(DepositStrings.watchOnly), findsOneWidget);
      expect(wallet.prepares, isEmpty);
    });

    testWidgets('the limit of the node is set in ERG', (tester) async {
      await pump(tester);
      await check(tester);
      await tester.enterText(find.byKey(const Key('deposit-limit')), '0.02');
      await tester.tap(find.byKey(const Key('deposit-set-limit')));
      await tester.pumpAndSettle();
      expect(api.limits.single, (peer: _peer, limit: BigInt.from(20000000)));
      expect(api.nodeCalls.length, 2);
      expect(
        find.text(DepositStrings.used(formatErg(0), formatErg(20000000))),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('deposit-limit')), 'x');
      await tester.tap(find.byKey(const Key('deposit-set-limit')));
      await tester.pumpAndSettle();
      expect(find.text(DepositStrings.limitInvalid), findsOneWidget);
      expect(api.limits.length, 1);
    });

    testWidgets('a bad node address calls nothing', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('deposit-node')), 'node.example');
      await tester.tap(find.byKey(const Key('deposit-check')));
      await tester.pumpAndSettle();
      expect(api.nodeCalls, isEmpty);
      expect(find.byKey(const Key('deposit-prepare')), findsNothing);
    });
  });
}
