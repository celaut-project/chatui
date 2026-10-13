import '../format.dart';
import '../l10n/l10n.dart';

/// Amounts on the Celaut screens (`docs/celaut/ui.md`, section 2): always with the unit,
/// and "unknown" for a value that is missing, never 0.

/// An amount of MU with its thousands grouped, as the wallet groups token amounts. Any
/// text that is not a whole number stays as it is.
String groupMu(String mu) {
  if (!RegExp(r'^[0-9]+$').hasMatch(mu)) return mu;
  final buf = StringBuffer();
  for (var i = 0; i < mu.length; i++) {
    if (i > 0 && (mu.length - i) % 3 == 0) buf.write(',');
    buf.write(mu[i]);
  }
  return buf.toString();
}

/// nanoERG as ERG with its unit, or "unknown".
String ergOrUnknown(int? nano) => nano == null ? appL10n.celautUnknown : formatErg(nano);

/// nanoERG as text (from Rust) as ERG with its unit, or "unknown".
String ergTextOrUnknown(String? nano) {
  final n = nano == null ? null : BigInt.tryParse(nano);
  return n == null ? appL10n.celautUnknown : formatNanoErg(n);
}

/// MU as text (from Rust) with its unit, or "unknown" if empty or missing.
String muOrUnknown(String? mu) =>
    mu == null || mu.isEmpty ? appL10n.celautUnknown : '${groupMu(mu)} MU';

/// A sum over nodes (`docs/celaut/ui.md`, section 2): the sum when every node gave the
/// value, "at least X (N nodes unknown)" when some did not, and "unknown" when no node
/// gave it. [format] writes a known value.
String partialSum<T>({
  required T? total,
  required T known,
  required int unknownNodes,
  required bool atLeast,
  required String Function(T value) format,
}) {
  if (total != null) return format(total);
  if (atLeast) return appL10n.celautAtLeast(format(known), unknownNodes);
  return appL10n.celautUnknown;
}

/// The ERG of some wallets: the sum when every balance is known, "at least X (N wallets
/// unknown)" when some are not, and "unknown" when none is known.
String walletsSum({required int knownNano, required int unknown, required int count}) {
  if (count == 0) return formatErg(0);
  if (unknown == 0) return formatErg(knownNano);
  if (unknown < count) return appL10n.celautAtLeastWallets(formatErg(knownNano), unknown);
  return appL10n.celautUnknown;
}

/// The USD value of [nanoErg] at [usdPerErg] (the oracle pool price), as "$1,234.56",
/// or with two significant digits under one cent ("$0.0054").
/// Null if the amount or the price is not known: the screen then says "USD unknown",
/// never $0.
String? usdOf(BigInt? nanoErg, double? usdPerErg) {
  if (nanoErg == null || usdPerErg == null || !usdPerErg.isFinite || usdPerErg <= 0) {
    return null;
  }
  final usd = nanoErg.toDouble() / 1e9 * usdPerErg;
  // Less than a cent: two significant digits, so that a small credit is not "\$0.00".
  if (usd > 0 && usd < 0.01) return '\$${usd.toStringAsPrecision(2)}';
  final cents = (usd * 100).round();
  final whole = groupMu('${cents ~/ 100}');
  final rest = (cents % 100).toString().padLeft(2, '0');
  return '\$$whole.$rest';
}

/// [usdOf] as the text of a row: "≈ $1.23", or "USD unknown".
String usdTextOf(BigInt? nanoErg, double? usdPerErg) {
  final usd = usdOf(nanoErg, usdPerErg);
  return usd == null ? appL10n.celautHomeUsdUnknown : appL10n.celautHomeUsd(usd);
}

/// nanoERG as text (from Rust), or null.
BigInt? nanoOf(String? text) => text == null ? null : BigInt.tryParse(text);
