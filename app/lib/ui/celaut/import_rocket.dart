import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridge/api/celaut_package.dart';
import '../../celaut/celaut_strings.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';
import 'raise_rocket.dart';

/// The user cancelled the import while the app checked the file.
class ImportCancelled implements Exception {
  const ImportCancelled();

  @override
  String toString() => 'ImportCancelled()';
}

/// Run [work] (the load of a service file) under a card with the rocket, the bytes that
/// the app checked so far, and Cancel. The rocket lies on its pad and the pad raises it as
/// the bytes are checked ([RaiseStage]); when [work] ends well, it stands before the card
/// goes. It does not take off: that is the launch's. A failure of [work] is thrown again, as [ImportCancelled] when the user
/// pressed Cancel.
///
/// [progress] and [cancel] are the calls of the Rust side (`celaut_transfer_progress`,
/// `celaut_cancel_transfer`): they are injected so that tests need no Rust.
Future<T> runWithImportRocket<T>(
  BuildContext context, {
  required Future<T> Function() work,
  required TransferView Function() progress,
  required void Function() cancel,
  Duration poll = const Duration(milliseconds: 200),
}) async {
  final navigator = Navigator.of(context);
  final stage = GlobalKey<RaiseStageState>();
  var cancelled = false;
  final route = RawDialogRoute<void>(
    barrierDismissible: false,
    barrierColor: Colors.black54,
    pageBuilder: (context, animation, secondary) => PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _ImportCard(
            stage: stage,
            progress: progress,
            poll: poll,
            onCancel: () {
              cancelled = true;
              cancel();
            },
          ),
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    final result = await work();
    await stage.currentState?.finish();
    return result;
  } catch (_) {
    if (cancelled) throw const ImportCancelled();
    rethrow;
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

class _ImportCard extends StatefulWidget {
  const _ImportCard({
    required this.stage,
    required this.progress,
    required this.poll,
    required this.onCancel,
  });

  final GlobalKey<RaiseStageState> stage;
  final TransferView Function() progress;
  final Duration poll;
  final VoidCallback onCancel;

  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  Timer? _timer;
  TransferView? _view;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.poll, (_) {
      if (!mounted) return;
      final view = widget.progress();
      setState(() => _view = view);
      widget.stage.currentState?.setProgress(_fractionOf(view));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The share of the file checked, or null while the total is not known.
  static double? _fractionOf(TransferView? view) {
    final total = view?.total?.toInt();
    if (view == null || total == null || total <= 0) return null;
    return (view.bytes.toInt() / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final view = _view;
    final done = view?.bytes.toInt() ?? 0;
    final total = view?.total?.toInt();
    final fraction = _fractionOf(view);
    final amount = fraction != null
        ? l.celautSendProgress(
            CelautStrings.bytes(done),
            CelautStrings.bytes(total!),
            (fraction * 100).floor().toString(),
          )
        : l.celautSendSoFar(CelautStrings.bytes(done));
    return Material(
      key: const Key('import-progress'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: RaiseStage(key: widget.stage)),
            const SizedBox(height: 12),
            Text(
              l.celautImportChecking,
              style: t.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l.celautImportNote,
              style: t.secondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              key: const Key('import-bar'),
              value: fraction,
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              key: const Key('import-amount'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('import-cancel'),
              onPressed: _cancelling
                  ? null
                  : () {
                      setState(() => _cancelling = true);
                      widget.onCancel();
                    },
              child: Text(l.celautSendCancel),
            ),
          ],
        ),
      ),
    );
  }
}
