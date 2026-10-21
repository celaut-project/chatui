import 'dart:async';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_catalog.dart';
import 'package:argus_wallet/bridge/api/celaut_package.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/conversations.dart';
import 'package:argus_wallet/celaut/launcher.dart';
import 'package:argus_wallet/celaut/package_library.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/wallet_money.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/celaut/chats_screen.dart';
import 'package:argus_wallet/ui/celaut/instance_list.dart';
import 'package:argus_wallet/ui/celaut/run_service_screen.dart';
import 'package:argus_wallet/ui/celaut/run_service_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _echoId = '65' * 32;

InstanceListView _instance(
  String id, {
  String name = 'Echo chat',
  bool chat = true,
  int startedAt = 100,
  String address = 'node.example:53460',
}) =>
    InstanceListView(
      instanceId: id,
      peerId: 'aa' * 32,
      address: address,
      serviceId: _echoId,
      slots: Uint16List.fromList([8080]),
      chatSlots: Uint16List.fromList(chat ? [8080] : []),
      startedAt: startedAt,
      startChargeMu: '1000',
      name: name,
    );

InstanceStatusView _status(String cost) =>
    InstanceStatusView(instanceBalanceMu: '900', costSoFarMu: cost, streamsOpened: BigInt.one);

class _Wallets implements FullWallets {
  _Wallets({this.full = true});

  final bool full;

  @override
  Future<List<PayerWallet>> payers() async =>
      full ? [const PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 1, open: true)] : const [];

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async => true;
}

/// The database and the nodes, in memory.
class _Node {
  List<InstanceListView> db = [];

  /// The answer of the node for each instance: a status, or an error.
  final Map<String, Object> answers = {};
  final stops = <String>[];
  final forgotten = <String>[];
  final tunnels = <String>[];

  List<InstanceListView> load() => List.of(db);

  Future<InstanceStatusView> status(String id) async {
    final a = answers[id];
    if (a is InstanceStatusView) return a;
    throw a ?? const CelautError(kind: CelautErrorKind.unreachable, message: 'no route');
  }

  Future<StopView> stop(String id) async {
    stops.add(id);
    db.removeWhere((i) => i.instanceId == id);
    return const StopView(refundMu: '700', clientBalanceMu: '5000');
  }

  void forget(String id) {
    forgotten.add(id);
    db.removeWhere((i) => i.instanceId == id);
  }

  Future<int> openTunnel(String id, int slot) async {
    tunnels.add('$id:$slot');
    return 4321;
  }
}

/// The page of a section of the drawer, in tests.
class _Section extends StatelessWidget {
  const _Section(this.section);

  final ChatsSection section;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: Text('page ${section.name}'));
}

void main() {
  late _Node node;
  late ConversationNotes notes;
  late List<String> wallet;
  late List<String> named;
  late List<String> launched;

  setUp(() {
    node = _Node();
    notes = ConversationNotes();
    wallet = [];
    named = [];
    launched = [];
  });

  InstanceList list(GlobalKey<InstanceListState> key, Widget empty, {bool full = true}) => InstanceList(
        key: key,
        chats: true,
        empty: empty,
        wallets: _Wallets(full: full),
        notes: notes,
        load: node.load,
        loadStatus: node.status,
        stop: node.stop,
        forget: node.forget,
        openTunnel: node.openTunnel,
        chatPage: (i, port, starting) => Scaffold(
          appBar: AppBar(),
          body: Text('chat ${i.instanceId} ${i.name} $port ${starting ? 'starting' : 'running'}'),
        ),
      );

  /// The picker of a new conversation, with the catalog and the launch in memory.
  Widget picker(String title, StartedCall onStarted) => RunServiceScreen(
        title: title,
        section: RunServiceSection(
          showTitle: false,
          wallets: _Wallets(),
          onStarted: onStarted,
          nameInstance: (id, name) => named.add('$id $name'),
          loadSkills: () async => const [
            SkillView(boxId: 'skill-echo', name: 'Echo chat', prose: 'Says it back.', tags: []),
          ],
          loadServices: (_) async => [SkillServiceView(serviceId: _echoId, score: 0.9, direct: true)],
          previewQuote: (_) async => null,
          library: PackageLibrary(
            importPackage: (path, name, dir) async => throw UnimplementedError(),
            list: () => const <LibraryPackageView>[],
            remove: (_) async {},
            privateDir: () async => '/data',
          ),
          launch: ({required serviceIdHex, initialMu}) async {
            launched.add(serviceIdHex);
            final started = _instance('new-1', name: 'Echo chat', startedAt: 999);
            node.db.add(started);
            return LaunchOutcome(
              quote: QuoteView(
                address: const NodeAddress(host: 'node.example', port: 53460),
                peerId: 'aa' * 32,
                costMu: '1000',
                initMaintenanceMu: '1',
                maxMaintenanceMu: '1',
                maintenanceSecondsLoop: 10,
                variance: 0,
                comparedNanoErg: '1',
                clientBalanceMu: '',
              ),
              instance: InstanceView(
                instanceId: 'new-1',
                peerId: 'aa' * 32,
                slots: started.slots,
                chatSlots: started.chatSlots,
                clientBalanceMu: '5',
              ),
              skipped: const [],
            );
          },
        ),
      );

  Future<void> open(WidgetTester tester, {bool full = true, bool settle = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // The theme of the app: its buttons ask for the full width, which a row cannot
        // give (the bug of the Run screen). The layout is checked with it.
        theme: argusTheme(watchful: false),
        home: ChatsScreen(
          money: const WalletMoney(
            full: WalletSum(count: 1, unknown: 0, knownNano: 1500000000),
            gate: FullWalletGate.open,
          ),
          onWallet: () => wallet.add('open'),
          notes: notes,
          wallets: _Wallets(full: full),
          list: (key, empty) => list(key, empty, full: full),
          runPage: picker,
          page: (s) => s == ChatsSection.wallet ? null : _Section(s),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  group('the list of conversations', () {
    testWidgets('with no instance it says how to start one, and its button opens the picker', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const Key('chats-empty')), findsOneWidget);
      expect(find.text(appL10n.chatsEmptyTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('chats-empty-new')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.chatsNewTitle), findsOneWidget);
      expect(find.byKey(const Key('run-skill-skill-echo')), findsOneWidget);
    });

    testWidgets('a row has the initial, the name, the cost, the preview, the state and the node', (
      tester,
    ) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('2500');
      notes.saw('i1', const [ChatMessage(seq: 1, role: 'assistant', text: 'two')]);
      await open(tester);
      expect(find.byKey(const Key('chats-row-i1')), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('Echo chat'), findsOneWidget);
      expect(find.text('2,500 MU'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('chats-state-i1'))).data,
        '${appL10n.chatsStateRunning} · node.example:53460',
      );
    });

    testWidgets('the preview of a message of the user says "You"', (tester) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('1');
      notes.saw('i1', const [ChatMessage(seq: 0, role: 'user', text: 'hello')]);
      await open(tester);
      expect(find.text(appL10n.chatsPreviewYou('hello')), findsOneWidget);
    });

    testWidgets('without a name the row shows the short service id', (tester) async {
      node.db = [_instance('i1', name: '')];
      await open(tester);
      expect(find.text('65656565…656565'), findsOneWidget);
    });

    testWidgets('the states: running, starting, not answering, stopped; the newest first', (
      tester,
    ) async {
      node.db = [
        _instance('run', startedAt: 5),
        _instance('down', startedAt: 4),
        _instance('new', startedAt: 3),
      ];
      node.answers['run'] = _status('1');
      node.answers['down'] = const CelautError(kind: CelautErrorKind.timeout, message: 'late');
      node.answers['new'] = _status('1');
      notes.markStarting('new');
      notes.markStopped(_instance('gone', startedAt: 9), '700');
      await open(tester);
      String state(String id) => tester.widget<Text>(find.byKey(Key('chats-state-$id'))).data!;
      expect(state('run'), startsWith(appL10n.chatsStateRunning));
      expect(state('down'), startsWith(appL10n.chatsStateUnreachable));
      expect(state('new'), startsWith(appL10n.chatsStateStarting));
      expect(state('gone'), startsWith(appL10n.chatsStateStopped));
      // The running ones by start, the newest first; the stopped ones after them.
      final ys = [
        for (final id in ['run', 'down', 'new', 'gone'])
          tester.getTopLeft(find.byKey(Key('chats-row-$id'))).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('a row that the node does not answer for yet says "Checking"', (tester) async {
      final pending = Completer<InstanceStatusView>();
      node.db = [_instance('i1')];
      await tester.pumpWidget(
        MaterialApp(
          theme: argusTheme(watchful: false),
          home: Scaffold(
            body: InstanceList(
              chats: true,
              notes: notes,
              load: node.load,
              loadStatus: (_) => pending.future,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chats-state-i1'))).data,
        startsWith(appL10n.chatsStateChecking),
      );
      pending.complete(_status('1'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('chats-state-i1'))).data,
        startsWith(appL10n.chatsStateRunning),
      );
    });

    testWidgets('an instance without a chat slot is not in the list of conversations', (tester) async {
      node.db = [_instance('plain', chat: false)];
      await open(tester);
      expect(find.byKey(const Key('chats-row-plain')), findsNothing);
      expect(find.byKey(const Key('chats-empty')), findsOneWidget);
    });

    testWidgets('a tap opens the conversation of a running instance, which reads it again', (
      tester,
    ) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('1');
      await open(tester);
      await tester.tap(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      expect(node.tunnels, ['i1:8080']);
      expect(find.text('chat i1 Echo chat 4321 running'), findsOneWidget);
      // Back: the list is there, and the instance is still in it.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-row-i1')), findsOneWidget);
      expect(node.stops, isEmpty);
    });

    testWidgets('a tunnel that fails says why and opens nothing', (tester) async {
      node.db = [_instance('i1')];
      await tester.pumpWidget(
        MaterialApp(
          theme: argusTheme(watchful: false),
          home: Scaffold(
            body: InstanceList(
              chats: true,
              notes: notes,
              load: node.load,
              loadStatus: node.status,
              openTunnel: (_, _) async =>
                  throw const CelautError(kind: CelautErrorKind.unreachable, message: 'x'),
              chatPage: (i, port, s) => const Text('chat'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a tap on a stopped instance opens its info page, with the refund', (tester) async {
      notes.markStopped(_instance('gone'), '700');
      await open(tester);
      await tester.tap(find.byKey(const Key('chats-row-gone')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.chatsInfoTitle), findsOneWidget);
      expect(tester.widget<SelectableText>(find.byKey(const Key('info-refund'))).data, '700 MU');
      expect(find.byKey(const Key('info-stop')), findsNothing);
      expect(node.tunnels, isEmpty);
    });
  });

  group('long press', () {
    testWidgets('a running instance: Info and Stop, no Remove', (tester) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('1');
      await open(tester);
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-action-info')), findsOneWidget);
      expect(find.byKey(const Key('chats-action-stop')), findsOneWidget);
      expect(find.byKey(const Key('chats-action-remove')), findsNothing);
    });

    testWidgets('Info opens the info page', (tester) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('321');
      await open(tester);
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chats-action-info')));
      await tester.pumpAndSettle();
      expect(tester.widget<SelectableText>(find.byKey(const Key('info-cost'))).data, '321 MU');
      expect(tester.widget<SelectableText>(find.byKey(const Key('info-service'))).data, _echoId);
    });

    testWidgets('Stop asks, stops, and the row stays as stopped until it is removed', (tester) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('1');
      notes.saw('i1', const [ChatMessage(seq: 1, role: 'assistant', text: 'bye')]);
      await open(tester);
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chats-action-stop')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stop-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stop-ok')));
      await tester.pumpAndSettle();
      expect(node.stops, ['i1']);
      expect(
        tester.widget<Text>(find.byKey(const Key('chats-state-i1'))).data,
        startsWith(appL10n.chatsStateStopped),
      );
      expect(find.text('bye'), findsOneWidget);
      // Remove takes a stopped row out without a question: the node has nothing.
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-action-stop')), findsNothing);
      await tester.tap(find.byKey(const Key('chats-action-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-row-i1')), findsNothing);
      expect(node.forgotten, isEmpty);
    });

    testWidgets('Stop with no wallet stops nothing and says why', (tester) async {
      node.db = [_instance('i1')];
      node.answers['i1'] = _status('1');
      await open(tester, full: false);
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chats-action-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stop-ok')));
      await tester.pumpAndSettle();
      expect(node.stops, isEmpty);
      expect(find.text(appL10n.celautOpenFullWalletNeeded), findsOneWidget);
    });

    testWidgets('an instance that the node does not answer for can be removed, after a warning', (
      tester,
    ) async {
      node.db = [_instance('i1')];
      await open(tester);
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chats-action-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forget-confirm')), findsOneWidget);
      expect(find.text(appL10n.chatsForgetBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('forget-cancel')));
      await tester.pumpAndSettle();
      expect(node.forgotten, isEmpty);
      expect(find.byKey(const Key('chats-row-i1')), findsOneWidget);
      await tester.longPress(find.byKey(const Key('chats-row-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chats-action-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forget-ok')));
      await tester.pumpAndSettle();
      expect(node.forgotten, ['i1']);
      expect(find.byKey(const Key('chats-row-i1')), findsNothing);
    });
  });

  group('the drawer', () {
    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('chats-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-drawer')), findsOneWidget);
    }

    testWidgets('its head has the wallet with its ERG', (tester) async {
      await open(tester);
      await openDrawer(tester);
      expect(find.text('1.5 ERG'), findsOneWidget);
    });

    for (final section in ChatsSection.values.where((s) => s != ChatsSection.wallet)) {
      testWidgets('${section.name} opens its page, and back is the list', (tester) async {
        await open(tester);
        await openDrawer(tester);
        await tester.ensureVisible(find.byKey(Key('drawer-${section.name}')));
        await tester.tap(find.byKey(Key('drawer-${section.name}')));
        await tester.pumpAndSettle();
        expect(find.text('page ${section.name}'), findsOneWidget);
        expect(find.byKey(const Key('chats-drawer')), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chats-new')), findsOneWidget);
      });
    }

    testWidgets('Wallet and the head open the wallet of the app', (tester) async {
      await open(tester);
      await openDrawer(tester);
      await tester.tap(find.byKey(const Key('drawer-wallet')));
      await tester.pumpAndSettle();
      expect(wallet, ['open']);
      expect(find.byKey(const Key('chats-drawer')), findsNothing);
      await openDrawer(tester);
      await tester.tap(find.byKey(const Key('drawer-head')));
      await tester.pumpAndSettle();
      expect(wallet, ['open', 'open']);
    });

    testWidgets('the rows are in Spanish too', (tester) async {
      setAppLocale(const Locale('es'));
      addTearDown(() => setAppLocale(const Locale('en')));
      await open(tester);
      await openDrawer(tester);
      expect(find.text('Billetera'), findsOneWidget);
      expect(find.text('Otras instancias'), findsOneWidget);
    });
  });

  group('new conversation', () {
    Future<void> runEcho(WidgetTester tester, {bool confirm = true}) async {
      await tester.tap(find.byKey(const Key('chats-new')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.chatsNewTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('run-skill-skill-echo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-sheet-run')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run-confirm')), findsOneWidget);
      await tester.tap(find.byKey(Key(confirm ? 'run-confirm-ok' : 'run-confirm-cancel')));
      await tester.pumpAndSettle();
    }

    testWidgets('the pencil, a skill, the confirmation, then the conversation that starts', (
      tester,
    ) async {
      await open(tester);
      await runEcho(tester);
      expect(launched, [_echoId]);
      expect(named, ['new-1 Echo chat']);
      expect(node.tunnels, ['new-1:8080']);
      expect(find.text('chat new-1 Echo chat 4321 starting'), findsOneWidget);
      expect(notes.isStarting('new-1'), isTrue);
      // Back from the conversation is the list, not the picker, with the new row.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-new')), findsOneWidget);
      expect(find.byKey(const Key('chats-row-new-1')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('chats-state-new-1'))).data,
        startsWith(appL10n.chatsStateStarting),
      );
    });

    testWidgets('Cancel in the confirmation starts nothing', (tester) async {
      await open(tester);
      await runEcho(tester, confirm: false);
      expect(launched, isEmpty);
      expect(node.tunnels, isEmpty);
      expect(find.text(appL10n.chatsNewTitle), findsOneWidget);
    });
  });

  group('other instances', () {
    testWidgets('they list the instances without a chat slot, and a tap opens the info', (tester) async {
      node.db = [_instance('plain', chat: false, name: 'Solver'), _instance('chat')];
      node.answers['plain'] = _status('5');
      await tester.pumpWidget(
        MaterialApp(
          theme: argusTheme(watchful: false),
          home: OtherInstancesScreen(
            list: InstanceList(
              chats: false,
              notes: notes,
              load: node.load,
              loadStatus: node.status,
              openTunnel: node.openTunnel,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chats-row-plain')), findsOneWidget);
      expect(find.byKey(const Key('chats-row-chat')), findsNothing);
      expect(find.text(appL10n.chatsNoChatSlot), findsOneWidget);
      await tester.tap(find.byKey(const Key('chats-row-plain')));
      await tester.pumpAndSettle();
      expect(node.tunnels, isEmpty);
      expect(
        tester.widget<SelectableText>(find.byKey(const Key('info-slot'))).data,
        appL10n.chatsInfoNoChatSlot,
      );
    });
  });
}
