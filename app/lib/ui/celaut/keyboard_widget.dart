import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import 'html_widget.dart';
import 'wheel_options.dart';

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

/// The most options that a `select` of a keyboard block shows. An option after this is lost.
const int keyboardMaxOptions = 32;

/// The most characters of the label of an option. The client cuts the rest.
const int keyboardMaxOptionChars = 80;

/// The most steps that a slider has. A slider with more is continuous, and its value is
/// rounded to the step.
const int keyboardMaxSliderSteps = 1000;

/// What the user does in a field of a keyboard block.
enum ChatFieldKind {
  /// One line of text (`input`, or `input` with a `type` that the client does not know).
  text,

  /// A day, chosen in a calendar (`type="date"`). The value is `YYYY-MM-DD`.
  date,

  /// A time of day, chosen in a clock (`type="time"`). The value is `HH:MM`, in 24 hours.
  time,

  /// A number, chosen with a slider (`type="range"`).
  range,

  /// A box that is on or off (`type="checkbox"`). The value is its `value`, or its `data-off`.
  checkbox,

  /// One of some options (`select`). The value is the `value` of the option. With `multiple`,
  /// some of them: the values in the order of the options, with ", " between them.
  select,
}

/// An option of a `select`: [value] is what goes in the message, [label] is what the user reads.
class ChatOption {
  const ChatOption(this.value, this.label, {this.selected = false});

  final String value;
  final String label;

  /// The option is chosen at the start (the `selected` attribute).
  final bool selected;
}

/// The separator of the values of a `select` that has `multiple`.
const String keyboardMultipleSeparator = ', ';

/// The longest start of [values] that, joined with [keyboardMultipleSeparator], has at most
/// [keyboardMaxFieldChars] characters. A value is never cut in half.
List<String> fitChosen(Iterable<String> values) {
  final out = <String>[];
  var length = 0;
  for (final v in values) {
    final next = length + (out.isEmpty ? 0 : keyboardMultipleSeparator.length) + v.length;
    if (next > keyboardMaxFieldChars) break;
    out.add(v);
    length = next;
  }
  return out;
}

/// A field of a keyboard block: an `input` or a `select` element that has a valid `data-name`.
/// The user gives a value in it, and a `{name}` in the `data-say` of a key is that value.
/// Only the attributes of its [kind] have a meaning; the rest are [initial] and the defaults.
class ChatKeyField {
  const ChatKeyField(
    this.name,
    this.placeholder, {
    this.kind = ChatFieldKind.text,
    this.options = const [],
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.decimals = 0,
    this.firstDate,
    this.lastDate,
    this.initial = '',
    this.multiple = false,
    this.chosen = const [],
    this.on = 'yes',
    this.off = 'no',
  });

  final String name;
  final String placeholder;
  final ChatFieldKind kind;

  /// The options of a `select`.
  final List<ChatOption> options;

  /// The range and the step of a slider, and how many decimals its value has.
  final double min, max, step;
  final int decimals;

  /// The first and the last day that a calendar offers, or null for no limit.
  final DateTime? firstDate, lastDate;

  /// The value of the field before the user does anything. Empty for a field that waits.
  final String initial;

  /// A `select` with `multiple`, and the values that are chosen at the start (they are in
  /// [initial] too, joined).
  final bool multiple;
  final List<String> chosen;

  /// The value of a checkbox that is on, and the one of a checkbox that is off.
  final String on, off;
}

final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// The day of `YYYY-MM-DD`, or null if [v] is not a real day.
DateTime? parseChatDate(String v) {
  final m = _datePattern.firstMatch(v.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final date = DateTime(y, mo, d);
  return date.year == y && date.month == mo && date.day == d ? date : null;
}

String formatChatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The time of `HH:MM` (24 hours), or null.
TimeOfDay? parseChatTime(String v) {
  final m = _timePattern.firstMatch(v.trim());
  return m == null ? null : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
}

String formatChatTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

int _decimals(String? v) {
  final i = v?.indexOf('.') ?? -1;
  return i < 0 ? 0 : (v!.length - i - 1).clamp(0, 6);
}

/// [v] as a value of the slider of [f]: inside the range, on a step, with the decimals of
/// the step and the minimum. It is the text that goes in the message.
String snapRange(double v, ChatKeyField f) {
  final c = v.clamp(f.min, f.max);
  final snapped = (f.min + ((c - f.min) / f.step).round() * f.step).clamp(f.min, f.max);
  return snapped.toStringAsFixed(f.decimals);
}

/// The slider of [f] has steps to snap to: the number of divisions, or null if it has too many.
int? rangeDivisions(ChatKeyField f) {
  final n = ((f.max - f.min) / f.step).round();
  return n >= 1 && n <= keyboardMaxSliderSteps ? n : null;
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

/// The options of a `select`: its `option` elements, also those that an `option` without a
/// closing tag holds. An option with no value, or a value that is too long, is lost; two with
/// the same value are one.
List<ChatOption> _optionsOf(List<HtmlNode> nodes, [List<ChatOption>? out]) {
  final options = out ?? <ChatOption>[];
  for (final n in nodes) {
    if (n.tag == null) continue;
    if (n.tag == 'option' && options.length < keyboardMaxOptions) {
      final text = n.children.where((c) => c.tag == null).map((c) => c.text!).join().replaceAll(_spaces, ' ').trim();
      final value = (n.attrs['value'] ?? text).replaceAll(_spaces, ' ').trim();
      if (value.isNotEmpty && value.length <= keyboardMaxFieldChars && !options.any((o) => o.value == value)) {
        final label = text.isEmpty ? value : text;
        options.add(ChatOption(
          value,
          label.length > keyboardMaxOptionChars ? label.substring(0, keyboardMaxOptionChars) : label,
          selected: n.attrs.containsKey('selected'),
        ));
      }
    }
    _optionsOf(n.children, options);
  }
  return options;
}

/// The field of an `input` or `select` element that has the valid [name].
ChatKeyField _fieldOf(HtmlNode n, String name) {
  final hint = (n.attrs['placeholder'] ?? '').replaceAll(_spaces, ' ').trim();
  final placeholder = hint.length > keyboardMaxPlaceholderChars ? hint.substring(0, keyboardMaxPlaceholderChars) : hint;
  if (n.tag == 'select') {
    final options = _optionsOf(n.children);
    final multiple = n.attrs.containsKey('multiple');
    final start = options.where((o) => o.selected).map((o) => o.value);
    final chosen = multiple ? fitChosen(start) : start.take(1).toList();
    return ChatKeyField(
      name,
      placeholder,
      kind: ChatFieldKind.select,
      options: options,
      multiple: multiple,
      chosen: chosen,
      initial: chosen.join(keyboardMultipleSeparator),
    );
  }
  String attr(String k) => (n.attrs[k] ?? '').replaceAll(_spaces, ' ').trim();
  switch (attr('type').toLowerCase()) {
    case 'date':
      final first = parseChatDate(attr('min')), last = parseChatDate(attr('max'));
      final ok = first == null || last == null || !last.isBefore(first);
      final initial = parseChatDate(attr('value'));
      return ChatKeyField(
        name,
        placeholder,
        kind: ChatFieldKind.date,
        firstDate: ok ? first : null,
        lastDate: ok ? last : null,
        initial: initial == null ? '' : formatChatDate(initial),
      );
    case 'time':
      final initial = parseChatTime(attr('value'));
      return ChatKeyField(name, placeholder,
          kind: ChatFieldKind.time, initial: initial == null ? '' : formatChatTime(initial));
    case 'range':
      double? number(String k) {
        final v = double.tryParse(attr(k));
        return v != null && v.isFinite ? v : null;
      }

      var min = number('min') ?? 0.0, max = number('max') ?? 100.0;
      if (max <= min) {
        min = 0;
        max = 100;
      }
      var step = number('step') ?? 1.0;
      if (step <= 0) step = 1;
      final decimals = _decimals(attr('min')) > _decimals(attr('step')) ? _decimals(attr('min')) : _decimals(attr('step'));
      ChatKeyField range([String initial = '']) => ChatKeyField(name, placeholder,
          kind: ChatFieldKind.range, min: min, max: max, step: step, decimals: decimals, initial: initial);
      return range(snapRange(number('value') ?? min, range()));
    case 'checkbox':
      String cut(String v) => v.length > keyboardMaxFieldChars ? v.substring(0, keyboardMaxFieldChars) : v;
      final on = cut(attr('value').isEmpty ? 'yes' : attr('value'));
      final off = cut(attr('data-off').isEmpty ? 'no' : attr('data-off'));
      return ChatKeyField(name, placeholder,
          kind: ChatFieldKind.checkbox, on: on, off: off, initial: n.attrs.containsKey('checked') ? on : off);
  }
  return ChatKeyField(name, placeholder);
}

/// The rows of a keyboard block. A row has keys ([ChatKey]), fields ([ChatKeyField])
/// and texts ([String]) in the order of the source. A block element (`div`, `p`, `li`, `tr`, a heading...) starts
/// and ends a row. It reads the same restricted HTML as [parseChatHtml]: no script, no
/// network and no `on*` attribute.
List<List<Object>> keyboardRows(String html) => keyboardPlan(html).all;

/// The most steps that a keyboard block has. An element with `data-step` after this is not a
/// step: it is read as any other element.
const int keyboardMaxSteps = 8;

/// The most characters of the title of a step. The client cuts the rest.
const int keyboardMaxStepTitleChars = 80;

/// A step of a keyboard block: an element that has a `data-step` (its title) and the rows
/// that are in it.
class ChatStep {
  const ChatStep(this.title, this.rows);

  final String title;
  final List<List<Object>> rows;
}

/// A keyboard block in its parts. Without steps, everything is in [before]. With steps,
/// [before] is what comes before the first step (it shows in every step), [steps] are the
/// steps in order, and [after] is the rest that comes after the first step (the keys, most of
/// the time): it shows in the last step only.
class ChatKeyboardPlan {
  const ChatKeyboardPlan(this.before, this.steps, this.after);

  final List<List<Object>> before;
  final List<ChatStep> steps;
  final List<List<Object>> after;

  /// All the rows, in the order of [before], the steps and [after].
  List<List<Object>> get all => [
        ...before,
        for (final step in steps) ...step.rows,
        ...after,
      ];

  /// The rows that show in step [i] (0 to `steps.length - 1`). With no steps, all of them.
  List<List<Object>> rowsOfStep(int i) => steps.isEmpty
      ? before
      : [
          ...before,
          ...steps[i].rows,
          if (i == steps.length - 1) ...after,
        ];
}

/// The parts of a keyboard block ([ChatKeyboardPlan]). The limits of keys and fields are for
/// the whole block, not for each step.
ChatKeyboardPlan keyboardPlan(String html) {
  final before = <List<Object>>[];
  final steps = <ChatStep>[];
  final after = <List<Object>>[];
  var rows = before;
  var inStep = false;
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
      if (tag == 'input' || tag == 'select') {
        final name = n.attrs['data-name'] ?? '';
        if (_fieldName.hasMatch(name) && names.length < keyboardMaxFields && names.add(name)) {
          row.add(_fieldOf(n, name));
        }
        continue;
      }
      if (tag == 'option') continue;
      final say = n.attrs['data-say'];
      if (say != null && say.trim().isNotEmpty && say.length <= keyboardMaxSayChars && keys < keyboardMaxKeys) {
        final label = textOf(n).replaceAll(_spaces, ' ').trim();
        row.add(ChatKey(label.isEmpty ? say : label, say, send: n.attrs.containsKey('data-send')));
        keys++;
        continue;
      }
      final stepTitle = (n.attrs['data-step'] ?? '').replaceAll(_spaces, ' ').trim();
      if (stepTitle.isNotEmpty && !inStep && steps.length < keyboardMaxSteps) {
        flush();
        final own = <List<Object>>[];
        rows = own;
        inStep = true;
        walk(n.children);
        flush();
        inStep = false;
        rows = after;
        if (own.isNotEmpty) {
          steps.add(ChatStep(
            stepTitle.length > keyboardMaxStepTitleChars ? stepTitle.substring(0, keyboardMaxStepTitleChars) : stepTitle,
            own,
          ));
        }
        continue;
      }
      final block = tag != 'td' && tag != 'th' && htmlIsBlockTag(tag);
      if (block) flush();
      walk(n.children);
      if (block) flush();
    }
  }

  walk(parseChatHtml(html, forms: true));
  flush();
  // With no step, what came after the first (empty) step is not "after": it is the block.
  if (steps.isEmpty) return ChatKeyboardPlan([...before, ...after], const [], const []);
  return ChatKeyboardPlan(before, steps, after);
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

  /// The step that shows, if the block has steps.
  int _step = 0;

  /// The values that are chosen in a `select` with `multiple`, by name of the field.
  final Map<String, List<String>> _chosen = {};

  TextEditingController _field(ChatKeyField f) => _fields.putIfAbsent(f.name, () {
        final c = TextEditingController(text: f.initial);
        // A key can need the field, so the keys follow what the user writes.
        c.addListener(() => setState(() {}));
        return c;
      });

  void _clear() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _fields.clear();
    _chosen.clear();
  }

  @override
  void didUpdateWidget(ChatKeyboard old) {
    super.didUpdateWidget(old);
    // Another block is another form: the values of the old one do not go to it.
    if (old.html != widget.html) {
      _clear();
      _step = 0;
    }
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
    final plan = keyboardPlan(widget.html);
    final all = plan.all;
    if (all.isEmpty) return const SizedBox.shrink();
    final steps = plan.steps.length;
    final step = _step.clamp(0, steps == 0 ? 0 : steps - 1);
    final rows = plan.rowsOfStep(step);
    final values = {
      for (final row in all)
        for (final item in row)
          if (item is ChatKeyField) item.name: _field(item).text,
    };
    var index = 0;
    // The width that a field can have: the width of the form, less its padding.
    return LayoutBuilder(
      builder: (context, box) {
        final maxWidth = (box.maxWidth.isFinite ? box.maxWidth : 320.0) - 24;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: SingleChildScrollView(
            key: const Key('chat-keyboard'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (steps > 0) _stepHeader(plan, step, text),
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
                            _fieldWidget(item, text, maxWidth)
                          else
                            Text(item as String, style: text),
                      ],
                    ),
                  ),
                if (steps > 0) _stepNav(plan, step),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The title of the step, with its place: "2/3 · Weight".
  Widget _stepHeader(ChatKeyboardPlan plan, int step, TextStyle text) => Padding(
        key: const Key('chat-step-header'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '${step + 1}/${plan.steps.length} · ${plan.steps[step].title}',
          style: text.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
        ),
      );

  /// Back and Next. Next waits until every field of the step has a value.
  Widget _stepNav(ChatKeyboardPlan plan, int step) {
    final l10n = context.l10n;
    final ready = [
      for (final row in plan.steps[step].rows)
        for (final item in row)
          if (item is ChatKeyField) _field(item).text.isNotEmpty,
    ].every((r) => r);
    final last = step == plan.steps.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          if (step > 0)
            TextButton.icon(
              key: const Key('chat-step-back'),
              onPressed: () => setState(() => _step = step - 1),
              icon: const Icon(Icons.chevron_left),
              label: Text(l10n.chatStepBack),
            ),
          const Spacer(),
          if (!last)
            FilledButton.icon(
              key: const Key('chat-step-next'),
              onPressed: ready ? () => setState(() => _step = step + 1) : null,
              icon: const Icon(Icons.chevron_right),
              iconAlignment: IconAlignment.end,
              label: Text(l10n.chatStepNext),
            ),
        ],
      ),
    );
  }

  Widget _fieldWidget(ChatKeyField item, TextStyle text, double maxWidth) {
    final c = _field(item);
    final hint = item.placeholder;
    // A field that waits shows its hint; one with a value shows the value.
    Widget chooser(String shown, IconData icon, {VoidCallback? onTap}) => InkWell(
          key: Key('chat-field-${item.name}'),
          onTap: onTap,
          child: InputDecorator(
            isEmpty: shown.isEmpty,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              suffixIcon: Icon(icon, size: 18),
            ),
            child: Text(shown, style: text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    switch (item.kind) {
      case ChatFieldKind.date:
        return SizedBox(
          width: 200,
          child: chooser(c.text, Icons.calendar_today_outlined, onTap: () async {
            final first = item.firstDate ?? DateTime(1900);
            final last = item.lastDate ?? DateTime(2100, 12, 31);
            var initial = parseChatDate(c.text) ?? DateTime.now();
            if (initial.isBefore(first)) initial = first;
            if (initial.isAfter(last)) initial = last;
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
            );
            if (picked != null && mounted) c.text = formatChatDate(picked);
          }),
        );
      case ChatFieldKind.time:
        return SizedBox(
          width: 200,
          child: chooser(c.text, Icons.schedule, onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: parseChatTime(c.text) ?? TimeOfDay.now(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                child: child!,
              ),
            );
            if (picked != null && mounted) c.text = formatChatTime(picked);
          }),
        );
      case ChatFieldKind.select:
        final multiple = item.multiple;
        final chosen = multiple ? _chosen.putIfAbsent(item.name, () => [...item.chosen]) : [c.text];
        return SizedBox(
          width: maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hint.isNotEmpty)
                Text(hint, style: text.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ChatWheelOptions(
                key: Key('chat-field-${item.name}'),
                labels: [for (final o in item.options) o.label],
                selected: [for (final o in item.options) chosen.contains(o.value)],
                multiple: multiple,
                style: text,
                onTap: (i) {
                  final value = item.options[i].value;
                  if (!multiple) {
                    c.text = value;
                    return;
                  }
                  // The values keep the order of the options. A box that would make the value
                  // too long does not turn on.
                  final on = !chosen.contains(value);
                  final next = [
                    for (final o in item.options)
                      if (o.value == value ? on : chosen.contains(o.value)) o.value,
                  ];
                  if (on && fitChosen(next).length != next.length) return;
                  _chosen[item.name] = next;
                  c.text = next.join(keyboardMultipleSeparator);
                },
              ),
            ],
          ),
        );
      case ChatFieldKind.range:
        final v = (double.tryParse(c.text) ?? item.min).clamp(item.min, item.max).toDouble();
        return SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(hint, style: text, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(c.text, style: text),
                ],
              ),
              Slider(
                key: Key('chat-field-${item.name}'),
                value: v,
                min: item.min,
                max: item.max,
                divisions: rangeDivisions(item),
                onChanged: (x) => c.text = snapRange(x, item),
              ),
            ],
          ),
        );
      case ChatFieldKind.checkbox:
        final on = c.text == item.on;
        return InkWell(
          onTap: () => c.text = on ? item.off : item.on,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  key: Key('chat-field-${item.name}'),
                  value: on,
                  onChanged: (v) => c.text = v == true ? item.on : item.off,
                ),
                Flexible(child: Text(hint.isEmpty ? item.name : hint, style: text)),
              ],
            ),
          ),
        );
      case ChatFieldKind.text:
        return SizedBox(
          width: 200,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (f) => widget.onFieldFocus?.call(c, f),
            child: TextField(
              key: Key('chat-field-${item.name}'),
              controller: c,
              keyboardType: widget.systemKeyboard ? null : TextInputType.none,
              style: text,
              maxLength: keyboardMaxFieldChars,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: hint,
              ),
            ),
          ),
        );
    }
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
