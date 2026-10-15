import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bridge/api/celaut_network.dart';
import '../services/secure_storage.dart';

/// What the user chose for the outbound connections (milestone M5).
enum NetworkMode { off, embedded, socks }

/// The network route of the app: no Tor, the Tor client inside the app, or an external
/// SOCKS5 proxy (Orbot). The choice is kept in the preferences and given to the Rust core
/// at the start of the app, before any connection. With Tor on, the core blocks every
/// connection until the proxy is ready, and the app never connects directly
/// (`docs/celaut-plan.md`, M5).
class NetworkRoute extends ChangeNotifier {
  /// The functions stand in for the Rust core and the private directory in tests.
  NetworkRoute({
    Future<void> Function(NetworkChoice choice, String? socksAddress, String dataDir)? push,
    NetworkStatusView Function()? readStatus,
    Future<String?> Function()? privateDir,
  })  : _push = push ?? _pushToRust,
        _readStatus = readStatus ?? celautNetworkStatus,
        _privateDir = privateDir ?? _appPrivateDir;

  static const modeKey = 'celaut_network_mode';
  static const socksKey = 'celaut_network_socks';

  /// The address that Orbot listens on.
  static const defaultSocks = '127.0.0.1:9050';

  final Future<void> Function(NetworkChoice, String?, String) _push;
  final NetworkStatusView Function() _readStatus;
  final Future<String?> Function() _privateDir;

  NetworkMode _mode = NetworkMode.off;
  String _socks = defaultSocks;
  bool _loaded = false;

  NetworkMode get mode => _mode;
  String get socksAddress => _socks;

  /// The state of the route now, read from the Rust core.
  NetworkStatusView get status => _readStatus();

  static Future<void> _pushToRust(NetworkChoice choice, String? socks, String dataDir) =>
      celautSetNetwork(choice: choice, socksAddress: socks, dataDir: dataDir);

  /// The directory of the Celaut database: private to the app. The Tor client keeps its
  /// state in a folder inside it.
  static Future<String?> _appPrivateDir() async {
    try {
      final path = await SecureStorageService.celautDbPath();
      if (path == null || path.isEmpty) return null;
      return File(path).parent.path;
    } on MissingPluginException {
      return null;
    }
  }

  static NetworkChoice _choiceOf(NetworkMode mode) => switch (mode) {
        NetworkMode.off => NetworkChoice.off,
        NetworkMode.embedded => NetworkChoice.embedded,
        NetworkMode.socks => NetworkChoice.socks,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(modeKey);
    _mode = NetworkMode.values.firstWhere((m) => m.name == name, orElse: () => NetworkMode.off);
    _socks = prefs.getString(socksKey) ?? defaultSocks;
    _loaded = true;
    notifyListeners();
  }

  /// Give the stored choice to the Rust core. Call it once after `RustLib.init`, before
  /// any connection. A failure is not thrown: with Tor on, the core has blocked the
  /// connections, and the screen shows the reason.
  Future<void> apply() async {
    if (!_loaded) await load();
    try {
      await _pushCurrent();
    } catch (e) {
      debugPrint('Network route not applied: $e');
    }
    notifyListeners();
  }

  /// Keep the choice first, then apply it: a failed write leaves the old route in force.
  /// Throws if the choice cannot be kept. If the Rust core refuses the settings, it blocks
  /// the connections and this throws its error.
  Future<void> choose(NetworkMode mode, {String? socksAddress}) async {
    final socks = (socksAddress ?? _socks).trim();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(modeKey, mode.name) || !await prefs.setString(socksKey, socks)) {
      throw StateError('Could not save the network setting');
    }
    _mode = mode;
    _socks = socks;
    _loaded = true;
    notifyListeners();
    await _pushCurrent();
  }

  Future<void> _pushCurrent() async {
    final dir = await _privateDir() ?? '';
    await _push(_choiceOf(_mode), _mode == NetworkMode.socks ? _socks : null, dir);
  }
}

final networkRoute = NetworkRoute();
