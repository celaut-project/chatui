// The time that the moves between the pages of the app take, on a device or an
// emulator, in profile mode. `docs/performance.md` says how to run it and what it needs.

import 'package:argus_wallet/main.dart' as app;
import 'package:argus_wallet/ui/celaut/chat_screen.dart';
import 'package:argus_wallet/ui/celaut/chats_screen.dart';
import 'package:argus_wallet/ui/celaut/compute_home_screen.dart';
import 'package:argus_wallet/ui/celaut/instance_info_screen.dart';
import 'package:argus_wallet/ui/celaut/known_nodes_screen.dart';
import 'package:argus_wallet/ui/celaut/launch_rocket.dart';
import 'package:argus_wallet/ui/celaut/network_screen.dart';
import 'package:argus_wallet/ui/celaut/run_service_screen.dart';
import 'package:argus_wallet/ui/home/overview_screen.dart';
import 'package:argus_wallet/ui/home/wallet_page.dart';
import 'package:argus_wallet/ui/settings/about_page.dart';
import 'package:argus_wallet/ui/settings/security_settings_page.dart';
import 'package:argus_wallet/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// How many times each move runs.
const _rounds = int.fromEnvironment('PERF_ROUNDS', defaultValue: 4);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('navigation', (tester) async {
    // The time from the tap to the first frame with the new page, per move.
    final latency = <String, List<int>>{};

    Future<void> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
      final end = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(end)) throw TestFailure('Not found: $finder');
        await tester.pump();
      }
    }

    /// Frames for [ms], so that a transition ends before the next move.
    Future<void> idle([int ms = 700]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump();
      }
    }

    Future<void> move(String name, Future<void> Function() act, Finder page) async {
      final watch = Stopwatch()..start();
      await act();
      await waitFor(page);
      (latency[name] ??= []).add(watch.elapsedMilliseconds);
      await idle();
    }

    Future<void> back(Finder gone) async {
      await tester.binding.handlePopRoute();
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (gone.evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
        await tester.pump();
      }
      await idle();
    }

    Future<void> tab(String key) => tester.tap(find.byKey(Key('tab-$key')));

    // The page of each tab, found only while it shows.
    final tabPage = {
      'chats': find.byType(ChatsScreen),
      'wallet': find.byType(OverviewScreen),
      'compute': find.byType(ComputeHomeScreen),
      'settings': find.byType(SettingsScreen),
    };

    /// Scroll the list of [within] until [finder] shows: down, else back up.
    Future<void> scrollTo(Finder finder, Finder within) async {
      final list = find.descendant(of: within, matching: find.byType(Scrollable)).first;
      try {
        await tester.scrollUntilVisible(finder, 200, scrollable: list, maxScrolls: 20);
      } on StateError {
        await tester.scrollUntilVisible(finder, -200, scrollable: list, maxScrolls: 40);
      }
      await idle(300);
    }

    Finder keyPrefix(String prefix) => find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix),
        );

    app.main();
    await waitFor(find.byKey(const Key('tab-chats')), timeout: const Duration(seconds: 90));
    await idle(3000);

    // Each tab, the first time it shows, then again.
    await binding.traceAction(() async {
      for (final t in ['wallet', 'compute', 'settings', 'chats']) {
        await move('tab_first_$t', () => tab(t), tabPage[t]!);
      }
    }, reportKey: 'tabs_first');
    await binding.traceAction(() async {
      for (var i = 0; i < _rounds; i++) {
        for (final t in ['wallet', 'compute', 'settings', 'chats']) {
          await move('tab_$t', () => tab(t), tabPage[t]!);
        }
      }
    }, reportKey: 'tabs');

    // A conversation, when an instance with a chat slot runs.
    await idle(2000);
    final running = find.byWidgetPredicate((w) {
      if (w is! Text || w.key is! ValueKey<String>) return false;
      final key = (w.key! as ValueKey<String>).value;
      return key.startsWith('chats-state-') && (w.data ?? '').startsWith('Running');
    });
    final conversationPage = find.byWidgetPredicate(
      (w) => w is ChatScreen || w.key == const Key('chat-connecting'),
    );
    if (running.evaluate().isNotEmpty) {
      final id = (running.evaluate().first.widget.key! as ValueKey<String>).value.substring('chats-state-'.length);
      // The conversation, then the info page of the instance from its title.
      await binding.traceAction(() async {
        for (var i = 0; i < _rounds; i++) {
          // The page of the conversation shows, then the conversation once its tunnel is open.
          final watch = Stopwatch()..start();
          await tester.tap(find.byKey(Key('chats-row-$id')));
          await waitFor(conversationPage);
          (latency['conversation'] ??= []).add(watch.elapsedMilliseconds);
          await waitFor(find.byType(ChatScreen));
          (latency['conversation_ready'] ??= []).add(watch.elapsedMilliseconds);
          await idle(1500);
          await move('instance_info', () => tester.tap(find.byKey(const Key('chat-title'))),
              find.byType(InstanceInfoScreen));
          await back(find.byType(InstanceInfoScreen));
          await back(find.byType(ChatScreen));
        }
      }, reportKey: 'conversation');
    } else {
      debugPrint('perf: no running conversation, conversation skipped');
    }

    // New conversation.
    await binding.traceAction(() async {
      for (var i = 0; i < _rounds; i++) {
        await move('new_conversation', () => tester.tap(find.byKey(const Key('chats-new'))),
            find.byType(RunServiceScreen));
        await idle(1500);
        await back(find.byType(RunServiceScreen));
      }
    }, reportKey: 'new_conversation');

    // The page of the wallet, from the Wallet tab.
    await tab('wallet');
    await idle(1000);
    final wallet = keyPrefix('overview-row-seed-');
    if (wallet.evaluate().isNotEmpty) {
      await binding.traceAction(() async {
        for (var i = 0; i < _rounds; i++) {
          await move('wallet_page', () => tester.tap(wallet.first), find.byType(WalletPageScreen));
          await idle(800);
          await back(find.byType(WalletPageScreen));
          await waitFor(wallet);
        }
      }, reportKey: 'wallet_page');
    }

    // Compute: Nodes and Services.
    await tab('compute');
    await idle(1000);
    await binding.traceAction(() async {
      for (var i = 0; i < _rounds; i++) {
        await scrollTo(find.byKey(const Key('place-nodes')), tabPage['compute']!);
        await move('compute_nodes', () => tester.tap(find.byKey(const Key('place-nodes'))),
            find.byType(KnownNodesScreen));
        await idle(1500);
        await back(find.byType(KnownNodesScreen));
        await scrollTo(find.byKey(const Key('place-services')), tabPage['compute']!);
        await move('compute_services', () => tester.tap(find.byKey(const Key('place-services'))),
            find.byType(RunServiceScreen));
        await idle(1500);
        await back(find.byType(RunServiceScreen));
      }
    }, reportKey: 'compute_pages');

    // Settings: Security, Tor, Nodes and About.
    await tab('settings');
    await idle(1000);
    final pages = <String, (Finder, Finder)>{
      'settings_security': (find.text('Security'), find.byType(SecuritySettingsPage)),
      'settings_tor': (find.byKey(const Key('settings-tor')), find.byType(NetworkScreen)),
      'settings_nodes': (find.byKey(const Key('settings-nodes')), find.byType(KnownNodesScreen)),
      'settings_about': (find.byKey(const Key('settings-about')), find.byType(AboutPage)),
    };
    await binding.traceAction(() async {
      for (var i = 0; i < _rounds; i++) {
        for (final MapEntry(key: name, value: (row, page)) in pages.entries) {
          await scrollTo(row, tabPage['settings']!);
          await move(name, () => tester.tap(row), page);
          await idle(800);
          await back(page);
        }
      }
    }, reportKey: 'settings_pages');
    await tab('chats');
    await idle(1000);

    // The rocket of a launch over the Chats tab, with no launch: it hovers, then lifts off.
    // Nothing is started and nothing is spent.
    await binding.traceAction(() async {
      for (var i = 0; i < _rounds; i++) {
        final rocket = LaunchRocket.show(tester.element(tabPage['chats']!), name: 'echo-chat');
        await idle(2000);
        final lifted = rocket.liftOff();
        await idle(800);
        await lifted;
        await idle(300);
      }
    }, reportKey: 'launch_rocket');
    await idle(500);

    binding.reportData ??= {};
    binding.reportData!['latency_ms'] = latency;
  });
}
