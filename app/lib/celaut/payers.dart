import 'package:flutter/widgets.dart';

import '../ui/home/overview_model.dart';
import 'wallet_unlock.dart';

/// The wallet that pays a node: the wallet of the app, with its seed on this device
/// (`docs/celaut/ui.md`, section 1).
class PayerWallet {
  const PayerWallet({
    required this.walletId,
    required this.name,
    required this.balanceNano,
    required this.open,
  });

  final String walletId;
  final String name;

  /// What the wallet holds, in nanoERG; null if the app does not know it.
  final int? balanceNano;

  /// True if the wallet is open (its key is in memory now). Only an open wallet can
  /// sign, so the user opens the chosen wallet before the deposit.
  final bool open;

  @override
  bool operator ==(Object other) =>
      other is PayerWallet &&
      other.walletId == walletId &&
      other.name == name &&
      other.balanceNano == balanceNano &&
      other.open == open;

  @override
  int get hashCode => Object.hash(walletId, name, balanceNano, open);
}

/// The wallets of [entries] that can pay, in their order: the wallet of the app, if any.
List<PayerWallet> payerWallets(Iterable<OverviewEntry> entries) => [
  for (final e in entries)
    PayerWallet(
      walletId: e.ref.id,
      name: e.name,
      balanceNano: e.balanceNano,
      open: e.state == OverviewRowState.unlocked,
    ),
];

/// The full wallets of the app, for the Celaut screens. The app uses [AppFullWallets];
/// tests give their own.
abstract class FullWallets {
  /// The full wallets of the app, in the order of the wallets list.
  Future<List<PayerWallet>> payers();

  /// Ask for the fingerprint or the screen lock for [wallet] and open it. True if it is open
  /// after that.
  Future<bool> unlock(BuildContext context, PayerWallet wallet);
}

/// The full wallets of the app, from the wallets list.
class AppFullWallets implements FullWallets {
  const AppFullWallets();

  @override
  Future<List<PayerWallet>> payers() async {
    final model = WalletsOverviewModel();
    try {
      await model.loadWallets();
      return payerWallets(model.entries());
    } finally {
      model.dispose();
    }
  }

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) =>
      unlockFullWallet(context, walletId: wallet.walletId, name: wallet.name);
}

/// What start and stop can do (`docs/celaut/ui.md`, section 1): they need a full
/// wallet that is open, not only one that exists.
enum FullWalletGate {
  /// The app has no full wallet: start and stop are off.
  none,

  /// The app has full wallets, but none is open: the action asks to open one first.
  locked,

  /// A full wallet is open.
  open,
}

FullWalletGate fullWalletGate(List<PayerWallet> payers) {
  if (payers.isEmpty) return FullWalletGate.none;
  return payers.any((p) => p.open) ? FullWalletGate.open : FullWalletGate.locked;
}

/// Before a start or a stop: true if the wallet is open. If it is locked, ask the phone to unlock it
/// or its fingerprint and open it. False if the app has no wallet or the user did not
/// open it.
Future<bool> ensureOpenFullWallet(BuildContext context, FullWallets wallets) async {
  final payers = await wallets.payers();
  switch (fullWalletGate(payers)) {
    case FullWalletGate.none:
      return false;
    case FullWalletGate.open:
      return true;
    case FullWalletGate.locked:
      if (!context.mounted) return false;
      return wallets.unlock(context, payers.first);
  }
}
