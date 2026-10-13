import 'package:shared_preferences/shared_preferences.dart';

import '../ui/home/overview_model.dart';

/// A wallet that can pay a node: a full wallet, with its seed on this device
/// (`docs/celaut/ui.md`, section 1). Read-only (watched) wallets cannot sign, so they are
/// never payers.
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

/// The wallets that can pay: the full wallets of [entries], in their order. Watched
/// addresses and watched accounts are left out.
List<PayerWallet> payerWallets(Iterable<OverviewEntry> entries) => [
  for (final e in entries)
    if (e.ref.kind == WalletKind.seed)
      PayerWallet(
        walletId: e.ref.id,
        name: e.name,
        balanceNano: e.balanceNano,
        open: e.state == OverviewRowState.unlocked,
      ),
];

/// The payer to show first: the one the user chose on this screen, else the saved
/// default, else the open wallet, else the first. Null if there is no full wallet. An
/// id that is not a full wallet (removed, or read-only) is not used.
PayerWallet? choosePayer(List<PayerWallet> payers, {String? chosenId, String? defaultId}) {
  PayerWallet? find(String? id) {
    if (id == null) return null;
    for (final p in payers) {
      if (p.walletId == id) return p;
    }
    return null;
  }

  final picked = find(chosenId) ?? find(defaultId);
  if (picked != null) return picked;
  for (final p in payers) {
    if (p.open) return p;
  }
  return payers.isEmpty ? null : payers.first;
}

/// The default payer, saved in the settings. It is a wallet id only: no secret.
class DefaultPayerStore {
  const DefaultPayerStore();

  static const key = 'celaut_default_payer_v1';

  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> save(String? walletId) async {
    final prefs = await SharedPreferences.getInstance();
    if (walletId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, walletId);
    }
  }
}
