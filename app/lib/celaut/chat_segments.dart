/// What a part of a chat message is: plain text (Markdown for the screen), a closed
/// fenced HTML block, or an HTML block that has no closing fence yet.
enum ChatSegmentKind { text, html, pendingHtml }

/// A part of the `text` of a chat message. For [ChatSegmentKind.html] and
/// [ChatSegmentKind.pendingHtml], [text] is the HTML with no fence lines. For
/// [ChatSegmentKind.text], [text] is the text as it is.
class ChatSegment {
  const ChatSegment(this.kind, this.text);

  final ChatSegmentKind kind;
  final String text;

  @override
  bool operator ==(Object other) => other is ChatSegment && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'ChatSegment($kind, ${text.length} chars)';
}

/// The most characters of one HTML block. A longer block stays plain text, so it shows as code.
const int maxHtmlBlockChars = 20000;

/// The most HTML blocks that one message can have. The blocks after this stay plain text.
const int maxHtmlBlocks = 8;

final RegExp _openFence = RegExp(r'^ {0,3}```[ \t]*html[ \t]*$', caseSensitive: false);
final RegExp _closeFence = RegExp(r'^ {0,3}```[ \t]*$');

/// Splits [text] at the fenced blocks that start with a line "```html" and end with a
/// line "```". The parts in sequence give back [text] when the fence lines are put back.
///
/// A block with no closing fence is [ChatSegmentKind.pendingHtml] if [streaming] is true
/// (the message is open and the fence can still come), and plain text if it is false.
/// A block that is too long, or one after [maxHtmlBlocks], stays plain text.
List<ChatSegment> splitHtmlBlocks(String text, {bool streaming = false}) {
  if (!text.contains('`')) return text.isEmpty ? const [] : [ChatSegment(ChatSegmentKind.text, text)];
  final lines = text.split('\n');
  final out = <ChatSegment>[];
  final plain = StringBuffer();
  var blocks = 0;

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
    if (blocks < maxHtmlBlocks && _openFence.hasMatch(_noCr(lines[i]))) {
      final close = nextClose[i + 1];
      final end = close < 0 ? lines.length : close;
      final fits = size[end] - size[i + 1] <= maxHtmlBlockChars + 1;
      if (close >= 0 && fits) {
        flushPlain();
        out.add(ChatSegment(ChatSegmentKind.html, raw(i + 1, close)));
        blocks++;
        i = close + 1;
        continue;
      }
      if (close < 0 && streaming && fits) {
        flushPlain();
        out.add(ChatSegment(ChatSegmentKind.pendingHtml, raw(i + 1, lines.length)));
        break;
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
