import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/host_port.dart';
import '../../celaut/node_health_monitor.dart';
import '../../celaut/overview_cache.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../scan_screen.dart';
import '../settings/settings_shared.dart';
import '../widgets/soft_card.dart';
import 'client_unknown_dialog.dart';
import 'node_status.dart';

/// What the node list screen needs. The app uses [AppKnownNodes]; tests give their own.
abstract class KnownNodes {
  List<KnownNodeView> list();
  Future<KnownNodeView> add(NodeAddress node);
  void remove(String peerId);
}

class AppKnownNodes implements KnownNodes {
  const AppKnownNodes();

  @override
  List<KnownNodeView> list() => celautKnownNodes();

  @override
  Future<KnownNodeView> add(NodeAddress node) => celautAddNode(node: node);

  @override
  void remove(String peerId) => celautRemoveNode(peerId: peerId);
}

/// The node list of the app (`docs/celaut/ui.md`, section 4): add a node by its address
/// or by a QR code (`docs/celaut/wire.md`, section 6), remove a node. Only these nodes are in the sums of the home screen. A removed node
/// keeps its client id and its deposits in the database, so adding it again restores
/// them.
class KnownNodesScreen extends StatefulWidget {
  const KnownNodesScreen({
    super.key,
    this.nodes = const AppKnownNodes(),
    this.newClient,
    this.scan,
    this.healthMonitor,
  });

  /// Keeps the availability of the nodes up to date while this screen is open. Tests give
  /// their own; without one the screen makes its own and stops it when it closes.
  final NodeHealthMonitor? healthMonitor;

  final KnownNodes nodes;

  /// Read a QR code: the text, or null when the user goes back. The app opens the
  /// camera ([ScanScreen]); tests give their own.
  final Future<String?> Function(BuildContext context)? scan;

  /// Make a new client on a node that forgot the client id. Tests give their own.
  final Future<NewClientView> Function(NodeAddress node)? newClient;

  @override
  State<KnownNodesScreen> createState() => _KnownNodesScreenState();
}

class _KnownNodesScreenState extends State<KnownNodesScreen> {
  final _addressCtrl = TextEditingController();
  late List<KnownNodeView> _list = widget.nodes.list();
  late final NodeHealthMonitor _health = widget.healthMonitor ?? NodeHealthMonitor();

  @override
  void initState() {
    super.initState();
    _health.addListener(_onHealth);
    _health.start();
  }

  void _onHealth() {
    if (mounted) setState(() {});
  }

  /// What the last overview of the home screen says of a node: its credit, and whether it
  /// forgot the client of the app.
  NodeComputeView? _computed(String peerId) {
    for (final n in overviewCache.value?.nodes ?? const <NodeComputeView>[]) {
      if (n.peerId == peerId) return n;
    }
    return null;
  }

  Future<void> _clientUnknown(KnownNodeView n) async {
    if (n.addresses.isEmpty) return;
    final parsed = parseHostPort(n.addresses.first).value;
    if (parsed == null) return;
    await showClientUnknownChoice(
      context,
      node: NodeAddress(host: parsed.host, port: parsed.port),
      error: _computed(n.peerId)?.error ?? '',
      newClient: widget.newClient,
    );
  }
  String? _addressError;
  bool _adding = false;
  String? _note;
  CelautError? _error;

  @override
  void dispose() {
    _health.removeListener(_onHealth);
    if (widget.healthMonitor == null) {
      _health.dispose();
    } else {
      _health.stop();
    }
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final parsed = parseHostPort(_addressCtrl.text);
    if (parsed.value == null) {
      setState(
        () => _addressError = switch (parsed.error) {
          HostPortError.empty => CelautStrings.addressEmpty,
          HostPortError.port => CelautStrings.portInvalid,
          _ => CelautStrings.addressInvalid,
        },
      );
      return;
    }
    final node = NodeAddress(host: parsed.value!.host, port: parsed.value!.port);
    setState(() {
      _addressError = null;
      _adding = true;
      _error = null;
      _note = null;
    });
    try {
      await widget.nodes.add(node);
      if (!mounted) return;
      setState(() {
        _list = widget.nodes.list();
        _note = context.l10n.celautNodesAdded;
        _addressCtrl.clear();
      });
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
      if (mounted && e.kind == CelautErrorKind.clientUnknown) {
        final choice = await showClientUnknownChoice(
          context,
          node: node,
          error: e.message,
          newClient: widget.newClient,
        );
        if (choice == ClientUnknownChoice.newClient && mounted) {
          setState(() => _adding = false);
          await _add();
          return;
        }
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// A scanned address goes into the field and then through [_add], the same check as
  /// a typed address. Text that is not a node address shows the error of a bad typed
  /// address and stores nothing.
  Future<void> _scan() async {
    final scan = widget.scan ??
        (context) => Navigator.push<String>(context, fadeRoute(const ScanScreen()));
    final raw = await scan(context);
    if (!mounted || raw == null) return;
    final parsed = parseNodeQr(raw);
    if (parsed.value == null) {
      setState(() {
        _addressError = parsed.error == HostPortError.port
            ? CelautStrings.portInvalid
            : CelautStrings.addressInvalid;
        _note = null;
        _error = null;
      });
      return;
    }
    _addressCtrl.text = parsed.value.toString();
    await _add();
  }

  void _remove(KnownNodeView n) {
    try {
      widget.nodes.remove(n.peerId);
      setState(() {
        _list = widget.nodes.list();
        _note = context.l10n.celautNodesRemoved;
        _error = null;
      });
    } on CelautError catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final muted = ArgusColors.of(context).muted;
    return SettingsPage(
      title: l.celautNodesTitle,
      children: [
        SettingsNote(l.celautNodesIntro),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('nodes-address'),
                controller: _addressCtrl,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: CelautStrings.addressLabel,
                  hintText: CelautStrings.addressHint,
                  errorText: _addressError,
                  suffixIcon: IconButton(
                    key: const Key('nodes-scan'),
                    tooltip: l.celautNodesScan,
                    onPressed: _adding ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
                onSubmitted: (_) => _adding ? null : _add(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('nodes-add'),
                onPressed: _adding ? null : _add,
                child: Text(_adding ? CelautStrings.connecting : l.celautNodesAdd),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_note != null) SoftCard(child: Text(_note!, key: const Key('nodes-note'))),
        if (_error != null)
          SoftCard(
            child: Text(
              '${CelautStrings.errorText(_error!.kind)}\n${_error!.message}',
              key: const Key('nodes-error'),
              style: TextStyle(color: rustFor(context)),
            ),
          ),
        const SizedBox(height: 8),
        if (_list.isEmpty)
          SoftCard(child: Text(l.celautNodesEmpty, style: TextStyle(color: muted))),
        if (_list.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('nodes-check-now'),
              onPressed: _health.checking ? null : _health.checkNow,
              child: Text(_health.checking ? l.celautNodeChecking : l.celautNodesCheckNow),
            ),
          ),
        for (final n in _list)
          SoftCard(
            child: Row(
              key: Key('nodes-row-${n.peerId}'),
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shorten(n.peerId, head: 10, tail: 8)),
                      Text(
                        n.addresses.isEmpty ? l.celautUnknown : n.addresses.join(', '),
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                      Text(
                        l.celautNodesDeposited(formatErg(n.depositedNanoErg.toInt())),
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                      if (_computed(n.peerId) case final c?)
                        Text(
                          l.celautNodeCredit(muOrUnknown(c.creditMu)),
                          key: Key('nodes-credit-${n.peerId}'),
                          style: TextStyle(fontSize: 12.5, color: muted),
                        ),
                      ...nodeStatusLines(
                        context,
                        peerId: n.peerId,
                        health: _health.of(n.peerId),
                        checking: _health.checking,
                      ),
                      if (_computed(n.peerId)?.clientUnknown ?? false) ...[
                        Text(
                          CelautStrings.errorText(CelautErrorKind.clientUnknown),
                          style: TextStyle(fontSize: 12.5, color: rustFor(context)),
                        ),
                        TextButton(
                          key: Key('nodes-client-unknown-${n.peerId}'),
                          onPressed: () => _clientUnknown(n),
                          child: Text(l.celautHomeClientUnknownAction),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: Key('nodes-remove-${n.peerId}'),
                  onPressed: () => _remove(n),
                  child: Text(l.celautNodesRemove),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
