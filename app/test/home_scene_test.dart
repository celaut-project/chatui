import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/home/home_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page with the scene of the overview, as the overview and the Compute tab have it.
Widget _page({required double height, double radius = 80}) => MaterialApp(
      theme: argusTheme(watchful: true),
      home: HomeScene(
        light: SceneLight.eclipse,
        lightAt: const Offset(96, 130),
        lightRadius: radius,
        height: height,
        child: const Scaffold(backgroundColor: Colors.transparent, body: Text('page')),
      ),
    );

void main() {
  setUp(SceneImagePainter.clearImages);
  tearDown(SceneImagePainter.clearImages);

  testWidgets('the scene is drawn from one image, made once for its size and look', (tester) async {
    await tester.pumpWidget(_page(height: 520));
    expect(find.byKey(const Key('home-scene')), findsOneWidget);
    expect(SceneImagePainter.imageCount, 1);

    // A page over it and back, as a route transition does: the same image.
    await tester.pumpWidget(const MaterialApp(home: Text('other')));
    await tester.pumpWidget(_page(height: 520));
    expect(SceneImagePainter.imageCount, 1);

    // Another size or another light has its own image.
    await tester.pumpWidget(_page(height: 560));
    expect(SceneImagePainter.imageCount, 2);
    await tester.pumpWidget(_page(height: 560, radius: 70));
    expect(SceneImagePainter.imageCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a few images are kept, no more', (tester) async {
    for (var h = 400.0; h < 480; h += 10) {
      await tester.pumpWidget(_page(height: h));
    }
    expect(SceneImagePainter.imageCount, 4);
    expect(tester.takeException(), isNull);
  });
}
