import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/wallet_money.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/home/overview_model.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('money of the wallet', () {
    test('the ERG of the wallet', () {
      final money = WalletMoney.of([seedOpen]);
      expect(money.full.count, 1);
      expect(money.full.exactNano, BigInt.from(5000000));
      expect(money.full.text, formatErg(5000000));
    });

    test('no wallet is 0 ERG; an unknown balance is unknown', () {
      final none = WalletMoney.of(const []);
      expect(none.full.count, 0);
      expect(none.full.exactNano, BigInt.zero);
      expect(none.full.text, formatErg(0));
      final unknown = WalletMoney.of([seedLocked]);
      expect(unknown.full.exactNano, isNull);
      expect(unknown.full.text, appL10n.celautUnknown);
    });

    test('start and stop need the wallet open', () {
      expect(WalletMoney.of(const []).gate, FullWalletGate.none);
      expect(WalletMoney.of([seedLocked]).gate, FullWalletGate.locked);
      expect(WalletMoney.of([seedOpen]).gate, FullWalletGate.open);
    });
  });

  group('payer wallets', () {
    test('the wallet is the payer', () {
      final payers = payerWallets([seedLocked]);
      expect(payers.single.walletId, 'w2');
      expect(payers.single.name, 'Spare');
      expect(payers.single.open, isFalse);
      // An unknown balance stays unknown.
      expect(payers.single.balanceNano, isNull);
      expect(payerWallets([seedOpen]).single.open, isTrue);
      expect(payerWallets([seedOpen]).single.balanceNano, 5000000);
    });

    test('no wallet: no payer', () {
      expect(payerWallets(const []), isEmpty);
    });
  });
}
