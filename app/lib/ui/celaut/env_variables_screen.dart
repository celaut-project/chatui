import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_env.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/env_store.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';

/// The text for a problem with a name or a value.
String envProblemText(AppLocalizations l, EnvProblem problem) => switch (problem) {
      EnvProblem.nameEmpty => l.celautEnvNameBad,
      EnvProblem.nameBad => l.celautEnvNameBad,
      EnvProblem.nameReserved => l.celautEnvNameReserved,
      EnvProblem.valueEmpty => l.celautEnvValueEmpty,
      EnvProblem.valueLong => l.celautEnvValueLong,
      EnvProblem.valueNul => l.celautEnvValueNul,
    };

/// The container of environment variables (`docs/celaut/env-variables.md`, section 2):
/// the names, with the value hidden. Add, edit and delete. A value is shown only in the
/// edit form, with the eye.
class EnvVariablesScreen extends StatefulWidget {
  const EnvVariablesScreen({super.key, EnvStore? store}) : _store = store;

  final EnvStore? _store;

  @override
  State<EnvVariablesScreen> createState() => _EnvVariablesScreenState();
}

class _EnvVariablesScreenState extends State<EnvVariablesScreen> {
  late final EnvStore _store = widget._store ?? EnvStore();
  late List<EnvNameView> _names = _read();

  List<EnvNameView> _read() {
    try {
      return _store.names();
    } catch (_) {
      // No database yet: the screen shows an empty container.
      return const [];
    }
  }

  void _reload() => setState(() => _names = _read());

  Future<void> _edit(String? name) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EnvEditDialog(store: _store, name: name, existing: {for (final n in _names) n.name}),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(String name) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('env-delete-confirm'),
        title: Text(l.celautEnvDeleteTitle(name)),
        content: Text(l.celautEnvDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.commonCancel)),
          TextButton(
            key: const Key('env-delete-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.celautEnvDelete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      _store.delete(name);
    } on CelautError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(CelautStrings.errorText(e.kind))));
      }
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = ArgusColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.celautEnvTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('env-add'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text(l.celautEnvAdd),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text(l.celautEnvIntro, style: TextStyle(fontSize: 13, color: colors.muted)),
          const SizedBox(height: 16),
          if (_names.isEmpty)
            Padding(
              key: const Key('env-empty'),
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text(l.celautEnvEmpty, style: TextStyle(color: colors.muted))),
            ),
          for (final n in _names)
            ListTile(
              key: Key('env-row-${n.name}'),
              contentPadding: EdgeInsets.zero,
              title: Text(n.name, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 14)),
              subtitle: const Text('••••••••'),
              onTap: () => _edit(n.name),
              trailing: IconButton(
                key: Key('env-delete-${n.name}'),
                tooltip: l.celautEnvDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(n.name),
              ),
            ),
        ],
      ),
    );
  }
}

/// Add a variable (no [name]) or edit one. The value is hidden until the eye is tapped.
class _EnvEditDialog extends StatefulWidget {
  const _EnvEditDialog({required this.store, required this.name, required this.existing});

  final EnvStore store;
  final String? name;
  final Set<String> existing;

  @override
  State<_EnvEditDialog> createState() => _EnvEditDialogState();
}

class _EnvEditDialogState extends State<_EnvEditDialog> {
  late final _nameCtrl = TextEditingController(text: widget.name ?? '');
  late final _valueCtrl = TextEditingController(text: widget.name == null ? '' : widget.store.value(widget.name!) ?? '');
  bool _hidden = true;
  String? _nameError;
  String? _valueError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final l = context.l10n;
    final name = _nameCtrl.text;
    final value = _valueCtrl.text;
    final nameProblem = widget.name == null ? envNameProblem(name) : null;
    final valueProblem = envValueProblem(value);
    String? nameError = nameProblem == null ? null : envProblemText(l, nameProblem);
    if (nameError == null && widget.name == null) {
      if (widget.existing.contains(name)) {
        nameError = l.celautEnvNameTaken;
      } else if (widget.existing.length >= envMaxVariables) {
        nameError = l.celautEnvTooMany;
      }
    }
    setState(() {
      _nameError = nameError;
      _valueError = valueProblem == null ? null : envProblemText(l, valueProblem);
    });
    if (nameError != null || valueProblem != null) return;
    try {
      widget.store.set(widget.name ?? name, value);
      Navigator.pop(context, true);
    } on CelautError catch (e) {
      setState(() => _valueError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final editing = widget.name != null;
    return AlertDialog(
      key: const Key('env-edit'),
      title: Text(editing ? l.celautEnvEditTitle(widget.name!) : l.celautEnvAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!editing)
              TextField(
                key: const Key('env-name'),
                controller: _nameCtrl,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: l.celautEnvName, errorText: _nameError, errorMaxLines: 3),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('env-value'),
              controller: _valueCtrl,
              obscureText: _hidden,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: _hidden ? 1 : 4,
              decoration: InputDecoration(
                labelText: l.celautEnvValue,
                errorText: _valueError,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  key: const Key('env-eye'),
                  tooltip: _hidden ? l.celautEnvShow : l.celautEnvHide,
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.commonCancel)),
        FilledButton(key: const Key('env-save'), onPressed: _save, child: Text(l.commonSave)),
      ],
    );
  }
}
