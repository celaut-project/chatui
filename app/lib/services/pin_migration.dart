import 'secure_storage.dart';
import 'wallet_service.dart';

/// A wallet made before the app dropped the PIN still has its key wrapped by one. The
/// user types the PIN one last time: the key then lives in the Keystore, the wallet
/// opens with the fingerprint or the screen lock of the phone, and the PIN wrap goes.
///
/// Throws [ArgusException] on a wrong PIN; the caller records the failure for the
/// lockout. Gives the wrap key.
Future<String> movePinWalletToDeviceLock({
  required String walletId,
  required String pinWrapJson,
  required String pin,
}) async {
  final wrapKey = await walletService.unwrapKeyWithPin(pinWrapJson, pin);
  await SecureStorageService.saveWrapKey(wrapKey, walletId: walletId);
  await dropPinWrap(walletId);
  try {
    await SecureStorageService.clearPinGate();
  } catch (_) {}
  return wrapKey;
}

/// The wallet opened with the lock of the phone, so an old PIN wrap is not needed.
/// Best effort: a failure leaves the wrap for the next unlock to remove.
Future<void> dropPinWrap(String walletId) async {
  try {
    if (await SecureStorageService.hasPinWrap(walletId: walletId)) {
      await SecureStorageService.deletePinWrap(walletId: walletId);
    }
  } catch (_) {}
}
