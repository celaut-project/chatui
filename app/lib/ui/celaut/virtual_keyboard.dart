import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';

const _lettersRows = ['qwertyuiop', 'asdfghjklñ', 'zxcvbnm'];
const _symbolsRows = ['1234567890', '@#€_&-+()/', '*"\':;!?'];

/// [text] with [insert] in place of the selection. A selection that is not valid (the field
/// never had the focus) puts [insert] at the end. The cursor goes after [insert].
TextEditingValue insertAtSelection(TextEditingValue v, String insert) {
  final sel = v.selection;
  final start = sel.isValid ? sel.start : v.text.length;
  final end = sel.isValid ? sel.end : v.text.length;
  return TextEditingValue(
    text: v.text.replaceRange(start, end, insert),
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

/// [v] after Backspace: the selection if there is one, else the character before the
/// cursor (a whole character, not half of an emoji).
TextEditingValue deleteBackward(TextEditingValue v) {
  final sel = v.selection;
  final start = sel.isValid ? sel.start : v.text.length;
  final end = sel.isValid ? sel.end : v.text.length;
  if (start != end) {
    return TextEditingValue(
      text: v.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }
  if (start == 0) return v;
  final before = v.text.substring(0, start).characters.skipLast(1).toString();
  return TextEditingValue(
    text: before + v.text.substring(start),
    selection: TextSelection.collapsed(offset: before.length),
  );
}

/// The keyboard of the app: letters, and numbers and symbols. It types in [controller], so
/// the chat never needs the keyboard of the system. A key does not take the focus: the
/// field that has it keeps it, and [focusNode] (if given) takes it when a key is tapped.
/// With [maxLength], a key that would make the text longer does nothing.
class ChatVirtualKeyboard extends StatefulWidget {
  const ChatVirtualKeyboard({super.key, required this.controller, this.focusNode, this.maxLength});

  final TextEditingController controller;
  final FocusNode? focusNode;
  final int? maxLength;

  @override
  State<ChatVirtualKeyboard> createState() => _ChatVirtualKeyboardState();
}

class _ChatVirtualKeyboardState extends State<ChatVirtualKeyboard> {
  bool _shift = false;
  bool _symbols = false;

  void _apply(TextEditingValue v) {
    final max = widget.maxLength;
    if (max != null && v.text.length > max && v.text.length > widget.controller.text.length) return;
    widget.controller.value = v;
    widget.focusNode?.requestFocus();
  }

  void _type(String s) {
    _apply(insertAtSelection(widget.controller.value, s));
    if (_shift) setState(() => _shift = false);
  }

  Widget _key(String id, Widget child, VoidCallback onTap, {double flex = 1, String? label, bool on = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: (flex * 10).round(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: label != null,
          child: Material(
            color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: Key('vk-$id'),
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: SizedBox(height: 42, child: Center(child: child)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _char(String c) {
    final shown = _shift && !_symbols ? c.toUpperCase() : c;
    // The case comes from the state at the tap, not from the last build: a second tap can
    // come before the next frame, and Shift is for one letter only.
    return _key('char-$c', Text(shown, style: const TextStyle(fontSize: 18)),
        () => _type(_shift && !_symbols ? c.toUpperCase() : c));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = _symbols ? _symbolsRows : _lettersRows;
    return Container(
      key: const Key('chat-virtual-keyboard'),
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [for (final c in rows[0].characters) _char(c)]),
          Row(children: [for (final c in rows[1].characters) _char(c)]),
          Row(
            children: [
              if (_symbols)
                const Spacer(flex: 15)
              else
                _key('shift', const Icon(Icons.arrow_upward), () => setState(() => _shift = !_shift),
                    flex: 1.5, label: l10n.chatVkShift, on: _shift),
              for (final c in rows[2].characters) _char(c),
              _key('backspace', const Icon(Icons.backspace_outlined), () => _apply(deleteBackward(widget.controller.value)),
                  flex: 1.5, label: l10n.chatVkBackspace),
            ],
          ),
          Row(
            children: [
              _key('symbols', Text(_symbols ? 'ABC' : '?123'), () => setState(() => _symbols = !_symbols),
                  flex: 1.5, label: _symbols ? l10n.chatVkLetters : l10n.chatVkSymbols),
              _key('char-,', const Text(',', style: TextStyle(fontSize: 18)), () => _type(',')),
              _key('space', const SizedBox.shrink(), () => _type(' '), flex: 5, label: l10n.chatVkSpace),
              _key('char-.', const Text('.', style: TextStyle(fontSize: 18)), () => _type('.')),
              _key('enter', const Icon(Icons.keyboard_return), () => _type('\n'), flex: 1.5, label: l10n.chatVkEnter),
            ],
          ),
        ],
      ),
    );
  }
}
