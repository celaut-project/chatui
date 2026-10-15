import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_package.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/service_transfer.dart';
import '../../l10n/l10n.dart';

/// Ask before a transfer of a service: the whole service goes through the phone, and on
/// mobile data that can cost a lot. True if the user agrees.
Future<bool> confirmServiceTransfer(BuildContext context, {required bool metered}) async {
  final l = context.l10n;
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('send-confirm'),
      title: Text(l.celautSendConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.celautSendConfirmBody),
          if (metered) ...[
            const SizedBox(height: 12),
            Text(
              l.celautSendMetered,
              key: const Key('send-metered'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('send-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.celautSendCancel),
        ),
        FilledButton(
          key: const Key('send-confirm-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.celautSendConfirm),
        ),
      ],
    ),
  );
  return agreed ?? false;
}

/// How a transfer ended: the quote of the node that has the service now, or the error.
class TransferResult {
  const TransferResult.sent(QuoteView this.quote) : error = null;
  const TransferResult.failed(Object this.error) : quote = null;

  final QuoteView? quote;

  /// A [CelautError] or a [PackageRefused].
  final Object? error;
}

/// Run [work] (a transfer of a service) in a dialog that shows its bytes and has Cancel.
Future<TransferResult> showServiceTransfer(
  BuildContext context, {
  required ServiceTransfer transfer,
  required Future<QuoteView> Function() work,
  Duration poll = const Duration(milliseconds: 300),
}) async {
  final result = await showDialog<TransferResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TransferDialog(transfer: transfer, work: work, poll: poll),
  );
  return result ?? const TransferResult.failed(CelautError(kind: CelautErrorKind.transferFailed, message: ''));
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.transfer, required this.work, required this.poll});

  final ServiceTransfer transfer;
  final Future<QuoteView> Function() work;
  final Duration poll;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  Timer? _timer;
  TransferView? _progress;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.poll, (_) {
      if (mounted) setState(() => _progress = widget.transfer.progress());
    });
    _run();
  }

  Future<void> _run() async {
    TransferResult result;
    try {
      result = TransferResult.sent(await widget.work());
    } catch (e) {
      result = TransferResult.failed(e);
    }
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancel() {
    setState(() => _cancelling = true);
    widget.transfer.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = _progress;
    final stage = switch (p?.stage) {
      TransferStage.fetching => l.celautSendFetching,
      TransferStage.sending => l.celautSendSending,
      _ => l.celautSendStarting,
    };
    final done = p?.bytes.toInt() ?? 0;
    final total = p?.total?.toInt();
    final fraction = total != null && total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    final amount = total != null && total > 0
        ? l.celautSendProgress(
            CelautStrings.bytes(done),
            CelautStrings.bytes(total),
            (fraction! * 100).floor().toString(),
          )
        : l.celautSendSoFar(CelautStrings.bytes(done));
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('send-progress'),
        title: Text(stage, key: const Key('send-stage')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 12),
            Text(amount, key: const Key('send-amount')),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('send-cancel'),
            onPressed: _cancelling ? null : _cancel,
            child: Text(l.celautSendCancel),
          ),
        ],
      ),
    );
  }
}

/// The text of why a transfer did not end with the service on the node.
String transferErrorText(BuildContext context, Object error) {
  final l = context.l10n;
  return switch (error) {
    CelautError(:final kind) => CelautStrings.errorText(kind),
    PackageRefused(reason: PackageRefusal.otherService) => l.celautSendOtherService,
    PackageRefused(reason: PackageRefusal.noService) => l.celautSendNoServicePart,
    PackageRefused(reason: PackageRefusal.noDirectory) => l.celautSendNoDirectory,
    _ => CelautStrings.errorText(CelautErrorKind.transferFailed),
  };
}

/// Say why a transfer did not end with the service on the node.
Future<void> showTransferFailure(BuildContext context, Object error) {
  final l = context.l10n;
  final detail = error is CelautError ? error.message : '';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('send-failed'),
      title: Text(l.celautSendFailedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(transferErrorText(context, error), key: const Key('send-failed-text')),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              detail,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('send-failed-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.celautRunClose),
        ),
      ],
    ),
  );
}
