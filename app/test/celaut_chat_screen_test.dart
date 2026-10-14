import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/tunnel_http.dart';
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

  @override
  Future<void> sync() async {}

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

class _Wallets implements FullWallets {
  _Wallets({required this.full});

  final bool full;

  @override
  Future<List<PayerWallet>> payers() async =>
      full ? [const PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 1, open: true)] : const [];

  @override
  Future<String?> loadDefault() async => null;

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async => true;
}

void main() {
  late _FakeChat chat;
  late List<String> stops;
  late bool closed;

  Future<void> open(WidgetTester tester, {bool fullWallet = true}) async {
    stops = [];
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      instanceId: 'i1',
                      port: 1,
                      chat: chat,
                      http: TunnelHttp(),
                      wallets: _Wallets(full: fullWallet),
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
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, '');
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

  testWidgets('leaving asks, and "Stay" keeps the screen', (tester) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Leave the conversation?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-stay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-input')), findsOneWidget);
    expect(stops, isEmpty);
    expect(closed, isFalse);
  });

  testWidgets('"Leave it running" closes the screen and does not stop the instance', (tester) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-leave-running')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(stops, isEmpty);
  });

  testWidgets('"Stop the instance" stops it, shows the refund and closes the screen', (tester) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-stop')));
    await tester.pumpAndSettle();
    expect(stops, ['i1']);
    expect(closed, isTrue);
    expect(find.textContaining('Refund'), findsOneWidget);
  });

  testWidgets('stop needs a full wallet: without one it stays and stops nothing', (tester) async {
    await open(tester, fullWallet: false);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-stop')));
    await tester.pumpAndSettle();
    expect(stops, isEmpty);
    expect(closed, isFalse);
    expect(find.byKey(const Key('chat-error')), findsOneWidget);
  });
}
