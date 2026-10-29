import 'dart:convert';

import 'package:argus_wallet/celaut/chat_segments.dart';
import 'package:argus_wallet/ui/celaut/html_widget.dart';
import 'package:argus_wallet/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String dump(List<HtmlNode> ns) => ns
    .map((n) => n.tag == null
        ? n.text!
        : '<${n.tag}${(n.attrs.keys.toList()..sort()).map((k) => ' $k').join()}>${dump(n.children)}</${n.tag}>')
    .join();

int count(List<HtmlNode> ns) => ns.fold(0, (a, n) => a + 1 + count(n.children));
int depth(List<HtmlNode> ns) => ns.isEmpty ? 0 : 1 + ns.map((n) => depth(n.children)).reduce((a, b) => a > b ? a : b);

Future<void> pump(WidgetTester t, String html, {Brightness b = Brightness.light}) => t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: SingleChildScrollView(child: ChatHtmlWidget(html: html))),
    ));

void main() {
  group('splitHtmlBlocks', () {
    test('plain text stays one segment', () {
      expect(splitHtmlBlocks('hello\nworld'), [const ChatSegment(ChatSegmentKind.text, 'hello\nworld')]);
      expect(splitHtmlBlocks(''), isEmpty);
    });

    test('a closed block is split out', () {
      final s = splitHtmlBlocks('before\n```html\n<b>x</b>\n```\nafter');
      expect(s, [
        const ChatSegment(ChatSegmentKind.text, 'before\n'),
        const ChatSegment(ChatSegmentKind.html, '<b>x</b>'),
        const ChatSegment(ChatSegmentKind.text, 'after'),
      ]);
    });

    test('other fences are code, with the language', () {
      expect(splitHtmlBlocks('a\n```Dart\nvar a;\n```\nb'), [
        const ChatSegment(ChatSegmentKind.text, 'a\n'),
        const ChatSegment(ChatSegmentKind.code, 'var a;', 'dart'),
        const ChatSegment(ChatSegmentKind.text, 'b'),
      ]);
      expect(splitHtmlBlocks('```\nx\n```').single, const ChatSegment(ChatSegmentKind.code, 'x'));
    });

    test('an html fence inside code stays code', () {
      expect(splitHtmlBlocks('```python\n# ```html\nx\n```').single.kind, ChatSegmentKind.code);
    });

    test('with html off, an html fence is code', () {
      expect(splitHtmlBlocks('```html\n<p>a\n```', html: false).single,
          const ChatSegment(ChatSegmentKind.code, '<p>a', 'html'));
    });

    test('an open code block is pending while streaming and text otherwise', () {
      const t = 'a\n```rust\nfn main() {';
      expect(splitHtmlBlocks(t, streaming: true), [
        const ChatSegment(ChatSegmentKind.text, 'a\n'),
        const ChatSegment(ChatSegmentKind.pendingCode, 'fn main() {', 'rust'),
      ]);
      expect(splitHtmlBlocks(t), [const ChatSegment(ChatSegmentKind.text, t)]);
    });

    test('a code block over the limit stays text and its closing fence opens nothing', () {
      final t = '```c\n${'x' * (maxCodeBlockChars + 1)}\n```\nafter';
      expect(splitHtmlBlocks(t, streaming: true), [ChatSegment(ChatSegmentKind.text, t)]);
    });

    test('an open block is pending while streaming and text otherwise', () {
      const t = 'a\n```html\n<p>par';
      expect(splitHtmlBlocks(t, streaming: true), [
        const ChatSegment(ChatSegmentKind.text, 'a\n'),
        const ChatSegment(ChatSegmentKind.pendingHtml, '<p>par'),
      ]);
      expect(splitHtmlBlocks(t), [const ChatSegment(ChatSegmentKind.text, t)]);
    });

    test('a partial opening fence is an open block with a short language', () {
      expect(splitHtmlBlocks('x\n```ht', streaming: true).last, const ChatSegment(ChatSegmentKind.pendingCode, '', 'ht'));
      expect(splitHtmlBlocks('x\n```ht').single.kind, ChatSegmentKind.text);
    });

    test('two blocks and CRLF', () {
      final s = splitHtmlBlocks('```html\r\n<i>a</i>\r\n```\r\nmid\n```HTML\n<u>b</u>\n```');
      expect(s.where((e) => e.kind == ChatSegmentKind.html).length, 2);
    });

    test('too long and too many blocks stay text', () {
      final big = '```html\n${'a' * (maxHtmlBlockChars + 1)}\n```';
      expect(splitHtmlBlocks(big).single.kind, ChatSegmentKind.text);
      final many = List.filled(maxHtmlBlocks + 3, '```html\n<b>x</b>\n```').join('\n');
      expect(splitHtmlBlocks(many).where((e) => e.kind == ChatSegmentKind.html).length, maxHtmlBlocks);
    });

    test('hostile input does not hang', () {
      final sw = Stopwatch()..start();
      splitHtmlBlocks('```html\n' * 50000, streaming: true);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('parseChatHtml', () {
    test('a letter that changes length in lower case does not shift the offsets', () {
      // "İ".toLowerCase() has two code units: offsets of a lower case copy would be wrong.
      final hostile = '${'İ' * 50}<script>x</script><b>ok</b><SCRIPT>y</SCRIPT><i>z</i>'
          '<p title="İİİ" STYLE="color:red">İ</p><script>İ';
      final out = dump(parseChatHtml(hostile));
      expect(out, contains('<b>ok</b>'));
      expect(out, contains('<i>z</i>'));
      expect(out, isNot(contains('x</script')));
      expect(out, isNot(contains('y<')));
      expect(() => parseChatHtml('<script>İ</SCRİPT><b>a</b>'), returnsNormally);
      expect(dump(parseChatHtml('<ScRiPt>a</sCrIpT><b>a</b>')), '<b>a</b>');
    });

    test('keeps allowed tags and drops scripts with content', () {
      expect(dump(parseChatHtml('<p>a<b>b</b></p><script>alert(1)</script>c')), '<p>a<b>b</b></p>c');
      expect(dump(parseChatHtml('<style>p{}</style><iframe src=x>t</iframe><svg><b>z</b></svg>ok')), 'ok');
    });

    test('unwraps unknown tags and loses event handlers', () {
      expect(dump(parseChatHtml('<marquee><b onclick="x()" onmouseover=y class=z>t</b></marquee>')), '<b>t</b>');
      expect(dump(parseChatHtml('<a href="http://x" onclick="e">l</a>')), '<a href>l</a>');
    });

    test('unterminated script and comments are dropped', () {
      expect(dump(parseChatHtml('a<script>b')), 'a');
      expect(dump(parseChatHtml('a<!-- b')), 'a');
      expect(dump(parseChatHtml('a<!-- b -->c')), 'ac');
      expect(dump(parseChatHtml('<!doctype html>a')), 'a');
    });

    test('entities decode', () {
      expect(dump(parseChatHtml('&lt;b&gt; &amp; &#65;&#x42; &bogus; &#0;')), '<b> & AB &bogus; �');
    });

    test('broken markup does not throw', () {
      for (final s in ['<', '<<<', '<a', '<a href="x', '</', '</p></p>', '<p <p>', '< b>', '<b/>x', '<a b=>']) {
        expect(() => parseChatHtml(s), returnsNormally, reason: s);
      }
    });

    test('limits on depth, nodes and input', () {
      final deep = '<div>' * 5000;
      expect(depth(parseChatHtml(deep)), lessThanOrEqualTo(htmlMaxDepth + 1));
      expect(count(parseChatHtml('<b>x</b>' * 50000)), lessThanOrEqualTo(htmlMaxNodes));
      expect(count(parseChatHtml('a' * 1000000)), 1);
      final sw = Stopwatch()..start();
      parseChatHtml('<' * 100000);
      parseChatHtml('<a b="' * 10000);
      parseChatHtml('<script>' * 10000);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('colors', () {
    test('parses safe forms', () {
      expect(parseCssColor('#f00'), const Color(0xffff0000));
      expect(parseCssColor('#00ff00'), const Color(0xff00ff00));
      expect(parseCssColor('rgb(0, 0, 255)'), const Color(0xff0000ff));
      expect(parseCssColor('RED'), isNotNull);
      expect(parseCssColor('rgba(255,0,0,0.5)')!.a, closeTo(0.5, 0.01));
    });

    test('rejects the rest', () {
      for (final s in ['url(http://x)', 'expression(1)', '#12', '#gg0000', 'var(--x)', 'rgb(1,2)', '', 'x' * 100]) {
        expect(parseCssColor(s), isNull, reason: s);
      }
    });
  });

  group('decodeDataImage', () {
    final png = base64.encode(List.filled(10, 1));
    test('accepts png and jpeg data URIs only', () {
      expect(decodeDataImage('data:image/png;base64,$png'), isNotNull);
      expect(decodeDataImage('data:image/jpeg;base64,$png'), isNotNull);
      expect(decodeDataImage('data:image/svg+xml;base64,$png'), isNull);
      expect(decodeDataImage('http://example.com/a.png'), isNull);
      expect(decodeDataImage('file:///etc/passwd'), isNull);
      expect(decodeDataImage('data:image/png;base64,!!!'), isNull);
      expect(decodeDataImage(null), isNull);
    });

    test('rejects large images', () {
      final big = base64.encode(List.filled(htmlMaxImageBytes + 10, 1));
      expect(decodeDataImage('data:image/png;base64,$big'), isNull);
    });
  });

  group('ChatHtmlWidget', () {
    testWidgets('shows text, lists and tables', (t) async {
      await pump(t, '<h1>Title</h1><p>Hello <b>bold</b></p><ul><li>one</li><li>two</li></ul>'
          '<ol><li>first</li></ol><table><tr><th>H</th><td>C</td></tr></table><hr>');
      expect(find.text('Title'), findsOneWidget);
      expect(find.textContaining('Hello', findRichText: true), findsOneWidget);
      expect(find.text('one', findRichText: true), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('script and hostile input show nothing', (t) async {
      await pump(t, '<script>alert(1)</script><img src="http://evil/x.png"><img src="javascript:x"><iframe src=x></iframe>');
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('alert', findRichText: true), findsNothing);
    });

    testWidgets('the pending card has the frame and a loading mark', (t) async {
      await t.pumpWidget(const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChatHtmlPendingCard()),
      ));
      expect(find.byKey(const Key('chat-html-pending')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('the code block shows the language and the code', (t) async {
      await t.pumpWidget(const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChatCodeBlock(code: 'var a;', lang: 'dart', pending: true)),
      ));
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('var a;', findRichText: true), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('chat-code-copy')), findsOneWidget);
    });

    testWidgets('the Markdown shows with no symbols, and links and images make nothing', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: ChatMarkdown(data: '**bold** and *it*\n\n- one\n\n[go](https://x.test) ![pic](https://x.test/a.png)')),
      ));
      final text = t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('|');
      expect(text, contains('bold and it'));
      expect(text, isNot(contains('**')));
      expect(text, contains('go'));
      expect(text, contains('pic'));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('empty input renders no widget', (t) async {
      await pump(t, '');
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a data image is shown', (t) async {
      await pump(t, '<img src="data:image/png;base64,${base64.encode(List.filled(20, 0))}">');
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a color with no contrast is not used, in light and dark', (t) async {
      for (final b in Brightness.values) {
        await pump(t, '<span style="color:#ffffff">w</span><span style="color:#000000">k</span>', b: b);
        await t.pumpAndSettle();
        final spans = <TextSpan>[];
        t.widgetList<RichText>(find.byType(RichText)).forEach((r) => r.text.visitChildren((s) {
              if (s is TextSpan && (s.text == 'w' || s.text == 'k')) spans.add(s);
              return true;
            }));
        final w = spans.firstWhere((s) => s.text == 'w').style!.color;
        final k = spans.firstWhere((s) => s.text == 'k').style!.color;
        if (b == Brightness.light) {
          expect(w, isNot(const Color(0xffffffff)));
          expect(k, const Color(0xff000000));
        } else {
          expect(k, isNot(const Color(0xff000000)));
          expect(w, const Color(0xffffffff));
        }
      }
    });

    testWidgets('deep nesting and a big table render without error', (t) async {
      await pump(t, '<div>' * 3000 + 'x');
      await pump(t, '<table>${'<tr>${'<td>c</td>' * 40}</tr>' * 30}</table>');
      expect(t.takeException(), isNull);
    });

    testWidgets('block background keeps the text readable', (t) async {
      await pump(t, '<div style="background-color:#000000">dark box</div>');
      final r = t.widget<RichText>(find.byType(RichText).last);
      var color = const Color(0x00000000);
      r.text.visitChildren((s) {
        if (s is TextSpan && s.text == 'dark box') color = s.style!.color!;
        return true;
      });
      expect(color.computeLuminance(), greaterThan(0.4));
    });
  });
}
