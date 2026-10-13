import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/host_port.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../settings/settings_shared.dart';
import '../widgets/soft_card.dart';
import 'client_unknown_dialog.dart';

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

/// The node list of the app (`docs/celaut/ui.md`, section 4): add a node by its address,
/// remove a node. Only these nodes are in the sums of the home screen. A removed node
/// keeps its client id and its deposits in the database, so adding it again restores
/// them.
class KnownNodesScreen extends StatefulWidget {
  const KnownNodesScreen({super.key, this.nodes = const AppKnownNodes(), this.newClient});

  final KnownNodes nodes;

  /// Make a new client on a node that forgot the client id. Tests give their own.
  final Future<NewClientView> Function(NodeAddress node)? newClient;

  @override
  State<KnownNodesScreen> createState() => _KnownNodesScreenState();
}

class _KnownNodesScreenState extends State<KnownNodesScreen> {
  final _addressCtrl = TextEditingController();
  late List<KnownNodeView> _list = widget.nodes.list();
  String? _addressError;
  bool _adding = false;
  String? _note;
  CelautError? _error;

  @override
  void dispose() {
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
