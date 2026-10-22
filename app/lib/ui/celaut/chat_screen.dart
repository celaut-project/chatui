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
  });

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

  /// Let the user pick the files of a message, for the kinds that the service accepts.
  /// Null: the file picker of the system. Tests give their own.
  final Future<List<OutgoingAttachment>> Function(Set<String> kinds)? pickFiles;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final TunnelHttp _http = widget.http ?? TunnelHttp();
  late final ChatClient _chat = widget.chat ?? ChatClient(port: widget.port, http: _http);
  late final ConversationKeepAlive _keepAlive =
      widget.keepAlive ?? ChannelConversationKeepAlive();
  late final ConversationNotes _notes = widget.notes ?? conversationNotes;

  bool _sending = false;
  final List<OutgoingAttachment> _pending = [];
  bool _stopping = false;
  late bool _waitingStart = widget.starting;
  ChatErrorKind? _error;
  String? _costMu;

  String get _id => widget.instance.instanceId;

  @override
  void initState() {
    super.initState();
    unawaited(_keepAlive.start());
    _open();
  }

  /// A running instance can have messages already: read them, then the cost.
  Future<void> _open() async {
    try {
      await (widget.starting ? _chat.syncWhenStarted() : _chat.sync());
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.kind);
    }
    // Answered or not, the wait of the start is over: the list shows the check of the
    // node again.
    _notes.answered(_id);
    _notes.saw(_id, _chat.messages);
    if (mounted) setState(() => _waitingStart = false);
    await _refreshCost();
    _scrollToEnd();
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

  Future<void> _attach() async {
    final pick = widget.pickFiles ?? pickAttachments;
    final files = await pick(_chat.accepts);
    if (!mounted || files.isEmpty) return;
    setState(() {
      _error = null;
      _pending.addAll(files);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _chat.send(text, attachments: List.of(_pending));
      _input.clear();
      _pending.clear();
    } on ChatException catch (e) {
      // The text and the files stay, so the user can send them again.
      if (mounted) setState(() => _error = e.kind);
    } finally {
      _notes.saw(_id, _chat.messages);
      if (mounted) setState(() => _sending = false);
    }
    await _refreshCost();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

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
      widget.instance,
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
          instance: widget.instance,
          state: _state,
          costMu: _costMu,
          wallets: widget.wallets,
          stop: widget.stopInstance,
          notes: _notes,
        ),
      ),
    );
    if (stopped == true) _closeStopped();
  }

  @override
  void dispose() {
    unawaited(_keepAlive.stop());
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
    final error = _error == null ? null : _errorText(_error!);
    final title = instanceTitle(widget.instance);
    final subtitle = [
      instanceStateText(context, _state),
      widget.instance.address,
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
                InstanceAvatar(title: title, size: 38),
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
            child: messages.isEmpty
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
                    itemCount: messages.length,
                    itemBuilder: (context, i) => _Bubble(
                      message: messages[i],
                      scheme: scheme,
                      read: _chat.readAttachment,
                    ),
                  ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                error,
                key: const Key('chat-error'),
                style: TextStyle(color: scheme.error),
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
                        label: Text(_pending[i].name ?? _pending[i].mime),
                        deleteButtonTooltipMessage: l10n.chatAttachmentRemove,
                        onDeleted: _sending ? null : () => setState(() => _pending.removeAt(i)),
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
                  if (_chat.accepts.isNotEmpty)
                    IconButton(
                      key: const Key('chat-attach'),
                      tooltip: l10n.chatAttach,
                      onPressed: _sending || _stopping ? null : _attach,
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
                    onPressed: _sending || _stopping ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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

/// A message as a bubble: the user on the right, the service on the left, with a small
/// tail corner on the side of the sender. The files of the message come before its text.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.scheme, required this.read});

  final ChatMessage message;
  final ColorScheme scheme;

  /// Reads the bytes of a file of the message (`ChatClient.readAttachment`).
  final Future<Uint8List> Function(int seq, int index) read;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromUser;
    const r = Radius.circular(16);
    const tail = Radius.circular(4);
    final color = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
                color: color,
              ),
            if (message.text.isNotEmpty) SelectableText(message.text, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

/// One file of a message. An image shows in the bubble. An audio file shows its name and
/// size, and a tap hands it to the share sheet of the system, which can open it in a
/// player. The bytes are read once, when the bubble first shows, and stay in memory.
class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    super.key,
    required this.attachment,
    required this.load,
    required this.color,
  });

  final ChatAttachment attachment;
  final Future<Uint8List> Function() load;
  final Color color;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  late final Future<Uint8List> _bytes = widget.load();

  Future<void> _share(Uint8List bytes) async {
    final a = widget.attachment;
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: a.mime, name: a.name)],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = widget.attachment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(l10n.chatAttachmentFailed, style: TextStyle(color: widget.color));
          }
          final bytes = snapshot.data;
          if (a.isImage && bytes != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                height: 200,
                errorBuilder: (context, _, __) =>
                    Text(l10n.chatAttachmentFailed, style: TextStyle(color: widget.color)),
              ),
            );
          }
          return InkWell(
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
                      a.name ?? a.mime,
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
          );
        },
      ),
    );
  }
}
