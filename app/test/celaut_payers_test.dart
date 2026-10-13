import 'package:argus_wallet/celaut/deposit_strings.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/wallet_money.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/default_payer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:argus_wallet/ui/home/overview_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const seedOpen = OverviewEntry(
    ref: WalletRef.seed('w1'),
    name: 'Main',
    state: OverviewRowState.unlocked,
    balanceNano: 5000000,
  );
  const seedLocked = OverviewEntry(
    ref: WalletRef.seed('w2'),
    name: 'Spare',
    state: OverviewRowState.locked,
  );
  const watchedAddress = OverviewEntry(
    ref: WalletRef.watchedAddress('9fWatched'),
    name: 'Cold',
    state: OverviewRowState.watched,
    balanceNano: 900000000,
  );
  const watchedAccount = OverviewEntry(
    ref: WalletRef.watchedAccount('xpub-key'),
    name: 'Ledger',
    state: OverviewRowState.watched,
    balanceNano: 100,
  );

  group('money of the wallets', () {
    test('full wallets and watched wallets are two separate figures', () {
      final money = WalletMoney.of([watchedAddress, seedLocked, watchedAccount, seedOpen]);
      // Full: Main (5000000) and Spare (unknown balance).
      expect(money.full.count, 2);
      expect(money.full.unknown, 1);
      expect(money.full.knownNano, 5000000);
      expect(money.full.exactNano, isNull);
      expect(money.full.text, appL10n.celautAtLeastWallets(formatErg(5000000), 1));
      // Watched: the address and the account, never added to the full wallets.
      expect(money.watched.count, 2);
      expect(money.watched.exactNano, BigInt.from(900000100));
      expect(money.watched.text, formatErg(900000100));
    });

    test('no wallet of a kind is 0 ERG; all unknown is unknown', () {
      final money = WalletMoney.of([watchedAddress]);
      expect(money.full.count, 0);
      expect(money.full.exactNano, BigInt.zero);
      expect(money.full.text, formatErg(0));
      final unknown = WalletMoney.of([seedLocked]);
      expect(unknown.full.text, appL10n.celautUnknown);
    });

    test('start and stop need an open full wallet', () {
      expect(WalletMoney.of([watchedAddress, watchedAccount]).gate, FullWalletGate.none);
      expect(WalletMoney.of([seedLocked, watchedAddress]).gate, FullWalletGate.locked);
      expect(WalletMoney.of([seedLocked, seedOpen]).gate, FullWalletGate.open);
    });
  });

  group('payer wallets', () {
    test('only full wallets are offered as payers', () {
      final payers = payerWallets([watchedAddress, seedLocked, watchedAccount, seedOpen]);
      expect(payers.map((p) => p.walletId), ['w2', 'w1']);
      expect(payers.map((p) => p.name), ['Spare', 'Main']);
      expect(payers[0].open, isFalse);
      expect(payers[1].open, isTrue);
      // An unknown balance stays unknown.
      expect(payers[0].balanceNano, isNull);
      expect(payers[1].balanceNano, 5000000);
    });

    test('read-only wallets only: no payer', () {
      expect(payerWallets([watchedAddress, watchedAccount]), isEmpty);
      expect(choosePayer(payerWallets([watchedAddress])), isNull);
    });

    test('the choice of the user, then the default, then the open wallet, then the first', () {
      final payers = payerWallets([seedLocked, seedOpen]);
      expect(choosePayer(payers)!.walletId, 'w1');
      expect(choosePayer(payers, defaultId: 'w2')!.walletId, 'w2');
      expect(choosePayer(payers, chosenId: 'w1', defaultId: 'w2')!.walletId, 'w1');
      // A saved id that is not a full wallet (removed, or read-only) is not used.
      expect(choosePayer(payers, defaultId: '9fWatched')!.walletId, 'w1');
      expect(choosePayer(payerWallets([seedLocked]))!.walletId, 'w2');
    });
  });

  testWidgets('the default payer dialog offers only full wallets and saves one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final payers = payerWallets([watchedAddress, seedLocked, seedOpen]);
    await tester.pumpWidget(
      _Host((ctx) => showDefaultPayerDialog(ctx, payers: payers, current: null)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cold'), findsNothing);
    expect(find.byKey(const Key('default-payer-w1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('default-payer-w2')));
    await tester.pumpAndSettle();
    expect(await const DefaultPayerStore().load(), 'w2');
  });

  testWidgets('with no full wallet the default payer dialog says so', (tester) async {
    await tester.pumpWidget(
      _Host((ctx) => showDefaultPayerDialog(ctx, payers: const [], current: null)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(DepositStrings.noFullWallet), findsOneWidget);
  });

  test('the default payer is saved in the settings', () async {
    SharedPreferences.setMockInitialValues({});
    const store = DefaultPayerStore();
    expect(await store.load(), isNull);
    await store.save('w2');
    expect(await store.load(), 'w2');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DefaultPayerStore.key), 'w2');
    await store.save(null);
    expect(await store.load(), isNull);
  });
}

class _Host extends StatelessWidget {
  const _Host(this.onTap);
  final Future<void> Function(BuildContext) onTap;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (ctx) => TextButton(onPressed: () => onTap(ctx), child: const Text('open')),
    ),
  );
}
