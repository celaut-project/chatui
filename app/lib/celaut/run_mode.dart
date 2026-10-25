import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the screen "New conversation" shows: the skills of the catalog, or the service
/// files of the user. One at a time, so that neither pushes the other off the screen.
enum RunMode { skills, files }

/// The mode that the user chose last, kept: who runs from files opens on them next time.
/// Skills by default.
class RunModeChoice extends ValueNotifier<RunMode> {
  RunModeChoice() : super(RunMode.skills);

  static const key = 'celaut_run_mode_v1';

  bool _loaded = false;

  /// Read the kept choice, once. A failure to read leaves the default.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final kept = prefs.getString(key);
      value = RunMode.values.firstWhere((m) => m.name == kept, orElse: () => RunMode.skills);
    } catch (_) {}
  }

  /// Show [mode] now and keep it for the next time.
  Future<void> set(RunMode mode) async {
    _loaded = true;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, mode.name);
    } catch (_) {}
  }
}

/// The choice of the app.
final runMode = RunModeChoice();
