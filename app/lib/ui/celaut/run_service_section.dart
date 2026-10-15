import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_catalog.dart';
import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/launcher.dart';
import '../../celaut/payers.dart';
import '../../celaut/service_strings.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';
import 'chat_screen.dart';
import 'client_unknown_dialog.dart';
import 'deposit_screen.dart';
import 'launch_failure_sheet.dart';
import 'skill_services_sheet.dart';

/// Start a service: the ids and the settings go to the launcher.
typedef LaunchCall = Future<LaunchOutcome> Function({
  required String serviceIdHex,
  String? initialMu,
});

/// "Run a service" on the home screen (`docs/celaut/ui.md`, section 2): the skills of the
/// catalog with a search field. A skill opens a sheet with its ranked services. Run starts
/// the best node by the balancer (`launchService`). If the service has a chat slot, the
/// conversation opens; if not, the instance shows in the list of the home screen.
/// If no node starts it, a sheet says why for each node.
class RunServiceSection extends StatefulWidget {
  const RunServiceSection({
    super.key,
    this.wallets = const AppFullWallets(),
    this.onChanged,
    this.newClient,
    this.loadSkills,
    this.loadServices,
    this.previewQuote,
    this.launch,
    this.openTunnel,
    this.chatBuilder,
    this.openDeposit,
  });

  /// The full wallets: Run needs one that is open. Tests give their own.
  final FullWallets wallets;

  /// Called when an instance started, so that the home screen loads its data again.
  final VoidCallback? onChanged;

  /// Make a new client on a node that forgot the client id. Tests give their own.
  final Future<NewClientView> Function(NodeAddress node)? newClient;

  /// The skills of the catalog. Tests give their own.
  final Future<List<SkillView>> Function()? loadSkills;

  /// The ranked services of a skill. Tests give their own.
  final Future<List<SkillServiceView>> Function(String skillBoxId)? loadServices;

  /// The best quote of a service on the nodes of the list. Tests give their own.
  final Future<QuoteView?> Function(String serviceId)? previewQuote;

  /// Start the service. Tests give their own.
  final LaunchCall? launch;

  /// A local port for a slot of an instance. Tests give their own.
  final Future<int> Function(String instanceId, int slot)? openTunnel;

  /// The conversation screen. Tests give their own.
  final Widget Function(String instanceId, int port)? chatBuilder;

  /// Open the deposit screen. Tests give their own.
  final VoidCallback? openDeposit;

  @override
  State<RunServiceSection> createState() => _RunServiceSectionState();
}

class _RunServiceSectionState extends State<RunServiceSection> {
  final _search = TextEditingController();
  List<SkillView>? _skills;
  bool _loading = true;
  bool _failed = false;
  bool _running = false;

  /// The most skills shown at once: the search narrows the list.
  static const _shown = 6;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final skills = await (widget.loadSkills ?? celautSkills)();
      if (mounted) setState(() => _skills = skills);
    } catch (_) {
      // Any failure, also one that is not a Celaut error: the section shows the retry.
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<SkillServiceView>> _services(String skillBoxId) =>
      (widget.loadServices ?? (id) => celautSkillServices(skillBoxId: id))(skillBoxId);

  Future<QuoteView?> _preview(String serviceId) async {
    final custom = widget.previewQuote;
    if (custom != null) return custom(serviceId);
    final nodes = knownNodeAddresses(celautKnownNodes());
    if (nodes.isEmpty) return null;
    final quotes = await celautQuoteService(
      nodes: nodes,
      serviceIdHex: serviceId,
      initialMu: ServiceStrings.initialDefault,
    );
    return quotes.quotes.isEmpty ? null : quotes.quotes.first;
  }

  Future<void> _open(SkillView skill) async {
    final serviceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SkillServicesSheet(
        skill: skill,
        loadServices: _services,
        previewQuote: _preview,
        wallets: widget.wallets,
      ),
    );
    if (serviceId != null && mounted) await _run(serviceId);
  }

  Future<void> _run(String serviceId) async {
    if (!await ensureOpenFullWallet(context, widget.wallets) || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.celautOpenFullWalletNeeded)),
        );
      }
      return;
    }
    setState(() => _running = true);
    try {
      final launch = widget.launch ??
          ({required serviceIdHex, initialMu}) =>
              launchService(serviceIdHex: serviceIdHex, initialMu: initialMu);
      final outcome = await launch(
        serviceIdHex: serviceId,
        initialMu: ServiceStrings.initialDefault,
      );
      if (!mounted) return;
      // The progress bar stops before the next screen or sheet, which can stay open.
      setState(() => _running = false);
      await _started(outcome);
    } on LaunchFailure catch (failure) {
      if (!mounted) return;
      setState(() => _running = false);
      await _showFailure(failure);
    } on CelautError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(CelautStrings.errorText(e.kind))),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _started(LaunchOutcome outcome) async {
    final instance = outcome.instance;
    widget.onChanged?.call();
    if (instance.chatSlots.isNotEmpty) {
      final slot = instance.chatSlots.first;
      try {
        final port = await (widget.openTunnel ??
            (id, s) => celautOpenTunnel(instanceId: id, slot: s))(instance.instanceId, slot);
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                (widget.chatBuilder ?? _defaultChat)(instance.instanceId, port),
          ),
        );
        // The user may have stopped the instance in the conversation.
        widget.onChanged?.call();
        return;
      } on CelautError catch (e) {
        // No conversation: the instance runs, so the home screen shows it.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(CelautStrings.errorText(e.kind))),
          );
        }
        return;
      }
    }
    final quote = outcome.quote;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.celautRunStarted(
            '${quote.address.host}:${quote.address.port}',
            muOrUnknown(quote.costMu),
          ),
        ),
      ),
    );
  }

  Widget _defaultChat(String instanceId, int port) =>
      ChatScreen(instanceId: instanceId, port: port, wallets: widget.wallets);

  Future<void> _showFailure(LaunchFailure failure) async {
    await showLaunchFailureSheet(
      context,
      failure,
      onDeposit: widget.openDeposit ??
          () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DepositScreen()),
          ),
    );
    // A node that forgot the client id: the user chooses. The app never makes a new
    // client by itself.
    final forgot = failure.clientUnknown;
    if (forgot.isNotEmpty && mounted) {
      await showClientUnknownChoice(
        context,
        node: forgot.first.quote.address,
        error: forgot.first.error.message,
        newClient: widget.newClient,
      );
    }
  }

  List<SkillView> _filtered() {
    final query = _search.text.trim().toLowerCase();
    final all = _skills ?? const <SkillView>[];
    final found = query.isEmpty
        ? all
        : [
            for (final s in all)
              if (s.name.toLowerCase().contains(query)) s,
          ];
    return found.take(_shown).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final skills = _filtered();
    return Padding(
      key: const Key('run-section'),
      padding: const EdgeInsets.symmetric(horizontal: homeGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.celautRunTitle.toUpperCase(), style: t.label),
          const SizedBox(height: 10),
          TextField(
            key: const Key('run-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: l.celautRunSearchHint,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            Text(l.celautRunLoading, key: const Key('run-loading'), style: t.secondary)
          else if (_failed) ...[
            Text(l.celautRunCatalogError, key: const Key('run-error'), style: t.secondary),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const Key('run-retry'),
                onPressed: _read,
                child: Text(l.celautRunRetry),
              ),
            ),
          ] else if (skills.isEmpty)
            Text(l.celautRunEmpty, key: const Key('run-empty'), style: t.secondary)
          else
            for (final skill in skills)
              InkWell(
                key: Key('run-skill-${skill.boxId}'),
                onTap: _running ? null : () => _open(skill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(skill.name, style: t.primary),
                            if (skill.prose.isNotEmpty)
                              Text(
                                skill.prose,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.secondary,
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: t.muted),
                    ],
                  ),
                ),
              ),
          if (_running) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(key: Key('run-progress')),
            const SizedBox(height: 4),
            Text(l.celautRunStarting, style: t.secondary),
          ],
        ],
      ),
    );
  }
}
