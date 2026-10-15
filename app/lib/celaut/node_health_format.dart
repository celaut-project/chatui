import '../l10n/l10n.dart';

/// "N s", "N min", "N h" or "N d" for a time of [seconds] ago: seconds under a minute,
/// minutes under an hour, hours under 48, else days. A negative time is 0.
String agoText(AppLocalizations l, int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) return l.celautAgoSeconds('$s');
  if (s < 3600) return l.celautAgoMinutes('${s ~/ 60}');
  if (s < 48 * 3600) return l.celautAgoHours('${s ~/ 3600}');
  return l.celautAgoDays('${s ~/ 86400}');
}
