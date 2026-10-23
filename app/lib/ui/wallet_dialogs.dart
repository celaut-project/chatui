import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/secure_storage.dart';
import '../services/session_lock.dart';
import '../services/wallet_service.dart';

/// Right after a wallet gets its PIN: offer biometric unlock while the PIN
/// is still in hand, so the user need not find it in Settings later. Does
/// nothing on a device without biometrics. Never throws.
Future<void> offerBiometricUnlock(
  BuildContext context, {
  required String walletId,
  required String pin,
}) async {
  bool possible;
  try {
    possible = await SecureStorageService.hasBiometric();
  } catch (_) {
    possible = false;
  }
  if (!possible || !context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.dialogBiometricTitle),
      content: Text(
        ctx.l10n.dialogBiometricBody,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.dialogNotNow)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.dialogEnable)),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  String message;
  try {
    final saved = await sessionLock.run(() async {
      final pinWrap = await SecureStorageService.loadPinWrap(walletId: walletId);
      if (pinWrap == null) return false;
      final wrapKey = await walletService.unwrapKeyWithPin(pinWrap, pin);
      await SecureStorageService.saveWrapKey(wrapKey, walletId: walletId);
      await SecureStorageService.clearPinGate();
      return true;
    });
    message = saved ? appL10n.dialogBiometricEnabled : appL10n.dialogBiometricFailed;
  } catch (_) {
    message = appL10n.dialogBiometricFailed;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

