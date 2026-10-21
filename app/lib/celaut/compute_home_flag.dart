import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The setting that shows the Celaut home screen: the tabs of the bottom bar, Chats
/// first (`docs/celaut/ui-chat-first.md`), whose Compute tab is the compute view of
/// `docs/celaut/ui.md`, section 2. On by default. A user can turn it off in Settings,
/// Developer, to see the wallets list first.
class ComputeHomeFlag extends ValueNotifier<bool> {
  ComputeHomeFlag() : super(true);

  static const key = 'celaut_compute_home_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(key) ?? true;
  }

  Future<void> set(bool on) async {
    value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, on);
  }
}

final computeHomeFlag = ComputeHomeFlag();
