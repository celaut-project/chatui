import '../ui/home/overview_model.dart';
import 'celaut_format.dart';
import 'payers.dart';

/// The ERG of some wallets. A wallet whose balance the app does not know is counted in
/// [unknown], never as 0.
class WalletSum {
  const WalletSum({required this.count, required this.unknown, required this.knownNano});

  static const empty = WalletSum(count: 0, unknown: 0, knownNano: 0);

  /// How many wallets.
  final int count;

  /// How many of them have a balance that the app does not know.
  final int unknown;

  /// The sum of the known balances, in nanoERG.
  final int knownNano;

  /// The exact sum, or null if a balance is unknown. No wallet is 0 ERG.
  BigInt? get exactNano => unknown == 0 ? BigInt.from(knownNano) : null;

  /// The sum as the screen shows it: exact, "at least …", or "unknown".
  String get text => walletsSum(knownNano: knownNano, unknown: unknown, count: count);

  WalletSum plus(int? balanceNano) => WalletSum(
    count: count + 1,
    unknown: unknown + (balanceNano == null ? 1 : 0),
    knownNano: knownNano + (balanceNano ?? 0),
  );
}

/// The money of the wallet for the compute home (`docs/celaut/ui.md`, section 2): the
/// ERG of the wallet of the app, which pays for compute.
class WalletMoney {
  const WalletMoney({required this.full, required this.gate});

  static const none = WalletMoney(full: WalletSum.empty, gate: FullWalletGate.none);

  /// The wallet (a seed on this device).
  final WalletSum full;

  /// Whether start and stop can run: no wallet, a locked one, or an open one.
  final FullWalletGate gate;

  factory WalletMoney.of(Iterable<OverviewEntry> entries) {
    var full = WalletSum.empty;
    for (final e in entries) {
      full = full.plus(e.balanceNano);
    }
    return WalletMoney(full: full, gate: fullWalletGate(payerWallets(entries)));
  }
}
