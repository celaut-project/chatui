import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridge/api/celaut_service.dart';
import '../../celaut/conversations.dart';
import '../../celaut/launcher.dart';
import '../../celaut/payers.dart';
import '../../celaut/wallet_money.dart';
import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';
import '../home/home_style.dart';
import '../settings/about_page.dart';
import '../settings_screen.dart';
import 'deposit_screen.dart';
import 'instance_list.dart';
import 'known_nodes_screen.dart';
import 'network_screen.dart';
import 'run_service_screen.dart';
import 'run_service_section.dart' show StartedCall;

/// The places of the secondary menu (the drawer) of the home screen.
enum ChatsSection {
  wallet,
  deposit,
  compute,
  nodes,
  services,
  otherInstances,
  network,
  settings,
  about,
}

/// The home screen of the app, chat first, as Telegram (`docs/celaut/ui-chat-first.md`):
///
/// - the list of conversations: each row is an instance whose interface has a chat slot
///   (`docs/celaut/chat.md`, section 2);
/// - the pencil button opens "New conversation": the skills of the catalog and the
///   service files, then the confirmation, the wallet, the launch, and the conversation;
/// - the drawer (the button at the top left) holds the rest of the app: the wallet, the
///   deposit, the compute and the credit, the nodes, the services, the other instances,
///   the network, the settings, and the about page.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    this.money = WalletMoney.none,
    this.onWallet,
    this.computePage,
    this.page,
    this.wallets = const AppFullWallets(),
    this.notes,
    this.newClient,
    this.list,
    this.runPage,
  });

  /// The ERG of the wallet, for the head of the drawer.
  final WalletMoney money;

  /// Open the page of the wallet (or create or restore one).
  final VoidCallback? onWallet;

  /// The compute and the credit of the nodes. The dashboard gives it, with the money.
  final WidgetBuilder? computePage;

  /// The page of a section of the drawer. Tests give their own; null for a section
  /// keeps the page of the app.
  final Widget? Function(ChatsSection section)? page;

  final FullWallets wallets;
  final ConversationNotes? notes;

  /// Make a new client on a node that forgot the client id.
  final Future<NewClientView> Function(NodeAddress node)? newClient;

  /// The list. Tests give their own, with fake calls.
  final InstanceList Function(GlobalKey<InstanceListState> key, Widget empty)? list;

  /// The picker of "New conversation" and "Services". Tests give their own; it gets the
  /// title and what to do after a start.
  final Widget Function(String title, StartedCall onStarted)? runPage;

  @override
  State<ChatsScreen> createState() => ChatsScreenState();
}

class ChatsScreenState extends State<ChatsScreen> {
  final _list = GlobalKey<InstanceListState>();
  late final ConversationNotes _notes = widget.notes ?? conversationNotes;

  /// Read the list again (after a change on another screen).
  Future<void> refresh() async => _list.currentState?.refresh();

  /// The picker of services, for "New conversation", "Services" and the Run button of
  /// the compute page.
  Widget runPage(String title) =>
      widget.runPage?.call(title, _started) ??
      RunServiceScreen(
        title: title,
        wallets: widget.wallets,
        newClient: widget.newClient,
        onStarted: _started,
      );

  /// A service started from the picker: back to the list, and into the conversation,
  /// as a messenger does after "New chat". An instance without a chat slot is in "Other
  /// instances".
  Future<void> _started(LaunchOutcome outcome, String serviceId, String? name) async {
    final instance = outcome.instance;
    final chat = instance.chatSlots.isNotEmpty;
    if (chat) _notes.markStarting(instance.instanceId);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await refresh();
    if (!mounted) return;
    if (!chat) {
      final quote = outcome.quote;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.chatsStartedOther(
              '${quote.address.host}:${quote.address.port}',
            ),
          ),
        ),
      );
      return;
    }
    await _list.currentState?.openChat(
      instanceOfLaunch(outcome, serviceId, name),
      starting: true,
    );
  }

  Future<void> _newChat() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => runPage(context.l10n.chatsNewTitle)),
    );
    if (mounted) await refresh();
  }

  Widget _defaultPage(ChatsSection section) {
    final l = context.l10n;
    return switch (section) {
      ChatsSection.deposit => const DepositScreen(),
      ChatsSection.compute => widget.computePage?.call(context) ?? const SizedBox.shrink(),
      ChatsSection.nodes => KnownNodesScreen(newClient: widget.newClient),
      ChatsSection.services => runPage(l.chatsServicesTitle),
      ChatsSection.otherInstances => OtherInstancesScreen(wallets: widget.wallets, notes: _notes),
      ChatsSection.network => const NetworkScreen(),
      ChatsSection.settings => const SettingsScreen(),
      ChatsSection.about => const AboutPage(),
      // The dashboard opens the wallet in place (see [_open]).
      ChatsSection.wallet => const SizedBox.shrink(),
    };
  }

  Future<void> _open(ChatsSection section) async {
    // Close the drawer first, as Telegram does.
    Navigator.of(context).pop();
    final custom = widget.page?.call(section);
    if (section == ChatsSection.wallet && custom == null) {
      widget.onWallet?.call();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => custom ?? _defaultPage(section)),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final empty = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: t.muted),
          const SizedBox(height: 16),
          Text(l.chatsEmptyTitle, style: t.title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(l.chatsEmptyBody, style: t.secondary, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('chats-empty-new'),
            onPressed: _newChat,
            icon: const Icon(Icons.edit_outlined),
            label: Text(l.chatsNewTitle),
          ),
        ],
      ),
    );
    return Scaffold(
      drawer: ChatsDrawer(money: widget.money, onOpen: _open),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            key: const Key('chats-menu'),
            tooltip: l.chatsMenu,
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        titleSpacing: 4,
        title: Semantics(
          header: true,
          label: 'Celaut',
          excludeSemantics: true,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CellMark(size: 28),
              SizedBox(width: 10),
              CelautWordmark(size: 20),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('chats-new'),
        tooltip: l.chatsNewTitle,
        onPressed: _newChat,
        child: const Icon(Icons.edit_outlined),
      ),
      body: widget.list?.call(_list, empty) ??
          InstanceList(
            key: _list,
            chats: true,
            empty: empty,
            wallets: widget.wallets,
            notes: _notes,
            bottomPadding: 88,
          ),
    );
  }
}

/// The secondary menu of the home screen, as the drawer of Telegram: the wallet on top
/// (as the account of Telegram), then one row for each part of the app.
class ChatsDrawer extends StatelessWidget {
  const ChatsDrawer({super.key, required this.money, required this.onOpen});

  final WalletMoney money;
  final void Function(ChatsSection section) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    Widget row(ChatsSection section, IconData icon, String title) => ListTile(
          key: Key('drawer-${section.name}'),
          leading: Icon(icon),
          title: Text(title),
          onTap: () => onOpen(section),
        );
    final walletLine = money.full.count == 0 ? l.chatsDrawerNoWallet : money.full.text;
    return Drawer(
      key: const Key('chats-drawer'),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              key: const Key('drawer-head'),
              onTap: () => onOpen(ChatsSection.wallet),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(homeGutter, 24, homeGutter, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CellMark(size: 48),
                    const SizedBox(height: 14),
                    const CelautWordmark(size: 22),
                    const SizedBox(height: 4),
                    Text(walletLine, key: const Key('drawer-wallet-erg'), style: t.secondary),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            row(ChatsSection.wallet, Icons.account_balance_wallet_outlined, l.chatsDrawerWallet),
            row(ChatsSection.deposit, Icons.savings_outlined, l.chatsDrawerDeposit),
            row(ChatsSection.compute, Icons.memory_outlined, l.chatsDrawerCompute),
            row(ChatsSection.nodes, Icons.hub_outlined, l.celautNodesTitle),
            row(ChatsSection.services, Icons.widgets_outlined, l.chatsServicesTitle),
            row(ChatsSection.otherInstances, Icons.layers_outlined, l.chatsOtherTitle),
            const Divider(height: 1),
            row(ChatsSection.network, Icons.shield_outlined, l.chatsDrawerNetwork),
            row(ChatsSection.settings, Icons.settings_outlined, l.commonSettings),
            row(ChatsSection.about, Icons.info_outline, l.aboutTitle),
          ],
        ),
      ),
    );
  }
}

/// The instances whose interface has no chat slot (`docs/celaut/chat.md`, section 2).
/// They have no conversation: a row opens the info page of the instance.
class OtherInstancesScreen extends StatelessWidget {
  const OtherInstancesScreen({
    super.key,
    this.wallets = const AppFullWallets(),
    this.notes,
    this.list,
  });

  final FullWallets wallets;
  final ConversationNotes? notes;

  /// The list. Tests give their own.
  final InstanceList? list;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.chatsOtherTitle)),
      body: list ??
          InstanceList(
            chats: false,
            wallets: wallets,
            notes: notes,
            empty: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                l.chatsOtherEmpty,
                key: const Key('other-empty'),
                style: t.secondary,
                textAlign: TextAlign.center,
              ),
            ),
          ),
    );
  }
}
