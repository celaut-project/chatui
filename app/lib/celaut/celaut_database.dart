import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/api/celaut_db.dart';
import '../services/secure_storage.dart';

/// Open the Celaut database of the app (`docs/celaut/ui.md`, section 1): one encrypted
/// file for all the wallets, with the client ids, instance tokens, deposits and the
/// event log. The key is in the Keystore store of the app, as the wrap keys of the
/// seeds are.
///
/// Call it once after `RustLib.init`. If it fails, the Celaut data stays in memory for
/// this run, as before, and the error is logged.
Future<CelautDatabaseView?> openCelautDatabase() async {
  try {
    final path = await SecureStorageService.celautDbPath();
    if (path == null || path.isEmpty) return null;
    var key = await SecureStorageService.loadCelautDbKey();
    if (key == null || key.isEmpty) {
      key = celautNewDatabaseKey();
      await SecureStorageService.saveCelautDbKey(key);
    }
    final view = await celautOpenDatabase(path: path, keyHex: key);
    if (view.setAsidePath != null) {
      debugPrint('Celaut database: the old file could not be opened; kept as ${view.setAsidePath}');
    }
    return view;
  } on MissingPluginException {
    // No platform store (tests, desktop): the data stays in memory.
    return null;
  } catch (e) {
    debugPrint('Celaut database not opened: $e');
    return null;
  }
}
