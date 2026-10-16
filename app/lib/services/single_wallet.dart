import 'package:shared_preferences/shared_preferences.dart';

import 'wallet_service.dart';

/// The preference keys that earlier versions of the app used for the watched
/// addresses, the watched accounts and the default payer of the Celaut deposits.
const retiredStorageKeys = [
  'argus_watch_only_addresses',
  'argus_watch_only_accounts_v1',
  'celaut_default_payer_v1',
];

/// The prefix of the token tables of the watched wallets of earlier versions.
const retiredStoragePrefix = 'argus_token_descriptors_v1_watched:';

/// The app holds one Ergo wallet and no watched wallets (`docs/celaut/ui.md`,
/// section 1). An earlier version can leave more: this removes them.
///
/// - The watched addresses and accounts are removed, with the token tables
///   of their holdings.
/// - The first wallet of the user order stays. The other wallets are deleted
///   with their seeds, and the delete cannot be undone.
///
/// It runs at each start and does nothing when the app already has at most
/// one wallet and no watched wallets.
Future<void> enforceSingleWallet({
  Future<List<String>> Function()? walletIds,
  Future<void> Function(String walletId)? deleteWallet,
}) async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys().toList()) {
    if (retiredStorageKeys.contains(key) || key.startsWith(retiredStoragePrefix)) {
      await prefs.remove(key);
    }
  }
  final ids =
      await (walletIds ??
          () async => [for (final w in await walletService.listWallets()) w.walletId])();
  for (final id in ids.skip(1)) {
    await (deleteWallet ?? walletService.deleteWallet)(id);
  }
}
