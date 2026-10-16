import 'package:flutter/material.dart';

import '../../bridge/api/celaut_health.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/node_health_format.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../home/home_style.dart';

/// The availability lines of one node, from the checks that the core keeps: a coloured dot
/// with the text, never the dot alone; for a node that does not answer, the time of its last
/// answer, the reason in words, and the text of the node, small. Nothing if the core has no
/// state for the node and no check runs.
List<Widget> nodeStatusLines(
  BuildContext context, {
  required String peerId,
  required NodeHealthView? health,
  required bool checking,
  int? now,
}) {
  final l = context.l10n;
  final t = HomeText.of(context);
  final tones = HomeTones.of(context);
  final h = health;
  if (h == null && !checking) return const [];
  final Color dot;
  final String text;
  switch (h?.availability) {
    case null:
      dot = tones.muted;
      text = l.celautNodeChecking;
    case NodeAvailability.unknown:
      dot = tones.muted;
      text = l.celautNodeUnknownState;
    case NodeAvailability.available:
      dot = tones.positive;
      text = l.celautNodeAvailable('${h!.latencyMs ?? '?'}');
    case NodeAvailability.slow:
      dot = rustFor(context);
      text = l.celautNodeSlow('${h!.latencyMs ?? '?'}');
    case NodeAvailability.unreachable:
      dot = tones.negative;
      final at = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final seen = h!.lastOkAt == 0
          ? l.celautNodeNeverSeen
          : l.celautNodeLastSeen(agoText(l, at - h.lastOkAt));
      text = '${l.celautNodeUnreachable} · $seen';
  }
  final shown = h != null && checking ? '$text · ${l.celautNodeChecking}' : text;
  final kind = h?.errorKind;
  final raw = h?.error;
  return [
    Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        key: Key('node-health-$peerId'),
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(shown, style: t.secondary)),
        ],
      ),
    ),
    if (h != null && h.availability == NodeAvailability.unreachable) ...[
      if (kind != null)
        Text(
          CelautStrings.errorText(kind),
          key: Key('node-health-reason-$peerId'),
          style: t.secondary,
        ),
      if (raw != null && raw.isNotEmpty)
        Text(
          CelautStrings.detailLabel(raw),
          key: Key('node-health-detail-$peerId'),
          style: t.secondary.copyWith(fontSize: 12, color: t.muted),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
    ],
  ];
}
