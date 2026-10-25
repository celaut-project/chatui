import 'package:flutter/material.dart';

import '../../bridge/api/celaut_env.dart';
import '../../bridge/api/celaut_service_info.dart' show NetworkView;
import '../../celaut/egress.dart';
import '../../celaut/env_store.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import 'env_variables_screen.dart' show envProblemText;

/// What the user chose for one declared variable.
sealed class EnvAnswer {
  const EnvAnswer();
}

/// The value of a variable of the container.
class EnvFromContainer extends EnvAnswer {
  const EnvFromContainer(this.name);
  final String name;
}

/// A value that the user typed.
class EnvTyped extends EnvAnswer {
  const EnvTyped(this.text);
  final String text;
}

/// The variable is not given: it is not in the configuration.
class EnvSkipped extends EnvAnswer {
  const EnvSkipped();
}

/// The choices that go to the start, in the order of [declared]. A skipped variable, or
/// one without an answer, is left out.
List<EnvChoice> envChoices(List<DeclaredVariableView> declared, List<EnvAnswer?> answers) {
  final out = <EnvChoice>[];
  for (var i = 0; i < declared.length; i++) {
    switch (answers[i]) {
      case EnvFromContainer(:final name):
        out.add(EnvChoice(name: declared[i].name, container: name));
      case EnvTyped(:final text):
        out.add(EnvChoice(name: declared[i].name, text: text));
      case EnvSkipped() || null:
        break;
    }
  }
  return out;
}

/// The question about the environment variables of a service, one variable at a time,
/// then a review (`docs/celaut/env-variables.md`, section 3). For each variable the user
/// chooses one of the container, types a value, or skips it. Closing the screen cancels
/// the launch: it gives null. Run on the review gives the choices.
class EnvQuestionsScreen extends StatefulWidget {
  const EnvQuestionsScreen({
    super.key,
    required this.declared,
    this.networks = const [],
    EnvStore? store,
  }) : _store = store;

  final List<DeclaredVariableView> declared;

  /// The networks that the service declares. Where it can connect decides what the screen
  /// tells the user about the values (`docs/celaut/env-variables.md`, section 3.1).
  final List<NetworkView> networks;
  final EnvStore? _store;

  @override
  State<EnvQuestionsScreen> createState() => _EnvQuestionsScreenState();
}

class _EnvQuestionsScreenState extends State<EnvQuestionsScreen> {
  late final EnvStore _store = widget._store ?? EnvStore();
  late final List<EnvAnswer?> _answers = List.filled(widget.declared.length, null);
  late final EgressReport _egress = egressOf(widget.networks);

  /// The user accepted, on the review, that the service can send the values out.
  bool _ack = false;
  int _index = 0;
  bool _typing = false;
  bool _hidden = true;
  String? _typedError;
  final _typedCtrl = TextEditingController();

  bool get _review => _index >= widget.declared.length;

  @override
  void dispose() {
    _typedCtrl.dispose();
    super.dispose();
  }

  void _go(int index) {
    setState(() {
      _index = index;
      _typing = false;
      _hidden = true;
      _typedError = null;
      _typedCtrl.clear();
      // The answers can change from here: the acceptance is of the answers as they are.
      _ack = false;
    });
  }

  /// The review asks for an acceptance when what the user gives can leave the node: any
  /// value, if the service can connect to every address; a value of the container (the
  /// secrets that the user keeps) if it declares hosts.
  bool get _needsAck {
    if (!_egress.leaves) return false;
    final fromContainer = _answers.any((a) => a is EnvFromContainer);
    final given = fromContainer || _answers.any((a) => a is EnvTyped);
    return _egress.level == EgressLevel.open ? given : fromContainer;
  }

  /// Where the service can send what it is given, or null if it has no exit.
  Widget? _egressNotice(AppLocalizations l) {
    if (!_egress.leaves) return null;
    final open = _egress.level == EgressLevel.open;
    final color = open ? rustFor(context) : ArgusColors.of(context).accentText;
    final shown = _egress.hosts.take(4).join(', ');
    final hosts = _egress.hosts.length > 4 ? '$shown…' : shown;
    return Container(
      key: const Key('env-egress-notice'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(open ? Icons.public : Icons.north_east, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(open ? l.celautEnvEgressOpen : l.celautEnvEgressNamed(hosts))),
        ],
      ),
    );
  }

  void _answer(EnvAnswer answer) {
    _answers[_index] = answer;
    _go(_index + 1);
  }

  List<String> _containerNames(String declared) {
    List<String> names;
    try {
      names = [for (final n in _store.names()) n.name];
    } catch (_) {
      names = const [];
    }
    // The variables with the same name as the declared one come first.
    return [...names.where((n) => n == declared), ...names.where((n) => n != declared)];
  }

  Future<void> _pick() async {
    final l = context.l10n;
    final names = _containerNames(widget.declared[_index].name);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const Key('env-pick-sheet'),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l.celautEnvAskPickTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (names.isEmpty)
              Padding(
                key: const Key('env-pick-empty'),
                padding: const EdgeInsets.all(16),
                child: Text(l.celautEnvAskPickEmpty),
              ),
            for (final n in names)
              ListTile(
                key: Key('env-pick-$n'),
                title: Text(n, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 14)),
                subtitle: const Text('••••••••'),
                onTap: () => Navigator.pop(context, n),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _answer(EnvFromContainer(picked));
  }

  void _useTyped() {
    final problem = envValueProblem(_typedCtrl.text);
    if (problem != null) {
      setState(() => _typedError = envProblemText(context.l10n, problem));
      return;
    }
    _answer(EnvTyped(_typedCtrl.text));
  }

  String _describe(AppLocalizations l, EnvAnswer? a) => switch (a) {
        EnvFromContainer(:final name) => l.celautEnvReviewFromContainer(name),
        EnvTyped() => l.celautEnvReviewTyped,
        EnvSkipped() || null => l.celautEnvReviewSkipped,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final total = widget.declared.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back goes to the earlier variable; on the first one it cancels the launch.
        if (_index > 0) {
          _go(_index - 1);
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.celautEnvAskTitle),
          leading: IconButton(
            key: const Key('env-cancel'),
            tooltip: l.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: _review ? _reviewPage(l) : _questionPage(l, _index, total),
        ),
      ),
    );
  }

  List<Widget> _questionPage(AppLocalizations l, int i, int total) {
    final colors = ArgusColors.of(context);
    final v = widget.declared[i];
    final usable = envNameProblem(v.name) == null;
    final text = v.prose.isNotEmpty ? v.prose : (v.tags.isNotEmpty ? v.tags.join(', ') : l.celautEnvAskNoText);
    final chosen = _answers[i];
    return [
      Text(
        l.celautEnvAskStep(i + 1, total),
        key: const Key('env-step'),
        style: TextStyle(fontSize: 12.5, color: colors.muted),
      ),
      const SizedBox(height: 8),
      Text(v.name, key: const Key('env-var-name'), style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 20)),
      const SizedBox(height: 8),
      Text(text, key: const Key('env-var-text')),
      if (_egress.steered.containsKey(v.name))
        Padding(
          key: const Key('env-egress-steers'),
          padding: const EdgeInsets.only(top: 8),
          child: Text(l.celautEnvEgressSteers, style: TextStyle(fontSize: 12.5, color: rustFor(context))),
        ),
      if (_egress.leaves) ...[const SizedBox(height: 12), ?_egressNotice(l)],
      if (chosen != null) ...[
        const SizedBox(height: 8),
        Text(l.celautEnvAskChosen(_describe(l, chosen)), style: TextStyle(fontSize: 12.5, color: colors.muted)),
      ],
      const SizedBox(height: 16),
      if (!usable)
        Padding(
          key: const Key('env-bad-name'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(l.celautEnvAskBadName),
        )
      else ...[
        OutlinedButton.icon(
          key: const Key('env-ask-pick'),
          onPressed: _pick,
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text(l.celautEnvAskPick),
        ),
        const SizedBox(height: 8),
        if (!_typing)
          OutlinedButton.icon(
            key: const Key('env-ask-type'),
            onPressed: () => setState(() => _typing = true),
            icon: const Icon(Icons.edit_outlined),
            label: Text(l.celautEnvAskType),
          )
        else ...[
          TextField(
            key: const Key('env-typed'),
            controller: _typedCtrl,
            autofocus: true,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.celautEnvValue,
              errorText: _typedError,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                key: const Key('env-typed-eye'),
                tooltip: _hidden ? l.celautEnvShow : l.celautEnvHide,
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(key: const Key('env-typed-use'), onPressed: _useTyped, child: Text(l.celautEnvAskUse)),
        ],
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        key: const Key('env-ask-skip'),
        onPressed: () => _answer(const EnvSkipped()),
        icon: const Icon(Icons.not_interested),
        label: Text(l.celautEnvAskSkip),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(l.celautEnvAskSkipHint, style: TextStyle(fontSize: 12.5, color: colors.muted)),
      ),
      if (i > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('env-back'),
            onPressed: () => _go(i - 1),
            child: Text(l.celautEnvAskBack),
          ),
        ),
    ];
  }

  List<Widget> _reviewPage(AppLocalizations l) {
    final colors = ArgusColors.of(context);
    return [
      Text(l.celautEnvReviewTitle, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      ?_egressNotice(l),
      for (var i = 0; i < widget.declared.length; i++)
        ListTile(
          key: Key('env-review-${widget.declared[i].name}'),
          contentPadding: EdgeInsets.zero,
          title: Text(widget.declared[i].name, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 14)),
          subtitle: Text(_describe(l, _answers[i])),
        ),
      const SizedBox(height: 8),
      Text(l.celautEnvReviewNote, key: const Key('env-review-note'), style: TextStyle(fontSize: 12.5, color: colors.muted)),
      const SizedBox(height: 16),
      if (_needsAck)
        CheckboxListTile(
          key: const Key('env-egress-ack'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _ack,
          onChanged: (v) => setState(() => _ack = v ?? false),
          title: Text(l.celautEnvEgressAck),
        ),
      FilledButton(
        key: const Key('env-run'),
        onPressed: _needsAck && !_ack
            ? null
            : () => Navigator.pop(context, envChoices(widget.declared, _answers)),
        child: Text(l.celautEnvRun),
      ),
      TextButton(
        key: const Key('env-back'),
        onPressed: () => _go(widget.declared.length - 1),
        child: Text(l.celautEnvAskBack),
      ),
    ];
  }
}
