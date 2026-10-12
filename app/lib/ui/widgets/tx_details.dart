import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../services/token_metadata.dart';
import '../../services/wallet_service.dart';
import '../../theme/argus_theme.dart';

/// Everything a transaction will do, for the user who wants to see it
/// before signing: every input, every output by kind, every fee, the data
/// inputs, and the unsigned transaction to copy and check elsewhere.
///
/// Loads from the preparation on first expansion; the preparation is not
/// consumed.
class TxDetailsExpander extends StatefulWidget {
  const TxDetailsExpander({super.key, required this.preparationId});

  final int preparationId;

  @override
  State<TxDetailsExpander> createState() => _TxDetailsExpanderState();
}

class _TxDetailsExpanderState extends State<TxDetailsExpander> {
  late final Future<Map<String, dynamic>> _details =
      walletService.preparationDetails(widget.preparationId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _details,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              context.l10n.txDetailsLoadFailed('${snap.error}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return TxDetailsView(details: snap.data!);
      },
    );
  }
}

/// A human-readable name for an output's kind.
String txOutputKindLabel(String kind) => switch (kind) {
      'recipient' => appL10n.txTo,
      'change' => appL10n.txChange,
      'fee' => appL10n.commonMinerFee,
      _ => kind,
    };

/// Renders the summary JSON from `preparation_details`.
class TxDetailsView extends StatelessWidget {
  const TxDetailsView({super.key, required this.details});

  final Map<String, dynamic> details;

  // Named and scaled by the one token lookup; an amount nothing can scale
  // says it is raw units rather than reading as whole tokens.
  String _tokens(List? tokens) {
    if (tokens == null || tokens.isEmpty) return '';
    final parts = <String>[];
    for (final t in tokens.cast<Map>()) {
      final id = t['id']?.toString() ?? '';
      final amount = (t['amount'] as num?)?.toInt() ?? 0;
      parts.add(tokenAmountText(BigInt.from(amount), id));
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final muted = ArgusColors.of(context).muted;
    final inputs = (details['inputs'] as List? ?? const []).cast<Map>();
    final outputs = (details['outputs'] as List? ?? const []).cast<Map>();
    final dataInputs = (details['data_inputs'] as List? ?? const []).cast<String>();
    final fee = (details['fee_nano_erg'] as num?)?.toInt() ?? 0;
    final txId = details['tx_id']?.toString() ?? '';
    final l = context.l10n;

    Widget line(String label, String value, {String? sub}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: Text(label, style: TextStyle(fontSize: 12, color: muted))),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SelectableText(value, textAlign: TextAlign.end, style: monoStyle(context, size: 11.5)),
                    if (sub != null && sub.isNotEmpty)
                      Text(sub, textAlign: TextAlign.end, style: TextStyle(fontSize: 11, color: muted)),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, color: muted)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(l.txInputsCount('${inputs.length}')),
        for (final i in inputs)
          line(
            i['owned'] == true ? l.txYours : l.txInput,
            i['value_nano_erg'] == null ? l.txValueUnknown : formatErg((i['value_nano_erg'] as num).toInt()),
            sub: [
              shorten(i['address']?.toString() ?? i['box_id']?.toString() ?? '', head: 10, tail: 6),
              _tokens(i['tokens'] as List?),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
        heading(l.txOutputsCount('${outputs.length}')),
        for (final o in outputs)
          line(
            txOutputKindLabel(o['kind']?.toString() ?? ''),
            formatErg((o['value_nano_erg'] as num?)?.toInt() ?? 0),
            sub: [
              if (o['kind'] != 'fee') shorten(o['address']?.toString() ?? '', head: 10, tail: 6),
              _tokens(o['tokens'] as List?),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
        heading(l.txFees),
        line(l.txMiner, formatErg(fee)),
        if (dataInputs.isNotEmpty) ...[
          heading(l.txDataInputsCount('${dataInputs.length}')),
          for (final d in dataInputs) line(l.txBox, shorten(d, head: 10, tail: 6)),
        ],
        if (txId.isNotEmpty) ...[
          heading(l.txIdHeading),
          line(l.txIdLabel, shorten(txId, head: 12, tail: 8)),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('tx-details-copy'),
          onPressed: () {
            final raw = details['unsigned_tx'];
            Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(raw)));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.txUnsignedCopied)),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: Text(l.txCopyUnsigned),
        ),
      ],
    );
  }
}
