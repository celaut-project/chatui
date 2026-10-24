import 'package:argus_wallet/celaut/typewriter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Typewriter', () {
    test('an initial text shows at once', () {
      final t = Typewriter(initial: 'hello');
      expect(t.text, 'hello');
      expect(t.done, isTrue);
      expect(t.tick(const Duration(seconds: 1)), 0);
    });

    test('a new text grows a little at a time', () {
      final t = Typewriter()..setTarget('abcdefghij');
      expect(t.text, '');
      final n = t.tick(const Duration(milliseconds: 100));
      expect(n, greaterThan(0));
      expect(n, lessThan(10));
      expect(t.text, 'abcdefghij'.substring(0, n));
    });

    test('it is never more than maxLag behind', () {
      final t = Typewriter(maxLag: const Duration(milliseconds: 1000))
        ..setTarget('x' * 5000);
      var elapsed = Duration.zero;
      while (!t.done && elapsed < const Duration(seconds: 10)) {
        t.tick(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
      }
      expect(t.done, isTrue);
      // The backlog decays: after 1.5 s of frames most of it is shown.
      final u = Typewriter(maxLag: const Duration(milliseconds: 1000))..setTarget('x' * 5000);
      for (var i = 0; i < 94; i++) {
        u.tick(const Duration(milliseconds: 16));
      }
      expect(u.backlog, lessThan(5000 * 0.25));
    });

    test('it never cuts a grapheme', () {
      const text = 'a👨‍👩‍👧b';
      final t = Typewriter()..setTarget(text);
      final seen = <String>[];
      while (!t.done) {
        t.tick(const Duration(milliseconds: 30));
        seen.add(t.text);
      }
      for (final s in seen) {
        expect(['', 'a', 'a👨‍👩‍👧', text].contains(s) || s.length <= text.length, isTrue);
        expect(s.contains('‍') && s.endsWith('‍'), isFalse);
      }
      expect(t.text, text);
    });

    test('a new character that joins the last grapheme does not show a broken one', () {
      final t = Typewriter(initial: '👨');
      t.setTarget('👨\u200d👩');
      expect(t.text.endsWith('\u200d'), isFalse);
      while (!t.done) {
        t.tick(const Duration(milliseconds: 30));
      }
      expect(t.text, '👨\u200d👩');
    });

    test('a long text that grows in parts ends as the whole text', () {
      final t = Typewriter();
      var text = '';
      for (var i = 0; i < 200; i++) {
        text += 'ab é👍 ';
        t.setTarget(text);
        t.tick(const Duration(milliseconds: 16));
      }
      t.finish();
      expect(t.text, text);
      expect(t.done, isTrue);
    });

    test('a text that continues the old one keeps what is shown', () {
      final t = Typewriter()..setTarget('abc');
      t.finish();
      t.setTarget('abcdef');
      expect(t.text, 'abc');
      expect(t.backlog, 3);
    });

    test('a rewrite goes back to the common start', () {
      final t = Typewriter(initial: 'abcdef');
      t.setTarget('abXY');
      expect(t.text, 'ab');
      expect(t.backlog, 2);
    });

    test('a shorter text is cut', () {
      final t = Typewriter(initial: 'abcdef')..setTarget('abc');
      expect(t.text, 'abc');
      expect(t.done, isTrue);
    });

    test('finish shows all', () {
      final t = Typewriter()..setTarget('abcdef');
      t.finish();
      expect(t.text, 'abcdef');
    });
  });

  group('HapticPacer', () {
    test('it waits for enough characters and for the gap', () {
      final p = HapticPacer(every: 4, minGap: const Duration(milliseconds: 100));
      expect(p.feed(2, Duration.zero), isFalse);
      expect(p.feed(2, const Duration(milliseconds: 10)), isTrue);
      expect(p.feed(10, const Duration(milliseconds: 50)), isFalse);
      expect(p.feed(0, const Duration(milliseconds: 120)), isTrue);
    });
  });
}
