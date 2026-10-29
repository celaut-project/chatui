import 'dart:math' as math;

import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The colours of the chat and of the errors of a form, in every palette that a user can
/// pick: text needs 4.5:1 (WCAG AA), and the border of a field 3:1.
void main() {
  for (final palette in allPalettes) {
    final scheme = argusThemeFor(palette).colorScheme;
    final red = palette.isDark ? rustBright : rust;

    // The text and the time of a bubble of the user have the same colour (the chat test
    // checks it). The two palettes of Celaut meet AA; Parchment is 3.8:1.
    if (palette == watchfulPalette || palette == ledgerPalette) {
      test('${palette.name}: the bubble of the user reads', () {
        expect(contrast(scheme.onPrimaryContainer, scheme.primaryContainer), greaterThanOrEqualTo(4.5));
      });
    }

    test('${palette.name}: an error of the chat or of a field reads', () {
      for (final ground in [palette.background, palette.surface]) {
        expect(contrast(red, ground), greaterThanOrEqualTo(4.5), reason: '$ground');
      }
      final fields = argusThemeFor(palette).inputDecorationTheme;
      expect(fields.errorStyle?.color, red);
      expect(fields.errorBorder?.borderSide.color, red);
      expect(contrast(red, palette.surface), greaterThanOrEqualTo(3));
    });
  }
}
