/// Validation for issuing a token, shared by the form and its tests.
library;

import '../l10n/l10n.dart';

/// The problem with an issuance as typed, or null when it is fine.
String? issuanceError({
  required String name,
  required String amountText,
  required int decimals,
  required bool nft,
  String contentHashHex = '',
  String url = '',
}) {
  if (name.trim().isEmpty) return appL10n.tokenErrorNoName;
  if (name.trim().length > 64) return appL10n.tokenErrorNameTooLong;
  if (decimals < 0 || decimals > 18) return appL10n.tokenErrorDecimalsRange;
  final amount = parseIssuanceAmount(amountText, decimals);
  if (amount == null) return appL10n.tokenErrorAmountMissing;
  if (amount <= BigInt.zero) return appL10n.tokenErrorAmountZero;
  if (amount > BigInt.parse('9223372036854775807')) return appL10n.tokenErrorAmountTooBig;
  if (nft) {
    if (decimals != 0) return appL10n.nftErrorDecimals;
    if (amount != BigInt.one) return appL10n.nftErrorOneUnit;
    final h = contentHashHex.trim().toLowerCase();
    if (h.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return appL10n.nftErrorHash;
    if (url.trim().isNotEmpty && !RegExp(r'^(https?|ipfs)://').hasMatch(url.trim())) return appL10n.nftErrorLink;
  }
  return null;
}

/// The supply in base units: `amountText` scaled by `decimals`, exactly.
BigInt? parseIssuanceAmount(String amountText, int decimals) {
  final t = amountText.trim().replaceAll(',', '');
  if (t.isEmpty || !RegExp(r'^\d*\.?\d*$').hasMatch(t) || t == '.') return null;
  final parts = t.split('.');
  final whole = parts[0].isEmpty ? '0' : parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > decimals) return null;
  return BigInt.tryParse(whole + frac.padRight(decimals, '0'));
}

/// The word the user must type before a burn goes ahead.
const burnConfirmWord = 'BURN';
