import 'package:argus_wallet/l10n/app_localizations.dart';
import 'package:argus_wallet/ui/celaut/virtual_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _v(String text, int start, [int? end]) =>
    TextEditingValue(text: text, selection: TextSelection(baseOffset: start, extentOffset: end ?? start));

void main() {
  group('editing', () {
    test('insertAtSelection puts the text at the cursor and moves the cursor', () {
      final r = insertAtSelection(_v('ac', 1), 'b');
      expect((r.text, r.selection.baseOffset), ('abc', 2));
    });

    test('insertAtSelection replaces the selection', () {
      expect(insertAtSelection(_v('abc', 0, 2), 'x').text, 'xc');
    });

    test('with no valid selection the text goes at the end', () {
      expect(insertAtSelection(const TextEditingValue(text: 'ab'), 'c').text, 'abc');
    });

    test('deleteBackward deletes the selection, or the character before the cursor', () {
      expect(deleteBackward(_v('abc', 0, 2)).text, 'c');
      final r = deleteBackward(_v('abc', 2));
      expect((r.text, r.selection.baseOffset), ('ac', 1));
      expect(deleteBackward(_v('abc', 0)).text, 'abc');
    });

    test('deleteBackward deletes a whole emoji', () {
      expect(deleteBackward(_v('a😀', 3)).text, 'a');
    });
  });

  group('widget', () {
    late TextEditingController controller;

    Future<void> pump(WidgetTester t, {int? maxLength}) async {
      controller = TextEditingController();
      addTearDown(controller.dispose);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: ChatVirtualKeyboard(controller: controller, maxLength: maxLength)),
      ));
    }

    testWidgets('letters, space, shift for one letter, and backspace', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('vk-char-h')));
      await t.tap(find.byKey(const Key('vk-shift')));
      await t.pump();
      await t.tap(find.byKey(const Key('vk-char-i')));
      await t.tap(find.byKey(const Key('vk-char-j')));
      await t.tap(find.byKey(const Key('vk-space')));
      await t.tap(find.byKey(const Key('vk-char-ñ')));
      expect(controller.text, 'hIj ñ');
      await t.tap(find.byKey(const Key('vk-backspace')));
      expect(controller.text, 'hIj ');
    });

    testWidgets('the symbols layer has digits, and ABC goes back', (t) async {
      await pump(t);
      expect(find.byKey(const Key('vk-char-1')), findsNothing);
      await t.tap(find.byKey(const Key('vk-symbols')));
      await t.pump();
      await t.tap(find.byKey(const Key('vk-char-1')));
      expect(controller.text, '1');
      await t.tap(find.byKey(const Key('vk-symbols')));
      await t.pump();
      expect(find.byKey(const Key('vk-char-q')), findsOneWidget);
    });

    testWidgets('enter writes a new line', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('vk-enter')));
      expect(controller.text, '\n');
    });

    testWidgets('maxLength stops the text, but backspace still works', (t) async {
      await pump(t, maxLength: 2);
      for (final c in ['a', 'b', 'c']) {
        await t.tap(find.byKey(Key('vk-char-$c')));
      }
      expect(controller.text, 'ab');
      await t.tap(find.byKey(const Key('vk-backspace')));
      expect(controller.text, 'a');
    });
  });
}
