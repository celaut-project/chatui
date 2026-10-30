import 'package:flutter/material.dart';

import '../../celaut/chat_groups.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';

/// Ask for the name of a group ([initial] when renaming). The name, cleaned, or null if the
/// user cancels or leaves it blank.
Future<String?> askGroupName(BuildContext context, {required String title, String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _GroupNameDialog(title: title, initial: initial),
  );
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final name = ChatGroups.cleanName(_field.text);
    Navigator.pop(context, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const Key('group-name-dialog'),
      title: Text(widget.title),
      content: TextField(
        key: const Key('group-name-field'),
        controller: _field,
        autofocus: true,
        maxLength: ChatGroups.maxNameChars,
        decoration: InputDecoration(labelText: l.chatsGroupsNameLabel),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: const Key('group-name-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const Key('group-name-ok'),
          onPressed: _save,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}

/// The header of a group in the grouped chat list: its name and the number of rows,
/// a tap collapses or expands it, and the menu renames or deletes it. [GroupHeader.plain]
/// is the header of the conversations that are in no group, with no menu.
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required ChatGroup this.group,
    required this.count,
    required this.collapsed,
    required VoidCallback this.onToggle,
    required VoidCallback this.onRename,
    required VoidCallback this.onDelete,
  })  : title = null;

  const GroupHeader.plain({super.key, required String this.title})
      : group = null,
        count = 0,
        collapsed = false,
        onToggle = null,
        onRename = null,
        onDelete = null;

  final ChatGroup? group;
  final String? title;
  final int count;
  final bool collapsed;
  final VoidCallback? onToggle;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final g = group;
    if (g == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title ?? '', style: t.secondary),
      );
    }
    return InkWell(
      key: Key('group-header-${g.id}'),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 22, color: t.muted),
            const SizedBox(width: 6),
            Icon(Icons.folder_outlined, size: 20, color: t.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                g.name,
                key: Key('group-name-${g.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.title,
              ),
            ),
            Text('$count', key: Key('group-count-${g.id}'), style: t.secondary),
            PopupMenuButton<String>(
              key: Key('group-menu-${g.id}'),
              onSelected: (v) => v == 'rename' ? onRename?.call() : onDelete?.call(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: Key('group-rename-${g.id}'),
                  value: 'rename',
                  child: Text(l.chatsGroupsRename),
                ),
                PopupMenuItem(
                  key: Key('group-delete-${g.id}'),
                  value: 'delete',
                  child: Text(l.chatsGroupsDelete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
