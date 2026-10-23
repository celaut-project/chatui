import 'dart:math';

import 'package:flutter/material.dart';

/// The parts of the robot of one instance. They come from the instance id, so an instance
/// keeps its robot after a restart of the app, and two instances rarely share one.
///
/// The robots are drawn here, with paths: there is no image file, no network and no
/// licence of a third party (original art of this repository, GPL-3.0-only like the app).
@immutable
class RobotFace {
  const RobotFace({
    required this.head,
    required this.eyes,
    required this.mouth,
    required this.antenna,
    required this.hue,
  });

  /// The robot of [seed] (the instance id). The same seed gives the same robot.
  factory RobotFace.of(String seed) {
    // FNV-1a, 32 bits: the same number on every phone and in every run.
    var h = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return RobotFace(
      head: h % heads,
      eyes: (h >> 4) % eyeKinds,
      mouth: (h >> 8) % mouths,
      antenna: (h >> 12) % antennas,
      hue: (h >> 16) % hues,
    );
  }

  static const heads = 3;
  static const eyeKinds = 4;
  static const mouths = 4;
  static const antennas = 4;
  static const hues = 8;

  final int head;
  final int eyes;
  final int mouth;
  final int antenna;
  final int hue;

  /// The hue in degrees: eight hues, 45 degrees apart.
  double get hueDegrees => hue * 360.0 / hues + 15;

  @override
  bool operator ==(Object other) =>
      other is RobotFace &&
      other.head == head &&
      other.eyes == eyes &&
      other.mouth == mouth &&
      other.antenna == antenna &&
      other.hue == hue;

  @override
  int get hashCode => Object.hash(head, eyes, mouth, antenna, hue);
}

/// The round mark of an instance: a robot of its own, from the instance id
/// ([RobotFace.of]). Services have no picture of their own, so every instance gets one.
class RobotAvatar extends StatelessWidget {
  const RobotAvatar({super.key, required this.seed, this.size = 40});

  /// The instance id.
  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final face = RobotFace.of(seed);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = face.hueDegrees;
    final disc = HSLColor.fromAHSL(1, hue, 0.42, dark ? 0.30 : 0.84).toColor();
    final body = HSLColor.fromAHSL(1, hue, 0.38, dark ? 0.80 : 0.32).toColor();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          key: Key('robot-$seed'),
          size: Size.square(size),
          painter: RobotPainter(face: face, disc: disc, body: body),
        ),
      ),
    );
  }
}

/// Paints [face] in a unit square scaled to the size: the disc, the antenna, the head,
/// and the eyes and the mouth cut out of the head in the colour of the disc.
class RobotPainter extends CustomPainter {
  const RobotPainter({required this.face, required this.disc, required this.body});

  final RobotFace face;
  final Color disc;
  final Color body;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s);
    final discPaint = Paint()..color = disc;
    final bodyPaint = Paint()..color = body;
    final line = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(0.5, 0.5), 0.5, discPaint);

    // The head: wide, round or tall.
    const widths = [0.58, 0.52, 0.48];
    const heights = [0.40, 0.44, 0.48];
    const radii = [0.10, 0.20, 0.06];
    final w = widths[face.head], h = heights[face.head];
    final top = 0.60 - h / 2;
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0.5, 0.60), width: w, height: h),
      Radius.circular(radii[face.head]),
    );

    // The antenna, above the head.
    switch (face.antenna) {
      case 0:
        canvas.drawLine(Offset(0.5, top), const Offset(0.5, 0.20), line);
        canvas.drawCircle(const Offset(0.5, 0.18), 0.045, bodyPaint);
      case 1:
        canvas.drawLine(Offset(0.42, top), const Offset(0.36, 0.22), line);
        canvas.drawLine(Offset(0.58, top), const Offset(0.64, 0.22), line);
        canvas.drawCircle(const Offset(0.36, 0.21), 0.035, bodyPaint);
        canvas.drawCircle(const Offset(0.64, 0.21), 0.035, bodyPaint);
      case 2:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(0.44, top - 0.07, 0.56, top + 0.01),
            const Radius.circular(0.02),
          ),
          bodyPaint,
        );
      default:
        // No antenna: ears on the sides of the head instead.
        for (final x in [0.5 - w / 2 - 0.05, 0.5 + w / 2]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 0.53, 0.05, 0.14),
              const Radius.circular(0.02),
            ),
            bodyPaint,
          );
        }
    }
    canvas.drawRRect(head, bodyPaint);

    // The eyes, in the colour of the disc.
    final eyeY = 0.60 - h * 0.12;
    switch (face.eyes) {
      case 0:
        canvas.drawCircle(Offset(0.5 - w * 0.2, eyeY), 0.055, discPaint);
        canvas.drawCircle(Offset(0.5 + w * 0.2, eyeY), 0.055, discPaint);
      case 1:
        for (final x in [0.5 - w * 0.2, 0.5 + w * 0.2]) {
          canvas.drawRect(Rect.fromCenter(center: Offset(x, eyeY), width: 0.09, height: 0.09), discPaint);
        }
      case 2:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0.5, eyeY), width: w * 0.7, height: 0.08),
            const Radius.circular(0.04),
          ),
          discPaint,
        );
      default:
        canvas.drawCircle(Offset(0.5, eyeY), 0.08, discPaint);
        canvas.drawCircle(Offset(0.5, eyeY), 0.03, bodyPaint);
    }

    // The mouth.
    final mouthY = 0.60 + h * 0.24;
    final mouthLine = Paint()
      ..color = disc
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03
      ..strokeCap = StrokeCap.round;
    switch (face.mouth) {
      case 0:
        for (var i = -1; i <= 1; i++) {
          canvas.drawRect(
            Rect.fromCenter(center: Offset(0.5 + i * 0.06, mouthY), width: 0.03, height: 0.06),
            discPaint,
          );
        }
      case 1:
        canvas.drawLine(Offset(0.5 - w * 0.22, mouthY), Offset(0.5 + w * 0.22, mouthY), mouthLine);
      case 2:
        canvas.drawArc(
          Rect.fromCenter(center: Offset(0.5, mouthY - 0.04), width: w * 0.42, height: 0.1),
          0.15 * pi,
          0.7 * pi,
          false,
          mouthLine,
        );
      default:
        canvas.drawCircle(Offset(0.5 - 0.05, mouthY), 0.02, discPaint);
        canvas.drawCircle(Offset(0.5 + 0.05, mouthY), 0.02, discPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RobotPainter old) => old.face != face || old.disc != disc || old.body != body;
}
