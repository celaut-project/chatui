import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/conversations.dart';
import '../../celaut/payers.dart';
import '../../l10n/l10n.dart';

/// Where an instance of the list of conversations is.
enum InstanceState {
  /// The app asks the node.
  checking,

  /// The instance started in this run of the app, and its service did not answer yet.
  starting,

  /// The node reports the instance.
  running,

  /// The node does not answer, or does not report the instance.
  unreachable,

  /// The instance stopped. It stays in the list until the user deletes it.
  stopped,
}

String instanceStateText(BuildContext context, InstanceState state) {
  final l = context.l10n;
  return switch (state) {
    InstanceState.checking => l.chatsStateChecking,
    InstanceState.starting => l.chatsStateStarting,
    InstanceState.running => l.chatsStateRunning,
    InstanceState.unreachable => l.chatsStateUnreachable,
    InstanceState.stopped => l.chatsStateStopped,
  };
}

/// Stop [instance] after the user confirms it. Stopping needs the wallet open
/// (`docs/celaut/ui.md`, section 1). The stopped instance stays in the database, and in
/// the list, until the user deletes it. If the node does not answer, the user sees why
/// and the instance stays as it was. Gives the answer of the node, or null if nothing
/// was stopped.
Future<StopView?> confirmAndStopInstance(
  BuildContext context,
  InstanceListView instance, {
  FullWallets wallets = const AppFullWallets(),
  Future<StopView> Function(String instanceId)? stop,
  ConversationNotes? notes,
}) async {
  final l = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('stop-confirm'),
      title: Text(l.chatsStopTitle(instanceTitle(instance))),
      content: Text(l.chatsStopBody),
      actions: [
        TextButton(
          key: const Key('stop-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.celautSendCancel),
        ),
        FilledButton(
          key: const Key('stop-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.chatStop),
        ),
      ],
    ),
  );
  if (sure != true || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  if (!await ensureOpenFullWallet(context, wallets)) {
    messenger.showSnackBar(SnackBar(content: Text(l.celautOpenFullWalletNeeded)));
    return null;
  }
  try {
    final done = await (stop ?? (id) => celautStopService(instanceId: id))(instance.instanceId);
    (notes ?? conversationNotes).stopped(instance.instanceId);
    messenger.showSnackBar(SnackBar(content: Text(l.chatStopped(muOrUnknown(done.refundMu)))));
    return done;
  } on CelautError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(CelautStrings.errorText(e.kind))));
    return null;
  }
}

/// Delete a stopped [instance] after the user confirms it: it leaves the database and
/// the list. Only a stopped instance can be deleted; the app never forgets an instance
/// that was not stopped (`docs/celaut/decisions.md`). Gives true if it left the list.
Future<bool> confirmAndDeleteInstance(
  BuildContext context,
  InstanceListView instance, {
  void Function(String instanceId)? forget,
  ConversationNotes? notes,
}) async {
  if (instance.stoppedAt == null) return false;
  final l = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('delete-confirm'),
      title: Text(l.chatsDeleteTitle(instanceTitle(instance))),
      content: Text(l.chatsDeleteBody),
      actions: [
        TextButton(
          key: const Key('delete-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.celautSendCancel),
        ),
        FilledButton(
          key: const Key('delete-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.chatsDelete),
        ),
      ],
    ),
  );
  if (sure != true || !context.mounted) return false;
  try {
    (forget ?? (id) => celautForgetInstance(instanceId: id))(instance.instanceId);
  } on CelautError catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(CelautStrings.errorText(e.kind))),
    );
    return false;
  }
  (notes ?? conversationNotes).remove(instance.instanceId);
  return true;
}
