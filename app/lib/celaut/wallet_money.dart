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

/// The money of the wallets for the compute home (`docs/celaut/ui.md`, section 2): the
/// ERG of the full wallets, which can pay for compute, and the ERG of the watched
/// addresses and accounts, which cannot. They are two figures and are never added.
class WalletMoney {
  const WalletMoney({required this.full, required this.watched, required this.gate});

  static const none = WalletMoney(
    full: WalletSum.empty,
    watched: WalletSum.empty,
    gate: FullWalletGate.none,
  );

  /// The full wallets (a seed on this device).
  final WalletSum full;

  /// The watched addresses and the watched accounts.
  final WalletSum watched;

  /// Whether start and stop can run: no full wallet, only locked ones, or an open one.
  final FullWalletGate gate;

  factory WalletMoney.of(Iterable<OverviewEntry> entries) {
    var full = WalletSum.empty;
    var watched = WalletSum.empty;
    for (final e in entries) {
      if (e.ref.kind == WalletKind.seed) {
        full = full.plus(e.balanceNano);
      } else {
        watched = watched.plus(e.balanceNano);
      }
    }
    return WalletMoney(
      full: full,
      watched: watched,
      gate: fullWalletGate(payerWallets(entries)),
    );
  }
}
