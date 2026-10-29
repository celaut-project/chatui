import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../l10n/l10n.dart';

/// The most characters of HTML that the parser reads. It ignores the rest.
const int htmlMaxInputChars = 20000;

/// The most elements and text nodes in one tree.
const int htmlMaxNodes = 2000;

/// The most nested elements. A deeper element is replaced by its content.
const int htmlMaxDepth = 12;

/// The most columns of a table. A cell after this is not shown.
const int htmlMaxColumns = 12;

/// The most bytes of one image, after the base64 is decoded.
const int htmlMaxImageBytes = 256 * 1024;

/// The widest decode of an image, in pixels. A bigger image is scaled down while it
/// decodes, so a small file cannot use much memory.
const int htmlMaxImageDecodeWidth = 1024;

/// Whether [tag] is a block element of the parser.
bool htmlIsBlockTag(String tag) => _blockTags.contains(tag);

/// A node of the parsed HTML: an element ([tag] is its name in lower case) or a text
/// ([tag] is null and [text] is set).
class HtmlNode {
  HtmlNode.element(String this.tag, [Map<String, String>? attrs])
      : attrs = attrs ?? <String, String>{},
        text = null;
  HtmlNode.text(String this.text)
      : tag = null,
        attrs = const {};

  final String? tag;
  final String? text;
  final Map<String, String> attrs;
  final List<HtmlNode> children = [];
}

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'ul', 'ol', 'li', 'table', 'tr', 'td', 'th', 'hr', 'pre', 'img',
};
const _inlineTags = {'b', 'strong', 'i', 'em', 'u', 's', 'a', 'span', 'code', 'br', 'button', 'input'};
const _voidTags = {'br', 'hr', 'img', 'input'};

/// Elements that are dropped with all their content.
const _dropWithContent = {
  'script', 'style', 'iframe', 'object', 'embed', 'noscript', 'template', 'svg', 'math', 'head', 'title',
  'textarea', 'select', 'frame', 'frameset', 'applet', 'audio', 'video', 'canvas',
};

/// The attributes that the parser keeps. All other attributes (all `on*` ones too) are lost.
const _keptAttrs = {'style', 'href', 'src', 'alt', 'colspan', 'data-say', 'data-send', 'data-name', 'placeholder'};

bool _isNameChar(int c) =>
    (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39) || c == 0x2d;

/// The index of the first `</name` in [src] from [from], with the name in any case, or -1.
/// [name] is in lower case and has ASCII characters only. It reads [src] itself: a lower
/// case copy of a text can have another length (for example "İ"), so its offsets do not fit.
int _indexOfCloseTag(String src, String name, int from) {
  var j = src.indexOf('</', from);
  while (j >= 0) {
    final end = j + 2 + name.length;
    if (end <= src.length) {
      var same = true;
      for (var k = 0; k < name.length && same; k++) {
        final c = src.codeUnitAt(j + 2 + k);
        same = (c >= 0x41 && c <= 0x5a ? c + 0x20 : c) == name.codeUnitAt(k);
      }
      if (same) return j;
    }
    j = src.indexOf('</', j + 2);
  }
  return -1;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0x0c;

final _entityPattern = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});');
const _namedEntities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'copy': '©',
  'hellip': '…', 'ndash': '–', 'mdash': '—', 'euro': '€', 'times': '×',
};

String _decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entityPattern, (m) {
    final e = m.group(1)!;
    if (e.startsWith('#')) {
      final code = (e[1] == 'x' || e[1] == 'X') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
      if (code == null || code == 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return '�';
      return String.fromCharCode(code);
    }
    return _namedEntities[e] ?? m.group(0)!;
  });
}

/// Parses [html] into a tree that has only allowed elements and attributes. It never
/// throws, and its work and its result are bounded by [htmlMaxInputChars], [htmlMaxNodes]
/// and [htmlMaxDepth]. Unknown elements are replaced by their content; scripts, styles,
/// frames and the like are dropped with their content.
List<HtmlNode> parseChatHtml(String html) {
  final src = html.length > htmlMaxInputChars ? html.substring(0, htmlMaxInputChars) : html;
  final root = HtmlNode.element('#root');
  // The open elements. An element that the parser replaces by its content is not here.
  final stack = <HtmlNode>[root];
  var nodes = 0;
  var i = 0;
  final n = src.length;

  void addText(String t) {
    if (t.isEmpty || nodes >= htmlMaxNodes) return;
    nodes++;
    stack.last.children.add(HtmlNode.text(_decodeEntities(t)));
  }

  while (i < n && nodes < htmlMaxNodes) {
    final lt = src.indexOf('<', i);
    if (lt < 0) {
      addText(src.substring(i));
      break;
    }
    if (lt > i) addText(src.substring(i, lt));
    i = lt;
    if (src.startsWith('<!--', i)) {
      final end = src.indexOf('-->', i + 4);
      i = end < 0 ? n : end + 3;
      continue;
    }
    final closing = i + 1 < n && src.codeUnitAt(i + 1) == 0x2f;
    var p = i + (closing ? 2 : 1);
    final nameStart = p;
    if (p >= n || !((src.codeUnitAt(p) | 0x20) >= 0x61 && (src.codeUnitAt(p) | 0x20) <= 0x7a)) {
      // Not a tag ("<", "<3", "<!doctype", "<?x"): a doctype or a declaration is skipped, the rest is text.
      if (p < n && (src[p] == '!' || src[p] == '?')) {
        final end = src.indexOf('>', p);
        i = end < 0 ? n : end + 1;
      } else {
        addText('<');
        i++;
      }
      continue;
    }
    while (p < n && _isNameChar(src.codeUnitAt(p))) {
      p++;
    }
    // A name has ASCII characters only, so its lower case has the same length.
    final name = src.substring(nameStart, p).toLowerCase();
    // The attributes, up to the ">" that is not in quotes.
    final attrs = <String, String>{};
    var selfClose = false;
    var count = 0;
    while (p < n) {
      final c = src.codeUnitAt(p);
      if (c == 0x3e) {
        p++;
        break;
      }
      if (_isSpace(c)) {
        p++;
        continue;
      }
      if (c == 0x2f) {
        selfClose = p + 1 < n && src.codeUnitAt(p + 1) == 0x3e;
        p++;
        continue;
      }
      final aStart = p;
      while (p < n) {
        final d = src.codeUnitAt(p);
        if (_isSpace(d) || d == 0x3d || d == 0x3e || d == 0x2f) break;
        p++;
      }
      if (p == aStart) {
        p++;
        continue;
      }
      final aName = src.substring(aStart, p).toLowerCase();
      while (p < n && _isSpace(src.codeUnitAt(p))) {
        p++;
      }
      var value = '';
      if (p < n && src.codeUnitAt(p) == 0x3d) {
        p++;
        while (p < n && _isSpace(src.codeUnitAt(p))) {
          p++;
        }
        if (p < n && (src.codeUnitAt(p) == 0x22 || src.codeUnitAt(p) == 0x27)) {
          final q = src[p];
          final end = src.indexOf(q, p + 1);
          value = src.substring(p + 1, end < 0 ? n : end);
          p = end < 0 ? n : end + 1;
        } else {
          final vStart = p;
          while (p < n && !_isSpace(src.codeUnitAt(p)) && src.codeUnitAt(p) != 0x3e) {
            p++;
          }
          value = src.substring(vStart, p);
        }
      }
      if (++count <= 24 && _keptAttrs.contains(aName) && !aName.startsWith('on')) {
        attrs[aName] = _decodeEntities(value);
      }
    }
    i = p;

    if (closing) {
      for (var k = stack.length - 1; k > 0; k--) {
        if (stack[k].tag == name) {
          stack.length = k;
          break;
        }
      }
      continue;
    }
    if (_dropWithContent.contains(name)) {
      if (selfClose) continue;
      final end = _indexOfCloseTag(src, name, i);
      if (end < 0) {
        i = n;
      } else {
        final gt = src.indexOf('>', end);
        i = gt < 0 ? n : gt + 1;
      }
      continue;
    }
    if (!_blockTags.contains(name) && !_inlineTags.contains(name)) continue;
    if (stack.length > htmlMaxDepth && !_voidTags.contains(name)) continue;
    nodes++;
    final el = HtmlNode.element(name, attrs);
    stack.last.children.add(el);
    if (!_voidTags.contains(name) && !selfClose) stack.add(el);
  }
  return root.children;
}

/// A color from the CSS value [v], or null when the value is not a safe color. It reads
/// `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()` and a short list of names.
Color? parseCssColor(String v) {
  final s = v.trim().toLowerCase();
  if (s.isEmpty || s.length > 40) return null;
  if (s.startsWith('#')) {
    final h = s.substring(1);
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(h)) return null;
    if (h.length == 3 || h.length == 4) {
      final e = h.split('').map((c) => c + c).join();
      return parseCssColor('#$e');
    }
    if (h.length == 6) return Color(0xff000000 | int.parse(h, radix: 16));
    if (h.length == 8) {
      final r = int.parse(h.substring(0, 6), radix: 16);
      final a = int.parse(h.substring(6), radix: 16);
      return Color((a << 24) | r);
    }
    return null;
  }
  final m = RegExp(r'^rgba?\(\s*([0-9.]+%?)\s*[, ]\s*([0-9.]+%?)\s*[, ]\s*([0-9.]+%?)\s*(?:[,/]\s*([0-9.]+%?)\s*)?\)$').firstMatch(s);
  if (m != null) {
    int? ch(String x) {
      final pct = x.endsWith('%');
      final d = double.tryParse(pct ? x.substring(0, x.length - 1) : x);
      if (d == null) return null;
      return (pct ? d * 2.55 : d).round().clamp(0, 255);
    }

    final r = ch(m.group(1)!), g = ch(m.group(2)!), b = ch(m.group(3)!);
    if (r == null || g == null || b == null) return null;
    var a = 255;
    final ag = m.group(4);
    if (ag != null) {
      final pct = ag.endsWith('%');
      final d = double.tryParse(pct ? ag.substring(0, ag.length - 1) : ag);
      if (d == null) return null;
      a = ((pct ? d / 100 : d).clamp(0.0, 1.0) * 255).round();
    }
    return Color.fromARGB(a, r, g, b);
  }
  return _namedColors[s];
}

const _namedColors = <String, Color>{
  'black': Color(0xff000000), 'white': Color(0xffffffff), 'red': Color(0xffd32f2f), 'green': Color(0xff2e7d32),
  'blue': Color(0xff1976d2), 'yellow': Color(0xfffbc02d), 'orange': Color(0xfff57c00), 'purple': Color(0xff7b1fa2),
  'gray': Color(0xff757575), 'grey': Color(0xff757575), 'silver': Color(0xffbdbdbd), 'pink': Color(0xffec407a),
  'teal': Color(0xff00897b), 'brown': Color(0xff6d4c41), 'navy': Color(0xff0d2a6b), 'maroon': Color(0xff800000),
  'lime': Color(0xff7cb342), 'cyan': Color(0xff00acc1), 'transparent': Color(0x00000000),
};

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, String> _parseStyle(String? s) {
  final out = <String, String>{};
  if (s == null || s.isEmpty) return out;
  for (final decl in (s.length > 600 ? s.substring(0, 600) : s).split(';')) {
    final c = decl.indexOf(':');
    if (c <= 0) continue;
    out[decl.substring(0, c).trim().toLowerCase()] = decl.substring(c + 1).trim();
  }
  return out;
}

/// An HTML block from a chat message as widgets: only the allowed elements and styles, no
/// script, no network and no resource from outside. The colors follow the theme; a color
/// that the HTML sets and that is hard to read on the theme is not used.
class ChatHtmlWidget extends StatelessWidget {
  const ChatHtmlWidget({super.key, required this.html, this.style});

  final String html;

  /// The base text style. The default is the body text of the theme.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium!.merge(style);
    final r = _Renderer(theme, theme.scaffoldBackgroundColor);
    final tree = parseChatHtml(html);
    final children = r.blocks(tree, base, null, theme.scaffoldBackgroundColor);
    if (children.isEmpty) return const SizedBox.shrink();
    // The card has the color that the renderer takes as the surface, so the contrast of
    // the text is checked against the real background.
    return Container(
      key: const Key('chat-html-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The card of an HTML block that is still coming in the stream: the frame of
/// [ChatHtmlWidget] with a loading mark, and no HTML of the block.
class ChatHtmlPendingCard extends StatelessWidget {
  const ChatHtmlPendingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('chat-html-pending'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(
            context.l10n.chatHtmlLoading,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The Markdown of a chat message as widgets. A link shows as a link but does not open,
/// and an image shows as its alt text: the text of a message makes no request and opens
/// nothing, as the HTML widgets.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.data, this.style, this.selectable = false});

  final String data;

  /// The base text style of the chat.
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium!.merge(style);
    final size = base.fontSize ?? 15;
    TextStyle heading(double k) => base.copyWith(fontSize: size * k, fontWeight: FontWeight.w700, height: 1.3);
    final mono = base.copyWith(
      fontFamily: 'monospace',
      fontSize: size - 2,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
    );
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      a: base.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      h1: heading(1.5),
      h2: heading(1.35),
      h3: heading(1.2),
      h4: heading(1.1),
      h5: heading(1.0),
      h6: heading(1.0),
      listBullet: base,
      tableBody: base,
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      blockquote: base.copyWith(color: theme.colorScheme.onSurfaceVariant),
      code: mono,
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3)),
      ),
    );
    return MarkdownBody(
      data: data,
      styleSheet: sheet,
      selectable: selectable,
      shrinkWrap: true,
      imageBuilder: (uri, title, alt) => Text(alt ?? '', style: base),
    );
  }
}

/// A fenced code block of a chat message: a card with the language, a copy button and the
/// code in monospace, which scrolls sideways (the lines are not wrapped). While [pending]
/// the closing fence has not come yet, and the card shows a loading mark.
class ChatCodeBlock extends StatelessWidget {
  const ChatCodeBlock({super.key, required this.code, this.lang = '', this.pending = false, this.style});

  final String code;
  final String lang;
  final bool pending;

  /// The base text style of the chat. The code is two points smaller, in monospace.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyMedium!.merge(style);
    final mono = base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 15) - 2, color: scheme.onSurface);
    final muted = theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant);
    return Container(
      key: const Key('chat-code-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              children: [
                Expanded(child: Text(lang, key: const Key('chat-code-lang'), style: muted)),
                if (pending)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                IconButton(
                  key: const Key('chat-code-copy'),
                  tooltip: context.l10n.commonCopy,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SelectableText(code, style: mono),
          ),
        ],
      ),
    );
  }
}

class _Renderer {
  _Renderer(this.theme, this.surface);

  final ThemeData theme;
  final Color surface;

  /// [base] with the styles of [css] on it. [on] is the color that is behind the text.
  TextStyle inlineStyle(TextStyle base, Map<String, String> css, Color on) {
    var st = base;
    final color = css['color'] == null ? null : parseCssColor(css['color']!);
    if (color != null && color.a > 0.5 && _contrast(Color.alphaBlend(color, on), on) >= 3) st = st.copyWith(color: color);
    final bg = css['background-color'] == null ? null : parseCssColor(css['background-color']!);
    if (bg != null && bg.a > 0) {
      final eff = Color.alphaBlend(bg, on);
      st = st.copyWith(backgroundColor: bg);
      if (_contrast(st.color ?? Colors.black, eff) < 3) {
        st = st.copyWith(color: eff.computeLuminance() > 0.4 ? Colors.black : Colors.white);
      }
    }
    final fw = css['font-weight']?.toLowerCase();
    if (fw != null) {
      final w = int.tryParse(fw);
      if (fw == 'bold' || fw == 'bolder' || (w != null && w >= 600)) {
        st = st.copyWith(fontWeight: FontWeight.w700);
      } else if (fw == 'normal' || (w != null && w < 600)) {
        st = st.copyWith(fontWeight: FontWeight.w400);
      }
    }
    final fs = css['font-style']?.toLowerCase();
    if (fs == 'italic' || fs == 'oblique') st = st.copyWith(fontStyle: FontStyle.italic);
    if (fs == 'normal') st = st.copyWith(fontStyle: FontStyle.normal);
    final td = css['text-decoration']?.toLowerCase();
    if (td != null) {
      final deco = <TextDecoration>[
        if (td.contains('underline')) TextDecoration.underline,
        if (td.contains('line-through')) TextDecoration.lineThrough,
      ];
      st = st.copyWith(decoration: deco.isEmpty ? TextDecoration.none : TextDecoration.combine(deco));
    }
    return st;
  }

  TextAlign? align(Map<String, String> css, TextAlign? inherited) {
    switch (css['text-align']?.toLowerCase()) {
      case 'left':
      case 'start':
        return TextAlign.left;
      case 'right':
      case 'end':
        return TextAlign.right;
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
    }
    return inherited;
  }

  /// The inline spans of [nodes]. A block element inside an inline one gives its text only.
  void inline(List<HtmlNode> nodes, TextStyle st, Color on, List<InlineSpan> out, {bool pre = false}) {
    for (final node in nodes) {
      final tag = node.tag;
      if (tag == null) {
        final t = pre ? node.text! : node.text!.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) out.add(TextSpan(text: t, style: st));
        continue;
      }
      if (tag == 'br') {
        out.add(TextSpan(text: '\n', style: st));
        continue;
      }
      if (tag == 'img') continue;
      var s = st;
      switch (tag) {
        case 'b':
        case 'strong':
        case 'th':
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
          s = s.copyWith(fontWeight: FontWeight.w700);
        case 'i':
        case 'em':
          s = s.copyWith(fontStyle: FontStyle.italic);
        case 'u':
          s = s.copyWith(decoration: TextDecoration.underline);
        case 's':
          s = s.copyWith(decoration: TextDecoration.lineThrough);
        case 'a':
          s = s.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline);
        case 'code':
          s = s.copyWith(fontFamily: 'monospace', backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08));
      }
      s = inlineStyle(s, _parseStyle(node.attrs['style']), on);
      inline(node.children, s, on, out, pre: pre || tag == 'pre');
      if (_blockTags.contains(tag) && out.isNotEmpty) out.add(TextSpan(text: '\n', style: s));
    }
  }

  Widget? text(List<InlineSpan> spans, TextAlign? ta) {
    // Trim the white space at the ends, so a line break in the source gives no empty line.
    while (spans.isNotEmpty && spans.last is TextSpan && ((spans.last as TextSpan).text ?? '').trim().isEmpty) {
      spans.removeLast();
    }
    if (spans.isNotEmpty && spans.first is TextSpan) {
      final f = spans.first as TextSpan;
      spans[0] = TextSpan(text: f.text?.trimLeft(), style: f.style);
    }
    if (spans.isEmpty) return null;
    return Text.rich(TextSpan(children: List.of(spans)), textAlign: ta);
  }

  Widget stack(List<Widget> items, {double gap = 6}) {
    if (items.length == 1) return items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: gap), items[i]]],
    );
  }

  /// The block widgets of [nodes]: inline runs between blocks become paragraphs.
  List<Widget> blocks(List<HtmlNode> nodes, TextStyle st, TextAlign? ta, Color on, {bool pre = false}) {
    final out = <Widget>[];
    final run = <InlineSpan>[];
    void flush() {
      final w = text(run, ta);
      run.clear();
      if (w != null) out.add(w);
    }

    final gapped = <Widget>[];
    for (final node in nodes) {
      final tag = node.tag;
      if (tag == null || !_blockTags.contains(tag)) {
        inline([node], st, on, run, pre: pre);
        continue;
      }
      flush();
      final w = block(node, st, ta, on);
      if (w != null) out.add(w);
    }
    flush();
    // Space between the blocks.
    for (var i = 0; i < out.length; i++) {
      if (i > 0) gapped.add(const SizedBox(height: 6));
      gapped.add(out[i]);
    }
    return gapped;
  }

  Widget? block(HtmlNode node, TextStyle st, TextAlign? ta, Color on) {
    final tag = node.tag!;
    final css = _parseStyle(node.attrs['style']);
    final a = align(css, ta);
    switch (tag) {
      case 'hr':
        return Divider(height: 12, color: theme.colorScheme.outlineVariant);
      case 'img':
        return image(node);
      case 'table':
        return table(node, st, a, on);
      case 'ul':
      case 'ol':
        return list(node, st, a, on);
    }
    var s = st;
    var bg = on;
    Color? box;
    switch (tag) {
      case 'h1':
        s = s.copyWith(fontSize: (st.fontSize ?? 14) * 1.6, fontWeight: FontWeight.w700);
      case 'h2':
        s = s.copyWith(fontSize: (st.fontSize ?? 14) * 1.4, fontWeight: FontWeight.w700);
      case 'h3':
        s = s.copyWith(fontSize: (st.fontSize ?? 14) * 1.2, fontWeight: FontWeight.w700);
      case 'h4':
        s = s.copyWith(fontWeight: FontWeight.w700);
      case 'pre':
        s = s.copyWith(fontFamily: 'monospace');
        box = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    }
    final bgCss = css['background-color'] == null ? null : parseCssColor(css['background-color']!);
    if (bgCss != null && bgCss.a > 0) {
      box = bgCss;
      bg = Color.alphaBlend(bgCss, on);
    }
    // The background goes on the box, not on each text span.
    final inlineCss = Map.of(css)..remove('background-color');
    s = inlineStyle(s, inlineCss, bg);
    if (bgCss != null && bgCss.a > 0 && _contrast(s.color ?? Colors.black, bg) < 3) {
      s = s.copyWith(color: bg.computeLuminance() > 0.4 ? Colors.black : Colors.white);
    }
    final kids = blocks(node.children, s, a, bg, pre: tag == 'pre');
    if (kids.isEmpty) return null;
    Widget w = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: kids);
    if (tag == 'pre') w = SingleChildScrollView(scrollDirection: Axis.horizontal, child: w);
    if (box != null) {
      w = DecoratedBox(
        decoration: BoxDecoration(color: box, borderRadius: BorderRadius.circular(8)),
        child: Padding(padding: const EdgeInsets.all(8), child: w),
      );
    }
    return w;
  }

  Widget? list(HtmlNode node, TextStyle st, TextAlign? ta, Color on) {
    final ordered = node.tag == 'ol';
    final items = <Widget>[];
    var n = 0;
    for (final li in node.children) {
      if (li.tag != 'li') continue;
      n++;
      final kids = blocks(li.children, st, ta, on);
      if (kids.isEmpty) continue;
      items.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 24, child: Text(ordered ? '$n.' : '•', style: st, textAlign: TextAlign.end)),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids)),
      ]));
    }
    return items.isEmpty ? null : stack(items, gap: 3);
  }

  Widget? table(HtmlNode node, TextStyle st, TextAlign? ta, Color on) {
    final rows = <List<Widget>>[];
    var cols = 0;
    for (final tr in node.children) {
      if (tr.tag != 'tr') continue;
      final cells = <Widget>[];
      for (final cell in tr.children) {
        if (cell.tag != 'td' && cell.tag != 'th') continue;
        if (cells.length >= htmlMaxColumns) break;
        final s = cell.tag == 'th' ? st.copyWith(fontWeight: FontWeight.w700) : st;
        final kids = blocks(cell.children, s, ta, on);
        cells.add(Padding(
          padding: const EdgeInsets.all(6),
          child: kids.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
        ));
      }
      if (cells.isEmpty) continue;
      if (cells.length > cols) cols = cells.length;
      rows.add(cells);
    }
    if (rows.isEmpty) return null;
    return Table(
      border: TableBorder.all(color: theme.colorScheme.outlineVariant),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final r in rows)
          TableRow(children: [...r, for (var k = r.length; k < cols; k++) const SizedBox.shrink()]),
      ],
    );
  }

  Widget? image(HtmlNode node) {
    final bytes = decodeDataImage(node.attrs['src']);
    if (bytes == null) return null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Image.memory(bytes, cacheWidth: htmlMaxImageDecodeWidth, fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, gaplessPlayback: true,
          semanticLabel: node.attrs['alt'], errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    );
  }
}

/// The bytes of a `data:image/png;base64,...` or `data:image/jpeg;base64,...` URI that is
/// not larger than [htmlMaxImageBytes], or null for any other value.
Uint8List? decodeDataImage(String? src) {
  if (src == null) return null;
  final m = RegExp(r'^\s*data:image/(png|jpeg|jpg);base64,([A-Za-z0-9+/=\s]*)$').firstMatch(src);
  if (m == null) return null;
  final b64 = m.group(2)!.replaceAll(RegExp(r'\s'), '');
  if (b64.length > htmlMaxImageBytes * 4 ~/ 3 + 8) return null;
  try {
    final bytes = base64.decode(b64);
    if (bytes.isEmpty || bytes.length > htmlMaxImageBytes) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}
