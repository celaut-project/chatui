import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/argus_theme.dart';
import '../../services/wallet_service.dart';
import 'tx_result_view.dart';
import 'tx_explorer_link.dart';
import '../../l10n/l10n.dart';

/// A receipt of acknowledged submissions, not a claim of chain confirmation.
class TxBatchResultView extends StatelessWidget {
  const TxBatchResultView({
    super.key,
    required this.txIds,
    required this.plannedCount,
    required this.onDismiss,
    this.failure,
  });

  final List<String> txIds;
  final int plannedCount;
  final String? failure;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.txBatchTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(context.l10n.txBatchSubmitted('${txIds.length}', '$plannedCount')),
        if (txIds.length < plannedCount)
          Text(
            context.l10n.txBatchStopped('${txIds.length}', '$plannedCount'),
          ),
        if (failure != null) ...[
          const SizedBox(height: 12),
          SelectableText(failure!, style: TextStyle(color: rustFor(context))),
        ],
        for (var i = 0; i < txIds.length; i++) ...[
          const Divider(height: 24),
          Text(context.l10n.txBatchItem('${i + 1}')),
          SelectableText(txIds[i], style: monoStyle(context, size: 12)),
          if (walletService.broadcastWarning(txIds[i]) case final warning?)
            SelectableText(warning, style: TextStyle(color: rustFor(context))),
          TextButton.icon(
            key: ValueKey('copy-${txIds[i]}'),
            onPressed: () => Clipboard.setData(ClipboardData(text: txIds[i])),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(context.l10n.commonCopyId),
          ),
          TxExplorerLink(
            key: ValueKey('explorer-${txIds[i]}'),
            txId: txIds[i],
            label: context.l10n.txViewOnExplorer,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: onDismiss, child: Text(context.l10n.commonDone)),
      ],
    ),
  );
}

Future<void> showTxBatchResultSheet(
  BuildContext context, {
  required List<String> txIds,
  required int plannedCount,
  String? failure,
}) => queueTxPresentation(
  context,
  (survivingContext) => showModalBottomSheet<void>(
    context: survivingContext,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(survivingContext).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
    ),
    builder: (ctx) => SafeArea(
      child: TxBatchResultView(
        txIds: List.unmodifiable(txIds),
        plannedCount: plannedCount,
        failure: failure,
        onDismiss: () => Navigator.pop(ctx),
      ),
    ),
  ),
);
