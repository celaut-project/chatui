import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/celaut/robot_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Each instance has a robot of its own, from its id (Josemi, 2026-10-23).

void main() {
  test('the same id gives the same robot, in every run', () {
    const id = '0f3c9e7a5b1d4c2e8f6a0b9c7d5e3f1a';
    expect(RobotFace.of(id), RobotFace.of(id));
    // Fixed values: the robot of an instance does not change with a new version of the
    // app unless this test changes too.
    expect(RobotFace.of('a'), const RobotFace(head: 1, eyes: 2, mouth: 1, antenna: 2, hue: 4));
    expect(RobotFace.of(id), const RobotFace(head: 2, eyes: 0, mouth: 1, antenna: 2, hue: 7));
  });

  test('the ids of many instances give many different robots', () {
    final faces = {
      for (var i = 0; i < 200; i++) RobotFace.of('instance-$i'),
    };
    expect(faces.length, greaterThan(100));
    // Every part is used.
    expect({for (final f in faces) f.head}.length, RobotFace.heads);
    expect({for (final f in faces) f.eyes}.length, RobotFace.eyeKinds);
    expect({for (final f in faces) f.mouth}.length, RobotFace.mouths);
    expect({for (final f in faces) f.antenna}.length, RobotFace.antennas);
    expect({for (final f in faces) f.hue}.length, RobotFace.hues);
  });

  testWidgets('every robot paints in the light and the dark theme', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: argusTheme(watchful: false).copyWith(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: Wrap(
              children: [
                for (var i = 0; i < 64; i++) RobotAvatar(seed: 'instance-$i', size: 40),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RobotAvatar), findsNWidgets(64));
    }
    // A screen reader skips the picture.
    expect(
      tester.getSemantics(find.byKey(const Key('robot-instance-0'))).label,
      isEmpty,
    );
  });
}
