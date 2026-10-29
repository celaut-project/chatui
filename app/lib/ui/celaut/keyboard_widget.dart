import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import 'html_widget.dart';

/// The most keys that one keyboard block shows. An element after this shows as text.
const int keyboardMaxKeys = 64;

/// The most characters of the `data-say` of one key. A key with a longer one is not a key:
/// it shows as text, so the user never sends a part of what the service wrote.
const int keyboardMaxSayChars = 500;

/// The most fields that one keyboard block shows. An `input` after this is not shown.
const int keyboardMaxFields = 8;

/// The most characters of the value of a field. The field does not take more.
const int keyboardMaxFieldChars = 200;

/// The most characters of the `placeholder` of a field. The client cuts the rest.
const int keyboardMaxPlaceholderChars = 80;

/// The name of a field (`data-name`), and the name in a `{name}` of a `data-say`.
final _fieldName = RegExp(r'^[A-Za-z0-9_-]{1,32}$');
final _placeholder = RegExp(r'\{([A-Za-z0-9_-]{1,32})\}');

/// A field of a keyboard block: the `input` element that has a valid `data-name`. The
/// user writes a value in it, and a `{name}` in the `data-say` of a key is that value.
class ChatKeyField {
  const ChatKeyField(this.name, this.placeholder);

  final String name;
  final String placeholder;
}

/// A key of a keyboard block: the element that has a `data-say`. [label] is its text (the
/// `data-say` if the element has no text) and [say] is what a tap puts in the input. If
/// [send] is true (the element has a `data-send`), a tap sends [say] at once.
class ChatKey {
  const ChatKey(this.label, this.say, {this.send = false});

  final String label;
  final String say;
  final bool send;
}

final _spaces = RegExp(r'\s+');

/// The rows of a keyboard block. A row has keys ([ChatKey]), fields ([ChatKeyField])
/// and texts ([String]) in the order of the source. A block element (`div`, `p`, `li`, `tr`, a heading...) starts
/// and ends a row. It reads the same restricted HTML as [parseChatHtml]: no script, no
/// network and no `on*` attribute.
List<List<Object>> keyboardRows(String html) {
  final rows = <List<Object>>[];
  var row = <Object>[];
  var keys = 0;
  final names = <String>{};

  void flush() {
    if (row.isEmpty) return;
    rows.add(row);
    row = <Object>[];
  }

  String textOf(HtmlNode n) => n.tag == null ? n.text! : n.children.map(textOf).join();

  void walk(List<HtmlNode> nodes) {
    for (final n in nodes) {
      final tag = n.tag;
      if (tag == null) {
        final t = n.text!.replaceAll(_spaces, ' ').trim();
        if (t.isNotEmpty) row.add(t);
        continue;
      }
      if (tag == 'input') {
        final name = n.attrs['data-name'] ?? '';
        if (_fieldName.hasMatch(name) && names.length < keyboardMaxFields && names.add(name)) {
          final hint = (n.attrs['placeholder'] ?? '').replaceAll(_spaces, ' ').trim();
          row.add(ChatKeyField(
            name,
            hint.length > keyboardMaxPlaceholderChars ? hint.substring(0, keyboardMaxPlaceholderChars) : hint,
          ));
        }
        continue;
      }
      final say = n.attrs['data-say'];
      if (say != null && say.trim().isNotEmpty && say.length <= keyboardMaxSayChars && keys < keyboardMaxKeys) {
        final label = textOf(n).replaceAll(_spaces, ' ').trim();
        row.add(ChatKey(label.isEmpty ? say : label, say, send: n.attrs.containsKey('data-send')));
        keys++;
        continue;
      }
      final block = tag != 'td' && tag != 'th' && htmlIsBlockTag(tag);
      if (block) flush();
      walk(n.children);
      if (block) flush();
    }
  }

  walk(parseChatHtml(html));
  flush();
  return rows;
}

/// The value of a field as it goes in a message: the white space is one space, with none at
/// the ends, and it has at most [keyboardMaxFieldChars] characters.
String cleanFieldValue(String value) {
  final v = value.replaceAll(_spaces, ' ').trim();
  return v.length > keyboardMaxFieldChars ? v.substring(0, keyboardMaxFieldChars).trimRight() : v;
}

/// The `data-say` [say] with each `{name}` of a field in [values] (name to the text of the
/// field) replaced by the clean value of the field, in one pass: a value is not read again,
/// so a value that has `{other}` stays as it is. A `{name}` that is not a field stays as it
/// is. It gives null if a field that [say] uses is empty: the key cannot be used yet.
String? fillSay(String say, Map<String, String> values) {
  var empty = false;
  final out = say.replaceAllMapped(_placeholder, (m) {
    final raw = values[m.group(1)];
    if (raw == null) return m.group(0)!;
    final v = cleanFieldValue(raw);
    if (v.isEmpty) empty = true;
    return v;
  });
  return empty ? null : out;
}

/// [say] put in [current]: it is the text if the input is empty, and it follows the text
/// after a space if the text does not end in a space. A key never replaces what the user
/// has written.
String applySay(String current, String say) {
  if (current.isEmpty) return say;
  return current.endsWith(' ') || current.endsWith('\n') ? '$current$say' : '$current $say';
}

/// The keys and the fields of a keyboard block ([keyboardRows]). A tap on a key calls
/// [onSay] with the key and its `data-say` after the fields are put in it ([fillSay]): the
/// client puts it in the input, and the user sends it with Send, or sends it at once if the
/// key has `data-send`. A key that uses an empty field cannot be tapped. The widget sends
/// nothing itself. The keys scroll if they do not fit in [maxHeight].
class ChatKeyboard extends StatefulWidget {
  const ChatKeyboard({
    super.key,
    required this.html,
    required this.onSay,
    this.maxHeight = 240,
    this.style,
    this.systemKeyboard = true,
    this.onFieldFocus,
  });

  final String html;
  final void Function(ChatKey key, String say) onSay;
  final double maxHeight;

  /// The base text style: the font and the size of the chat. The default is the body text
  /// of the theme. The colors always come from the theme.
  final TextStyle? style;

  /// The fields use the keyboard of the system. If false, they do not open it: the client
  /// shows its own keyboard for the field that [onFieldFocus] tells.
  final bool systemKeyboard;

  /// A field got the focus (true) or lost it (false). It gives the controller of the field.
  final void Function(TextEditingController field, bool focused)? onFieldFocus;

  @override
  State<ChatKeyboard> createState() => _ChatKeyboardState();
}

class _ChatKeyboardState extends State<ChatKeyboard> {
  final Map<String, TextEditingController> _fields = {};

  TextEditingController _field(String name) => _fields.putIfAbsent(name, () {
        final c = TextEditingController();
        // A key can need the field, so the keys follow what the user writes.
        c.addListener(() => setState(() {}));
        return c;
      });

  void _clear() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _fields.clear();
  }

  @override
  void didUpdateWidget(ChatKeyboard old) {
    super.didUpdateWidget(old);
    // Another block is another form: the values of the old one do not go to it.
    if (old.html != widget.html) _clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium!.merge(widget.style);
    final rows = keyboardRows(widget.html);
    if (rows.isEmpty) return const SizedBox.shrink();
    final values = {
      for (final row in rows)
        for (final item in row)
          if (item is ChatKeyField) item.name: _field(item.name).text,
    };
    var index = 0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: SingleChildScrollView(
        key: const Key('chat-keyboard'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final item in row)
                      if (item is ChatKey)
                        _key(item, values, text, index++)
                      else if (item is ChatKeyField)
                        SizedBox(
                          width: 200,
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: (f) => widget.onFieldFocus?.call(_field(item.name), f),
                            child: TextField(
                              key: Key('chat-field-${item.name}'),
                              controller: _field(item.name),
                              keyboardType: widget.systemKeyboard ? null : TextInputType.none,
                              style: text,
                              maxLength: keyboardMaxFieldChars,
                              maxLengthEnforcement: MaxLengthEnforcement.enforced,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                isDense: true,
                                counterText: '',
                                hintText: item.placeholder,
                              ),
                            ),
                          ),
                        )
                      else
                        Text(item as String, style: text),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _key(ChatKey key, Map<String, String> values, TextStyle text, int i) {
    final say = fillSay(key.say, values);
    return ActionChip(
      key: Key('chat-key-$i'),
      avatar: key.send ? const Icon(Icons.send, size: 16) : null,
      label: Text(key.label, style: text),
      onPressed: say == null ? null : () => widget.onSay(key, say),
    );
  }
}

/// What a keyboard block shows in the message: a quiet card. The keys are in the keyboard
/// of the chat ([ChatKeyboard]) while this is the last message, so they are not twice on
/// the screen. If the user closed the keyboard, [onTap] opens it again.
class ChatKeyboardNote extends StatelessWidget {
  const ChatKeyboardNote({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      key: const Key('chat-keyboard-note'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            context.l10n.chatKeyboardLabel,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      key: const Key('chat-keyboard-reopen'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: card,
    );
  }
}
