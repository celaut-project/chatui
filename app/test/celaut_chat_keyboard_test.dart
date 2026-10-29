import 'package:argus_wallet/celaut/chat_segments.dart';
import 'package:argus_wallet/l10n/app_localizations.dart';
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
}
