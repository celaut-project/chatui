import 'package:flutter/material.dart';

import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/conversations.dart';
import '../../celaut/payers.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../home/home_style.dart';
import 'instance_actions.dart';

/// The page of one instance, as the info page of a chat in a messenger: the service,
/// the node, the chat slot, the cost so far, the start time, and Stop; for a stopped
/// instance, the refund and Delete (`docs/celaut/ui-chat-first.md`). It opens from the title of the conversation, from
/// its ⋮ menu, and from a long press in the list.
class InstanceInfoScreen extends StatefulWidget {
  const InstanceInfoScreen({
    super.key,
    required this.instance,
    required this.state,
    this.costMu,
    this.reason,
    this.wallets = const AppFullWallets(),
    this.stop,
    this.forget,
    this.notes,
  });

  final InstanceListView instance;
  final InstanceState state;

  /// What the instance cost so far, in MU (empty or null if unknown).
  final String? costMu;

  /// Why the node does not report the instance, for [InstanceState.unreachable].
  final String? reason;

  final FullWallets wallets;

  /// Stop the instance. Tests give their own.
  final Future<StopView> Function(String instanceId)? stop;

  /// Delete the stopped instance. Tests give their own.
  final void Function(String instanceId)? forget;

  final ConversationNotes? notes;

  @override
  State<InstanceInfoScreen> createState() => _InstanceInfoScreenState();
}

class _InstanceInfoScreenState extends State<InstanceInfoScreen> {
  bool _stopping = false;

  Future<void> _stop() async {
    setState(() => _stopping = true);
    final done = await confirmAndStopInstance(
      context,
      widget.instance,
      wallets: widget.wallets,
      stop: widget.stop,
      notes: widget.notes,
    );
    if (!mounted) return;
    setState(() => _stopping = false);
    // The caller reads the list again: the instance stopped.
    if (done != null) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final deleted = await confirmAndDeleteInstance(
      context,
      widget.instance,
      forget: widget.forget,
      notes: widget.notes,
    );
    // The caller reads the list again: the instance left it.
    if (deleted && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final i = widget.instance;
    final title = instanceTitle(i);
    final slot = i.chatSlots.isNotEmpty ? i.chatSlots.first : null;
    final started = formatTxTime(i.startedAt.toInt() * 1000);
    final rows = <(String, String, Key)>[
      (l.chatsInfoStatus, instanceStateText(context, widget.state), const Key('info-status')),
      (l.chatsInfoNode, i.address, const Key('info-node')),
      (l.chatsInfoPeer, i.peerId, const Key('info-peer')),
      (l.chatsInfoServiceId, i.serviceId, const Key('info-service')),
      (
        l.chatsInfoSlot,
        slot == null ? l.chatsInfoNoChatSlot : l.chatsInfoChatSlot('$slot'),
        const Key('info-slot'),
      ),
      (l.chatsInfoStarted, started.isEmpty ? l.celautUnknown : started, const Key('info-started')),
      if (widget.state == InstanceState.stopped)
        (l.chatsInfoRefund, muOrUnknown(i.refundMu), const Key('info-refund'))
      else
        (l.chatsInfoCost, muOrUnknown(widget.costMu), const Key('info-cost')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.chatsInfoTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          homeGutter,
          16,
          homeGutter,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              InstanceAvatar(title: title, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  key: const Key('info-name'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final (label, value, key) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: t.label),
                  const SizedBox(height: 2),
                  SelectableText(value, key: key, style: t.primary),
                ],
              ),
            ),
          if (widget.state == InstanceState.unreachable && (widget.reason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.reason!,
                key: const Key('info-reason'),
                style: t.secondary.copyWith(color: rustFor(context)),
              ),
            ),
          if (widget.state != InstanceState.stopped) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('info-stop'),
              onPressed: _stopping ? null : _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(l.chatStop),
            ),
            const SizedBox(height: 8),
            Text(l.chatsInfoStopNote, style: t.secondary),
          ] else ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const Key('info-delete'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(l.chatsDelete),
            ),
            const SizedBox(height: 8),
            Text(l.chatsInfoDeleteNote, style: t.secondary),
          ],
        ],
      ),
    );
  }
}

/// The round mark of a conversation: the first letter of the name of the service, as
/// a messenger shows the initial of a contact without a photo.
class InstanceAvatar extends StatelessWidget {
  const InstanceAvatar({super.key, required this.title, this.size = homeMarkSize + 8});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    final tones = HomeTones.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tones.filled, shape: BoxShape.circle),
        child: Text(
          letter,
          style: TextStyle(
            color: tones.onFilled,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
