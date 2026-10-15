import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/chat_client.dart';
import '../../celaut/conversation_keep_alive.dart';
import '../../celaut/payers.dart';
import '../../celaut/tunnel_http.dart';
import '../../l10n/l10n.dart';

/// The conversation with a running instance that follows the chat convention
/// (`docs/celaut/chat.md`). The service keeps the history; this screen keeps a copy in
/// memory and writes nothing to the Celaut database.
///
/// When the user leaves, the screen asks: stop the instance (the node refunds the
/// balance and the conversation ends) or leave it running (the node keeps charging).
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.instanceId,
    required this.port,
    this.http,
    this.chat,
    this.wallets = const AppFullWallets(),
    this.loadStatus,
    this.stopInstance,
    this.keepAlive,
  });

  /// The local id of the instance (`InstanceView.instanceId`).
  final String instanceId;

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

  bool _sending = false;
  bool _stopping = false;
  ChatErrorKind? _error;
  String? _costMu;
  String? _walletError;

  @override
  void initState() {
    super.initState();
    unawaited(_keepAlive.start());
    _open();
  }

  /// A running instance can have messages already: read them, then the cost.
  Future<void> _open() async {
    try {
      await _chat.sync();
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.kind);
    }
    if (mounted) setState(() {});
    await _refreshCost();
    _scrollToEnd();
  }

  Future<void> _refreshCost() async {
    try {
      final load = widget.loadStatus ?? ((id) => celautInstanceStatus(instanceId: id));
      final status = await load(widget.instanceId);
      if (mounted) setState(() => _costMu = status.costSoFarMu);
    } on CelautError {
      // The cost stays as it was: the conversation does not depend on it.
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _chat.send(text);
      _input.clear();
    } on ChatException catch (e) {
      // The text stays in the field, so the user can send it again.
      if (mounted) setState(() => _error = e.kind);
    } finally {
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
      ChatErrorKind.badRequest || ChatErrorKind.other => l10n.chatErrorOther,
    };
  }

  /// Ask what to do with the instance. Returns true if the screen can close.
  Future<bool> _confirmLeave() async {
    final l10n = context.l10n;
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.chatLeaveTitle),
        content: Text(l10n.chatLeaveBody),
        actions: [
          TextButton(
            key: const Key('chat-stay'),
            onPressed: () => Navigator.pop(context, _LeaveChoice.stay),
            child: Text(l10n.chatStay),
          ),
          TextButton(
            key: const Key('chat-leave-running'),
            onPressed: () => Navigator.pop(context, _LeaveChoice.leaveRunning),
            child: Text(l10n.chatLeaveRunning),
          ),
          FilledButton(
            key: const Key('chat-stop'),
            onPressed: () => Navigator.pop(context, _LeaveChoice.stop),
            child: Text(l10n.chatStop),
          ),
        ],
      ),
    );
    switch (choice) {
      case _LeaveChoice.leaveRunning:
        // The instance goes on at the node. Only the phone side is released.
        unawaited(_keepAlive.stop());
        return true;
      case _LeaveChoice.stop:
        return _stop();
      case _LeaveChoice.stay || null:
        return false;
    }
  }

  /// Stop the instance. Stopping needs an open full wallet (`docs/celaut/ui.md`).
  Future<bool> _stop() async {
    if (!await ensureOpenFullWallet(context, widget.wallets) || !mounted) {
      if (mounted) setState(() => _walletError = context.l10n.celautOpenFullWalletNeeded);
      return false;
    }
    setState(() {
      _stopping = true;
      _walletError = null;
    });
    try {
      final stop = widget.stopInstance ?? ((id) => celautStopService(instanceId: id));
      final stopped = await stop(widget.instanceId);
      // The local port is closed: drop the kept-alive connection too.
      _http.close();
      unawaited(_keepAlive.stop());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.chatStopped(muOrUnknown(stopped.refundMu)))),
        );
      }
      return true;
    } on CelautError catch (e) {
      if (mounted) setState(() => _walletError = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
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
    final error = _walletError ?? (_error == null ? null : _errorText(_error!));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _stopping) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.chatTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                key: const Key('chat-cost'),
                l10n.chatCost(muOrUnknown(_costMu)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.chatEmpty, textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('chat-messages'),
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final message = messages[i];
                        return Align(
                          alignment: message.fromUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                            ),
                            decoration: BoxDecoration(
                              color: message.fromUser
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(message.text),
                          ),
                        );
                      },
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
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
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
      ),
    );
  }
}

enum _LeaveChoice { stay, leaveRunning, stop }
