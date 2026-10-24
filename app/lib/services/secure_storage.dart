import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../l10n/l10n.dart';

/// Platform Keystore/Keychain for the sealed seed and its wrap key. The PIN wrap is only
/// read to move a wallet made before the app dropped the PIN.
class SecureStorageService {
  static const _channel = MethodChannel('com.argus.wallet/secure_storage');

  static Future<bool> saveEncryptedSeed(String encryptedSeedJson, {String? walletId}) async {
    try {
      await _channel.invokeMethod('saveEncryptedSeed', {
        'encryptedSeedJson': encryptedSeedJson,
        if (walletId != null) 'walletId': walletId,
      });
      return true;
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureSaveFailed);
    }
  }

  static Future<bool> saveWrapKey(String wrapKey, {String? walletId}) async {
    try {
      await _channel.invokeMethod('saveWrapKey', {
        'wrapKey': wrapKey,
        if (walletId != null) 'walletId': walletId,
      });
      return true;
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureSaveWrapKeyFailed);
    }
  }

  static Future<void> savePinWrap(String pinWrapJson, {String? walletId}) async {
    try {
      await _channel.invokeMethod('savePinWrap', {
        'pinWrapJson': pinWrapJson,
        if (walletId != null) 'walletId': walletId,
      });
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureSavePinWrapFailed);
    }
  }

  /// A new wallet: the sealed seed and the key that opens it. The wallet opens with the
  /// fingerprint or the screen lock of the phone, there is no PIN of the app.
  static Future<void> saveWallet({
    required String walletId,
    required String encryptedSeedJson,
    required String wrapKey,
  }) async {
    await saveEncryptedSeed(encryptedSeedJson, walletId: walletId);
    try {
      await saveWrapKey(wrapKey, walletId: walletId);
    } catch (_) {
      await deleteEncryptedSeed(walletId: walletId);
      rethrow;
    }
  }

  static Future<String?> loadWrapKey({String? walletId}) async {
    try {
      return await _channel.invokeMethod<String>(
        'loadWrapKey',
        walletId != null ? {'walletId': walletId} : null,
      );
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureLoadWrapKeyFailed);
    }
  }

  static Future<String?> loadPinWrap({String? walletId}) async {
    try {
      return await _channel.invokeMethod<String>(
        'loadPinWrap',
        walletId != null ? {'walletId': walletId} : null,
      );
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureLoadPinWrapFailed);
    }
  }

  static Future<String?> loadEncryptedSeed({String? walletId}) async {
    try {
      return await _channel.invokeMethod<String>(
        'loadEncryptedSeed',
        walletId != null ? {'walletId': walletId} : null,
      );
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureLoadFailed);
    }
  }

  /// The wallet no longer has a PIN: drop the old wrap, which the phone's lock replaces.
  static Future<void> deletePinWrap({String? walletId}) async {
    try {
      await _channel.invokeMethod(
        'deletePinWrap',
        walletId != null ? {'walletId': walletId} : null,
      );
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.secureDeleteWrapKeyFailed('${e.message}'));
    }
  }

  static Future<void> deleteWrapKey({String? walletId}) async {
    try {
      await _channel.invokeMethod(
        'deleteWrapKey',
        walletId != null ? {'walletId': walletId} : null,
      );
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.secureDeleteWrapKeyFailed('${e.message}'));
    }
  }

  static Future<void> deleteEncryptedSeed({String? walletId}) async {
    try {
      await _channel.invokeMethod(
        'deleteEncryptedSeed',
        walletId != null ? {'walletId': walletId} : null,
      );
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.secureDeleteSecretsFailed('${e.message}'));
    }
  }

  static Future<void> deleteWallet(String walletId) async {
    try {
      await _channel.invokeMethod('deleteWallet', {'walletId': walletId});
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.secureDeleteWalletFailed('${e.message}'));
    }
  }

  static Future<bool> hasEncryptedSeed({String? walletId}) async {
    try {
      return await _channel.invokeMethod<bool>(
        'hasEncryptedSeed',
        walletId != null ? {'walletId': walletId} : null,
      ) ?? false;
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.secureCheckFailed('${e.message}'));
    }
  }

  static Future<bool> hasPinWrap({String? walletId}) async {
    try {
      return await _channel.invokeMethod<bool>(
        'hasPinWrap',
        walletId != null ? {'walletId': walletId} : null,
      ) ?? false;
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureCheckPinWrapFailed);
    }
  }

  static Future<bool> hasWrapKey({String? walletId}) async {
    try {
      return await _channel.invokeMethod<bool>(
        'hasWrapKey',
        walletId != null ? {'walletId': walletId} : null,
      ) ?? false;
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureCheckWrapKeyFailed);
    }
  }

  static Future<bool> hasBiometric() async {
    try {
      return await _channel.invokeMethod<bool>('hasBiometric') ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'BIOMETRIC') return false;
      throw _map(e, appL10n.secureCheckBiometricsFailed);
    }
  }

  /// Returns the wrap key after the prompt of the phone (fingerprint or screen lock), or
  /// null if the user cancelled. A phone with neither gives the key with no prompt.
  static Future<String?> authenticateBiometric({String? walletId}) async {
    try {
      final raw = await _channel.invokeMethod(
        'authenticateBiometric',
        walletId != null ? {'walletId': walletId} : null,
      );
      if (raw is String && raw.isNotEmpty) return raw;
      return null;
    } on PlatformException catch (e) {
      if (_isCancel(e)) return null;
      throw _map(e, appL10n.secureBiometric);
    }
  }

  static Future<bool> setSecureFlag(bool enable) async {
    try {
      return await _channel.invokeMethod<bool>('setSecureFlag', {'enable': enable}) ?? false;
    } catch (_) {
      // PlatformException on old devices, MissingPluginException in tests.
      return false;
    }
  }

  static Future<({int count, int until})> loadPinGate() async {
    try {
      final raw = await _channel.invokeMethod('loadPinGate');
      if (raw is Map) {
        return (
          count: (raw['count'] as num?)?.toInt() ?? 0,
          until: (raw['until'] as num?)?.toInt() ?? 0,
        );
      }
      return (count: 0, until: 0);
    } on PlatformException catch (e) {
      throw _map(e, appL10n.secureLoadPinGateFailed);
    }
  }

  static Future<String?> pinBlockedMessage() async {
    final gate = await loadPinGate();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (gate.until > now) {
      final wait = ((gate.until - now) / 1000).ceil();
      return appL10n.secureTooManyAttempts('$wait');
    }
    return null;
  }

  static Future<void> recordPinFailure() async {
    final gate = await loadPinGate();
    final count = gate.count + 1;
    final delaySec = 1 << (count > 6 ? 5 : count - 1);
    await savePinGate(
      count: count,
      until: DateTime.now().millisecondsSinceEpoch + delaySec * 1000,
    );
  }

  static Future<void> clearPinGate() async {
    await savePinGate(count: 0, until: 0);
  }

  static Future<void> savePinGate({required int count, required int until}) async {
    try {
      await _channel.invokeMethod('savePinGate', {'count': count, 'until': until});
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.securePersistPinGateFailed('${e.message}'));
    }
  }

  /// Returns all wallet IDs currently stored.
  static Future<List<String>> listWalletIds() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listWalletIds');
      return result?.map((e) => e.toString()).toList() ?? [];
    } on PlatformException catch (e) {
      throw SecureStorageException(appL10n.secureListWalletsFailed('${e.message}'));
    }
  }

  /// The key of the Celaut database (one for the app, not one per wallet), or null if
  /// the app has none yet. Platform errors pass through as [PlatformException].
  static Future<String?> loadCelautDbKey() =>
      _channel.invokeMethod<String>('loadCelautDbKey');

  static Future<void> saveCelautDbKey(String key) =>
      _channel.invokeMethod('saveCelautDbKey', {'key': key});

  /// The file of the Celaut database, outside the cloud backup.
  static Future<String?> celautDbPath() => _channel.invokeMethod<String>('celautDbPath');

  /// Migrates a legacy single-slot wallet (pre-multi-wallet) to a new wallet ID.
  /// Returns the wallet ID if migration was performed, or null if there was
  /// nothing to migrate.
  static Future<String?> migrateLegacyWallet() async {
    final hasLegacy = await _channel.invokeMethod<bool>('hasEncryptedSeed');
    if (hasLegacy != true) return null;
    // If already migrated (wallet registry exists), do nothing.
    final ids = await listWalletIds();
    if (ids.isNotEmpty && !ids.contains('legacy')) return null;

    final newWalletId = const Uuid().v4();
    final migrated = await _channel.invokeMethod<bool>(
      'migrateLegacyWallet',
      {'newWalletId': newWalletId},
    );
    if (migrated == true) return newWalletId;
    return null;
  }

  static bool _isCancel(PlatformException e) {
    final msg = e.message?.toLowerCase() ?? '';
    return e.code == 'BIOMETRIC' &&
        (msg.contains('cancel') || msg.contains('negative'));
  }

  static SecureStorageException _map(PlatformException e, String prefix) {
    if (e.code == 'KEY_INVALIDATED') {
      return SecureStorageException.biometricChanged();
    }
    return SecureStorageException('$prefix: ${e.message}');
  }
}

class SecureStorageException implements Exception {
  final String message;
  final bool isBiometricChanged;

  SecureStorageException(this.message) : isBiometricChanged = false;

  SecureStorageException.biometricChanged()
      : message = appL10n.secureBiometricChanged,
        isBiometricChanged = true;

  @override
  String toString() => 'SecureStorageException: $message';
}
