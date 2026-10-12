import 'package:flutter/material.dart';

import '../../services/wallet_service.dart';
import 'asset_tile.dart';
import '../../l10n/l10n.dart';

/// Selection is independent of the filtered and lazily mounted rows.
class HeldTokenPicker extends StatefulWidget {
  const HeldTokenPicker({
    super.key,
    required this.tokens,
    required this.selected,
  });
  final List<TokenBalance> tokens;
  final Set<String> selected;

  @override
  State<HeldTokenPicker> createState() => _HeldTokenPickerState();
}

class _HeldTokenPickerState extends State<HeldTokenPicker> {
  late final _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = {for (final t in widget.tokens) t.id: t}.values
        .where(
          (t) =>
              t.label.toLowerCase().contains(_query) ||
              t.id.toLowerCase().contains(_query),
        )
        .toList();
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: Text(context.l10n.sendChooseTokens),
            trailing: IconButton(
              tooltip: context.l10n.commonCancel,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.l10n.pickerSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: tokens.isEmpty
                ? Center(child: Text(context.l10n.pickerNoMatch))
                : ListView.builder(
                    itemCount: tokens.length,
                    itemBuilder: (context, index) {
                      final t = tokens[index];
                      void toggle() => setState(() {
                        if (!_selected.add(t.id)) _selected.remove(t.id);
                      });
                      return Row(
                        key: ValueKey('pick-${t.id}'),
                        children: [
                          Checkbox(
                            value: _selected.contains(t.id),
                            onChanged: (_) => toggle(),
                            semanticLabel: context.l10n.pickerSelect(t.label),
                          ),
                          Expanded(
                            child: AssetTile.token(
                              t,
                              showChevron: false,
                              onTap: toggle,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: Text(context.l10n.pickerSelectedCount('${_selected.length}'))),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(context.l10n.commonDone),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<Set<String>?> showHeldTokenPicker(
  BuildContext context, {
  required List<TokenBalance> tokens,
  required Set<String> selected,
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: .85,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: HeldTokenPicker(tokens: tokens, selected: selected),
    ),
  ),
);
