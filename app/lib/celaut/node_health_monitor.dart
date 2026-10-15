import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/api/celaut_health.dart';

/// Check the nodes that are due (all of them if `force`) and give the state of every node.
typedef NodeHealthCheck = Future<List<NodeHealthView>> Function(bool force);

/// Make a timer that calls `tick` every `interval`. Tests give their own.
typedef HealthTimerFactory = Timer Function(Duration interval, void Function() tick);

Timer _periodic(Duration interval, void Function() tick) =>
    Timer.periodic(interval, (_) => tick());

/// Keeps the availability of the nodes of the node list up to date while the home screen
/// is open (`docs/celaut/ui.md`, section 2).
///
/// The Rust core keeps the result of the checks in the Celaut database and decides which
/// node is due: a node that fails is asked later and later. So this class only asks the
/// core, every [interval], to check the nodes that are due, and shows what the core says.
/// A check never overlaps another one, and an error does not stop the loop.
class NodeHealthMonitor extends ChangeNotifier {
  NodeHealthMonitor({
    NodeHealthCheck? check,
    List<NodeHealthView> Function()? read,
    HealthTimerFactory? timer,
    this.interval = const Duration(seconds: 60),
  })  : _check = check ?? ((force) => celautCheckNodes(force: force)),
        _read = read ?? celautNodesHealth,
        _timer = timer ?? _periodic;

  final NodeHealthCheck _check;
  final List<NodeHealthView> Function() _read;
  final HealthTimerFactory _timer;
  final Duration interval;

  List<NodeHealthView> _nodes = const [];
  bool _checking = false;
  Object? _lastError;
  Timer? _ticker;
  bool _started = false;
  bool _disposed = false;

  /// The state of each node of the list, from the last read or check.
  List<NodeHealthView> get nodes => _nodes;

  /// True while a check runs.
  bool get checking => _checking;

  /// The error of the last check, if it failed.
  Object? get lastError => _lastError;

  /// The state of one node, or null if the core has none.
  NodeHealthView? of(String peerId) {
    for (final n in _nodes) {
      if (n.peerId == peerId) return n;
    }
    return null;
  }

  /// Read the stored state at once (no connection), check the nodes that are due, and
  /// check again every [interval].
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _readStored();
    resume();
  }

  /// Start the timer and check the nodes that are due. Use it when the app is in use again.
  void resume() {
    if (!_started || _disposed) return;
    _ticker?.cancel();
    _ticker = _timer(interval, () => _run(false));
    _run(false).ignore();
  }

  /// Stop the timer. The state stays. Use it when the app goes to the background.
  void pause() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Check all the nodes now, also the ones that are not due.
  Future<void> checkNow() => _run(true);

  /// Stop for good.
  void stop() {
    pause();
    _started = false;
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    super.dispose();
  }

  void _readStored() {
    try {
      _nodes = _read();
    } catch (e) {
      // The core is not ready, or has nothing: there is nothing to show yet.
      _lastError = e;
    }
    _notify();
  }

  Future<void> _run(bool force) async {
    if (_checking || _disposed) return;
    _checking = true;
    _notify();
    try {
      final nodes = await _check(force);
      if (_disposed) return;
      _nodes = nodes;
      _lastError = null;
    } catch (e) {
      _lastError = e;
    } finally {
      _checking = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
