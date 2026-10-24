import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bridge/api/celaut.dart';
import '../bridge/api/celaut_service.dart';

/// A top-up that the app could not make: the credit of the app on the node of the
/// instance is less than the amount. The app does not pay a node by itself; the user
/// chooses to make a deposit, which has its own confirmation and unlock.
@immutable
class TopUpNeed {
  const TopUpNeed({required this.instanceId, required this.address, required this.detail});

  final String instanceId;

  /// The node (`host:port`).
  final String address;

  /// The numbers of the node, as the error gives them (credit and amount).
  final String detail;
}

/// The automatic top-up of instances (Josemi, 2026-10-23). Off by default; the user turns
/// it on in Settings, Compute.
///
/// When a running instance has less than [threshold] MU, the app moves [amount] MU of the
/// credit that it already has on the node of the instance to the instance
/// (`celaut_top_up_instance`, `ModifyDeposit`). That is not a payment: nothing goes on the
/// blockchain and nothing is signed. If the credit on the node is too low, the app does
/// not pay: it sets [need], and the list of conversations asks the user, who can make a
/// deposit. A deposit has its own confirmation and asks for the fingerprint or the screen lock,
/// as always. So no transaction ever happens without the user.
///
/// The app checks when the list of conversations reads the instances ([observe]), and
/// once a minute while the app runs ([start]). After a top-up of an instance, it waits a
/// minute before the next one; after a failure, ten minutes.
class AutoTopUp extends ChangeNotifier {
  AutoTopUp({
    Future<TopUpView> Function(String instanceId, String amountMu)? topUp,
    List<InstanceListView> Function()? instances,
    Future<InstanceStatusView> Function(String instanceId)? status,
    DateTime Function()? now,
    this.periodic = true,
  })  : _topUp = topUp ?? ((id, mu) => celautTopUpInstance(instanceId: id, amountMu: mu)),
        _instances = instances ?? celautInstances,
        _status = status ?? ((id) => celautInstanceStatus(instanceId: id)),
        _now = now ?? DateTime.now;

  static const keyOn = 'celaut_auto_top_up_v1';
  static const keyThreshold = 'celaut_auto_top_up_threshold_mu_v1';
  static const keyAmount = 'celaut_auto_top_up_amount_mu_v1';

  static final defaultThreshold = BigInt.from(200000);
  static final defaultAmount = BigInt.from(1000000);

  /// The least threshold and amount, in MU.
  static final minMu = BigInt.from(10000);

  /// The largest threshold, in MU.
  static final maxThreshold = BigInt.from(50000000);

  /// The largest amount of one top-up, in MU (the app refuses more, `TOP_UP_MAX_MU` is
  /// 100,000,000).
  static final maxAmount = BigInt.from(10000000);

  static const _afterTopUp = Duration(minutes: 1);
  static const _afterFailure = Duration(minutes: 10);
  static const _every = Duration(minutes: 1);

  final Future<TopUpView> Function(String instanceId, String amountMu) _topUp;
  final List<InstanceListView> Function() _instances;
  final Future<InstanceStatusView> Function(String instanceId) _status;
  final DateTime Function() _now;

  /// Check once a minute while on. Tests check by hand.
  final bool periodic;

  bool _on = false;
  BigInt _threshold = defaultThreshold;
  BigInt _amount = defaultAmount;
  bool _loaded = false;
  TopUpNeed? _need;
  final Map<String, DateTime> _wait = {};
  final Set<String> _busy = {};
  Timer? _timer;

  bool get on => _on;
  BigInt get threshold => _threshold;
  BigInt get amount => _amount;

  /// A top-up that needs a deposit first; null if none.
  TopUpNeed? get need => _need;

  /// Read the settings, once.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _on = prefs.getBool(keyOn) ?? false;
      _threshold = _parse(prefs.getString(keyThreshold), defaultThreshold, maxThreshold);
      _amount = _parse(prefs.getString(keyAmount), defaultAmount, maxAmount);
    } catch (_) {
      // No preferences: the defaults, off.
    }
    notifyListeners();
  }

  static BigInt _parse(String? text, BigInt fallback, BigInt max) {
    final v = text == null ? null : BigInt.tryParse(text);
    if (v == null || v < minMu || v > max) return fallback;
    return v;
  }

  /// Keep new settings. [threshold] and [amount] must be in their limits.
  Future<void> save({required bool on, required BigInt threshold, required BigInt amount}) async {
    _loaded = true;
    _on = on;
    _threshold = threshold;
    _amount = amount;
    if (!on) _need = null;
    _schedule();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyOn, on);
      await prefs.setString(keyThreshold, '$threshold');
      await prefs.setString(keyAmount, '$amount');
    } catch (_) {
      // Not kept: the settings last for this run only.
    }
  }

  /// The user saw the [need] and closed it.
  void dismissNeed() {
    if (_need == null) return;
    _need = null;
    notifyListeners();
  }

  /// Read the settings, and check once a minute while the app runs and the top-up is on.
  Future<void> start() async {
    await load();
    _schedule();
  }

  /// A timer only while the top-up is on: with it off, nothing polls the nodes.
  void _schedule() {
    if (_on && periodic) {
      _timer ??= Timer.periodic(_every, (_) => unawaited(check()));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Read the balance of each running instance, and top up the ones under the threshold.
  Future<void> check() async {
    await load();
    if (!_on) return;
    List<InstanceListView> all;
    try {
      all = _instances();
    } catch (_) {
      return;
    }
    for (final i in all) {
      if (i.stoppedAt != null || _waiting(i.instanceId)) continue;
      try {
        await observe(i, await _status(i.instanceId));
      } on Object {
        // The node does not answer: the list says so; the next check tries again.
      }
    }
  }

  bool _waiting(String id) {
    final until = _wait[id];
    return until != null && _now().isBefore(until);
  }

  /// The balance of the running instance [i] is known ([status]): top it up if it is
  /// under the threshold.
  Future<void> observe(InstanceListView i, InstanceStatusView status) async {
    if (!_on || i.stoppedAt != null) return;
    final id = i.instanceId;
    final balance = BigInt.tryParse(status.instanceBalanceMu);
    if (balance == null || balance >= _threshold) return;
    if (_waiting(id) || !_busy.add(id)) return;
    try {
      await _topUp(id, '$_amount');
      _wait[id] = _now().add(_afterTopUp);
      if (_need?.instanceId == id) {
        _need = null;
        notifyListeners();
      }
    } on CelautError catch (e) {
      _wait[id] = _now().add(_afterFailure);
      if (e.kind == CelautErrorKind.insufficientCredit) {
        _need = TopUpNeed(instanceId: id, address: i.address, detail: e.message);
        notifyListeners();
      }
    } on Object {
      _wait[id] = _now().add(_afterFailure);
    } finally {
      _busy.remove(id);
    }
  }
}

/// The automatic top-up of the app.
final autoTopUp = AutoTopUp();
