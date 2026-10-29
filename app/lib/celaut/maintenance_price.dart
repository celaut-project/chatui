import 'dart:math';

/// What a node charges to keep an instance (Josemi, 2026-10-29): the node takes
/// [perPeriodMu] once each [periodSeconds], with a margin of [variance] for the difference
/// of the real cost (`cost * (1 + variance)`, as nodo's `variance_cost_normalization`).
/// It turns time into MU and back, for the start balance, "Add time" and "keep running".
class MaintenancePrice {
  const MaintenancePrice._(this.withMargin, this.periodSeconds);

  /// The price of one period with the margin, in MU, rounded up.
  final BigInt withMargin;
  final int periodSeconds;

  /// The price from the numbers of a quote or of the record of an instance; null if they
  /// give no price.
  static MaintenancePrice? of({
    required String perPeriodMu,
    required int periodSeconds,
    required num variance,
  }) {
    final perPeriod = BigInt.tryParse(perPeriodMu);
    if (periodSeconds <= 0 || perPeriod == null || perPeriod <= BigInt.zero) return null;
    final margin = 1 + max(0.0, variance.toDouble());
    return MaintenancePrice._(BigInt.from((perPeriod.toDouble() * margin).ceil()), periodSeconds);
  }

  int _periods(Duration time) {
    final seconds = time.inSeconds < 0 ? 0 : time.inSeconds;
    return (seconds + periodSeconds - 1) ~/ periodSeconds;
  }

  /// The balance that keeps a new instance for at least [time]: the periods in [time], plus
  /// one for the period that runs at the end (the node charges one at the start).
  BigInt balanceFor(Duration time) => withMargin * BigInt.from(_periods(time) + 1);

  /// The MU to add to a running instance so that it lasts [time] longer.
  BigInt addFor(Duration time) => withMargin * BigInt.from(_periods(time));

  /// How long the balance [balanceMu] keeps an instance, the inverse of [balanceFor].
  Duration lasts(BigInt balanceMu) {
    final periods = balanceMu ~/ withMargin - BigInt.one;
    if (periods <= BigInt.zero) return Duration.zero;
    return Duration(seconds: periods.toInt() * periodSeconds);
  }
}
