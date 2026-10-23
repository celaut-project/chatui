import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/attachment_picker.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/chat_client.dart';
import '../../celaut/conversation_keep_alive.dart';
import '../../celaut/conversations.dart';
import '../../celaut/payers.dart';
import '../../celaut/tunnel_http.dart';
import '../../l10n/l10n.dart';
import 'instance_actions.dart';
import 'instance_info_screen.dart';

/// The conversation with a running instance that follows the chat convention
/// (`docs/celaut/chat.md`), as a chat in a messenger (`docs/celaut/ui-chat-first.md`).
/// The service keeps the history; this screen reads it from the start each time it
/// opens, keeps a copy in memory, and writes nothing to the Celaut database. The last
/// message goes to the notes of the list of conversations, in memory.
///
/// A send does not wait for the answer, so the user can send many messages one after the
/// other. The screen reads the conversation every few seconds ([ChatClient.sync]) and shows
/// an answer that grows, with its reasoning apart from its text, while the service makes it.
///
/// The bar has the name of the service, and under it the state, the node and the cost so
/// far. A tap on the name, or ⋮ then Info, opens the info page of the instance; ⋮ also has
/// Stop. Back goes to the list: the instance runs on, and the list keeps it.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.instance,
    required this.port,
    this.http,
    this.chat,
    this.wallets = const AppFullWallets(),
    this.loadStatus,
    this.stopInstance,
    this.keepAlive,
    this.starting = false,
    this.notes,
    this.pickFiles,
    this.pollEvery,
  });

  /// How often the screen reads the conversation. Null: [ChatClient.pollWaiting] while it
  /// waits for an answer, and [ChatClient.pollIdle] otherwise. Tests give their own.
  final Duration? pollEvery;

  /// The instance has just started: the screen waits until the service answers
  /// (`ChatClient.syncWhenStarted`), and says that it starts.
  final bool starting;

  /// The instance, from the database of the app (`celautInstances`).
  final InstanceListView instance;

  /// The local port of the chat slot of the instance (`celautOpenTunnel`).
  final int port;

  /// The HTTP client of the local port. Tests give their own.
  final TunnelHttp? http;

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

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final TunnelHttp _http = widget.http ?? TunnelHttp();
  late final ChatClient _chat = widget.chat ?? ChatClient(port: widget.port, http: _http);
  late final ConversationKeepAlive _keepAlive = widget.keepAlive ?? ChannelConversationKeepAlive();
  late final ConversationNotes _notes = widget.notes ?? conversationNotes;

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

  /// A message is on its way, or the service still makes an answer.
  bool get _waiting => _flying.isNotEmpty || _chat.awaitingAnswer;

  @override
  void initState() {
    super.initState();
    unawaited(_keepAlive.start());
    _open();
  }

  /// A running instance can have messages already: read them, then the cost.
  Future<void> _open() async {
    // The wait for a service that just started goes on with the screen off.
    if (widget.starting) unawaited(_keepAlive.waiting(true));
    try {
      await (widget.starting ? _chat.syncWhenStarted() : _chat.sync());
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.kind);
    } finally {
      if (widget.starting) unawaited(_keepAlive.waiting(false));
    }
    // Answered or not, the wait of the start is over: the list shows the check of the
    // node again.
    _notes.answered(_id);
    _notes.saw(_id, _chat.messages);
    if (mounted) setState(() => _waitingStart = false);
    _syncTicker();
    _schedulePoll();
    await _refreshCost();
    _scrollToEnd();
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
    final every =
        widget.pollEvery ?? (_waiting ? ChatClient.pollWaiting : ChatClient.pollIdle);
    _poll = Timer(every, _pollOnce);
  }

  /// Read the new messages and the growth of the open ones, then plan the next read.
  Future<void> _pollOnce() async {
    if (!mounted) return;
    if (!_waitingStart && !_stopping) {
      final atEnd = !_scroll.hasClients ||
          _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
      try {
        await _chat.sync();
        if (mounted && _error == ChatErrorKind.unreachable) setState(() => _error = null);
      } on ChatException catch (e) {
        if (mounted) setState(() => _error = e.kind);
      }
      if (!mounted) return;
      _notes.saw(_id, _chat.messages);
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
    try {
      await _chat.sync();
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.kind);
    }
    _notes.saw(_id, _chat.messages);
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
      _notes.saw(_id, _chat.messages);
      if (mounted) setState(() {});
      _syncTicker();
    }
    _wasWaiting = _waiting;
    // The service has the message: read the answer soon, at the pace of a wait.
    _schedulePoll();
    _scrollToEnd();
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

  String _errorText(ChatErrorKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      ChatErrorKind.unreachable => l10n.chatErrorUnreachable,
      ChatErrorKind.badAnswer => l10n.chatErrorBadAnswer,
      ChatErrorKind.historyFull => l10n.chatErrorHistoryFull,
      ChatErrorKind.busy => l10n.chatErrorBusy,
      ChatErrorKind.unsupportedMedia => l10n.chatErrorUnsupportedMedia,
      ChatErrorKind.badRequest when _pending.isNotEmpty => l10n.chatErrorFile,
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
    _http.close();
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
    unawaited(_keepAlive.stop());
    _ticker?.cancel();
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    if (widget.http == null) _http.close();
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
    final title = instanceTitle(_instance);
    final subtitle = [
      instanceStateText(context, _state),
      _instance.address,
      muOrUnknown(_costMu),
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          key: const Key('chat-title'),
          onTap: _info,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                InstanceAvatar(instanceId: _id, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: const Key('chat-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
        actions: [
          PopupMenuButton<String>(
            key: const Key('chat-menu'),
            tooltip: l10n.chatsMenuMore,
            enabled: !_stopping,
            onSelected: (choice) => choice == 'stop' ? _stop() : _info(),
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('chat-menu-info'),
                value: 'info',
                child: Text(l10n.chatsActionInfo),
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
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty && _flying.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _waitingStart
                          ? Column(
                              key: const Key('chat-starting'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(l10n.chatStarting, textAlign: TextAlign.center),
                              ],
                            )
                          : Text(l10n.chatEmpty, textAlign: TextAlign.center),
                    ),
                  )
                : ListView.builder(
                    key: const Key('chat-messages'),
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + _flying.length + (typing ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i < messages.length) {
                        return _Bubble(
                          message: messages[i],
                          scheme: scheme,
                          read: _chat.readAttachment,
                          onLoaded: _fileLoaded,
                        );
                      }
                      if (i < messages.length + _flying.length) {
                        final flying = _flying[i - messages.length];
                        return _FlyingBubble(
                          text: flying.text,
                          files: flying.files,
                          scheme: scheme,
                        );
                      }
                      return _TypingBubble(seconds: _waited, scheme: scheme);
                    },
                  ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < _pending.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        key: Key('chat-pending-$i'),
                        avatar: Icon(_pending[i].kind == 'audio' ? Icons.audiotrack : Icons.image),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
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
                      decoration: InputDecoration(hintText: l10n.chatInputHint),
                    ),
                  ),
                  IconButton(
                    key: const Key('chat-send'),
                    tooltip: l10n.chatSend,
                    onPressed: _stopping ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The message that the client is sending: a bubble of the user, paler, with a small
/// "Sending…" under it. It is replaced by the real message when the answer comes.
class _FlyingBubble extends StatelessWidget {
  const _FlyingBubble({required this.text, required this.files, required this.scheme});

  final String text;
  final List<OutgoingAttachment> files;
  final ColorScheme scheme;

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
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
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
                      Icon(file.kind == 'audio' ? Icons.audiotrack : Icons.image, color: color),
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
                if (text.isNotEmpty) Text(text, style: TextStyle(color: color)),
                Text(
                  context.l10n.chatSending,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
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
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

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
                          child: CircleAvatar(radius: 4, backgroundColor: color),
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
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A message as a bubble: the user on the right, the service on the left, with a small
/// tail corner on the side of the sender. The files of the message come before its text.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.scheme,
    required this.read,
    required this.onLoaded,
  });

  final ChatMessage message;
  final ColorScheme scheme;

  /// Reads the bytes of a file of the message (`ChatClient.readAttachment`).
  final Future<Uint8List> Function(int seq, int index) read;

  /// A file of the message finished to load.
  final VoidCallback onLoaded;

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
      child: Container(
        key: Key('chat-bubble-${message.seq}'),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: r,
            topRight: r,
            bottomLeft: mine ? r : tail,
            bottomRight: mine ? tail : r,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < message.attachments.length; i++)
              _AttachmentView(
                key: Key('chat-file-${message.seq}-$i'),
                attachment: message.attachments[i],
                load: () => read(message.seq, i),
                onLoaded: onLoaded,
                color: color,
              ),
            if (message.reasoning.isNotEmpty)
              _Reasoning(
                key: Key('chat-reasoning-${message.seq}'),
                text: message.reasoning,
                // The user sees the reasoning grow until the text starts.
                openByDefault: message.isOpen && message.text.isEmpty,
                color: scheme.onSurfaceVariant,
              ),
            if (message.text.isNotEmpty)
              SelectableText(message.text, style: TextStyle(color: color)),
            if (message.isFailed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.l10n.chatAnswerFailed,
                  key: Key('chat-failed-${message.seq}'),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.error),
                ),
              ),
          ],
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
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: widget.color),
                const SizedBox(width: 4),
                Text(context.l10n.chatReasoning, style: style),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(widget.text, key: const Key('chat-reasoning-text'), style: style),
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
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: a.mime, name: a.safeName)],
    ));
  }

  Widget _failed(BuildContext context) => InkWell(
        key: const Key('chat-file-retry'),
        onTap: () => setState(() {
          _bytes = _start();
        }),
        child: Text(context.l10n.chatAttachmentFailed, style: TextStyle(color: widget.color)),
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
                    Icon(a.isAudio ? Icons.audiotrack : Icons.image, color: widget.color),
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
