import 'package:flutter/material.dart';

import '../bridge/argus_error.dart';
import '../l10n/l10n.dart';
import '../services/pin_migration.dart';
import '../services/secure_storage.dart';
import '../services/session_lock.dart';
import '../services/wallet_service.dart';
import '../services/wallet_sync_controller.dart';
import '../ui/widgets/entry_dialogs.dart';
import '../ui/widgets/error_sheet.dart';

/// Ask the phone (fingerprint or screen lock) to open the full wallet [walletId], as the
/// unlock gate of the wallet does, and open that wallet (`docs/celaut/ui.md`, section 1).
/// The app asks even if the wallet is already open: a deposit needs the consent of the
/// user for the wallet that pays.
///
/// A wallet made before the app dropped the PIN asks for its PIN one last time, with the
/// PIN lockout of the app, and then opens with the lock of the phone like the others. A
/// wallet that another wallet replaces as the open one is locked, as when the user
/// switches wallets in the wallets list.
///
/// Gives true when [walletId] is the open wallet after the check.
Future<bool> unlockFullWallet(
  BuildContext context, {
  required String walletId,
  required String name,
}) async {
  void say(String message) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  try {
    String? wrapKey;
    if (await SecureStorageService.hasWrapKey(walletId: walletId)) {
      wrapKey = await sessionLock.run(
        () => SecureStorageService.authenticateBiometric(walletId: walletId),
      );
      if (wrapKey == null) return false;
      await dropPinWrap(walletId);
    } else {
      final pinWrap = await SecureStorageService.loadPinWrap(walletId: walletId);
      if (pinWrap == null) {
        say(appL10n.celautUnlockFailed);
        return false;
      }
      final blocked = await SecureStorageService.pinBlockedMessage();
      if (blocked != null) {
        say(blocked);
        return false;
      }
      if (!context.mounted) return false;
      final entry = await showDialog<PinEntry>(
        context: context,
        builder: (_) => PinEntryDialog(title: appL10n.celautUnlockTitle(name)),
      );
      if (entry == null || entry.pin.isEmpty) return false;
      try {
        wrapKey = await movePinWalletToDeviceLock(
          walletId: walletId,
          pinWrapJson: pinWrap,
          pin: entry.pin,
        );
      } on ArgusException catch (e) {
        try {
          await SecureStorageService.recordPinFailure();
        } catch (_) {}
        if (context.mounted) await showErrorSheet(context, code: e.code, message: e.message);
        return false;
      }
    }

    if (walletService.isUnlocked && walletService.activeWalletId == walletId) return true;
    final json = await SecureStorageService.loadEncryptedSeed(walletId: walletId);
    if (json == null) {
      say(appL10n.celautUnlockFailed);
      return false;
    }
    final key = wrapKey;
    await sessionLock.run(() async {
      if (walletService.isUnlocked && walletService.activeWalletId != walletId) {
        await walletService.lockForSwitch();
      }
      await walletService.restoreWallet(json, wrapKey: key, walletId: walletId);
      await walletSyncController.hydrateAfterUnlock();
    });
    final open = walletService.isUnlocked && walletService.activeWalletId == walletId;
    if (!open) say(appL10n.celautUnlockFailed);
    return open;
  } on ArgusException catch (e) {
    if (context.mounted) await showErrorSheet(context, code: e.code, message: e.message);
    return false;
  } on SecureStorageException catch (e) {
    if (context.mounted) await showErrorSheet(context, message: e.message);
    return false;
  }
}
