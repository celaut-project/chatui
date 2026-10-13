import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/host_port.dart';
import '../../celaut/payers.dart';
import '../../celaut/wallet_money.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../home/home_scene.dart';
import '../home/home_style.dart';
import 'client_unknown_dialog.dart';

/// The home screen of the app (`docs/celaut/ui.md`, section 2), in the look of the
/// Celaut landing page: the palette, Playfair Display for the figure and the headings,
/// Lato for the rest, spaced capitals for the labels, hairlines between the parts.
///
/// In order of importance:
/// 1. the compute that the nodes of the node list offer;
/// 2. the money for compute: the ERG of the full wallets and of the watched wallets as
///    two figures, the paid credit and the free credit on the nodes, each with its USD
///    value from the oracle pool price;
/// 3. the running instances, with their cost so far and a stop action.
///
/// The ERG of each wallet is one level down, in the wallets list.
class ComputeHomeScreen extends StatefulWidget {
  const ComputeHomeScreen({
    super.key,
    required this.money,
    required this.usdPerErg,
    required this.onWallets,
    this.onNodes,
    this.onSettings,
    this.wallets = const AppFullWallets(),
    this.load,
    this.stop,
    this.newClient,
    this.refreshPrice,
  });

  /// Ask the oracle pool price again (it is cached for some minutes).
  final Future<void> Function()? refreshPrice;

  /// The ERG of the full wallets and of the watched wallets, and the wallet gate.
  final WalletMoney money;

  /// The USD price of one ERG from the oracle pool; null if it is not known.
  final double? usdPerErg;

  /// Open the wallets list (the second level).
  final VoidCallback onWallets;

  /// Open the node list.
  final VoidCallback? onNodes;
  final VoidCallback? onSettings;

  /// The full wallets, to open one before a stop. Tests give their own.
  final FullWallets wallets;

  /// The data of the overview. Tests give their own.
  final Future<ComputeOverviewView> Function()? load;

  /// Stop an instance. Tests give their own.
  final Future<StopView> Function(String instanceId)? stop;

  /// Make a new client on a node that forgot the client id. Tests give their own.
  final Future<NewClientView> Function(NodeAddress node)? newClient;

  @override
  State<ComputeHomeScreen> createState() => ComputeHomeScreenState();
}

class ComputeHomeScreenState extends State<ComputeHomeScreen> {
  ComputeOverviewView? _data;
  bool _loading = false;
  String? _stopping;
  String? _note;
  CelautError? _error;

  /// A failure that is not a Celaut error (for example, the bridge is not ready).
  String? _failure;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Ask the nodes again.
  Future<void> refresh() async {
    widget.refreshPrice?.call().ignore();
    setState(() {
      _loading = true;
      _error = null;
      _failure = null;
    });
    try {
      final data = await (widget.load ?? celautComputeOverview)();
      if (mounted) setState(() => _data = data);
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _failure = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop(RunningInstanceView i) async {
    if (!await ensureOpenFullWallet(context, widget.wallets) || !mounted) return;
    setState(() {
      _stopping = i.instanceId;
      _note = null;
      _error = null;
    });
    try {
      final stop = widget.stop ?? (id) => celautStopService(instanceId: id);
      final done = await stop(i.instanceId);
      if (mounted) {
        setState(() => _note = context.l10n.celautHomeStopped(muOrUnknown(done.refundMu)));
      }
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _stopping = null);
    }
    await refresh();
  }

  Future<void> _clientUnknown(NodeComputeView n) async {
    final parsed = parseHostPort(n.address).value;
    if (parsed == null) return;
    final choice = await showClientUnknownChoice(
      context,
      node: NodeAddress(host: parsed.host, port: parsed.port),
      error: n.error ?? '',
      newClient: widget.newClient,
    );
    if (choice == ClientUnknownChoice.newClient && mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final page = Theme.of(context).scaffoldBackgroundColor;
    final data = _data;
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? page.withValues(alpha: 0.94)
              : page.withValues(alpha: 0),
        ),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
        titleSpacing: homeGutter,
        title: Semantics(
          header: true,
          label: 'Celaut',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CellMark(size: 40),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CelautWordmark(size: 24),
                    Text(
                      l.celautHomeTagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.secondary.copyWith(fontSize: 14, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const Key('compute-home-refresh'),
            tooltip: l.celautHomeRefresh,
            onPressed: _loading ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onSettings != null)
            IconButton(
              key: const Key('compute-home-settings'),
              tooltip: l.commonSettings,
              onPressed: widget.onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, 8, 0, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            if (_loading && data == null)
              _Pad(
                child: Text(
                  l.celautHomeLoading,
                  key: const Key('compute-home-loading'),
                  style: t.secondary,
                ),
              ),
            if (_error != null)
              _Pad(
                child: Text(
                  '${CelautStrings.errorText(_error!.kind)}\n${_error!.message}',
                  key: const Key('compute-home-error'),
                  style: t.secondary.copyWith(color: rustFor(context)),
                ),
              ),
            if (_failure != null)
              _Pad(
                child: Text(
                  _failure!,
                  key: const Key('compute-home-failure'),
                  style: t.secondary.copyWith(color: rustFor(context)),
                ),
              ),
            if (_note != null)
              _Pad(child: Text(_note!, key: const Key('compute-home-note'), style: t.secondary)),
            ..._compute(context, data),
            const SizedBox(height: 28),
            const HomeRule(),
            const SizedBox(height: 24),
            ..._money(context, data),
            const SizedBox(height: 28),
            const HomeRule(),
            const SizedBox(height: 24),
            ..._instances(context, data),
            const SizedBox(height: 32),
            _Pad(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('compute-home-wallets'),
                      onPressed: widget.onWallets,
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(l.celautHomeWallets),
                    ),
                  ),
                  if (widget.onNodes != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('compute-home-nodes-button'),
                        onPressed: widget.onNodes,
                        icon: const Icon(Icons.hub_outlined),
                        label: Text(l.celautHomeNodesButton),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final top = MediaQuery.paddingOf(context).top + 72;
    return ColoredBox(
      color: page,
      child: HomeScene(
        light: SceneLight.eclipse,
        lightAt: Offset(96, top + 66),
        lightRadius: 80,
        height: top + 460,
        child: scaffold,
      ),
    );
  }

  /// 1. The compute that the nodes of the node list offer.
  List<Widget> _compute(BuildContext context, ComputeOverviewView? d) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final figure = TextStyle(
      fontFamily: headingFont,
      fontWeight: FontWeight.w500,
      fontSize: 46,
      height: 1.08,
      letterSpacing: -1,
      color: t.ink,
      fontFeatures: const [FontFeature.liningFigures()],
    );
    final children = <Widget>[
      _Pad(child: Text(l.celautHomeComputeTitle.toUpperCase(), style: t.label)),
      const SizedBox(height: 10),
    ];
    if (d == null) return children;
    if (d.nodes.isEmpty) {
      return [
        ...children,
        _Pad(
          child: Text(l.celautHomeNoNodes, key: const Key('compute-home-empty'), style: t.primary),
        ),
      ];
    }
    final cores = d.cpuCores;
    final coresText = partialSum<double>(
      total: cores.total,
      known: cores.known,
      unknownNodes: cores.unknownNodes,
      atLeast: cores.atLeast,
      format: CelautStrings.cores,
    );
    return [
      ...children,
      _Pad(
        child: Text(
          coresText,
          key: const Key('compute-home-cpu'),
          style: cores.total == null ? figure.copyWith(fontSize: 28, height: 1.2) : figure,
        ),
      ),
      const SizedBox(height: 14),
      _Pad(
        child: Wrap(
          spacing: 28,
          runSpacing: 10,
          children: [
            _Stat(
              key: const Key('compute-home-memory'),
              label: CelautStrings.memoryLabel,
              value: _bytes(d.memBytes),
            ),
            _Stat(
              key: const Key('compute-home-disk'),
              label: CelautStrings.diskLabel,
              value: _bytes(d.diskBytes),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Pad(
        child: Text(
          l.celautHomeNodes('${d.nodesCounted}', '${d.nodesUnreachable}'),
          key: const Key('compute-home-nodes'),
          style: t.primary,
        ),
      ),
      const SizedBox(height: 4),
      _Pad(child: Text(l.celautHomeOfferedNote, style: t.secondary)),
    ];
  }

  String _bytes(BytesTotalView b) => partialSum<int>(
    total: b.total,
    known: b.known,
    unknownNodes: b.unknownNodes,
    atLeast: b.atLeast,
    format: CelautStrings.bytes,
  );

  String _erg(NanoErgTotalView v) => partialSum<String>(
    total: v.total,
    known: v.known,
    unknownNodes: v.unknownNodes,
    atLeast: v.atLeast,
    format: ergTextOrUnknown,
  );

  /// 2. The money for compute.
  List<Widget> _money(BuildContext context, ComputeOverviewView? d) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final usd = widget.usdPerErg;
    final money = widget.money;
    return [
      _Pad(child: Text(l.celautHomeMoneyTitle.toUpperCase(), style: t.label)),
      const SizedBox(height: 6),
      _MoneyRow(
        key: const Key('compute-home-full'),
        title: l.celautHomeFullWallets,
        value: money.full.text,
        usd: usdTextOf(money.full.exactNano, usd),
      ),
      _MoneyRow(
        key: const Key('compute-home-watched'),
        title: l.celautHomeWatched,
        value: money.watched.text,
        usd: usdTextOf(money.watched.exactNano, usd),
      ),
      if (d != null && d.nodes.isNotEmpty) ...[
        _MoneyRow(
          key: const Key('compute-home-paid'),
          title: l.celautHomePaidCredit,
          value: _erg(d.paidNanoErg),
          usd: usdTextOf(nanoOf(d.paidNanoErg.total), usd),
        ),
        _MoneyRow(
          key: const Key('compute-home-free'),
          title: l.celautHomeFreeCredit,
          value: _erg(d.freeNanoErg),
          usd: usdTextOf(nanoOf(d.freeNanoErg.total), usd),
        ),
        const SizedBox(height: 8),
        for (final n in d.nodes) _node(context, n),
      ],
      const SizedBox(height: 10),
      _Pad(
        child: Text(
          l.celautHomeUsdSource,
          key: const Key('compute-home-usd-source'),
          style: t.secondary,
        ),
      ),
    ];
  }

  Widget _node(BuildContext context, NodeComputeView n) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final String detail;
    if (n.reachable) {
      detail = l.celautHomeNodeCredit(
        muOrUnknown(n.paidMu),
        muOrUnknown(n.freeMu),
        n.muPerNanoErg ?? l.celautUnknown,
      );
    } else {
      detail = l.celautHomeNodeUnreachable;
    }
    return _Pad(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          key: Key('compute-home-credit-${n.peerId}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${shorten(n.peerId, head: 8, tail: 6)} · ${n.address}',
                    style: t.primary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(muOrUnknown(n.creditMu), style: t.primary),
              ],
            ),
            Text(detail, style: t.secondary),
            if (n.clientUnknown) ...[
              Text(
                CelautStrings.errorText(CelautErrorKind.clientUnknown),
                style: t.secondary.copyWith(color: rustFor(context)),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: Key('compute-home-client-unknown-${n.peerId}'),
                  onPressed: () => _clientUnknown(n),
                  child: Text(l.celautHomeClientUnknownAction, style: t.link),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 3. The running instances.
  List<Widget> _instances(BuildContext context, ComputeOverviewView? d) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final gate = widget.money.gate;
    final instances = d?.instances ?? const <RunningInstanceView>[];
    return [
      _Pad(child: Text(l.celautHomeInstancesTitle.toUpperCase(), style: t.label)),
      const SizedBox(height: 10),
      if (d != null && instances.isEmpty)
        _Pad(child: Text(l.celautHomeNoInstances, style: t.secondary)),
      if (instances.isNotEmpty && gate == FullWalletGate.none)
        _Pad(
          child: Text(
            l.celautNoFullWallet,
            key: const Key('compute-home-no-full-wallet'),
            style: t.secondary.copyWith(color: rustFor(context)),
          ),
        ),
      if (instances.isNotEmpty && gate == FullWalletGate.locked)
        _Pad(
          child: Text(
            l.celautOpenFullWalletNeeded,
            key: const Key('compute-home-wallet-locked'),
            style: t.secondary.copyWith(color: rustFor(context)),
          ),
        ),
      for (final i in instances)
        _Pad(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              key: Key('compute-home-instance-${i.instanceId}'),
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shorten(i.serviceId, head: 8, tail: 6)} · '
                        '${shorten(i.peerId, head: 8, tail: 6)}',
                        style: t.primary,
                      ),
                      Text(
                        l.celautHomeCostSoFar(
                          muOrUnknown(i.costSoFarMu),
                          ergTextOrUnknown(i.costSoFarNanoErg),
                        ),
                        key: Key('compute-home-cost-${i.instanceId}'),
                        style: t.secondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  key: Key('compute-home-stop-${i.instanceId}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                  onPressed: gate == FullWalletGate.none || _stopping != null
                      ? null
                      : () => _stop(i),
                  child: Text(l.celautHomeStop),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

/// Content at the side margin of the page.
class _Pad extends StatelessWidget {
  const _Pad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: homeGutter),
    child: child,
  );
}

/// A label in spaced capitals over a value.
class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: t.label.copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: t.primary.copyWith(fontSize: 18)),
      ],
    );
  }
}

/// A row of the money: what it is on the left, the ERG and the USD on the right.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({super.key, required this.title, required this.value, required this.usd});

  final String title;
  final String value;
  final String usd;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    return _Pad(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: t.primary)),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, textAlign: TextAlign.end, style: t.primary),
                  Text(usd, textAlign: TextAlign.end, style: t.secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
