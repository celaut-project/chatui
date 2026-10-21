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

  /// The instance stopped in this run of the app.
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
/// (`docs/celaut/ui.md`, section 1). The stopped instance stays in the list of this
/// run ([ConversationNotes.markStopped]). Gives the answer of the node, or null if
/// nothing was stopped; the user has been told why.
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
    (notes ?? conversationNotes).markStopped(instance, done.refundMu);
    messenger.showSnackBar(SnackBar(content: Text(l.chatStopped(muOrUnknown(done.refundMu)))));
    return done;
  } on CelautError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(CelautStrings.errorText(e.kind))));
    return null;
  }
}

/// Take [instance] out of the list. A stopped instance only leaves the notes of this
/// run. An instance that the database still has is forgotten after the user confirms
/// it: the app loses its token, and cannot stop it later. Gives true if it left the
/// list.
Future<bool> confirmAndRemoveInstance(
  BuildContext context,
  InstanceListView instance, {
  required bool stopped,
  void Function(String instanceId)? forget,
  ConversationNotes? notes,
}) async {
  final memory = notes ?? conversationNotes;
  if (stopped) {
    memory.remove(instance.instanceId);
    return true;
  }
  final l = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('forget-confirm'),
      title: Text(l.chatsForgetTitle(instanceTitle(instance))),
      content: Text(l.chatsForgetBody),
      actions: [
        TextButton(
          key: const Key('forget-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.celautSendCancel),
        ),
        FilledButton(
          key: const Key('forget-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.chatsRemove),
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
  memory.remove(instance.instanceId);
  return true;
}
