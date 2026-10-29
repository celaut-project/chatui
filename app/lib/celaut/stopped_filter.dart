import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The filter of the lists of instances (Chats): it hides the stopped
/// instances. On by default (Josemi, 2026-10-23). The lists have a button that shows them
/// again; a shown stopped instance can be deleted as before. The choice is kept.
class StoppedFilter extends ValueNotifier<bool> {
  StoppedFilter() : super(true);

  static const key = 'celaut_hide_stopped_v1';

  bool _loaded = false;

  /// Read the kept choice, once.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(key) ?? true;
  }

  /// Hide the stopped instances ([hide] true), or show them.
  Future<void> set(bool hide) async {
    _loaded = true;
    value = hide;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, hide);
  }
}

/// The filter of the app.
final stoppedFilter = StoppedFilter();
