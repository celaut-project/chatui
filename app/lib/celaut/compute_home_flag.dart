import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The developer setting that shows the compute home (`docs/celaut/ui.md`, section 2)
/// instead of the wallet home. Off by default: the wallet home stays the default until
/// the open points of section 4 of ui.md are decided.
class ComputeHomeFlag extends ValueNotifier<bool> {
  ComputeHomeFlag() : super(false);

  static const key = 'celaut_compute_home_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(key) ?? false;
  }

  Future<void> set(bool on) async {
    value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, on);
  }
}

final computeHomeFlag = ComputeHomeFlag();
