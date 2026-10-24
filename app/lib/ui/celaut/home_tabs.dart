import 'package:flutter/material.dart';

import '../../bridge/api/celaut_home.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/conversations.dart';
import '../../celaut/payers.dart';
import '../../celaut/wallet_money.dart';
import '../../l10n/l10n.dart';
import '../settings_screen.dart';
import 'chats_screen.dart';
import 'compute_home_screen.dart';
import 'deposit_screen.dart';
import 'instance_list.dart';
import 'known_nodes_screen.dart';
import 'run_service_screen.dart';
import 'run_service_section.dart' show StartedCall;

/// The tabs of the bottom bar of the home screen.
enum HomeTab { chats, wallet, compute, settings }

/// The pages that a tab opens over the bar.
enum HomePlace { deposit, nodes, services, otherInstances }

/// The home screen of the app, chat first, with a bottom bar as WhatsApp and Telegram
/// on Android (`docs/celaut/ui-chat-first.md`):
///
/// - Chats: the list of conversations and the pencil button ([ChatsScreen]);
/// - Wallet: the wallet, and "Deposit to a node";
/// - Compute: the compute and the credit of the nodes, then Nodes, Services and Other
///   instances;
/// - Settings: the settings of the app, with Network and Tor, Developer and About.
///
/// Each tab keeps its state while another one shows. A tab is built the first time it
/// shows, except Chats, which is always there. Back on another tab goes to Chats. The
/// conversation, the info page of an instance and the pages of the tabs open over the
/// bar.
class HomeTabs extends StatefulWidget {
  const HomeTabs({
    super.key,
    this.initialTab = HomeTab.chats,
    this.onTab,
    this.money = WalletMoney.none,
    this.usdPerErg,
    this.refreshPrice,
    this.wallet,
    this.settings,
    this.wallets = const AppFullWallets(),
    this.notes,
    this.newClient,
    this.list,
    this.runPage,
    this.loadCompute,
    this.page,
  });

  final HomeTab initialTab;

  /// The tab changed. The dashboard keeps it while the page of the wallet covers the
  /// tabs.
  final ValueChanged<HomeTab>? onTab;

  /// The ERG of the wallet, for the Compute tab.
  final WalletMoney money;

  /// The USD price of one ERG from the oracle pool; null if it is not known.
  final double? usdPerErg;
  final Future<void> Function()? refreshPrice;

  /// The Wallet tab: the dashboard gives the wallet, with [deposit] in it.
  final Widget Function(BuildContext context, Widget deposit)? wallet;

  /// The Settings tab. Null: the settings of the app.
  final WidgetBuilder? settings;

  final FullWallets wallets;
  final ConversationNotes? notes;

  /// Make a new client on a node that forgot the client id.
  final Future<NewClientView> Function(NodeAddress node)? newClient;

  /// The list of conversations. Tests give their own, with fake calls.
  final InstanceList Function(GlobalKey<InstanceListState> key, Widget empty)? list;

  /// The picker of services. Tests give their own.
  final Widget Function(String title, StartedCall onStarted)? runPage;

  /// The data of the Compute tab. Tests give their own.
  final Future<ComputeOverviewView> Function()? loadCompute;

  /// The page of a place. Tests give their own; null keeps the page of the app.
  final Widget? Function(HomePlace place)? page;

  @override
  State<HomeTabs> createState() => HomeTabsState();
}

class HomeTabsState extends State<HomeTabs> {
  final _chats = GlobalKey<ChatsScreenState>();
  final _compute = GlobalKey<ComputeHomeScreenState>();
  late HomeTab _tab = widget.initialTab;
  late final Set<HomeTab> _built = {HomeTab.chats, widget.initialTab};

  HomeTab get tab => _tab;

  /// Show [tab]. Chats and Compute ask the nodes again when they show again.
  void select(HomeTab tab) {
    if (tab == _tab) return;
    final again = _built.contains(tab);
    setState(() {
      _tab = tab;
      _built.add(tab);
    });
    widget.onTab?.call(tab);
    if (!again) return;
    switch (tab) {
      case HomeTab.chats:
        _chats.currentState?.refresh();
      case HomeTab.compute:
        _compute.currentState?.refresh();
      case HomeTab.wallet || HomeTab.settings:
        break;
    }
  }

  /// Show the chat of the instance [instanceId], if it runs and has a chat slot. If not,
  /// the list of chats stays in view.
  Future<void> openChat(String instanceId) async {
    select(HomeTab.chats);
    // The page of the tab can be new: wait for its first frame.
    await WidgetsBinding.instance.endOfFrame;
    await _chats.currentState?.openChat(instanceId);
  }

  Widget _defaultPage(HomePlace place) {
    final l = context.l10n;
    return switch (place) {
      HomePlace.deposit => const DepositScreen(),
      HomePlace.nodes => KnownNodesScreen(newClient: widget.newClient),
      HomePlace.services => _runPage(l.chatsServicesTitle),
      HomePlace.otherInstances => OtherInstancesScreen(wallets: widget.wallets, notes: widget.notes),
    };
  }

  Widget _runPage(String title) =>
      _chats.currentState?.runPage(title) ??
      RunServiceScreen(title: title, wallets: widget.wallets, newClient: widget.newClient);

  Future<void> _open(HomePlace place) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => widget.page?.call(place) ?? _defaultPage(place)),
    );
    if (!mounted) return;
    await Future.wait([
      ?_chats.currentState?.refresh(),
      ?_compute.currentState?.refresh(),
    ]);
  }

  Widget _row(HomePlace place, IconData icon, String title, String subtitle) => ListTile(
        key: Key('place-${place.name}'),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(place),
      );

  Widget _page(HomeTab tab) {
    final l = context.l10n;
    switch (tab) {
      case HomeTab.chats:
        return ChatsScreen(
          key: _chats,
          wallets: widget.wallets,
          notes: widget.notes,
          newClient: widget.newClient,
          list: widget.list,
          runPage: widget.runPage,
          onConversation: () => select(HomeTab.chats),
        );
      case HomeTab.wallet:
        final deposit = _row(
          HomePlace.deposit,
          Icons.savings_outlined,
          l.chatsDepositRow,
          l.chatsDepositRowSubtitle,
        );
        return widget.wallet?.call(context, deposit) ??
            Scaffold(
              appBar: AppBar(title: Text(l.chatsTabWallet)),
              body: ListView(children: [deposit]),
            );
      case HomeTab.compute:
        return ComputeHomeScreen(
          key: _compute,
          money: widget.money,
          usdPerErg: widget.usdPerErg,
          refreshPrice: widget.refreshPrice,
          onWallets: () => select(HomeTab.wallet),
          onNodes: () => _open(HomePlace.nodes),
          wallets: widget.wallets,
          newClient: widget.newClient,
          load: widget.loadCompute,
          runScreen: (context) => _runPage(context.l10n.celautRunTitle),
          sections: [
            _row(HomePlace.nodes, Icons.hub_outlined, l.celautNodesTitle, l.chatsNodesRowSubtitle),
            _row(
              HomePlace.services,
              Icons.widgets_outlined,
              l.chatsServicesTitle,
              l.chatsServicesRowSubtitle,
            ),
            _row(
              HomePlace.otherInstances,
              Icons.layers_outlined,
              l.chatsOtherTitle,
              l.chatsOtherRowSubtitle,
            ),
          ],
        );
      case HomeTab.settings:
        return widget.settings?.call(context) ?? const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: _tab == HomeTab.chats,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(HomeTab.chats);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab.index,
          children: [
            for (final t in HomeTab.values)
              _built.contains(t) ? _page(t) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          key: const Key('home-tabs'),
          selectedIndex: _tab.index,
          onDestinationSelected: (i) => select(HomeTab.values[i]),
          destinations: [
            NavigationDestination(
              key: const Key('tab-chats'),
              icon: const Icon(Icons.forum_outlined),
              selectedIcon: const Icon(Icons.forum),
              label: l.chatsTabChats,
            ),
            NavigationDestination(
              key: const Key('tab-wallet'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: const Icon(Icons.account_balance_wallet),
              label: l.chatsTabWallet,
            ),
            NavigationDestination(
              key: const Key('tab-compute'),
              icon: const Icon(Icons.memory_outlined),
              selectedIcon: const Icon(Icons.memory),
              label: l.chatsTabCompute,
            ),
            NavigationDestination(
              key: const Key('tab-settings'),
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: l.commonSettings,
            ),
          ],
        ),
      ),
    );
  }
}
