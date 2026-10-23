import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/attachment_picker.dart';
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

  /// The reads fail while this is true, as when the service is not up yet.
  bool broken = false;

  @override
  Future<void> sync() async {
    if (broken) throw const ChatException(ChatErrorKind.unreachable);
  }

  @override
  Future<void> syncWhenStarted(
          {Duration limit = const Duration(minutes: 2), Future<void> Function(Duration)? wait}) =>
      starting?.future ?? Future.value();

  /// Holds [send] until it completes: a slow service.
  Completer<void>? gate;

  /// The kinds that the fake service accepts.
  Set<String> kinds = const {};

  @override
  Set<String> get accepts => broken ? const {} : kinds;

  /// The files of each send.
  final sentFiles = <List<OutgoingAttachment>>[];

  /// The bytes that [readAttachment] gives.
  Uint8List fileBytes = Uint8List(0);

  /// Holds [readAttachment] until it completes.
  Completer<void>? fileGate;

  /// The next reads of a file fail this many times.
  int failReads = 0;

  @override
  Future<Uint8List> readAttachment(int seq, int index) async {
    await fileGate?.future;
    if (failReads > 0) {
      failReads--;
      throw const ChatException(ChatErrorKind.unreachable);
    }
    return fileBytes;
  }

  @override
  Future<void> send(String text, {List<OutgoingAttachment> attachments = const []}) async {
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(text);
    sentFiles.add(attachments);
    _messages
      ..add(ChatMessage(
        seq: _messages.length,
        role: 'user',
        text: text,
        attachments: [
          for (final f in attachments)
            ChatAttachment(kind: f.kind!, mime: f.mime, size: f.bytes.length, name: f.name),
        ],
      ))
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
  Future<List<PayerWallet>> payers() async => full
      ? [const PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 1, open: true)]
      : const [];

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
  alias: '',
);

void main() {
  late _FakeChat chat;
  late List<String> stops;
  late bool closed;
  late _FakeKeepAlive keepAlive;
  late ConversationNotes notes;
  late Future<List<OutgoingAttachment>> Function(Set<String>) pick;
  Set<String>? pickedKinds;

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
                      pickFiles: (kinds, existing) async {
                        pickedKinds = kinds;
                        return selectAttachments(await pick(kinds), existing);
                      },
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

  setUp(() {
    chat = _FakeChat();
    pick = (_) async => const [];
    pickedKinds = null;
  });

  // A PNG of one pixel.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  testWidgets('a slow answer shows the message at once, the dots, then the seconds',
      (tester) async {
    chat.gate = Completer<void>();
    await open(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), 'think hard');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    // The message is on screen before the service answers, and the field is free.
    expect(find.byKey(const Key('chat-flying')), findsOneWidget);
    expect(find.text('think hard'), findsOneWidget);
    expect(find.text(appL10n.chatSending), findsOneWidget);
    expect(find.byKey(const Key('chat-typing')), findsOneWidget);
    expect(find.byKey(const Key('chat-waited')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, '');
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).enabled, isNot(false));

    await tester.pump(const Duration(seconds: 6));
    expect(find.text(appL10n.chatWaitingSeconds(6)), findsOneWidget);

    chat.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-flying')), findsNothing);
    expect(find.byKey(const Key('chat-typing')), findsNothing);
    expect(find.text('think hard'), findsOneWidget);
    expect(find.text('echo: think hard'), findsOneWidget);
  });

  testWidgets('a failed slow send gives the text back, with what the user wrote meanwhile',
      (tester) async {
    chat.gate = Completer<void>();
    chat.failWith = const ChatException(ChatErrorKind.busy);
    await open(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), 'first');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('chat-input')), 'second');
    chat.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-flying')), findsNothing);
    expect(find.text(appL10n.chatErrorBusy), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text,
        'first\nsecond');
  });

  testWidgets('a service that accepts text only has no attach button', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('chat-attach')), findsNothing);
  });

  testWidgets('a file is picked, shown as a chip, removed, and sent with no text', (tester) async {
    chat.kinds = {'image'};
    chat.fileBytes = Uint8List.fromList(png);
    pick = (_) async =>
        [OutgoingAttachment(mime: 'image/png', bytes: Uint8List.fromList(png), name: 'dot.png')];
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(pickedKinds, {'image'});
    expect(find.byKey(const Key('chat-pending-0')), findsOneWidget);
    expect(find.text('dot.png'), findsOneWidget);

    // Remove it, then pick it again.
    await tester.tap(find.byTooltip(appL10n.chatAttachmentRemove));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending')), findsNothing);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();

    // No text: the file alone is enough to send.
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(chat.sent, ['']);
    expect(chat.sentFiles.single.single.name, 'dot.png');
    expect(find.byKey(const Key('chat-pending')), findsNothing);
    expect(find.byKey(const Key('chat-file-0-0')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a send that fails keeps the files', (tester) async {
    chat.kinds = {'audio'};
    pick = (_) async => [OutgoingAttachment(mime: 'audio/wav', bytes: Uint8List(4), name: 'a.wav')];
    chat.failWith = const ChatException(ChatErrorKind.unsupportedMedia);
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.chatErrorUnsupportedMedia), findsOneWidget);
    expect(find.byKey(const Key('chat-pending-0')), findsOneWidget);
  });

  OutgoingAttachment wav(String name, {int size = 4}) =>
      OutgoingAttachment(mime: 'audio/wav', bytes: Uint8List(size), name: name);

  testWidgets('what the pick leaves out is told in one message, and at most 4 files stay', (
    tester,
  ) async {
    chat.kinds = {'audio'};
    pick = (_) async => [
          for (var i = 0; i < 5; i++) wav('$i.wav'),
          wav('empty.wav', size: 0),
        ];
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending-3')), findsOneWidget);
    expect(find.byKey(const Key('chat-pending-4')), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('${appL10n.chatSkippedInvalid(1)}. ${appL10n.chatSkippedTooMany(1)}'),
      findsOneWidget,
    );
    // Four files are the most: the button waits until one is removed.
    expect(tester.widget<IconButton>(find.byKey(const Key('chat-attach'))).onPressed, isNull);
  });

  testWidgets('a file that is already attached is skipped, and the user is told', (tester) async {
    chat.kinds = {'audio'};
    pick = (_) async => [wav('a.wav')];
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending-0')), findsOneWidget);
    expect(find.byKey(const Key('chat-pending-1')), findsNothing);
    expect(find.text(appL10n.chatSkippedDuplicate(1)), findsOneWidget);
  });

  testWidgets('a long file name is cut in the chip', (tester) async {
    chat.kinds = {'audio'};
    pick = (_) async => [wav('${'voice-note-' * 10}.wav')];
    await open(tester);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('chat-pending-0'))).width, lessThan(300));
  });

  testWidgets('after a first read that failed, Retry reads again and the attach button works', (
    tester,
  ) async {
    chat.kinds = {'audio'};
    chat.broken = true;
    pick = (_) async => [wav('a.wav')];
    await open(tester);
    expect(find.text(appL10n.chatErrorUnreachable), findsOneWidget);
    // The button stays, so the user is not locked out; the service is still down.
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending')), findsNothing);
    expect(find.text(appL10n.chatErrorUnreachable), findsOneWidget);

    chat.broken = false;
    await tester.tap(find.byKey(const Key('chat-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-error')), findsNothing);
    expect(find.byKey(const Key('chat-retry')), findsNothing);
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending-0')), findsOneWidget);
  });

  testWidgets('attach reads again first when the kinds are not known', (tester) async {
    chat.kinds = {'audio'};
    chat.broken = true;
    pick = (_) async => [wav('a.wav')];
    await open(tester);
    chat.broken = false;
    await tester.tap(find.byKey(const Key('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending-0')), findsOneWidget);
    expect(find.byKey(const Key('chat-error')), findsNothing);
  });

  testWidgets('an image has its final height while it loads, and a name for the screen reader', (
    tester,
  ) async {
    chat = _FakeChat(history: const [
      ChatMessage(
        seq: 0,
        role: 'assistant',
        text: '',
        attachments: [ChatAttachment(kind: 'image', mime: 'image/png', size: 3, name: 'dot.png')],
      ),
    ]);
    chat.fileBytes = Uint8List.fromList(png);
    chat.fileGate = Completer<void>();
    // The progress indicator turns until the file loads: open without a settle.
    await open(tester, starting: true);
    final file = find.byKey(const Key('chat-file-0-0'));
    final loading = tester.getSize(file).height;
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    chat.fileGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.getSize(file).height, loading);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'dot.png');
    expect(image.gaplessPlayback, isTrue);
    expect(image.image, isA<ResizeImage>());
  });

  testWidgets('a file that did not load loads again with a tap', (tester) async {
    chat = _FakeChat(history: const [
      ChatMessage(
        seq: 0,
        role: 'assistant',
        text: '',
        attachments: [ChatAttachment(kind: 'image', mime: 'image/png', size: 3)],
      ),
    ]);
    chat.fileBytes = Uint8List.fromList(png);
    chat.failReads = 1;
    await open(tester);
    expect(find.text(appL10n.chatAttachmentFailed), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-file-retry')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.chatAttachmentFailed), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).semanticLabel, appL10n.chatImage);
  });

  testWidgets('the audio row is a button for the screen reader, with its name', (tester) async {
    final handle = tester.ensureSemantics();
    chat = _FakeChat(history: const [
      ChatMessage(
        seq: 0,
        role: 'assistant',
        text: '',
        attachments: [
          ChatAttachment(kind: 'audio', mime: 'audio/mpeg', size: 4, name: 'a/../song.mp3')
        ],
      ),
    ]);
    await open(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('song.mp3. ${appL10n.chatAttachmentShare}')),
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        label: 'song.mp3. ${appL10n.chatAttachmentShare}',
      ),
    );
    handle.dispose();
  });

  testWidgets('an audio file shows its name in the bubble', (tester) async {
    chat = _FakeChat(history: const [
      ChatMessage(
        seq: 0,
        role: 'assistant',
        text: 'listen',
        attachments: [ChatAttachment(kind: 'audio', mime: 'audio/mpeg', size: 4, name: 'song.mp3')],
      ),
    ]);
    await open(tester);
    expect(find.text('song.mp3'), findsOneWidget);
    expect(find.text('listen'), findsOneWidget);
    expect(find.byIcon(Icons.audiotrack), findsOneWidget);
  });

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

  testWidgets('the bar has the name, and under it the state, the node and the cost',
      (tester) async {
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
    expect(tester.widget<SelectableText>(find.byKey(const Key('info-node'))).data,
        'node.example:53460');
    expect(tester.widget<SelectableText>(find.byKey(const Key('info-slot'))).data,
        appL10n.chatsInfoChatSlot);
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

  testWidgets('back goes to the list at once: no question, and the instance runs on',
      (tester) async {
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

  testWidgets('the keep-alive starts when the screen opens and runs while it is open',
      (tester) async {
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
