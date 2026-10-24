import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/attachment_picker.dart';
import '../../celaut/audio_recorder.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/chat_client.dart';
import '../../celaut/chat_done_watcher.dart';
import '../../celaut/chat_notifier.dart';
import '../../celaut/chat_prefs.dart';
import '../../celaut/chat_segments.dart';
import '../../celaut/conversation_keep_alive.dart';
import '../../celaut/conversations.dart';
import '../../celaut/payers.dart';
import '../../celaut/pinned_position.dart';
import '../../celaut/typewriter.dart';
import '../../l10n/l10n.dart';
import 'chat_floating.dart';
import 'html_widget.dart';
import 'instance_actions.dart';
import 'instance_info_screen.dart';

/// The conversation with a running instance that follows the chat convention
/// (`docs/celaut/chat.md`), as a chat in a messenger (`docs/celaut/ui-chat-first.md`).
/// The service keeps the history; this screen reads it from the start each time it
/// opens, keeps a copy in memory, and writes nothing to the Celaut database. The last
/// message goes to the notes of the list of conversations, in memory.
///
/// A send does not wait for the answer, so the user can send many messages one after the
/// other. The screen shows an answer that grows, with its reasoning apart from its text,
/// while the service makes it. The events of the stream of the client ([ChatClient.streaming])
/// bring the news. While no stream is open, the screen reads the conversation every few
/// seconds ([ChatClient.sync]).
///
/// The bar has the name of the service, and under it the state, the node and the cost so
/// far. A tap on the name, or ⋮ then Info, opens the info page of the instance; ⋮ also has
/// Stop. Back goes to the list: the instance runs on, and the list keeps it.
///
/// The bar and the input float over the list, as blurred and translucent surfaces; the
/// list scrolls behind them. The messages of the service have no bubble. The text of an
/// answer that grows shows a few characters at a time ([Typewriter]), with a small
/// vibration, while the screen is in front.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.instance,
    required this.port,
    this.chat,
    this.wallets = const AppFullWallets(),
    this.loadStatus,
    this.stopInstance,
    this.keepAlive,
    this.starting = false,
    this.notes,
    this.pickFiles,
    this.pollEvery,
    this.typewriter = true,
    this.haptic,
    this.recorder,
    this.notifier,
    this.watcher,
  });

  /// Records the voice messages. Null: the microphone of the phone, made when the user
  /// first taps the record button. Tests give their own.
  final AudioRecorderService? recorder;

  /// Tells the user, with a notice of the system, that an answer is done while the chat is
  /// not in front. Null: [chatNotifier]. Tests give their own.
  final ChatNotifier? notifier;

  /// Shares with the screen the list of the answers that got a notice, and takes the chat
  /// when the screen closes with an answer pending. Null: [chatDoneWatcher]. Tests give
  /// their own.
  final ChatDoneWatcher? watcher;

  /// Show the text of an answer that grows a few characters at a time. False: it shows
  /// as it arrives. Tests give false when they do not look at the effect.
  final bool typewriter;

  /// The small vibration for the new characters. Null: [HapticFeedback.selectionClick].
  /// Tests give their own.
  final VoidCallback? haptic;

  /// How often the screen reads the conversation while the client has no stream. Null:
  /// [ChatClient.pollWaiting] while it waits for an answer, and [ChatClient.pollIdle]
  /// otherwise. Tests give their own.
  final Duration? pollEvery;

  /// The instance has just started: the screen waits until the service answers
  /// (`ChatClient.syncWhenStarted`), and says that it starts.
  final bool starting;

  /// The instance, from the database of the app (`celautInstances`).
  final InstanceListView instance;

  /// The local port of the chat slot of the instance (`celautOpenTunnel`).
  final int port;

  /// The client of the convention. Tests give their own.
  final ChatClient? chat;

  /// The full wallets of the app. Stop needs one that is open. Tests give their own.
  final FullWallets wallets;

  /// Read the cost of the instance. Tests give their own.
  final Future<InstanceStatusView> Function(String instanceId)? loadStatus;

  /// Stop the instance. Tests give their own.
  final Future<StopView> Function(String instanceId)? stopInstance;

  /// Keeps the app alive in the background while the screen is open. Tests give their
  /// own.
  final ConversationKeepAlive? keepAlive;

  /// The notes of the list of conversations. Null: the notes of the app.
  final ConversationNotes? notes;

  /// Let the user pick the files of a message, for the kinds that the service accepts and
  /// with the files that the message already has. Null: the file picker of the system.
  /// Tests give their own.
  final Future<PickedAttachments> Function(
    Set<String> kinds,
    List<OutgoingAttachment> existing,
  )? pickFiles;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// The text and the reasoning of one answer that grows, as they show.
class _Reveal {
  _Reveal(String text, String reasoning)
      : text = Typewriter(initial: text),
        reasoning = Typewriter(initial: reasoning);

  final Typewriter text;
  final Typewriter reasoning;

  bool get done => text.done && reasoning.done;
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final ChatClient _chat = widget.chat ?? ChatClient(port: widget.port);
  late final ConversationKeepAlive _keepAlive = widget.keepAlive ?? ChannelConversationKeepAlive();
  late final ConversationNotes _notes = widget.notes ?? conversationNotes;
  late final ChatDoneWatcher _watcher = widget.watcher ?? chatDoneWatcher;

  /// The instance stopped from this screen: the watcher has nothing to read.
  bool _stoppedHere = false;

  /// The messages that are on their way: each shows as a bubble at once, until the
  /// service has it.
  final List<({String text, List<OutgoingAttachment> files})> _flying = [];

  /// Seconds that the screen has waited for an answer. A tick each second while it waits.
  int _waited = 0;
  Timer? _ticker;

  /// The timer of the next read of the conversation.
  Timer? _poll;
  bool _wasWaiting = false;
  final List<OutgoingAttachment> _pending = [];
  bool _stopping = false;
  late bool _waitingStart = widget.starting;
  ChatErrorKind? _error;
  String? _costMu;

  /// The instance, with the name that the user may give it on its info page.
  late InstanceListView _instance = widget.instance;

  String get _id => widget.instance.instanceId;

  /// The answers that grow while the screen is open, by `seq`, as they show.
  final Map<int, _Reveal> _reveals = {};

  /// The first read worked: what it had shows at once. A first read that failed does not
  /// count, so the history that a later read brings shows at once too.
  bool _loaded = false;

  /// The first read is over: the changes of the client show from now on.
  bool _opened = false;

  /// The `seq` of the messages that the screen has seen.
  final Set<int> _known = {};
  bool _foreground = true;
  late final Ticker _revealTicker;
  Duration _lastTick = Duration.zero;
  HapticPacer _pacer = HapticPacer();

  /// The `seq` of the message that the chat pins now, or null (`pinned_position.dart`).
  int? _pinnedSeq;
  bool _pinExpanded = false;

  /// Keys of the pinned messages, to read where they are on the screen.
  final Map<int, GlobalKey> _pinKeys = {};

  /// The first message that the list has built.
  int _firstBuilt = -1;

  /// The status of each message at the last read, to see which answers just got done.
  final Map<int, String> _statuses = {};
  bool _baselined = false;

  AudioRecorderService? _recorderService;
  AudioRecorderService get _mic => _recorderService ??= widget.recorder ?? RecordAudioRecorder();
  StreamSubscription<Duration>? _recSub;
  bool _recording = false;
  bool _recStarting = false;
  Duration _recElapsed = Duration.zero;

  /// The height of the input, which floats over the list, so the list leaves room.
  double _bottomHeight = 72;

  /// The least height of the bar above, which floats too (without its margin).
  static const _headerMin = 52.0;

  /// The height of the bar above with the margins and the status bar, as the screen
  /// measures it: a large text size makes it taller. Null before the first layout.
  double? _headerExtent;

  /// Where the bar above ends.
  double get _headerBottom => _headerExtent ?? MediaQuery.paddingOf(context).top + _headerMin + 8;

  /// The height of the pinned banner while it shows, or zero. The list leaves room for it,
  /// so no message is under it.
  double _bannerHeight = 0;

  /// How far the text fades before the bar above and the bar below, in logical pixels.
  static const _fadeExtent = 28.0;

  /// The list fades out where it reaches the bars that float over it: [top] is where the
  /// bar above (and the pinned banner) end, [bottom] the height of the input at the foot.
  /// The text is whole beyond [_fadeExtent] from each, and gone at the bar itself.
  Widget _fadeEdges({required double top, required double bottom, required Widget child}) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        if (!h.isFinite || h <= 0) return child;
        double at(double y) => (y / h).clamp(0.0, 1.0).toDouble();
        final s0 = at(top - 4);
        final s1 = at(top + _fadeExtent) < s0 ? s0 : at(top + _fadeExtent);
        final s3 = at(h - bottom) < s1 ? s1 : at(h - bottom);
        final s2 = at(h - bottom - _fadeExtent).clamp(s1, s3).toDouble();
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            stops: [s0, s1, s2, s3],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }

  /// A message is on its way, or the service still makes an answer.
  bool get _waiting => _flying.isNotEmpty || _chat.awaitingAnswer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revealTicker = createTicker(_onRevealTick);
    _scroll.addListener(_updatePinned);
    _chat.addListener(_onChat);
    unawaited(_keepAlive.start());
    // The screen reads the chat now: a watch that a former screen left stops.
    _watcher.release(_id);
    _open();
  }

  /// A running instance can have messages already: read them, then the cost.
  Future<void> _open() async {
    // The wait for a service that just started goes on with the screen off.
    if (widget.starting) unawaited(_keepAlive.waiting(true));
    var read = false;
    try {
      await (widget.starting ? _chat.syncWhenStarted() : _chat.sync());
      read = true;
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.kind);
    } finally {
      if (widget.starting) unawaited(_keepAlive.waiting(false));
    }
    // Answered or not, the wait of the start is over: the list shows the check of the
    // node again.
    _notes.answered(_id);
    _afterRead(read: read);
    _opened = true;
    if (mounted) setState(() => _waitingStart = false);
    _syncTicker();
    _schedulePoll();
    await _refreshCost();
    _scrollToEnd();
  }

  /// Use the messages that a read gave. [read] is true if the read worked: the first one
  /// that works gives the history, which shows at once.
  void _afterRead({required bool read}) {
    _notes.saw(_id, _chat.messages);
    _trackReveals();
    _checkDone();
    if (read) _loaded = true;
  }

  /// The ticker of the seconds runs only while the screen waits for an answer.
  void _syncTicker() {
    if (_waiting && _ticker == null) {
      _waited = 0;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _waited++);
      });
    } else if (!_waiting && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!mounted) return;
    // The events of the open stream bring the news: no read is needed.
    if (_chat.streaming) return;
    final every = widget.pollEvery ?? (_waiting ? ChatClient.pollWaiting : ChatClient.pollIdle);
    _poll = Timer(every, _pollOnce);
  }

  /// The stream of the client changed the messages: show them.
  void _onChat() {
    if (!mounted || !_opened || _waitingStart) return;
    final atEnd =
        !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    if (_error == ChatErrorKind.unreachable && _chat.streaming) _error = null;
    // The stream failed 3 times at its first event and stopped (section 6.5).
    _error ??= _chat.streamError?.kind;
    _afterRead(read: true);
    setState(() {});
    _syncTicker();
    _updatePinned();
    if (atEnd) _scrollToEnd();
    if (_wasWaiting && !_waiting) unawaited(_refreshCost());
    _wasWaiting = _waiting;
    _schedulePoll();
  }

  /// Read the new messages and the growth of the open ones, then plan the next read. While
  /// the stream is open the events do this, and the screen does not read.
  Future<void> _pollOnce() async {
    if (!mounted) return;
    if (!_waitingStart && !_stopping && !_chat.streaming) {
      final atEnd =
          !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
      var read = false;
      try {
        await _chat.sync();
        read = true;
        if (mounted && _error == ChatErrorKind.unreachable) setState(() => _error = null);
      } on ChatException catch (e) {
        if (mounted) setState(() => _error = e.kind);
      }
      if (!mounted) return;
      _afterRead(read: read);
      setState(() {});
      _syncTicker();
      if (atEnd) _scrollToEnd();
      if (_wasWaiting && !_waiting) unawaited(_refreshCost());
      _wasWaiting = _waiting;
    }
    _schedulePoll();
  }

  Future<void> _refreshCost() async {
    try {
      final load = widget.loadStatus ?? ((id) => celautInstanceStatus(instanceId: id));
      final status = await load(_id);
      if (mounted) setState(() => _costMu = status.costSoFarMu);
    } on CelautError {
      // The cost stays as it was: the conversation does not depend on it.
    }
  }

  /// Read the history again, after a first read that failed.
  Future<void> _retry() async {
    setState(() => _error = null);
    var read = false;
    try {
      await _chat.sync();
      read = true;
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.kind);
    }
    _afterRead(read: read);
    if (mounted) setState(() {});
    _syncTicker();
    _scrollToEnd();
  }

  Future<void> _attach() async {
    // The first read failed: the kinds that the service accepts are not known yet.
    if (_chat.accepts.isEmpty) await _retry();
    if (!mounted || _chat.accepts.isEmpty) return;
    final pick = widget.pickFiles ?? pickAttachments;
    final picked = await pick(_chat.accepts, List.unmodifiable(_pending));
    if (!mounted) return;
    if (picked.skipped > 0) {
      final l10n = context.l10n;
      final text = [
        if (picked.duplicates > 0) l10n.chatSkippedDuplicate(picked.duplicates),
        if (picked.invalid > 0) l10n.chatSkippedInvalid(picked.invalid),
        if (picked.tooMany > 0) l10n.chatSkippedTooMany(picked.tooMany),
      ].join('. ');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
    if (picked.files.isEmpty) return;
    setState(() {
      _error = null;
      _pending.addAll(picked.files);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _stopping) return;
    final files = List.of(_pending);
    final flying = (text: text, files: files);
    setState(() {
      _error = null;
      _flying.add(flying);
      // The field is free at once: the user can write the next message, and send it,
      // while the service answers.
      _input.clear();
      _pending.clear();
    });
    _syncTicker();
    _scrollToEnd();
    try {
      await _chat.send(text, attachments: files);
    } on ChatException catch (e) {
      // The text and the files come back, so the user can send them again. What the
      // user has written meanwhile stays: the old text goes before it.
      if (mounted) {
        setState(() {
          _error = e.kind;
          _input.text = _input.text.isEmpty ? text : '$text\n${_input.text}';
          _pending.insertAll(0, files);
        });
      }
    } finally {
      _flying.remove(flying);
      _afterRead(read: false);
      if (mounted) setState(() {});
      _syncTicker();
    }
    _wasWaiting = _waiting;
    // The service has the message: read the answer soon, at the pace of a wait.
    _schedulePoll();
    _scrollToEnd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A short pause (a system dialog, the app switcher) is "inactive": the chat is still in
    // front then, and gets no notice.
    _foreground = state != AppLifecycleState.paused && state != AppLifecycleState.hidden;
  }

  /// Follow the answers that grow: each one shows its text with a [Typewriter]. What the
  /// first read had shows at once, and so does an answer that is done and was never open
  /// while the screen was in front.
  void _trackReveals() {
    final newSeqs = <int>{};
    for (final m in _chat.messages) {
      if (_known.add(m.seq)) newSeqs.add(m.seq);
    }
    if (!widget.typewriter) return;
    for (final m in _chat.messages) {
      if (m.fromUser) continue;
      var r = _reveals[m.seq];
      if (r == null) {
        // An answer that came whole between two reads shows by typing too, if it is new.
        final fresh = _loaded && newSeqs.contains(m.seq);
        if (!m.isOpen && !fresh) continue;
        r = _reveals[m.seq] = _loaded ? _Reveal('', '') : _Reveal(m.text, m.reasoning);
      }
      r.text.setTarget(m.text);
      r.reasoning.setTarget(m.reasoning);
    }
    _reveals.removeWhere((seq, r) {
      final open = _chat.messages.any((m) => m.seq == seq && m.isOpen);
      return !open && r.done;
    });
    if (_reveals.values.any((r) => !r.done) && !_revealTicker.isActive) {
      _lastTick = Duration.zero;
      _pacer = HapticPacer();
      _revealTicker.start();
    }
  }

  void _onRevealTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    final atEnd =
        !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    var shown = 0;
    for (final r in _reveals.values) {
      shown += r.text.tick(dt) + r.reasoning.tick(dt);
    }
    if (shown > 0) {
      if (_pacer.feed(shown, elapsed) &&
          _foreground &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        (widget.haptic ?? HapticFeedback.selectionClick)();
      }
      setState(() {});
      if (atEnd) _scrollToEnd();
    }
    // Wait for the next read if all that came is shown.
    if (_reveals.values.every((r) => r.done)) {
      _revealTicker.stop();
      _trackReveals();
    }
  }

  /// Tell the user, with a notice of the system, about the answer that just got done, if
  /// the chat is not in front: the app is in the background, or another screen covers it.
  /// The first read only writes down the status of the history. A chat that the user
  /// muted gets no notice ([ChatNotifier]). A message gets one notice only: the screen and
  /// the watcher share the list of them ([ChatDoneWatcher.claim]). When the screen closes
  /// with an answer pending, the watcher goes on ([ChatDoneWatcher.handOver]). If many answers get done between two reads,
  /// the user gets one notice for the chat.
  void _checkDone() {
    // Nothing was read yet: what the next read brings is the history, not news.
    if (_error != null && !_baselined) return;
    final news = _baselined;
    _baselined = true;
    final done = <int>[];
    for (final m in _chat.messages) {
      final before = _statuses[m.seq];
      _statuses[m.seq] = m.status;
      if (news &&
          !m.fromUser &&
          m.status == ChatMessage.statusDone &&
          before != ChatMessage.statusDone) done.add(m.seq);
    }
    if (done.isEmpty || !mounted) return;
    final inFront = _foreground && (ModalRoute.of(context)?.isCurrent ?? true);
    if (inFront) return;
    // The watcher gives the notice of a message that it has seen too: one notice only.
    var fresh = false;
    for (final seq in done) {
      if (_watcher.claim(_id, seq)) fresh = true;
    }
    if (!fresh) return;
    // The body does not have the answer: the lock screen can show it to others.
    unawaited(
      (widget.notifier ?? chatNotifier).notifyDone(
        instanceId: _id,
        title: instanceTitle(_instance),
        body: context.l10n.chatNotifyDoneBody,
      ),
    );
  }

  /// Find the pinned message that the chat anchors under the bar, from where the pinned
  /// messages are on the screen ([pinnedIndexAbove]).
  void _updatePinned() {
    if (!mounted) return;
    final messages = _chat.messages;
    final pinned = [
      for (var i = 0; i < messages.length; i++)
        if (messages[i].pinned) i,
    ];
    int? found;
    if (pinned.isNotEmpty && _scroll.hasClients) {
      // The bars cover the top of the list: a message is above it when its top is. The
      // banner, while it shows, pushes the list down by its height, so it is part of the
      // cover and the choice does not flip when the banner shows or hides.
      final cover = _headerBottom + _bannerHeight;
      RenderObject? boxOf(int i) {
        final box = _pinKeys[messages[i].seq]?.currentContext?.findRenderObject();
        return box == null || !box.attached ? null : box;
      }

      double? topOf(int i) {
        final box = boxOf(i);
        if (box == null) return null;
        final viewport = RenderAbstractViewport.maybeOf(box);
        if (viewport == null) return null;
        return viewport.getOffsetToReveal(box, 0).offset - _scroll.position.pixels - cover;
      }

      found = pinnedIndexAbove(
        pinned: pinned,
        firstBuilt: _firstBuilt,
        count: messages.length,
        topOf: topOf,
        bottomOf: (i) {
          final top = topOf(i);
          final box = boxOf(i);
          return top == null || box is! RenderBox ? null : top + box.size.height;
        },
      );
    }
    final seq = found == null ? null : messages[found].seq;
    if (seq != _pinnedSeq) {
      setState(() {
        _pinnedSeq = seq;
        _pinExpanded = false;
        if (seq == null) _bannerHeight = 0;
      });
    }
  }

  Future<void> _startRecording() async {
    if (_stopping || _recording || _recStarting) return;
    _recStarting = true;
    final bool ok;
    try {
      ok = await _mic.start();
    } finally {
      _recStarting = false;
    }
    if (!mounted) {
      await _mic.cancel();
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.chatMicDenied)));
      return;
    }
    _recSub = _mic.elapsed.listen(
      (d) {
        if (mounted) setState(() => _recElapsed = d);
      },
      // The stream ends by itself only at the size limit: attach what the recorder has.
      onDone: () {
        if (mounted && _recording) unawaited(_finishRecording(limit: true));
      },
    );
    setState(() {
      _error = null;
      _recording = true;
      _recElapsed = Duration.zero;
    });
  }

  /// Stop the recording and keep it as a file of the next message, as a picked file.
  /// [limit]: the recorder stopped by itself at the size limit. The user gets a notice if
  /// the limit stopped the recording, or if the message has no room for the file.
  Future<void> _finishRecording({bool limit = false}) async {
    unawaited(_recSub?.cancel());
    _recSub = null;
    final file = await _mic.stop();
    if (!mounted) return;
    final full = file != null && _pending.length >= ChatClient.maxAttachments;
    setState(() {
      _recording = false;
      if (file != null && !full) _pending.add(file);
    });
    final l10n = context.l10n;
    final notice = full
        ? l10n.chatSkippedTooMany(1)
        : limit
            ? l10n.chatMicLimit
            : null;
    if (notice != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _cancelRecording() async {
    unawaited(_recSub?.cancel());
    _recSub = null;
    await _mic.cancel();
    if (mounted) setState(() => _recording = false);
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleMute() async {
    await chatPrefs.setMuted(_id, !chatPrefs.isMuted(_id));
    if (mounted) setState(() {});
  }

  /// A file finished to load: keep the end in view if the list was at the end.
  void _fileLoaded() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels < 80) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// The message has something to show: text, reasoning or a file.
  static bool _hasContent(ChatMessage m) =>
      m.text.isNotEmpty || m.reasoning.isNotEmpty || m.attachments.isNotEmpty;

  /// Pin or unpin [m]. The client changes the message at once and gives it back if the
  /// call fails: the user sees the reason.
  Future<void> _togglePin(ChatMessage m) async {
    try {
      await _chat.setPinned(m, !m.pinned);
    } on ChatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_errorText(e.kind, pin: true))));
    }
  }

  Future<void> _copy(ChatMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.chatCopied)));
  }

  String _errorText(ChatErrorKind kind, {bool pin = false}) {
    final l10n = context.l10n;
    return switch (kind) {
      ChatErrorKind.unreachable => l10n.chatErrorUnreachable,
      ChatErrorKind.badAnswer => l10n.chatErrorBadAnswer,
      ChatErrorKind.historyFull => l10n.chatErrorHistoryFull,
      ChatErrorKind.storageFull => l10n.chatErrorStorageFull,
      ChatErrorKind.busy => l10n.chatErrorBusy,
      ChatErrorKind.unsupportedMedia => l10n.chatErrorUnsupportedMedia,
      ChatErrorKind.badRequest when !pin && _pending.isNotEmpty => l10n.chatErrorFile,
      ChatErrorKind.badRequest || ChatErrorKind.other => l10n.chatErrorOther,
    };
  }

  InstanceState get _state => _waitingStart
      ? InstanceState.starting
      : _error == ChatErrorKind.unreachable
          ? InstanceState.unreachable
          : InstanceState.running;

  /// The instance stopped: the local port is closed, so drop the kept-alive connection
  /// too, and go back to the list.
  void _closeStopped() {
    _stoppedHere = true;
    unawaited(_chat.close());
    unawaited(_keepAlive.stop());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    final done = await confirmAndStopInstance(
      context,
      _instance,
      wallets: widget.wallets,
      stop: widget.stopInstance,
      notes: _notes,
    );
    if (mounted) setState(() => _stopping = false);
    if (done != null) _closeStopped();
  }

  Future<void> _info() async {
    final stopped = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InstanceInfoScreen(
          instance: _instance,
          state: _state,
          costMu: _costMu,
          wallets: widget.wallets,
          stop: widget.stopInstance,
          notes: _notes,
          onRenamed: (renamed) {
            if (mounted) setState(() => _instance = renamed);
          },
        ),
      ),
    );
    if (stopped == true) _closeStopped();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revealTicker.dispose();
    _scroll.removeListener(_updatePinned);
    unawaited(_recSub?.cancel() ?? Future<void>.value());
    final recorder = _recorderService;
    if (recorder != null) {
      unawaited(recorder.cancel());
      if (recorder is RecordAudioRecorder) unawaited(recorder.dispose());
    }
    unawaited(_keepAlive.stop());
    // An answer is pending, and the user leaves: the watcher tells the user when it is
    // done. Without a first good read, the screen does not know the history to skip.
    if (!_stoppedHere && _baselined && _chat.awaitingAnswer) {
      _watcher.handOver(_instance, Map.of(_statuses));
    }
    _ticker?.cancel();
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    _chat.removeListener(_onChat);
    if (widget.chat == null) unawaited(_chat.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final messages = _chat.messages;
    // The dots show while the service has nothing to show yet for the answer.
    final typing = _waiting && !messages.any((m) => m.isOpen && _hasContent(m));
    final error = _error == null ? null : _errorText(_error!);
    final pinned =
        _pinnedSeq == null ? null : messages.where((m) => m.seq == _pinnedSeq).firstOrNull;
    final title = instanceTitle(_instance);
    final subtitle = [
      instanceStateText(context, _state),
      _instance.address,
      muOrUnknown(_costMu),
    ].join(' · ');
    final headerBottom = _headerBottom;
    final screen = MediaQuery.sizeOf(context).height;
    // The pinned banner takes a part of the chat area, not of the screen.
    final chatArea = chatAreaHeight(screen: screen, top: headerBottom, bottom: _bottomHeight);
    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: ConstrainedBox(
          // A large text size makes the bar taller.
          constraints: const BoxConstraints(minHeight: _headerMin),
          child: FloatingSurface(
            key: const Key('chat-header'),
            radius: 24,
            child: Row(
              children: [
                const BackButton(),
                Expanded(
                  child: InkWell(
                    key: const Key('chat-title'),
                    onTap: _info,
                    child: Row(
                      children: [
                        InstanceAvatar(instanceId: _id, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                key: const Key('chat-name'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                subtitle,
                                key: const Key('chat-cost'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (chatPrefs.isMuted(_id))
                  Tooltip(
                    message: l10n.chatMutedHint,
                    child: const Icon(
                      Icons.notifications_off_outlined,
                      key: Key('chat-muted'),
                      size: 18,
                    ),
                  ),
                PopupMenuButton<String>(
                  key: const Key('chat-menu'),
                  tooltip: l10n.chatsMenuMore,
                  enabled: !_stopping,
                  onSelected: (choice) => switch (choice) {
                    'stop' => _stop(),
                    'mute' => _toggleMute(),
                    _ => _info(),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const Key('chat-menu-info'),
                      value: 'info',
                      child: Text(l10n.chatsActionInfo),
                    ),
                    PopupMenuItem(
                      key: const Key('chat-menu-mute'),
                      value: 'mute',
                      child: Text(
                        chatPrefs.isMuted(_id) ? l10n.chatUnmute : l10n.chatMute,
                      ),
                    ),
                    PopupMenuItem(
                      key: const Key('chat-menu-stop'),
                      value: 'stop',
                      child: Text(l10n.chatStop),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final inputBar = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: FloatingSurface(
          key: const Key('chat-input-bar'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            key: const Key('chat-error'),
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ),
                      if (_error == ChatErrorKind.unreachable)
                        TextButton(
                          key: const Key('chat-retry'),
                          onPressed: _retry,
                          child: Text(l10n.commonRetry),
                        ),
                    ],
                  ),
                ),
              if (_pending.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    key: const Key('chat-pending'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    children: [
                      for (var i = 0; i < _pending.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InputChip(
                            key: Key('chat-pending-$i'),
                            avatar: Icon(
                              _pending[i].kind == 'audio' ? Icons.audiotrack : Icons.image,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                _pending[i].name ?? _pending[i].mime,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            deleteButtonTooltipMessage: l10n.chatAttachmentRemove,
                            onDeleted: () => setState(() => _pending.removeAt(i)),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                child: _recording
                    ? Row(
                        children: [
                          IconButton(
                            key: const Key('chat-record-cancel'),
                            tooltip: l10n.chatMicCancel,
                            onPressed: _cancelRecording,
                            icon: const Icon(Icons.delete_outline),
                          ),
                          Icon(
                            Icons.fiber_manual_record,
                            size: 14,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _clock(_recElapsed),
                              key: const Key('chat-record-time'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            key: const Key('chat-record-done'),
                            tooltip: l10n.chatMicDone,
                            onPressed: _finishRecording,
                            icon: const Icon(Icons.check),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          if (_chat.accepts.isNotEmpty || _error == ChatErrorKind.unreachable)
                            IconButton(
                              key: const Key('chat-attach'),
                              tooltip: l10n.chatAttach,
                              onPressed: _stopping || _pending.length >= ChatClient.maxAttachments
                                  ? null
                                  : _attach,
                              icon: const Icon(Icons.attach_file),
                            ),
                          Expanded(
                            child: TextField(
                              key: const Key('chat-input'),
                              controller: _input,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: l10n.chatInputHint,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          // As in a messenger: the microphone takes the place of Send while
                          // there is nothing to send, if the service takes audio.
                          ListenableBuilder(
                            listenable: _input,
                            builder: (context, _) => _chat.accepts.contains('audio') &&
                                    _input.text.trim().isEmpty &&
                                    _pending.isEmpty
                                ? IconButton(
                                    key: const Key('chat-mic'),
                                    tooltip: l10n.chatMic,
                                    onPressed: _stopping ? null : _startRecording,
                                    icon: const Icon(Icons.mic_none),
                                  )
                                : IconButton(
                                    key: const Key('chat-send'),
                                    tooltip: l10n.chatSend,
                                    onPressed: _stopping ? null : _send,
                                    icon: const Icon(Icons.send),
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: ListenableBuilder(
        listenable: chatPrefs,
        builder: (context, _) {
          final base = chatPrefs.textStyle;
          return Stack(
            children: [
              ChatBackdrop(id: chatPrefs.background(_id)),
              Positioned.fill(
                child: messages.isEmpty && _flying.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            headerBottom + 24,
                            24,
                            _bottomHeight + 24,
                          ),
                          child: _waitingStart
                              ? Column(
                                  key: const Key('chat-starting'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text(
                                      l10n.chatStarting,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                )
                              : Text(
                                  l10n.chatEmpty,
                                  textAlign: TextAlign.center,
                                ),
                        ),
                      )
                    : _fadeEdges(
                        top: headerBottom + _bannerHeight,
                        bottom: _bottomHeight,
                        child: ListView.custom(
                        key: const Key('chat-messages'),
                        controller: _scroll,
                        // Room for the bars that float over the list.
                        padding: EdgeInsets.fromLTRB(
                          16,
                          headerBottom + _bannerHeight + 8,
                          16,
                          _bottomHeight + 8,
                        ),
                        childrenDelegate: _LayoutDelegate(
                          childCount: messages.length + _flying.length + (typing ? 1 : 0),
                          onLayout: (first) {
                            _firstBuilt = first;
                            WidgetsBinding.instance.addPostFrameCallback((_) => _updatePinned());
                          },
                          (context, i) {
                            if (i < messages.length) {
                              final m = messages[i];
                              final reveal = _reveals[m.seq];
                              final bubble = _Bubble(
                                message: m,
                                scheme: scheme,
                                textStyle: base,
                                shownText: reveal?.text.text ?? m.text,
                                shownReasoning: reveal?.reasoning.text ?? m.reasoning,
                                html: chatPrefs.htmlWidgets,
                                read: _chat.readAttachment,
                                onLoaded: _fileLoaded,
                                onPin: _chat.canPin && m.id.isNotEmpty ? () => _togglePin(m) : null,
                                onCopy: () => _copy(m),
                              );
                              return m.pinned
                                  ? KeyedSubtree(
                                      key: _pinKeys.putIfAbsent(
                                        m.seq,
                                        GlobalKey.new,
                                      ),
                                      child: bubble,
                                    )
                                  : bubble;
                            }
                            if (i < messages.length + _flying.length) {
                              final flying = _flying[i - messages.length];
                              return _FlyingBubble(
                                text: flying.text,
                                files: flying.files,
                                scheme: scheme,
                                textStyle: base,
                              );
                            }
                            return _TypingBubble(
                              seconds: _waited,
                              scheme: scheme,
                            );
                          },
                        ),
                      ),
                      ),
              ),
              if (pinned != null)
                Positioned(
                  top: headerBottom,
                  left: 8,
                  right: 8,
                  child: MeasureHeight(
                    // The list leaves room for the banner as it is before the user taps
                    // it. An open banner covers the list for a while.
                    onHeight: (h) {
                      if (_pinExpanded || h == _bannerHeight) return;
                      final atEnd = !_scroll.hasClients ||
                          _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
                      setState(() => _bannerHeight = h);
                      if (atEnd) _scrollToEnd();
                    },
                    child: _PinnedBanner(
                      message: pinned,
                      shownText: _reveals[pinned.seq]?.text.text ?? pinned.text,
                      style: base.copyWith(color: scheme.onSurface),
                      html: chatPrefs.htmlWidgets,
                      expanded: _pinExpanded,
                      maxHeight: chatArea * chatPrefs.pinnedMaxFraction,
                      maxExpandedHeight: chatArea * pinnedExpandedFraction,
                      onToggle: () => setState(() => _pinExpanded = !_pinExpanded),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MeasureHeight(
                  onHeight: (h) {
                    setState(() => _headerExtent = h);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePinned());
                  },
                  child: header,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MeasureHeight(
                  onHeight: (h) {
                    final atEnd = !_scroll.hasClients ||
                        _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
                    setState(() => _bottomHeight = h);
                    if (atEnd) _scrollToEnd();
                  },
                  child: inputBar,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The message that the client is sending: a bubble of the user, paler, with a small
/// "Sending…" under it. It is replaced by the real message when the answer comes.
class _FlyingBubble extends StatelessWidget {
  const _FlyingBubble({
    required this.text,
    required this.files,
    required this.scheme,
    required this.textStyle,
  });

  final String text;
  final List<OutgoingAttachment> files;
  final ColorScheme scheme;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(16);
    final color = scheme.onPrimaryContainer;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Opacity(
        opacity: 0.7,
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const Key('chat-flying'),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: r,
                topRight: r,
                bottomLeft: r,
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final file in files)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        file.kind == 'audio' ? Icons.audiotrack : Icons.image,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          file.name ?? file.mime,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color),
                        ),
                      ),
                    ],
                  ),
                if (text.isNotEmpty) Text(text, style: textStyle.copyWith(color: color)),
                Text(
                  context.l10n.chatSending,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer that is on its way: three dots that pulse, and, after a few seconds, the
/// time that the screen has waited. A slow service (an LLM can take a minute) shows that
/// it works, so the screen does not look stuck.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.seconds, required this.scheme});

  final int seconds;
  final ColorScheme scheme;

  /// The wait after which the bubble shows the seconds.
  static const showSecondsAfter = 5;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const r = Radius.circular(16);
    final color = widget.scheme.onSurfaceVariant;
    final long = widget.seconds >= _TypingBubble.showSecondsAfter;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        key: const Key('chat-typing'),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: r,
            topRight: r,
            bottomLeft: Radius.circular(4),
            bottomRight: r,
          ),
        ),
        child: Semantics(
          liveRegion: true,
          label: l10n.chatTyping,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Opacity(
                          // Each dot is one third of the cycle behind the one before.
                          opacity: 0.25 + 0.75 * (1 - ((_pulse.value - i / 3) % 1.0)),
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: color,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (long)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    key: const Key('chat-waited'),
                    l10n.chatWaitingSeconds(widget.seconds),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the menu of a message does.
enum _BubbleAction { copy, select, pin }

/// A message: the user in a bubble on the right, with a small tail corner. The service has
/// no bubble: its text is plain, over the background, at the full width, as it is what the
/// user reads most. The files of the message come before its text.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.scheme,
    required this.textStyle,
    required this.shownText,
    required this.shownReasoning,
    required this.html,
    required this.read,
    required this.onLoaded,
    required this.onPin,
    required this.onCopy,
  });

  final ChatMessage message;
  final ColorScheme scheme;

  /// The style of the text, from the settings of the chat.
  final TextStyle textStyle;

  /// The text and the reasoning as they show now: a part of the message while they type.
  final String shownText;
  final String shownReasoning;

  /// Show the HTML blocks of the text of the service as widgets (a setting of the chat).
  final bool html;

  /// Reads the bytes of a file of the message (`ChatClient.readAttachment`).
  final Future<Uint8List> Function(int seq, int index) read;

  /// A file of the message finished to load.
  final VoidCallback onLoaded;

  /// Pins or unpins the message. Null while the service does not take it.
  final VoidCallback? onPin;
  final VoidCallback onCopy;

  /// The menu of a long press on the message, anywhere on it: copy, select the text, and
  /// pin or unpin. The text of a bubble is not selectable by itself, so that a long press
  /// always opens this menu and never starts a selection; "Select text" opens the text in
  /// a sheet where it can be selected.
  Future<void> _menu(BuildContext context, Offset at) async {
    final l10n = context.l10n;
    final box = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final pin = onPin;
    final copy = message.text.isNotEmpty;
    final selectable = _selectableText.isNotEmpty;
    if (pin == null && !copy && !selectable) return;
    final chosen = await showMenu<_BubbleAction>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & box.size),
      items: [
        if (copy)
          PopupMenuItem(key: const Key('chat-menu-copy'), value: _BubbleAction.copy, child: Text(l10n.chatCopy)),
        if (selectable)
          PopupMenuItem(
            key: const Key('chat-menu-select'),
            value: _BubbleAction.select,
            child: Text(l10n.chatSelectText),
          ),
        if (pin != null)
          PopupMenuItem(
            key: const Key('chat-menu-pin'),
            value: _BubbleAction.pin,
            child: Text(message.pinned ? l10n.chatUnpin : l10n.chatPin),
          ),
      ],
    );
    if (chosen == null || !context.mounted) return;
    switch (chosen) {
      case _BubbleAction.copy:
        onCopy();
      case _BubbleAction.select:
        await _selectText(context);
      case _BubbleAction.pin:
        pin?.call();
    }
  }

  /// What "Select text" offers: the text of the message, or its reasoning if it has no
  /// text yet.
  String get _selectableText => message.text.isNotEmpty ? message.text : message.reasoning;

  /// The text of the message in a sheet, where the user can select and copy a part of it.
  Future<void> _selectText(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: SelectableText(
            _selectableText,
            key: const Key('chat-select-text'),
            style: textStyle.copyWith(color: Theme.of(ctx).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // An answer that has started but has nothing to show: the typing bubble stands for it.
    if (message.isOpen && !_ChatScreenState._hasContent(message)) return const SizedBox.shrink();
    final mine = message.fromUser;
    const r = Radius.circular(16);
    const tail = Radius.circular(4);
    final color = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _menu(context, d.globalPosition),
          child: Container(
          key: Key('chat-bubble-${message.seq}'),
          margin: EdgeInsets.symmetric(vertical: mine ? 3 : 8),
          padding: mine
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 4),
          constraints: mine ? BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8) : null,
          decoration: mine
              ? BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: r,
                    topRight: r,
                    bottomLeft: r,
                    bottomRight: tail,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.pinned)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Icon(
                    Icons.push_pin,
                    key: Key('chat-pin-icon-${message.seq}'),
                    size: 14,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: context.l10n.chatPinnedIcon,
                  ),
                ),
              for (var i = 0; i < message.attachments.length; i++)
                _AttachmentView(
                  key: Key('chat-file-${message.seq}-$i'),
                  attachment: message.attachments[i],
                  load: () => read(message.seq, i),
                  onLoaded: onLoaded,
                  color: color,
                ),
              if (shownReasoning.isNotEmpty)
                _Reasoning(
                  key: Key('chat-reasoning-${message.seq}'),
                  text: shownReasoning,
                  // The user sees the reasoning grow until the text starts.
                  openByDefault: message.isOpen && message.text.isEmpty,
                  color: scheme.onSurfaceVariant,
                ),
              if (shownText.isNotEmpty)
                _MessageText(
                  text: shownText,
                  style: textStyle.copyWith(color: color),
                  // Only the text of the service has HTML blocks: the user writes plain text.
                  html: html && !mine,
                  streaming: message.isOpen,
                  // Not selectable: a long press opens the menu, which can select the text.
                  selectable: false,
                ),
              if (message.isFailed || message.isCancelled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    message.isFailed ? context.l10n.chatAnswerFailed : context.l10n.chatAnswerCancelled,
                    key: Key('chat-${message.isFailed ? 'failed' : 'cancelled'}-${message.seq}'),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.error),
                  ),
                ),
              if (message.isFailed && message.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    message.error!,
                    key: Key('chat-error-${message.seq}'),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The builder of the list of messages, which tells the screen the first message that the
/// list built, after each layout ([pinnedIndexAbove] needs it).
class _LayoutDelegate extends SliverChildBuilderDelegate {
  _LayoutDelegate(super.builder, {super.childCount, required this.onLayout});

  final void Function(int first) onLayout;

  @override
  void didFinishLayout(int firstIndex, int lastIndex) => onLayout(firstIndex);
}

/// The text of a message. With [html] on, the fenced blocks "```html" show as widgets
/// ([ChatHtmlWidget]) and the rest as text. A block that is still open while the message
/// grows shows as code, until its closing fence comes. With [html] off, all shows as text.
class _MessageText extends StatelessWidget {
  const _MessageText({
    required this.text,
    required this.style,
    required this.html,
    required this.streaming,
    required this.selectable,
    this.onPin,
    this.pinLabel = '',
  });

  final String text;
  final TextStyle style;
  final bool html;
  final bool streaming;

  /// The text can be selected. The pinned banner has it off: a tap there opens it.
  final bool selectable;

  /// Pins or unpins the message: it adds an item to the menu of the selected text. Null
  /// adds nothing.
  final VoidCallback? onPin;
  final String pinLabel;

  Widget _text(String t, TextStyle s) => selectable
      ? SelectableText(
          t,
          style: s,
          contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: [
              ...state.contextMenuButtonItems,
              if (onPin != null)
                ContextMenuButtonItem(
                  label: pinLabel,
                  onPressed: () {
                    state.hideToolbar();
                    onPin!();
                  },
                ),
            ],
          ),
        )
      : Text(t, style: s);

  @override
  Widget build(BuildContext context) {
    final parts = html ? splitHtmlBlocks(text, streaming: streaming) : const <ChatSegment>[];
    if (parts.every((p) => p.kind == ChatSegmentKind.text)) return _text(text, style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final part in parts)
          switch (part.kind) {
            ChatSegmentKind.text => _text(part.text, style),
            ChatSegmentKind.html => Padding(
                key: const Key('chat-html'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ChatHtmlWidget(html: part.text, style: style),
              ),
            ChatSegmentKind.pendingHtml => _text(
                part.text,
                style.copyWith(
                  fontFamily: 'monospace',
                  fontSize: (style.fontSize ?? 17) - 2,
                ),
              ),
          },
      ],
    );
  }
}

/// A pinned message, anchored under the bar while the user reads what comes after it. It
/// takes at most [maxHeight]; what does not fit scrolls inside it, and a tap opens it to
/// [maxExpandedHeight].
class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.message,
    required this.shownText,
    required this.style,
    required this.html,
    required this.expanded,
    required this.maxHeight,
    required this.maxExpandedHeight,
    required this.onToggle,
  });

  final ChatMessage message;
  final String shownText;
  final TextStyle style;
  final bool html;
  final bool expanded;
  final double maxHeight;
  final double maxExpandedHeight;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return FloatingSurface(
      key: const Key('chat-pinned'),
      radius: 18,
      child: InkWell(
        key: const Key('chat-pinned-toggle'),
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: expanded ? maxExpandedHeight : maxHeight,
          ),
          child: ListView(
            key: const Key('chat-pinned-scroll'),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            children: [
              Row(
                children: [
                  Icon(Icons.push_pin_outlined, size: 16, color: muted),
                  const Spacer(),
                  Tooltip(
                    message: expanded ? l10n.chatPinnedCollapse : l10n.chatPinnedExpand,
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: muted,
                    ),
                  ),
                ],
              ),
              _MessageText(
                text: shownText,
                style: style,
                html: html,
                streaming: message.isOpen,
                selectable: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reasoning of the model, apart from the text of the answer: a line with its name
/// that opens and closes with a tap. It is open while the answer has no text yet, until
/// the user taps it.
class _Reasoning extends StatefulWidget {
  const _Reasoning({
    super.key,
    required this.text,
    required this.openByDefault,
    required this.color,
  });

  final String text;
  final bool openByDefault;
  final Color color;

  @override
  State<_Reasoning> createState() => _ReasoningState();
}

class _ReasoningState extends State<_Reasoning> {
  /// What the user chose with a tap, or null: follow [_Reasoning.openByDefault].
  bool? _choice;

  @override
  Widget build(BuildContext context) {
    final open = _choice ?? widget.openByDefault;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: widget.color,
          fontStyle: FontStyle.italic,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('chat-reasoning-toggle'),
            onTap: () => setState(() => _choice = !open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: widget.color,
                ),
                const SizedBox(width: 4),
                Text(context.l10n.chatReasoning, style: style),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.text,
                key: const Key('chat-reasoning-text'),
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

/// One file of a message. An image shows in the bubble. An audio file shows its name and
/// size, and a tap hands it to the share sheet of the system, which can open it in a
/// player. The bytes are read once, when the bubble first shows, and stay in memory. A
/// file that did not load loads again with a tap on its error.
class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    super.key,
    required this.attachment,
    required this.load,
    required this.onLoaded,
    required this.color,
  });

  final ChatAttachment attachment;
  final Future<Uint8List> Function() load;
  final VoidCallback onLoaded;
  final Color color;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  /// The height of an image in a bubble, also reserved while it loads, so the list does
  /// not jump when it shows.
  static const _imageHeight = 200.0;

  late Future<Uint8List> _bytes = _start();

  Future<Uint8List> _start() {
    final bytes = widget.load();
    bytes.then((_) {
      if (mounted) widget.onLoaded();
    }, onError: (_) {});
    return bytes;
  }

  Future<void> _share(Uint8List bytes) async {
    final a = widget.attachment;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: a.mime, name: a.safeName)],
      ),
    );
  }

  Widget _failed(BuildContext context) => InkWell(
        key: const Key('chat-file-retry'),
        onTap: () => setState(() {
          _bytes = _start();
        }),
        child: Text(
          context.l10n.chatAttachmentFailed,
          style: TextStyle(color: widget.color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = widget.attachment;
    final name = a.safeName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _failed(context);
          final bytes = snapshot.data;
          if (a.isImage) {
            if (bytes == null) {
              return const SizedBox(
                height: _imageHeight,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                height: _imageHeight,
                cacheHeight: (_imageHeight * MediaQuery.devicePixelRatioOf(context)).round(),
                gaplessPlayback: true,
                semanticLabel: name ?? l10n.chatImage,
                errorBuilder: (context, _, __) => _failed(context),
              ),
            );
          }
          return Semantics(
            button: true,
            label: '${name ?? a.mime}. ${l10n.chatAttachmentShare}',
            excludeSemantics: true,
            onTap: bytes == null ? null : () => _share(bytes),
            child: InkWell(
              onTap: bytes == null ? null : () => _share(bytes),
              child: Tooltip(
                message: l10n.chatAttachmentShare,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      a.isAudio ? Icons.audiotrack : Icons.image,
                      color: widget.color,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        name ?? a.mime,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: widget.color),
                      ),
                    ),
                    if (bytes == null)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
