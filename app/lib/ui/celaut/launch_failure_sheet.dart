import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/launch_problems.dart';
import '../../celaut/launcher.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';

/// Show why a launch failed: one line for each node, with the reason, what to do, and the
/// text of the node under "Details" (`docs/celaut/ui.md`).
Future<void> showLaunchFailureSheet(
  BuildContext context,
  LaunchFailure failure, {
  VoidCallback? onDeposit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => LaunchFailureSheet(
      failure: failure,
      onDeposit: onDeposit == null
          ? null
          : () {
              Navigator.of(context).pop();
              onDeposit();
            },
    ),
  );
}

/// The content of the sheet of a failed launch.
class LaunchFailureSheet extends StatelessWidget {
  const LaunchFailureSheet({super.key, required this.failure, this.onDeposit});

  final LaunchFailure failure;

  /// Open the deposit screen. The button is shown only for a credit problem.
  final VoidCallback? onDeposit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final problems = problemsOf(failure);
    final intro = switch (failure.kind) {
      LaunchFailureKind.noNodes => l.celautRunFailedNoNodes,
      LaunchFailureKind.noQuotes => l.celautRunFailedNoQuotes,
      LaunchFailureKind.allFailed => l.celautRunFailedAll,
    };
    final needsDeposit = problems.any((p) => p.action == ProblemAction.addDeposit);
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('launch-failure'),
        padding: const EdgeInsets.fromLTRB(homeGutter, 0, homeGutter, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.celautRunFailedTitle, style: t.title),
            const SizedBox(height: 8),
            Text(intro, key: const Key('launch-failure-intro'), style: t.secondary),
            const SizedBox(height: 12),
            for (final p in problems) ...[
              _ProblemTile(problem: p),
              const SizedBox(height: 10),
            ],
            if (needsDeposit && onDeposit != null) ...[
              const SizedBox(height: 4),
              FilledButton(
                key: const Key('launch-failure-deposit'),
                onPressed: onDeposit,
                child: Text(l.celautRunDeposit),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('launch-failure-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.celautRunClose),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProblemTile extends StatelessWidget {
  const _ProblemTile({required this.problem});

  final LaunchProblem problem;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final p = problem;
    final credit = p.kind == CelautErrorKind.insufficientCredit &&
        p.creditMu != null &&
        p.costMu != null;
    final lines = <String>[
      if (p.leftOut) l.celautRunLeftOut,
      if (credit)
        l.celautRunNeedsCredit(muOrUnknown(p.creditMu), muOrUnknown(p.costMu))
      else
        CelautStrings.errorText(p.kind),
    ];
    return Column(
      key: Key('launch-problem-${p.address}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.address,
          style: t.primary.copyWith(fontFamily: 'monospace', fontSize: 13.5),
        ),
        const SizedBox(height: 2),
        for (final line in lines) Text(line, style: t.secondary),
        if (p.message.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: Key('launch-details-${p.address}'),
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(l.celautRunDetails, style: t.label),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    p.message,
                    style: t.secondary.copyWith(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
