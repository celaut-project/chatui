import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/host_port.dart';
import '../../theme/argus_theme.dart';
import '../settings/settings_shared.dart';
import '../widgets/soft_card.dart';

/// Debug screen of milestone M1: connect to a Celaut node and show its
/// advertisement, after the identity and signature checks.
class NodeConnectScreen extends StatefulWidget {
  const NodeConnectScreen({super.key});

  @override
  State<NodeConnectScreen> createState() => _NodeConnectScreenState();
}

class _NodeConnectScreenState extends State<NodeConnectScreen> {
  final _addressCtrl = TextEditingController();
  final _expectedCtrl = TextEditingController();
  bool _busy = false;
  PeerInfoView? _info;
  CelautErrorKind? _errorKind;
  String? _errorDetail;
  String? _inputError;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _expectedCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final parsed = parseHostPort(_addressCtrl.text);
    final expected = _expectedCtrl.text.trim().toLowerCase();
    String? inputError;
    if (parsed.error == HostPortError.empty) {
      inputError = CelautStrings.addressEmpty;
    } else if (parsed.error == HostPortError.port) {
      inputError = CelautStrings.portInvalid;
    } else if (parsed.error != null) {
      inputError = CelautStrings.addressInvalid;
    } else if (expected.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      inputError = CelautStrings.expectedInvalid;
    }
    if (inputError != null || parsed.value == null) {
      setState(() {
        _inputError = inputError;
        _info = null;
        _errorKind = null;
      });
      return;
    }
    final target = parsed.value!;
    setState(() {
      _busy = true;
      _inputError = null;
      _info = null;
      _errorKind = null;
      _errorDetail = null;
    });
    try {
      // No file for the last advertisements yet: the app keeps them in memory.
      final info = await celautPeerInfo(
        host: target.host,
        port: target.port,
        expectedPeerId: expected.isEmpty ? null : expected,
      );
      if (!mounted) return;
      setState(() => _info = info);
    } on CelautError catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKind = e.kind;
        _errorDetail = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return SettingsPage(
      title: CelautStrings.screenTitle,
      children: [
        const SettingsNote(CelautStrings.intro),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('celaut-address'),
                controller: _addressCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: CelautStrings.addressLabel,
                  hintText: CelautStrings.addressHint,
                  errorText: _inputError,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _busy ? null : _connect(),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('celaut-expected'),
                controller: _expectedCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: CelautStrings.expectedLabel,
                  hintText: CelautStrings.expectedHint,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('celaut-connect'),
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? CelautStrings.connecting : CelautStrings.connect),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_errorKind != null) _ErrorCard(kind: _errorKind!, detail: _errorDetail ?? ''),
        if (info != null) ..._result(context, info),
      ],
    );
  }

  List<Widget> _result(BuildContext context, PeerInfoView info) {
    final colors = ArgusColors.of(context);
    return [
      SectionLabel(CelautStrings.identityTitle),
      const SizedBox(height: 10),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(CelautStrings.peerIdLabel, style: TextStyle(fontSize: 12.5, color: colors.muted)),
            const SizedBox(height: 4),
            SelectableText(
              info.peerId,
              key: const Key('celaut-peer-id'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _labelled(context, CelautStrings.advertisedLabel, formatUtc(info.ts)),
            const SizedBox(height: 6),
            _labelled(context, CelautStrings.proofsLabel, '${info.reputationProofs}'),
            const SizedBox(height: 10),
            Text(CelautStrings.verifiedNote, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SectionLabel(CelautStrings.urisTitle),
      const SizedBox(height: 10),
      _listCard(
        context,
        empty: CelautStrings.noUris,
        rows: [for (final u in info.uris) _uriRow(context, u)],
      ),
      const SizedBox(height: 24),
      SectionLabel(CelautStrings.ratesTitle),
      const SizedBox(height: 10),
      _listCard(
        context,
        empty: CelautStrings.noRates,
        rows: [
          for (final r in info.rates) _pairRow(context, r.key, r.value),
        ],
      ),
      if (info.rates.isNotEmpty) const SettingsNote(CelautStrings.ratesNote),
      if (info.rates.isEmpty) const SizedBox(height: 24),
      SectionLabel(CelautStrings.contractsTitle),
      const SizedBox(height: 10),
      _listCard(
        context,
        empty: CelautStrings.noContracts,
        rows: [for (final c in info.paymentContracts) _contractRow(context, c)],
      ),
      const SizedBox(height: 24),
      SectionLabel(CelautStrings.resourcesTitle),
      const SizedBox(height: 10),
      _listCard(
        context,
        empty: CelautStrings.noResources,
        rows: [for (final r in info.resources) _resourcesRow(context, r)],
      ),
    ];
  }

  Widget _labelled(BuildContext context, String label, String value) {
    final colors = ArgusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ', style: TextStyle(fontSize: 12.5, color: colors.muted)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
      ],
    );
  }

  Widget _listCard(BuildContext context, {required String empty, required List<Widget> rows}) {
    if (rows.isEmpty) {
      return SoftCard(
        child: Text(empty, style: TextStyle(fontSize: 13.5, color: ArgusColors.of(context).muted)),
      );
    }
    return SoftCard(padding: EdgeInsets.zero, child: DividedColumn(indent: 16, children: rows));
  }

  Widget _row(BuildContext context, String title, List<String> lines) {
    final colors = ArgusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          for (final line in lines) ...[
            const SizedBox(height: 3),
            SelectableText(line, style: TextStyle(fontSize: 12.5, color: colors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _pairRow(BuildContext context, String key, String value) {
    final colors = ArgusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(child: Text(key, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 12),
          SelectableText(value, style: TextStyle(fontSize: 14, color: colors.muted)),
        ],
      ),
    );
  }

  Widget _uriRow(BuildContext context, NodeUriView uri) {
    final expiry = uri.expiryUnixTimestamp == 0
        ? CelautStrings.noExpiry
        : CelautStrings.expires(formatUtc(uri.expiryUnixTimestamp));
    final stack = [if (uri.transport.isNotEmpty) uri.transport, ...uri.protocols].join(' · ');
    final host = uri.ip.contains(':') ? '[${uri.ip}]' : uri.ip;
    return _row(context, '$host:${uri.port}', [if (stack.isNotEmpty) stack, expiry]);
  }

  Widget _contractRow(BuildContext context, PaymentContractView c) {
    return _row(context, c.ledger.isEmpty ? '?' : c.ledger, [
      CelautStrings.perUnit(c.muPerUnit),
      for (final d in c.details) '${d.key}: ${d.value}',
    ]);
  }

  Widget _resourcesRow(BuildContext context, NodeResourcesView r) {
    return _row(context, r.architecture.isEmpty ? '?' : r.architecture, [
      if (r.cpuCores != null) '${CelautStrings.cpuLabel}: ${CelautStrings.cores(r.cpuCores!)}',
      if (r.memLimitBytes != null)
        '${CelautStrings.memoryLabel}: ${CelautStrings.bytes(r.memLimitBytes!)}',
      if (r.diskSpaceBytes != null)
        '${CelautStrings.diskLabel}: ${CelautStrings.bytes(r.diskSpaceBytes!)}',
      for (final b in r.benchmark)
        '${CelautStrings.benchmarkLabel} ${b.key}: ${b.value.isEmpty ? '-' : b.value}',
    ]);
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.kind, required this.detail});

  final CelautErrorKind kind;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = ArgusColors.of(context);
    return SoftCard(
      child: Column(
        key: const Key('celaut-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: rustFor(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  CelautStrings.errorTitle,
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: rustFor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(CelautStrings.errorText(kind), style: const TextStyle(fontSize: 14)),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              CelautStrings.detailLabel(detail),
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// `2026-10-12 13:20 UTC` from Unix seconds.
String formatUtc(int seconds) {
  // A node can send any number. DateTime accepts about ±8.64e12 seconds.
  if (seconds.abs() > 8640000000000) return '$seconds';
  final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} UTC';
}
