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
