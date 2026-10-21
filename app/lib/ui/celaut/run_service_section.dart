import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_catalog.dart';
import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/launcher.dart';
import '../../bridge/api/celaut_package.dart';
import '../../celaut/package_channel.dart';
import '../../celaut/package_library.dart';
import '../../celaut/payers.dart';
import '../../celaut/service_strings.dart';
import '../../celaut/service_transfer.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';
import 'chat_screen.dart';
import 'client_unknown_dialog.dart';
import 'deposit_screen.dart';
import 'launch_failure_sheet.dart';
import 'service_transfer_dialog.dart';
import 'skill_services_sheet.dart';

/// Start a service: the ids and the settings go to the launcher.
typedef LaunchCall = Future<LaunchOutcome> Function({
  required String serviceIdHex,
  String? initialMu,
});

/// "Run a service" on the home screen (`docs/celaut/ui.md`, section 2): the skills of the
/// catalog with a search field. A skill opens a sheet with its ranked services. Run starts
/// the best node by the balancer (`launchService`) after the user confirms it, with the
/// best node and its start cost. If the service has a chat slot, the
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
    this.transfer,
    this.packages,
    this.library,
    this.showTitle = true,
  });

  /// Show the title of the section. Off on its own screen, where the app bar has it.
  final bool showTitle;

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

  /// The transfer of a service to a node that does not have it. Tests give their own.
  final ServiceTransfer? transfer;

  /// The file picker and the metered check of Android. Tests give their own.
  final PackageChannel? packages;

  /// The service files that the user loaded into the app. Tests give their own.
  final PackageLibrary? library;

  @override
  State<RunServiceSection> createState() => _RunServiceSectionState();
}

class _RunServiceSectionState extends State<RunServiceSection> {
  final _search = TextEditingController();
  List<SkillView>? _skills;
  bool _loading = true;
  bool _failed = false;
  bool _running = false;
  List<LibraryPackageView> _packages = const [];
  late final PackageLibrary _library = widget.library ?? PackageLibrary();

  @override
  void initState() {
    super.initState();
    _readPackages();
    _read();
  }

  void _readPackages() {
    try {
      _packages = _library.list();
    } catch (_) {
      // The library is not there (no database yet): the section shows no service.
      _packages = const [];
    }
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
    if (serviceId != null && mounted) await _run(serviceId, name: skill.name);
  }

  /// Ask before a launch: an instance uses credit until it stops. The dialog shows the
  /// node that the balancer would use now, with its start cost.
  Future<bool> _confirm(String serviceId, String name) async {
    final l = context.l10n;
    final quote = _preview(serviceId);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = HomeText.of(context);
        return AlertDialog(
          key: const Key('run-confirm'),
          title: Text(l.celautRunConfirmTitle(name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.celautRunConfirmBody),
              const SizedBox(height: 12),
              FutureBuilder<QuoteView?>(
                future: quote,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Text(l.celautRunPreviewLoading, style: t.secondary);
                  }
                  final best = snapshot.hasError ? null : snapshot.data;
                  return Text(
                    best == null
                        ? l.celautRunConfirmNoQuote
                        : l.celautRunPreview(
                            '${best.address.host}:${best.address.port}',
                            muOrUnknown(best.costMu),
                          ),
                    key: const Key('run-confirm-quote'),
                    style: t.secondary,
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('run-confirm-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.celautSendCancel),
            ),
            FilledButton(
              key: const Key('run-confirm-ok'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.celautRunButton),
            ),
          ],
        );
      },
    );
    return sure == true;
  }

  /// Launch [serviceId]. [name] is what the confirmation calls it; with no name the user
  /// has already confirmed (the launch again after a transfer).
  Future<void> _run(String serviceId, {String? name}) async {
    if (name != null && (!await _confirm(serviceId, name) || !mounted)) return;
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
      await _showFailure(failure, serviceId);
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
      ChatScreen(instanceId: instanceId, port: port, wallets: widget.wallets, starting: true);

  Future<void> _showFailure(LaunchFailure failure, String serviceId) async {
    TransferOffer? chosen;
    await showLaunchFailureSheet(
      context,
      failure,
      libraryPath: _library.find(serviceId)?.path,
      onDeposit: widget.openDeposit ??
          () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DepositScreen()),
          ),
      onSendService: (offer) => chosen = offer,
    );
    final offer = chosen;
    if (offer != null && mounted) {
      await _sendService(offer, serviceId);
      return;
    }
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

  /// Pick a `.celaut.bee` file and load it into the library of the app. Gives the loaded
  /// service, or null if the user did not pick a file or the file is refused (the user
  /// has been told).
  Future<LibraryPackageView?> _loadPickedFile() async {
    final packages = widget.packages ?? const AndroidPackageChannel();
    final PickedPackage? picked;
    try {
      picked = await packages.pick();
    } catch (_) {
      return null;
    }
    if (picked == null || !mounted) return null;
    try {
      final loaded = await _library.importPicked(picked);
      if (mounted) setState(_readPackages);
      return loaded;
    } on CelautError catch (e) {
      if (mounted) await _showBadFile(e);
    } on PackageRefused {
      if (mounted) await showTransferFailure(context, const PackageRefused(PackageRefusal.noDirectory));
    }
    return null;
  }

  Future<void> _showBadFile(CelautError e) async {
    final l = context.l10n;
    final text = e.kind == CelautErrorKind.invalidInput
        ? l.celautPkgBadFile(e.message)
        : CelautStrings.errorText(e.kind);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Load a service file into the app, from the "Import" button.
  Future<void> _import() async {
    final loaded = await _loadPickedFile();
    if (loaded == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.celautPkgLoaded(loaded.name))),
    );
  }

  Future<void> _removePackage(LibraryPackageView package) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.celautPkgRemoveTitle),
        content: Text(l.celautPkgRemoveBody(package.name)),
        actions: [
          TextButton(
            key: const Key('pkg-remove-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.celautSendCancel),
          ),
          FilledButton(
            key: const Key('pkg-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.celautPkgRemove),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _library.remove(package.serviceId);
    } on CelautError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(CelautStrings.errorText(e.kind))),
        );
      }
    }
    if (mounted) setState(_readPackages);
  }

  Future<void> _runPackage(LibraryPackageView package) async {
    if (!package.present) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.celautPkgMissing)),
      );
      return;
    }
    await _run(package.serviceId, name: package.name);
  }

  /// Give the service to the node of [offer] that does not have it, then launch again: the
  /// balancer now sees that node (`docs/celaut/package.md`). The service comes from a file
  /// of the library, from another node (a copy that is deleted after the send), or from a
  /// file that the user picks now (it is loaded into the library first).
  Future<void> _sendService(TransferOffer offer, String serviceId) async {
    final packages = widget.packages ?? const AndroidPackageChannel();
    final transfer = widget.transfer ?? ServiceTransfer();
    final metered = await packages.isMetered();
    if (!mounted) return;
    if (!await confirmServiceTransfer(context, metered: metered) || !mounted) return;
    String? path = offer.libraryPath;
    if (offer.source == TransferSource.file) {
      final loaded = await _loadPickedFile();
      if (loaded == null || !mounted) return;
      if (loaded.serviceId != serviceId.toLowerCase()) {
        // The file holds another service: it stays in the library, but it is not this one.
        await showTransferFailure(context, const PackageRefused(PackageRefusal.otherService));
        return;
      }
      path = loaded.path;
    }
    final result = await showServiceTransfer(
      context,
      transfer: transfer,
      work: () => offer.source == TransferSource.node
          ? transfer.fromNode(offer, serviceId, ServiceStrings.initialDefault)
          : transfer.fromLibrary(offer.to, serviceId, ServiceStrings.initialDefault, path!),
    );
    if (!mounted) return;
    final error = result.error;
    if (error != null) {
      await showTransferFailure(context, error);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.celautSendDone)),
    );
    await _run(serviceId);
  }

  List<SkillView> _filtered() {
    final query = _search.text.trim().toLowerCase();
    final all = _skills ?? const <SkillView>[];
    if (query.isEmpty) return all;
    return [
      for (final s in all)
        if (s.name.toLowerCase().contains(query)) s,
    ];
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
          if (widget.showTitle) ...[
            Text(l.celautRunTitle.toUpperCase(), style: t.label),
            const SizedBox(height: 10),
          ],
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
          const SizedBox(height: 16),
          Text(l.celautPkgTitle.toUpperCase(), style: t.label),
          const SizedBox(height: 6),
          if (_packages.isEmpty)
            Text(l.celautPkgEmpty, key: const Key('pkg-empty'), style: t.secondary)
          else
            for (final package in _packages)
              Padding(
                key: Key('pkg-${package.serviceId}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(package.name, style: t.primary),
                          Text(
                            package.present
                                ? '${CelautStrings.bytes(package.bytes.toInt())} · '
                                    '${package.serviceId.substring(0, 8)}'
                                : l.celautPkgMissing,
                            style: t.secondary,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      key: Key('pkg-run-${package.serviceId}'),
                      // The theme asks for the full width, which a row cannot give.
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: _running || !package.present ? null : () => _runPackage(package),
                      child: Text(l.celautRunButton),
                    ),
                    IconButton(
                      key: Key('pkg-remove-${package.serviceId}'),
                      tooltip: l.celautPkgRemove,
                      onPressed: _running ? null : () => _removePackage(package),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('pkg-import'),
              onPressed: _running ? null : _import,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(l.celautPkgImport),
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
