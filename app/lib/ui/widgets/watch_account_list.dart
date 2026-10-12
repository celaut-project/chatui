import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/watch_account_service.dart';
import '../../services/watch_only_service.dart';
import '../../theme/argus_theme.dart';

// The two ways to watch a wallet without its keys. Both start from the
// overview; a watched wallet then opens the standard wallet page.

/// Asks for an Ergo address or a P2PK public key and watches it. Returns
/// true when one was added.
Future<bool> addWatchAddress(BuildContext context) async {
  final text = (await showDialog<String>(
    context: context,
    builder: (_) => const _WatchAddressDialog(),
  ))
      ?.trim();
  if (text == null || text.isEmpty || !context.mounted) return false;
  final bool added;
  try {
    added = await watchOnlyService.add(text);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.watchAddFailed('$e'))),
      );
    }
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? context.l10n.watchAddressAdded
              : context.l10n.watchAddInvalid,
        ),
      ),
    );
  }
  return added;
}

/// Owns its field's controller: one disposed as soon as `showDialog` returns
/// would still be in use by the dialog animating out.
class _WatchAddressDialog extends StatefulWidget {
  const _WatchAddressDialog();
  @override
  State<_WatchAddressDialog> createState() => _WatchAddressDialogState();
}

class _WatchAddressDialogState extends State<_WatchAddressDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.l10n.watchAddressTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.watchAddressIntro),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              style: monoStyle(context, size: 13),
              decoration: InputDecoration(
                labelText: context.l10n.watchAddressLabel,
                helperText: context.l10n.watchAddressHelper,
                helperMaxLines: 2,
                hintText: '9...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(context.l10n.watchAction),
          ),
        ],
      );
}

/// Asks for an Ergo Wallet App extended public key and watches its account,
/// after saying what holding that key reveals.
Future<void> addWatchAccount(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ImportAccountDialog(),
    );

class _ImportAccountDialog extends StatefulWidget {
  const _ImportAccountDialog();
  @override
  State<_ImportAccountDialog> createState() => _ImportAccountDialogState();
}

class _ImportAccountDialogState extends State<_ImportAccountDialog> {
  final controller = TextEditingController();
  String? error;
  var busy = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.l10n.watchXpubTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(watchAccountDisclosure),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.watchXpubLabel,
                  helperText: context.l10n.watchXpubHelper,
                  helperMaxLines: 3,
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final saved = await watchAccountService.add(controller.text);
                      if (!context.mounted) return;
                      if (saved) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          error = context.l10n.watchXpubAlreadyWatched;
                          busy = false;
                        });
                      }
                    } catch (e) {
                      if (context.mounted) {
                        setState(() {
                          error = e is StateError
                              ? e.message.toString()
                              : watchAccountExpected;
                          busy = false;
                        });
                      }
                    }
                  },
            child: Text(context.l10n.watchAccountAction),
          ),
        ],
      );
}
