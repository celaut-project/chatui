import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../widgets/soft_card.dart';

/// The compute home (`docs/celaut/ui.md`, section 2), behind a developer setting. In
/// order: the compute that the nodes of the app offer, the money for compute, and the
/// running instances with their cost so far and a stop action. The ERG of each wallet
/// is one level down, in the wallets list.
///
/// The layout is plain on purpose: the design (section 4 of ui.md) is not decided. It
/// shows no USD value, and a sum with an unknown part is "unknown".
class ComputeHomeScreen extends StatefulWidget {
  const ComputeHomeScreen({
    super.key,
    required this.walletsTotalNano,
    required this.hasFullWallet,
    required this.onWallets,
    this.onSettings,
    this.load,
    this.stop,
  });

  /// The ERG in all the wallets of the app, in nanoERG; null if a balance is unknown.
  final int? walletsTotalNano;

  /// True if the app has a full wallet: only then can it stop an instance.
  final bool hasFullWallet;

  /// Open the wallets list (the second level).
  final VoidCallback onWallets;
  final VoidCallback? onSettings;

  /// The data of the overview. Tests give their own.
  final Future<ComputeOverviewView> Function()? load;

  /// Stop an instance. Tests give their own.
  final Future<StopView> Function(String instanceId)? stop;

  @override
  State<ComputeHomeScreen> createState() => _ComputeHomeScreenState();
}

class _ComputeHomeScreenState extends State<ComputeHomeScreen> {
  ComputeOverviewView? _data;
  bool _loading = false;
  String? _stopping;
  String? _note;
  CelautError? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.load ?? celautComputeOverview)();
      if (mounted) setState(() => _data = data);
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop(RunningInstanceView i) async {
    setState(() {
      _stopping = i.instanceId;
      _note = null;
      _error = null;
    });
    try {
      final stop = widget.stop ?? (id) => celautStopService(instanceId: id);
      final done = await stop(i.instanceId);
      if (mounted)
        setState(() => _note = context.l10n.celautHomeStopped(muOrUnknown(done.refundMu)));
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _stopping = null);
    }
    await _refresh();
  }

  String _cores(CoresTotalView t) =>
      t.total == null ? context.l10n.celautUnknown : CelautStrings.cores(t.total!);

  String _bytes(BytesTotalView t) =>
      t.total == null ? context.l10n.celautUnknown : CelautStrings.bytes(t.total!);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Celaut'),
        actions: [
          IconButton(
            key: const Key('compute-home-refresh'),
            tooltip: l.celautHomeRefresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onSettings != null)
            IconButton(
              tooltip: l.commonSettings,
              onPressed: widget.onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          if (_loading && data == null)
            SoftCard(child: Text(l.celautHomeLoading, key: const Key('compute-home-loading'))),
          if (_error != null)
            SoftCard(
              child: Text(
                '${CelautStrings.errorText(_error!.kind)}\n${_error!.message}',
                key: const Key('compute-home-error'),
                style: TextStyle(color: rustFor(context)),
              ),
            ),
          if (_note != null) SoftCard(child: Text(_note!, key: const Key('compute-home-note'))),
          if (data != null) ..._sections(context, data),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('compute-home-wallets'),
            onPressed: widget.onWallets,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text(l.celautHomeWallets),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context, ComputeOverviewView d) {
    final l = context.l10n;
    final muted = ArgusColors.of(context).muted;
    final noNodes = d.nodes.isEmpty;
    return [
      // 1. Available compute.
      SectionLabel(l.celautHomeComputeTitle),
      const SizedBox(height: 10),
      SoftCard(
        child: Column(
          key: const Key('compute-home-offered'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: noNodes
              ? [Text(l.celautHomeNoNodes, style: TextStyle(color: muted))]
              : [
                  Text(
                    l.celautHomeNodes('${d.nodesCounted}', '${d.nodesUnreachable}'),
                    key: const Key('compute-home-nodes'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${CelautStrings.cpuLabel}: ${_cores(d.cpuCores)}',
                    key: const Key('compute-home-cpu'),
                  ),
                  Text(
                    '${CelautStrings.memoryLabel}: ${_bytes(d.memBytes)}',
                    key: const Key('compute-home-memory'),
                  ),
                  Text(
                    '${CelautStrings.diskLabel}: ${_bytes(d.diskBytes)}',
                    key: const Key('compute-home-disk'),
                  ),
                  const SizedBox(height: 6),
                  Text(l.celautHomeOfferedNote, style: TextStyle(fontSize: 12, color: muted)),
                ],
        ),
      ),
      const SizedBox(height: 24),
      // 2. Money for compute.
      SectionLabel(l.celautHomeMoneyTitle),
      const SizedBox(height: 10),
      SoftCard(
        child: Column(
          key: const Key('compute-home-money'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.celautHomeWalletsTotal(ergOrUnknown(widget.walletsTotalNano)),
              key: const Key('compute-home-wallets-total'),
            ),
            Text(
              l.celautHomeCredit(ergTextOrUnknown(d.creditNanoErg.total)),
              key: const Key('compute-home-credit'),
            ),
            for (final n in d.nodes)
              Text(
                l.celautHomeCreditNode(
                  shorten(n.peerId, head: 8, tail: 6),
                  muOrUnknown(n.creditMu),
                  muOrUnknown(n.muPerNanoErg),
                  ergTextOrUnknown(n.creditNanoErg),
                ),
                key: Key('compute-home-credit-${n.peerId}'),
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      // 3. Running instances.
      SectionLabel(l.celautHomeInstancesTitle),
      const SizedBox(height: 10),
      if (d.instances.isEmpty)
        SoftCard(
          child: Text(l.celautHomeNoInstances, style: TextStyle(color: muted)),
        ),
      if (d.instances.isNotEmpty && !widget.hasFullWallet)
        SoftCard(
          child: Text(
            l.celautNoFullWallet,
            key: const Key('compute-home-no-full-wallet'),
            style: TextStyle(color: rustFor(context)),
          ),
        ),
      for (final i in d.instances)
        SoftCard(
          child: Column(
            key: Key('compute-home-instance-${i.instanceId}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${shorten(i.serviceId, head: 8, tail: 6)} · '
                '${shorten(i.peerId, head: 8, tail: 6)}',
              ),
              Text(
                l.celautHomeCostSoFar(
                  muOrUnknown(i.costSoFarMu),
                  ergTextOrUnknown(i.costSoFarNanoErg),
                ),
                key: Key('compute-home-cost-${i.instanceId}'),
              ),
              const SizedBox(height: 6),
              FilledButton(
                key: Key('compute-home-stop-${i.instanceId}'),
                onPressed: !widget.hasFullWallet || _stopping != null ? null : () => _stop(i),
                child: Text(l.celautHomeStop),
              ),
            ],
          ),
        ),
    ];
  }
}
