import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/wallet_service.dart';
import 'conversation_keep_alive.dart';

/// The work that must not stop when the phone sleeps or the app goes to the background:
/// the launch of a service, the transfer of a service file to a node, and the import of
/// a service file (Josemi, 2026-10-23).
///
/// While a work runs:
///
/// - the foreground service holds the process and keeps the CPU awake
///   ([ForegroundHolds]), so the work goes on with the screen off;
/// - the auto-lock still locks the wallet on time: the keys leave the memory as before.
///   Only the pages change: a lock closes every page over the home screen
///   ([onWalletLocked]), and that would close the page of the work (the file picker of
///   Android puts the app in the background, and a 2-second auto-lock closed the import).
///   So while a work runs, the pages stay. When the last work ends, the pages over the
///   page of the work close, if the wallet is still locked. The page of the work shows no
///   secret, and anything that needs the wallet asks for the PIN again.
class BackgroundWork {
  BackgroundWork({ForegroundHolds? holds, bool Function()? walletLocked})
      : _holds = holds ?? foregroundHolds,
        _walletLocked = walletLocked ?? (() => !walletService.isUnlocked);

  final ForegroundHolds _holds;
  final bool Function() _walletLocked;
  int _running = 0;
  NavigatorState? _navigator;
  Route<dynamic>? _page;
  bool _lockedMeanwhile = false;

  /// True while a work runs.
  bool get busy => _running > 0;

  /// Run [body] as a work of [reason], from the page of [context].
  Future<T> run<T>(BuildContext context, KeepAliveReason reason, Future<T> Function() body) async {
    if (_running == 0) {
      _navigator = Navigator.maybeOf(context);
      _page = ModalRoute.of(context);
    }
    _running++;
    final release = _holds.hold(reason);
    try {
      return await body();
    } finally {
      _running--;
      await release();
      if (_running == 0) _end();
    }
  }

  void _end() {
    final navigator = _navigator, page = _page;
    _navigator = null;
    _page = null;
    if (!_lockedMeanwhile) return;
    _lockedMeanwhile = false;
    if (!_walletLocked() || navigator == null || !navigator.mounted) return;
    // The work may have gone to another page already (a launch opens its conversation):
    // then there is nothing to close.
    if (page != null && page.isActive) {
      navigator.popUntil((r) => r == page || r.isFirst);
    }
  }

  /// The wallet locked: close every page over the home screen, as the lock always did,
  /// unless a work runs (see the class).
  void onWalletLocked(NavigatorState? navigator) {
    if (navigator == null) return;
    if (busy) {
      _lockedMeanwhile = true;
      return;
    }
    navigator.popUntil((r) => r.isFirst);
  }
}

/// The work of the app.
final backgroundWork = BackgroundWork();
