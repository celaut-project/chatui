import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_strings.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';

/// What the user chose after a node forgot the client id of the app.
enum ClientUnknownChoice {
  /// A new client was made on the node. The balance of the old client is lost.
  newClient,

  /// Nothing changes; the user tries again later.
  retryLater,
}

/// The node at [node] does not know the client id of the app (`docs/celaut/ui.md`,
/// section 3). Show the error and let the user choose: a new client (the old balance is
/// lost) or a retry later. The app never makes a new client without this choice.
///
/// [newClient] makes the client; tests give their own.
Future<ClientUnknownChoice> showClientUnknownChoice(
  BuildContext context, {
  required NodeAddress node,
  required String error,
  Future<NewClientView> Function(NodeAddress node)? newClient,
}) async {
  final make = newClient ?? (n) => celautNewClient(node: n);
  final chosen = await showDialog<ClientUnknownChoice>(
    context: context,
    builder: (ctx) {
      final l = ctx.l10n;
      return AlertDialog(
        key: const Key('client-unknown-dialog'),
        title: Text(l.celautClientUnknownTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.celautClientUnknownBody('${node.host}:${node.port}')),
              const SizedBox(height: 10),
              Text(
                l.celautClientUnknownWarning,
                key: const Key('client-unknown-warning'),
                style: TextStyle(color: rustFor(ctx)),
              ),
              const SizedBox(height: 10),
              Text(
                CelautStrings.detailLabel(error),
                style: TextStyle(fontSize: 12, color: ArgusColors.of(ctx).muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('client-unknown-retry'),
            onPressed: () => Navigator.pop(ctx, ClientUnknownChoice.retryLater),
            child: Text(l.celautClientUnknownRetry),
          ),
          FilledButton(
            key: const Key('client-unknown-new'),
            onPressed: () => Navigator.pop(ctx, ClientUnknownChoice.newClient),
            child: Text(l.celautClientUnknownNew),
          ),
        ],
      );
    },
  );
  if (chosen != ClientUnknownChoice.newClient) return ClientUnknownChoice.retryLater;
  try {
    await make(node);
  } on CelautError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${CelautStrings.errorText(e.kind)} ${e.message}')),
      );
    }
    return ClientUnknownChoice.retryLater;
  }
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.celautClientUnknownDone)),
    );
  }
  return ClientUnknownChoice.newClient;
}
