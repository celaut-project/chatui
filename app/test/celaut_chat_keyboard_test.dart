import 'package:argus_wallet/celaut/chat_segments.dart';
import 'package:argus_wallet/l10n/app_localizations.dart';
import 'package:argus_wallet/ui/celaut/html_widget.dart';
import 'package:argus_wallet/ui/celaut/keyboard_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitHtmlBlocks keyboard', () {
    test('a closed keyboard block is split out', () {
      expect(splitHtmlBlocks('a\n```keyboard\n<button data-say="Yes">Yes</button>\n```\nb'), [
        const ChatSegment(ChatSegmentKind.text, 'a\n'),
        const ChatSegment(ChatSegmentKind.keyboard, '<button data-say="Yes">Yes</button>'),
        const ChatSegment(ChatSegmentKind.text, 'b'),
      ]);
    });

    test('an open block is pending only while the message streams', () {
      expect(splitHtmlBlocks('```keyboard\n<b', streaming: true).single.kind, ChatSegmentKind.pendingKeyboard);
      expect(splitHtmlBlocks('```keyboard\n<b').single.kind, ChatSegmentKind.text);
    });

    test('with the widgets off it is code', () {
      final s = splitHtmlBlocks('```keyboard\nx\n```', html: false).single;
      expect(s.kind, ChatSegmentKind.code);
      expect(s.lang, 'keyboard');
    });

    test('the blocks after the limit stay text', () {
      final text = List.filled(maxKeyboardBlocks + 1, '```keyboard\nx\n```').join('\n');
      final kinds = splitHtmlBlocks(text).map((s) => s.kind).toList();
      expect(kinds.where((k) => k == ChatSegmentKind.keyboard).length, maxKeyboardBlocks);
    });
  });

  group('keyboardRows', () {
    test('keys, texts and rows', () {
      final rows = keyboardRows('<p>Pick</p><div><button data-say="yes">Yes</button><span data-say="no"></span></div>');
      expect(rows.length, 2);
      expect(rows[0], ['Pick']);
      final keys = rows[1].cast<ChatKey>();
      expect(keys.map((k) => (k.label, k.say)), [('Yes', 'yes'), ('no', 'no')]);
    });

    test('an element with no data-say, or an empty one, is not a key', () {
      expect(keyboardRows('<button>Go</button><b data-say="  ">x</b>'), [
        ['Go', 'x'],
      ]);
    });

    test('data-send makes a key that sends', () {
      final keys = keyboardRows('<button data-say="a" data-send>A</button><button data-say="b">B</button>')
          .single
          .cast<ChatKey>();
      expect(keys.map((k) => k.send), [true, false]);
    });

    test('a data-say that is too long is text, not a key', () {
      final rows = keyboardRows('<button data-say="${'a' * (keyboardMaxSayChars + 1)}">Long</button>');
      expect(rows, [
        ['Long'],
      ]);
    });

    test('there are at most keyboardMaxKeys keys', () {
      final html = List.generate(keyboardMaxKeys + 5, (i) => '<button data-say="k$i">k$i</button>').join();
      expect(keyboardRows(html).expand((r) => r).whereType<ChatKey>().length, keyboardMaxKeys);
    });

    test('a script and an on* attribute are lost', () {
      final rows = keyboardRows('<script>x()</script><button onclick="x()" data-say="a">A</button>');
      expect(rows.single.single, isA<ChatKey>());
    });
  });

  test('applySay puts the text after what the user wrote', () {
    expect(applySay('', 'yes'), 'yes');
    expect(applySay('I say', 'yes'), 'I say yes');
    expect(applySay('I say ', 'yes'), 'I say yes');
    expect(applySay('I say\n', 'yes'), 'I say\nyes');
  });

  testWidgets('a tap on a key calls onSay with its data-say', (t) async {
    final said = <(ChatKey, String)>[];
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: ChatKeyboard(html: '<button data-say="I accept" data-send>OK</button>', onSay: (k, say) => said.add((k, say))),
      ),
    ));
    await t.tap(find.byType(ActionChip));
    expect(said.single.$1.send, isTrue);
    expect(said.single.$2, 'I accept');
  });

  group('fields', () {
    test('an input with a valid data-name is a field', () {
      final rows = keyboardRows('<input data-name="amount" placeholder=" Amount  here "><input data-name="bad name"><input>');
      final f = rows.single.single as ChatKeyField;
      expect((f.name, f.placeholder), ('amount', 'Amount here'));
    });

    test('a second field with the same name, and the fields after the limit, are lost', () {
      expect(keyboardRows('<input data-name="a"><input data-name="a">').single.length, 1);
      final html = List.generate(keyboardMaxFields + 3, (i) => '<input data-name="f$i">').join();
      expect(keyboardRows(html).expand((r) => r).whereType<ChatKeyField>().length, keyboardMaxFields);
    });

    test('fillSay puts the clean value of the field', () {
      expect(fillSay('Send {amount} ERG', {'amount': '  12 \n 5 '}), 'Send 12 5 ERG');
    });

    test('fillSay gives null if a used field is empty', () {
      expect(fillSay('Send {amount}', {'amount': '  '}), isNull);
      expect(fillSay('No field', {'amount': ''}), 'No field');
    });

    test('a name that is not a field stays as it is, and a value is not read again', () {
      expect(fillSay('a {x} b', {}), 'a {x} b');
      expect(fillSay('{a}', {'a': '{b}', 'b': 'no'}), '{b}');
    });

    test('a value has at most keyboardMaxFieldChars characters', () {
      expect(cleanFieldValue('a' * (keyboardMaxFieldChars + 50)).length, keyboardMaxFieldChars);
    });

    testWidgets('a key that uses a field waits until the field has a value', (t) async {
      final said = <String>[];
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ChatKeyboard(
            html: '<input data-name="amount" placeholder="Amount"><button data-say="Send {amount} ERG" data-send>Go</button>',
            onSay: (k, say) => said.add(say),
          ),
        ),
      ));
      await t.tap(find.byType(ActionChip), warnIfMissed: false);
      expect(said, isEmpty);
      await t.enterText(find.byKey(const Key('chat-field-amount')), '7');
      await t.pump();
      await t.tap(find.byType(ActionChip), warnIfMissed: false);
      expect(said, ['Send 7 ERG']);
    });
  });

  group('controls', () {
    ChatKeyField field(String html) => keyboardRows(html).expand((r) => r).whereType<ChatKeyField>().single;

    test('a plain input, and an unknown type, are text', () {
      expect(field('<input data-name="a">').kind, ChatFieldKind.text);
      expect(field('<input type="color" data-name="a">').kind, ChatFieldKind.text);
      expect(field('<input type="password" data-name="a">').kind, ChatFieldKind.text);
    });

    test('a date reads min, max and value, and loses what is not a real day', () {
      final f = field('<input type="date" data-name="d" min="2026-01-10" max="2026-02-30" value="2026-01-15">');
      expect(f.kind, ChatFieldKind.date);
      expect(f.firstDate, DateTime(2026, 1, 10));
      expect(f.lastDate, isNull);
      expect(f.initial, '2026-01-15');
      expect(field('<input type="date" data-name="d" value="15/01/2026">').initial, '');
    });

    test('a date range that is backwards is ignored', () {
      final f = field('<input type="date" data-name="d" min="2026-05-01" max="2026-01-01">');
      expect((f.firstDate, f.lastDate), (null, null));
    });

    test('a time reads value in 24 hours', () {
      expect(field('<input type="time" data-name="t" value="07:05">').initial, '07:05');
      expect(field('<input type="time" data-name="t" value="24:00">').initial, '');
      expect(parseChatTime('9:00'), isNull);
    });

    test('a slider reads min, max, step and value, and snaps the value', () {
      final f = field('<input type="range" data-name="n" min="0" max="10" step="0.5" value="3.3">');
      expect((f.kind, f.min, f.max, f.step, f.decimals), (ChatFieldKind.range, 0, 10, 0.5, 1));
      expect(f.initial, '3.5');
      expect(snapRange(99, f), '10.0');
      expect(snapRange(-4, f), '0.0');
    });

    test('a slider with a bad range or step has the defaults, and starts at the minimum', () {
      final f = field('<input type="range" data-name="n" min="5" max="1" step="-2">');
      expect((f.min, f.max, f.step, f.initial), (0, 100, 1, '0'));
      expect(field('<input type="range" data-name="n" min="NaN" max="Infinity">').max, 100);
    });

    test('a slider with too many steps is continuous', () {
      expect(rangeDivisions(field('<input type="range" data-name="n" max="10">')), 10);
      expect(rangeDivisions(field('<input type="range" data-name="n" max="100000">')), isNull);
    });

    test('a checkbox has a value when on and when off', () {
      final f = field('<input type="checkbox" data-name="c" value="agree" data-off="refuse" checked>');
      expect((f.kind, f.on, f.off, f.initial), (ChatFieldKind.checkbox, 'agree', 'refuse', 'agree'));
      final g = field('<input type="checkbox" data-name="c">');
      expect((g.on, g.off, g.initial), ('yes', 'no', 'no'));
    });

    test('a select has its options, with the label cut, and loses the empty and the repeated', () {
      final f = field(
        '<select data-name="s"><option value="a">Alpha</option><option>Beta</option>'
        '<option value="a">Again</option><option value=""></option><option value="g">${'x' * 120}</option></select>',
      );
      expect(f.kind, ChatFieldKind.select);
      expect(f.options.map((o) => (o.value, o.label.length > 10 ? 'long' : o.label)), [
        ('a', 'Alpha'),
        ('Beta', 'Beta'),
        ('g', 'long'),
      ]);
      expect(f.options.last.label.length, keyboardMaxOptionChars);
    });

    test('options that are not closed are read, and a select has at most keyboardMaxOptions', () {
      expect(field('<select data-name="s"><option>A<option>B<option>C</select>').options.map((o) => o.value), ['A', 'B', 'C']);
      final many = List.generate(keyboardMaxOptions + 5, (i) => '<option>o$i</option>').join();
      expect(field('<select data-name="s">$many</select>').options.length, keyboardMaxOptions);
    });

    test('the controls count as fields: same name and the limit of 8', () {
      expect(keyboardRows('<input type="date" data-name="a"><select data-name="a"></select>').single.length, 1);
      final html = List.generate(keyboardMaxFields + 2, (i) => '<input type="range" data-name="f$i">').join();
      expect(keyboardRows(html).expand((r) => r).whereType<ChatKeyField>().length, keyboardMaxFields);
    });

    test('the text of an option does not show as text of the block', () {
      expect(keyboardRows('<select data-name="s"><option>Alpha</option></select>').single.single, isA<ChatKeyField>());
    });

    test('select is still dropped in an html block', () {
      expect(parseChatHtml('<select><option>x</option></select>y').map((n) => n.tag), [null]);
    });

    Future<void> pump(WidgetTester t, String html, List<String> said) => t.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: ChatKeyboard(html: html, onSay: (k, say) => said.add(say))),
        ));

    testWidgets('a slider moves, and its value goes in the key', (t) async {
      final said = <String>[];
      await pump(t, '<input type="range" data-name="n" min="0" max="10" value="2" placeholder="Amount">'
          '<button data-say="Take {n}">Go</button>', said);
      await t.tap(find.byType(ActionChip));
      expect(said, ['Take 2']);
      await t.drag(find.byKey(const Key('chat-field-n')), const Offset(500, 0));
      await t.pump();
      await t.tap(find.byType(ActionChip));
      expect(said.last, 'Take 10');
    });

    testWidgets('a checkbox toggles, and it never blocks the key', (t) async {
      final said = <String>[];
      await pump(t, '<input type="checkbox" data-name="c" value="agree" data-off="refuse" placeholder="I agree">'
          '<button data-say="I {c}">Go</button>', said);
      await t.tap(find.byType(ActionChip));
      await t.tap(find.byKey(const Key('chat-field-c')));
      await t.pump();
      await t.tap(find.byType(ActionChip));
      expect(said, ['I refuse', 'I agree']);
    });

    testWidgets('a select waits for an option, then gives its value', (t) async {
      final said = <String>[];
      await pump(t, '<select data-name="s" placeholder="Pick"><option value="a">Alpha</option><option value="b">Beta</option></select>'
          '<button data-say="Take {s}">Go</button>', said);
      await t.tap(find.byType(ActionChip), warnIfMissed: false);
      expect(said, isEmpty);
      await t.tap(find.byKey(const Key('chat-field-s')));
      await t.pumpAndSettle();
      await t.tap(find.text('Beta').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(ActionChip));
      expect(said, ['Take b']);
    });

    testWidgets('a date waits for a day from the calendar', (t) async {
      final said = <String>[];
      await pump(t, '<input type="date" data-name="d" min="2026-03-01" max="2026-03-31" value="2026-03-10">'
          '<button data-say="On {d}">Go</button>', said);
      await t.tap(find.byType(ActionChip));
      expect(said, ['On 2026-03-10']);
      await t.tap(find.byKey(const Key('chat-field-d')));
      await t.pumpAndSettle();
      await t.tap(find.text('20'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.byType(ActionChip));
      expect(said.last, 'On 2026-03-20');
    });

    testWidgets('a time gives HH:MM', (t) async {
      final said = <String>[];
      await pump(t, '<input type="time" data-name="t" value="08:30"><button data-say="At {t}">Go</button>', said);
      await t.tap(find.byType(ActionChip));
      expect(said, ['At 08:30']);
    });
  });
}
