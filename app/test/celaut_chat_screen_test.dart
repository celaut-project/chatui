import 'dart:async';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/conversation_keep_alive.dart';
import 'package:argus_wallet/celaut/conversations.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/tunnel_http.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/celaut/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A chat client with no network: it echoes in memory, and it can fail.
class _FakeChat extends ChatClient {
  _FakeChat({List<ChatMessage> history = const []})
      : _messages = [...history],
        super(port: 0, http: TunnelHttp());

  final List<ChatMessage> _messages;
  ChatException? failWith;
  final sent = <String>[];

  @override
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  @override
  int get count => _messages.length;

  /// Holds [syncWhenStarted] until it completes.
  Completer<void>? starting;

  @override
  Future<void> sync() async {}

  @override
  Future<void> syncWhenStarted({Duration limit = const Duration(minutes: 2), Future<void> Function(Duration)? wait}) =>
      starting?.future ?? Future.value();

  @override
  Future<void> send(String text) async {
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(text);
    _messages
      ..add(ChatMessage(seq: _messages.length, role: 'user', text: text))
      ..add(ChatMessage(seq: _messages.length, role: 'assistant', text: 'echo: $text'));
  }
}

/// A keep-alive that writes down what the screen asks of it.
class _FakeKeepAlive implements ConversationKeepAlive {
  final events = <String>[];

  @override
  Future<void> start() async => events.add('start');

  @override
  Future<void> stop() async => events.add('stop');
}

class _Wallets implements FullWallets {
  _Wallets({required this.full});

  final bool full;

  @override
  Future<List<PayerWallet>> payers() async =>
      full ? [const PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 1, open: true)] : const [];

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async => true;
}

final _echo = InstanceListView(
  instanceId: 'i1',
  peerId: 'aa' * 32,
  address: 'node.example:53460',
  serviceId: '65' * 32,
  slots: Uint16List.fromList([8080]),
  chatSlots: Uint16List.fromList([8080]),
  startedAt: 1760000000,
  startChargeMu: '1000',
  refundMu: '',
  name: 'Echo chat',
);

void main() {
  late _FakeChat chat;
  late List<String> stops;
  late bool closed;
  late _FakeKeepAlive keepAlive;
  late ConversationNotes notes;

  Future<void> open(WidgetTester tester, {bool fullWallet = true, bool starting = false}) async {
    stops = [];
    closed = false;
    keepAlive = _FakeKeepAlive();
    notes = ConversationNotes();
    await tester.pumpWidget(
      MaterialApp(
        // The theme of the app: its buttons ask for the full width (the bug of the Run
        // screen), so the layout is checked with it.
        theme: argusTheme(watchful: false),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      instance: _echo,
                      port: 1,
                      chat: chat,
                      http: TunnelHttp(),
                      wallets: _Wallets(full: fullWallet),
                      keepAlive: keepAlive,
                      starting: starting,
                      notes: notes,
                      loadStatus: (_) async => InstanceStatusView(
                        instanceBalanceMu: '900',
                        costSoFarMu: '100',
                        streamsOpened: BigInt.one,
                      ),
                      stopInstance: (id) async {
                        stops.add(id);
                        return const StopView(refundMu: '900', clientBalanceMu: '5000');
                      },
                    ),
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    if (starting) {
      // The progress indicator turns until the service answers: no settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pumpAndSettle();
    }
  }

  /// ⋮, then Stop, then the confirmation.
  Future<void> stopFromMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stop-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stop-ok')));
    await tester.pumpAndSettle();
  }

  setUp(() => chat = _FakeChat());

  testWidgets('shows the history of a running instance and the cost so far', (tester) async {
    chat = _FakeChat(history: const [
      ChatMessage(seq: 0, role: 'user', text: 'one'),
      ChatMessage(seq: 1, role: 'assistant', text: 'echo: one'),
    ]);
    await open(tester);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('echo: one'), findsOneWidget);
    expect(find.byKey(const Key('chat-cost')), findsOneWidget);
    expect(find.textContaining('100'), findsOneWidget);
    // The last message goes to the notes of the list, in memory.
    expect(notes.lastMessage('i1')?.text, 'echo: one');
  });

  testWidgets('the bar has the name, and under it the state, the node and the cost', (tester) async {
    await open(tester);
    expect(find.text('Echo chat'), findsOneWidget);
    final subtitle = tester.widget<Text>(find.byKey(const Key('chat-cost'))).data!;
    expect(subtitle, contains(appL10n.chatsStateRunning));
    expect(subtitle, contains('node.example:53460'));
    expect(subtitle, contains('100 MU'));
  });

  testWidgets('a tap on the name opens the info page of the instance', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-title')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.chatsInfoTitle), findsOneWidget);
    expect(find.byKey(const Key('info-name')), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('info-service'))).data, '65' * 32);
    expect(tester.widget<SelectableText>(find.byKey(const Key('info-node'))).data, 'node.example:53460');
    expect(tester.widget<SelectableText>(find.byKey(const Key('info-slot'))).data, appL10n.chatsInfoChatSlot('8080'));
    expect(tester.widget<SelectableText>(find.byKey(const Key('info-cost'))).data, '100 MU');
    expect(find.byKey(const Key('info-started')), findsOneWidget);
    expect(find.byKey(const Key('info-stop')), findsOneWidget);
    // Back from the info page: the conversation is still there.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-input')), findsOneWidget);
  });

  testWidgets('⋮ has Info and Stop', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-menu-info')), findsOneWidget);
    expect(find.byKey(const Key('chat-menu-stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-menu-info')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.chatsInfoTitle), findsOneWidget);
  });

  testWidgets('Stop on the info page stops the instance and goes back to the list', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-title')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('info-stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('info-stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stop-ok')));
    await tester.pumpAndSettle();
    expect(stops, ['i1']);
    expect(closed, isTrue);
    expect(notes.isStarting('i1'), isFalse);
  });

  testWidgets('a new instance shows that the service starts, until it answers', (tester) async {
    chat.starting = Completer<void>();
    await open(tester, starting: true);
    notes.markStarting('i1');
    expect(find.byKey(const Key('chat-starting')), findsOneWidget);
    expect(find.text(appL10n.chatStarting), findsOneWidget);
    expect(find.text(appL10n.chatEmpty), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('chat-cost'))).data,
      contains(appL10n.chatsStateStarting),
    );
    chat.starting!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-starting')), findsNothing);
    expect(find.text(appL10n.chatEmpty), findsOneWidget);
    expect(find.byKey(const Key('chat-error')), findsNothing);
    expect(notes.isStarting('i1'), isFalse);
  });

  testWidgets('a service that never starts shows the error', (tester) async {
    chat.starting = Completer<void>();
    await open(tester, starting: true);
    chat.starting!.completeError(const ChatException(ChatErrorKind.unreachable));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-starting')), findsNothing);
    expect(find.text(appL10n.chatErrorUnreachable), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('chat-cost'))).data,
      contains(appL10n.chatsStateUnreachable),
    );
  });

  testWidgets('an empty conversation asks the user to write', (tester) async {
    await open(tester);
    expect(find.text('Say something to start the conversation.'), findsOneWidget);
  });

  testWidgets('send shows the message and the answer, and clears the field', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), 'Hello');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(chat.sent, ['Hello']);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('echo: Hello'), findsOneWidget);
    expect(find.byKey(const Key('chat-bubble-0')), findsOneWidget);
    expect(find.byKey(const Key('chat-bubble-1')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, '');
    expect(notes.lastMessage('i1')?.text, 'echo: Hello');
  });

  testWidgets('a failed send shows the error and keeps the text', (tester) async {
    chat.failWith = const ChatException(ChatErrorKind.busy);
    await open(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), 'Hello');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-error')), findsOneWidget);
    expect(find.textContaining('busy'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, 'Hello');
  });

  testWidgets('back goes to the list at once: no question, and the instance runs on', (tester) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stop-confirm')), findsNothing);
    expect(closed, isTrue);
    expect(stops, isEmpty);
    // Only the phone side is released.
    expect(keepAlive.events, ['start', 'stop']);
  });

  testWidgets('⋮ Stop asks, stops it, shows the refund and closes the screen', (tester) async {
    await open(tester);
    await stopFromMenu(tester);
    expect(stops, ['i1']);
    expect(closed, isTrue);
    expect(find.textContaining('Refund'), findsOneWidget);
  });

  testWidgets('⋮ Stop, then Cancel, changes nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stop-cancel')));
    await tester.pumpAndSettle();
    expect(stops, isEmpty);
    expect(closed, isFalse);
  });

  testWidgets('stop needs a full wallet: without one it stays and stops nothing', (tester) async {
    await open(tester, fullWallet: false);
    await stopFromMenu(tester);
    expect(stops, isEmpty);
    expect(closed, isFalse);
    expect(find.text(appL10n.celautOpenFullWalletNeeded), findsOneWidget);
  });

  testWidgets('the keep-alive starts when the screen opens and runs while it is open', (tester) async {
    await open(tester);
    expect(keepAlive.events, ['start']);
  });

  testWidgets('stopping the instance stops the keep-alive', (tester) async {
    await open(tester);
    await stopFromMenu(tester);
    expect(stops, ['i1']);
    expect(keepAlive.events.first, 'start');
    expect(keepAlive.events.last, 'stop');
  });

  testWidgets('a stop that needs a wallet and fails keeps the keep-alive', (tester) async {
    await open(tester, fullWallet: false);
    await stopFromMenu(tester);
    expect(keepAlive.events, ['start']);
  });
}
