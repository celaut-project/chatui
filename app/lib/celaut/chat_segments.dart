/// What a part of a chat message is: plain text, a closed fenced HTML block, a closed
/// fenced code block (any other language, or none), or one of those two kinds of block
/// that has no closing fence yet.
enum ChatSegmentKind { text, html, pendingHtml, code, pendingCode }

/// A part of the `text` of a chat message. For the block kinds, [text] is the content with
/// no fence lines. For [ChatSegmentKind.text], [text] is the text as it is. For
/// [ChatSegmentKind.code] and [ChatSegmentKind.pendingCode], [lang] is the language of the
/// fence in lower case ("" if the fence has none).
class ChatSegment {
  const ChatSegment(this.kind, this.text, [this.lang = '']);

  final ChatSegmentKind kind;
  final String text;
  final String lang;

  @override
  bool operator ==(Object other) =>
      other is ChatSegment && other.kind == kind && other.text == text && other.lang == lang;

  @override
  int get hashCode => Object.hash(kind, text, lang);

  @override
  String toString() => 'ChatSegment($kind, ${text.length} chars${lang.isEmpty ? '' : ', $lang'})';
}

/// The most characters of one HTML block. A longer block stays plain text, so it shows as code.
const int maxHtmlBlockChars = 20000;

/// The most HTML blocks that one message can have. The blocks after this stay plain text.
const int maxHtmlBlocks = 8;

/// The most characters of one code block. A longer block stays plain text.
const int maxCodeBlockChars = 60000;

/// The most code blocks that one message can have. The blocks after this stay plain text.
const int maxCodeBlocks = 32;

final RegExp _openFence = RegExp(r'^ {0,3}```[ \t]*([A-Za-z0-9_+#.\-]*)[ \t]*$');
final RegExp _closeFence = RegExp(r'^ {0,3}```[ \t]*$');

/// Splits [text] at the fenced blocks that start with a line "```lang" (or "```") and end
/// with a line "```", as Markdown does. The parts in sequence give back [text] when the
/// fence lines are put back. A "```html" block is [ChatSegmentKind.html] if [html] is true,
/// and any other block is [ChatSegmentKind.code], with the language in [ChatSegment.lang].
///
/// A block with no closing fence is pending if [streaming] is true (the message is open
/// and the fence can still come), and plain text if it is false. A block that is too long,
/// or one after [maxHtmlBlocks] or [maxCodeBlocks], stays plain text.
List<ChatSegment> splitHtmlBlocks(String text, {bool streaming = false, bool html = true}) {
  if (!text.contains('`')) return text.isEmpty ? const [] : [ChatSegment(ChatSegmentKind.text, text)];
  final lines = text.split('\n');
  final out = <ChatSegment>[];
  final plain = StringBuffer();
  var htmlBlocks = 0;
  var codeBlocks = 0;

  void flushPlain() {
    if (plain.isEmpty) return;
    out.add(ChatSegment(ChatSegmentKind.text, plain.toString()));
    plain.clear();
  }

  // The text of the lines [from, to) with their line breaks, as in [text].
  String raw(int from, int to) => lines.sublist(from, to).join('\n');

  // One pass for the work of all fences: the next closing fence at or after each line, and
  // the size of the lines before each line. A hostile text then costs a linear time.
  final nextClose = List<int>.filled(lines.length + 1, -1);
  final size = List<int>.filled(lines.length + 1, 0);
  for (var k = lines.length - 1; k >= 0; k--) {
    nextClose[k] = _closeFence.hasMatch(_noCr(lines[k])) ? k : nextClose[k + 1];
  }
  for (var k = 0; k < lines.length; k++) {
    size[k + 1] = size[k] + lines[k].length + 1;
  }

  var i = 0;
  while (i < lines.length) {
    final open = _openFence.firstMatch(_noCr(lines[i]));
    if (open != null) {
      final lang = open.group(1)!.toLowerCase();
      final isHtml = html && lang == 'html';
      final canOpen = isHtml ? htmlBlocks < maxHtmlBlocks : codeBlocks < maxCodeBlocks;
      final limit = isHtml ? maxHtmlBlockChars : maxCodeBlockChars;
      final close = nextClose[i + 1];
      final end = close < 0 ? lines.length : close;
      final fits = canOpen && size[end] - size[i + 1] <= limit + 1;
      if (close >= 0 && fits) {
        flushPlain();
        final body = raw(i + 1, close);
        out.add(isHtml ? ChatSegment(ChatSegmentKind.html, body) : ChatSegment(ChatSegmentKind.code, body, lang));
        isHtml ? htmlBlocks++ : codeBlocks++;
        i = close + 1;
        continue;
      }
      if (close < 0 && streaming && fits) {
        flushPlain();
        final body = raw(i + 1, lines.length);
        out.add(isHtml
            ? ChatSegment(ChatSegmentKind.pendingHtml, body)
            : ChatSegment(ChatSegmentKind.pendingCode, body, lang));
        break;
      }
      if (close >= 0) {
        // A closed block that stays text: its closing fence must not open another block.
        plain.write(raw(i, close + 1));
        if (close < lines.length - 1) plain.write('\n');
        i = close + 1;
        continue;
      }
    }
    // Plain line: the line break is kept between lines, not after the last one.
    plain.write(lines[i]);
    if (i < lines.length - 1) plain.write('\n');
    i++;
  }
  flushPlain();
  return out;
}

String _noCr(String l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l;
