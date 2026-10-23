import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../home/home_style.dart';

/// The rocket of a launch (Josemi, 2026-10-23): a card over the screen while the app asks
/// the nodes and starts the service. The rocket hovers on its flame; when the service
/// starts, it lifts off and the card goes. With "remove animations" on in Android, the
/// rocket stands still and the card goes at once.
///
/// It is drawn with a few paths ([RocketPainter]): no image, no blur, no shader, so it
/// adds almost nothing to the raster work of a frame (`docs/performance.md`).
class LaunchRocket {
  LaunchRocket._(this._navigator, this._route, this._card);

  final NavigatorState _navigator;
  final Route<void> _route;
  final GlobalKey<_RocketCardState> _card;

  /// Show the rocket over [context], for the launch of [name].
  static LaunchRocket show(BuildContext context, {required String name}) {
    final navigator = Navigator.of(context);
    final card = GlobalKey<_RocketCardState>();
    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (context, animation, secondary) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _RocketCard(key: card, name: name),
        ),
      ),
    );
    unawaited(navigator.push(route));
    return LaunchRocket._(navigator, route, card);
  }

  /// The service started: the rocket lifts off, then the card goes.
  Future<void> liftOff() async {
    await _card.currentState?.liftOff();
    dismiss();
  }

  /// Take the card away, at once. Nothing happens if it is gone already (the user went
  /// back, or a page closed it).
  void dismiss() {
    if (_route.isActive) _navigator.removeRoute(_route);
  }
}

class _RocketCard extends StatefulWidget {
  const _RocketCard({super.key, required this.name});

  final String name;

  @override
  State<_RocketCard> createState() => _RocketCardState();
}

class _RocketCardState extends State<_RocketCard> with TickerProviderStateMixin {
  late final _hover = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _hover.stop();
    } else if (!_hover.isAnimating && !_lift.isAnimating) {
      _hover.repeat();
    }
  }

  Future<void> liftOff() async {
    if (_still || !mounted) return;
    _hover.stop();
    await _lift.forward().orCancel.catchError((_) {});
  }

  @override
  void dispose() {
    _hover.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('run-progress'),
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 132,
              child: ClipRect(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const Key('launch-rocket'),
                    painter: RocketPainter(
                      hover: _hover,
                      lift: _lift,
                      body: scheme.onSurface,
                      window: accentOf(context),
                      flame: rustFor(context),
                      still: _still,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(l.celautRunLaunching(widget.name), style: t.title, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.celautRunLaunchingNote, style: t.secondary, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Paints the rocket: the body, its window, two fins, and the flame under it, which
/// flickers. [hover] moves it a little up and down; [lift] takes it up and out of the box.
class RocketPainter extends CustomPainter {
  RocketPainter({
    required this.hover,
    required this.lift,
    required this.body,
    required this.window,
    required this.flame,
    required this.still,
  }) : super(repaint: Listenable.merge([hover, lift]));

  final Animation<double> hover;
  final Animation<double> lift;
  final Color body;
  final Color window;
  final Color flame;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final phase = still ? 0.0 : hover.value * 2 * pi;
    final up = Curves.easeIn.transform(lift.value) * h;
    final dy = sin(phase) * 3 - up;
    canvas.save();
    canvas.translate(w / 2, h * 0.42 + dy);

    // The flame, under the body: longer and shorter as it flickers.
    final flicker = still ? 1.0 : 0.75 + 0.25 * sin(phase * 3).abs();
    final flamePath = Path()
      ..moveTo(-9, 30)
      ..quadraticBezierTo(0, 30 + 34 * flicker, 9, 30)
      ..close();
    canvas.drawPath(flamePath, Paint()..color = flame);
    final core = Path()
      ..moveTo(-4, 30)
      ..quadraticBezierTo(0, 30 + 18 * flicker, 4, 30)
      ..close();
    canvas.drawPath(core, Paint()..color = window);

    // The fins.
    final fin = Paint()..color = flame;
    canvas.drawPath(
      Path()
        ..moveTo(-14, 10)
        ..lineTo(-24, 32)
        ..lineTo(-14, 28)
        ..close(),
      fin,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, 10)
        ..lineTo(24, 32)
        ..lineTo(14, 28)
        ..close(),
      fin,
    );

    // The body: a nose cone on a rounded hull.
    final hull = Path()
      ..moveTo(0, -44)
      ..quadraticBezierTo(18, -24, 15, 10)
      ..lineTo(13, 30)
      ..lineTo(-13, 30)
      ..lineTo(-15, 10)
      ..quadraticBezierTo(-18, -24, 0, -44)
      ..close();
    canvas.drawPath(hull, Paint()..color = body);
    canvas.drawCircle(const Offset(0, -8), 7, Paint()..color = window);
    canvas.restore();

    // Three puffs of smoke that fall away under the rocket while it hovers.
    if (!still && lift.value == 0) {
      for (var i = 0; i < 3; i++) {
        final p = (hover.value + i / 3) % 1;
        canvas.drawCircle(
          Offset(w / 2 + (i - 1) * 6, h * 0.42 + 64 + p * 26),
          2.5 + p * 2,
          Paint()..color = body.withValues(alpha: 0.25 * (1 - p)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(RocketPainter old) =>
      old.body != body || old.window != window || old.flame != flame || old.still != still;
}
