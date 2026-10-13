import 'package:flutter/material.dart';

import '../../celaut/deposit_strings.dart';
import '../../celaut/payers.dart';

/// Choose the default payer: one of the full wallets, or none. Read-only wallets are not
/// in the list (`docs/celaut/ui.md`, section 1). Gives true if the choice changed.
Future<bool> showDefaultPayerDialog(
  BuildContext context, {
  required List<PayerWallet> payers,
  required String? current,
  DefaultPayerStore store = const DefaultPayerStore(),
}) async {
  if (payers.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(DepositStrings.defaultPayerTitle),
        content: Text(DepositStrings.noFullWallet, key: const Key('default-payer-none-full')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    return false;
  }
  // The empty string is "no default".
  final chosen = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(DepositStrings.defaultPayerTitle),
      children: [
        for (final p in payers)
          SimpleDialogOption(
            key: Key('default-payer-${p.walletId}'),
            onPressed: () => Navigator.pop(ctx, p.walletId),
            child: Text(p.walletId == current ? '${p.name}  ✓' : p.name),
          ),
        SimpleDialogOption(
          key: const Key('default-payer-clear'),
          onPressed: () => Navigator.pop(ctx, ''),
          child: Text(DepositStrings.defaultPayerNone),
        ),
      ],
    ),
  );
  if (chosen == null) return false;
  final id = chosen.isEmpty ? null : chosen;
  if (id == current) return false;
  await store.save(id);
  return true;
}
