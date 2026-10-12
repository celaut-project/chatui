import '../format.dart';
import '../l10n/l10n.dart';
import 'wallet_service.dart';

/// What a hand-picked set of boxes covers, and what spending it together
/// would reveal.
///
/// Spending two boxes in one transaction tells any observer that the same
/// wallet controls both. That is the cost coin control exists to let the
/// user weigh, so the summary states it plainly rather than only reporting
/// whether the amount is covered.
class CoinSelection {
  const CoinSelection({
    required this.boxes,
    required this.totalNanoErg,
    required this.tokens,
    required this.addresses,
    this.unconfirmedCount = 0,
  });

  /// How many of the chosen boxes a transaction still in the mempool
  /// created. Offered only while Settings allows spending unconfirmed funds.
  final int unconfirmedCount;

  final List<InputBoxInput> boxes;
  final int totalNanoErg;

  /// token id → amount across the chosen boxes.
  final Map<String, BigInt> tokens;

  /// Distinct addresses the chosen boxes sit on.
  final Set<String> addresses;

  bool get isEmpty => boxes.isEmpty;
  int get count => boxes.length;

  /// True when the choice would publicly link addresses that are not
  /// otherwise known to belong together.
  bool get linksAddresses => addresses.length > 1;
}

CoinSelection summariseSelection(
  List<InputBoxInput> all,
  Set<String> selectedIds,
) {
  final chosen = [for (final b in all) if (selectedIds.contains(b.boxId)) b];
  var total = 0;
  final tokens = <String, BigInt>{};
  final addresses = <String>{};
  for (final b in chosen) {
    total += b.valueNanoErg.toInt();
    final a = b.address;
    if (a != null && a.isNotEmpty) addresses.add(a);
    for (final asset in b.assets) {
      tokens[asset.tokenId] = (tokens[asset.tokenId] ?? BigInt.zero) + asset.amount;
    }
  }
  return CoinSelection(
    boxes: chosen,
    totalNanoErg: total,
    tokens: tokens,
    addresses: addresses,
    unconfirmedCount: chosen.where((b) => !b.confirmed).length,
  );
}

/// Whether [selection] can pay [amountNanoErg] plus fees, and how much is
/// left for change. Mirrors the Rust `select_exact` requirement so the user
/// is told before building rather than by a failed prepare.
class CoinSelectionCheck {
  const CoinSelectionCheck({
    required this.covers,
    required this.shortfallNano,
    required this.changeNano,
  });

  final bool covers;
  final int shortfallNano;
  final int changeNano;
}

CoinSelectionCheck checkSelection({
  required CoinSelection selection,
  required int amountNanoErg,
  required int feeNanoErg,
  int minBoxNano = 1000000,
}) {
  final needed = amountNanoErg + feeNanoErg + minBoxNano;
  final have = selection.totalNanoErg;
  return CoinSelectionCheck(
    covers: have >= needed,
    shortfallNano: have >= needed ? 0 : needed - have,
    changeNano: have >= needed ? have - amountNanoErg - feeNanoErg : 0,
  );
}

/// One line describing the privacy cost of a selection, or null when there
/// is nothing to warn about.
String? selectionPrivacyNote(CoinSelection selection) {
  if (selection.count < 2) return null;
  if (!selection.linksAddresses) return null;
  return appL10n.coinPrivacyNote(
    '${selection.count}',
    '${selection.addresses.length}',
  );
}

/// One line for a selection that spends boxes still confirming, or null.
/// Spending them is allowed in Settings; the cost is that this transaction
/// can confirm only after the one that created them, and fails with it if
/// that one is dropped.
String? selectionConfirmationNote(CoinSelection selection) {
  final n = selection.unconfirmedCount;
  if (n == 0) return null;
  return appL10n.coinConfirmationNote(n);
}

/// Human summary of what the chosen boxes hold.
String selectionSummary(CoinSelection selection) {
  if (selection.isEmpty) return appL10n.coinSelectionNone;
  final parts = <String>[
    appL10n.utxoBoxCount(selection.count),
    formatErg(selection.totalNanoErg, maxFrac: 4),
  ];
  if (selection.tokens.isNotEmpty) {
    parts.add(appL10n.utxoTokenCount(selection.tokens.length));
  }
  return parts.join(' · ');
}
