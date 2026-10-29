import 'package:flutter/material.dart';

/// The rows of a list of chips of [widths], side by side while they fit in [maxWidth] (with
/// [spacing] between them). A chip that is wider than [maxWidth] has a row of its own.
/// It gives the indexes of the chips of each row, in order.
List<List<int>> packChipRows(List<double> widths, double maxWidth, {double spacing = 8}) {
  final rows = <List<int>>[];
  var row = <int>[];
  var used = 0.0;
  for (var i = 0; i < widths.length; i++) {
    final next = row.isEmpty ? widths[i] : used + spacing + widths[i];
    if (row.isNotEmpty && next > maxWidth) {
      rows.add(row);
      row = <int>[];
      used = 0;
    }
    used = row.isEmpty ? widths[i] : used + spacing + widths[i];
    row.add(i);
  }
  if (row.isNotEmpty) rows.add(row);
  return rows;
}

/// The options of a list as chips, side by side while they fit, in rows that turn like a
/// wheel: the row in the middle is bigger and clear, and the rows above and below are
/// smaller and fade. The user turns it with a drag up or down, and taps a chip to choose it.
/// [selected] says which chips are on, and [onTap] gets the index of the chip that was tapped.
/// With [multiple] the chips show a check mark when they are on.
class ChatWheelOptions extends StatefulWidget {
  const ChatWheelOptions({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
    required this.style,
    this.multiple = false,
  });

  final List<String> labels;
  final List<bool> selected;
  final void Function(int index) onTap;
  final TextStyle style;
  final bool multiple;

  /// The height of a row, and how many rows show at once.
  static const double rowExtent = 44;
  static const int visibleRows = 3;

  @override
  State<ChatWheelOptions> createState() => _ChatWheelOptionsState();
}

class _ChatWheelOptionsState extends State<ChatWheelOptions> {
  FixedExtentScrollController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The width that a chip needs: its text, and the room that the chip and its mark take.
  double _chipWidth(String label, TextScaler scaler) {
    final p = TextPainter(
      text: TextSpan(text: label, style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = p.width;
    p.dispose();
    return width + (widget.multiple ? 56 : 40);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final maxWidth = box.maxWidth.isFinite ? box.maxWidth : 320.0;
        final rows = packChipRows([for (final l in widget.labels) _chipWidth(l, scaler)], maxWidth);
        if (rows.isEmpty) return const SizedBox.shrink();
        // The wheel starts at the row of the first chip that is on.
        _controller ??= FixedExtentScrollController(
          initialItem: rows.indexWhere((r) => r.any((i) => widget.selected[i])).clamp(0, rows.length - 1),
        );
        final shown = rows.length < ChatWheelOptions.visibleRows ? rows.length : ChatWheelOptions.visibleRows;
        return SizedBox(
          height: shown * ChatWheelOptions.rowExtent,
          child: ListWheelScrollView.useDelegate(
            key: const Key('chat-wheel'),
            controller: _controller,
            itemExtent: ChatWheelOptions.rowExtent,
            physics: const FixedExtentScrollPhysics(),
            diameterRatio: 2.2,
            perspective: 0.003,
            useMagnifier: true,
            magnification: 1.15,
            overAndUnderCenterOpacity: 0.35,
            childDelegate: ListWheelChildListDelegate(
              children: [
                for (final row in rows)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var k = 0; k < row.length; k++) ...[
                        if (k > 0) const SizedBox(width: 8),
                        Flexible(child: _chip(row[k])),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(int i) {
    final on = widget.selected[i];
    final label = Text(widget.labels[i], style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return widget.multiple
        ? FilterChip(
            key: Key('chat-option-$i'),
            label: label,
            selected: on,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => widget.onTap(i),
          )
        : ChoiceChip(
            key: Key('chat-option-$i'),
            label: label,
            selected: on,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => widget.onTap(i),
          );
  }
}
