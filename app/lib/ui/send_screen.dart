import 'widgets/error_sheet.dart';
import 'widgets/tx_result_view.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams, XFile;

import '../format.dart';
import '../services/contacts_service.dart';
import '../services/ergopay_service.dart';
import '../services/coin_control.dart';
import '../services/network_controller.dart';
import '../services/storage_rent.dart';
import '../services/wallet_service.dart';
import '../theme/argus_theme.dart';
import 'confirm_transaction_sheet.dart';
import 'ergopay_screen.dart';
import 'offline_banner.dart';
import 'scan_screen.dart';
import 'send_recipients.dart';
import 'widgets/held_token_picker.dart';
import 'widgets/amount_entry.dart';
import 'widgets/entry_dialogs.dart';
import 'widgets/rent_hint.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({
    super.key,
    this.initialAssetId,
    this.initialRecipient,
    this.initialAmountErg,
  });

  /// Token id to preselect in the asset picker (e.g. from a token sheet).
  final String? initialAssetId;

  /// Recipient and amount from a scanned `ergo:` payment URI; treated as a
  /// trusted source for the clipboard-hijack gate.
  final String? initialRecipient;
  final String? initialAmountErg;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

/// One extra token on the main recipient: which, and its amount field.
class _TokenEntry {
  String? tokenId;
  final amountCtrl = TextEditingController();
  void dispose() => amountCtrl.dispose();
}

class _RecipientEntry {
  _RecipientEntry() {}
  final addressCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  TextEditingController? tokenAmtCtrl;
  String? tokenId;

  String get address => addressCtrl.text.trim();
  String get amount => amountCtrl.text.trim();

  void dispose() {
    addressCtrl.dispose();
    amountCtrl.dispose();
    tokenAmtCtrl?.dispose();
  }
}

class _SendScreenState extends State<SendScreen> with TxReceiptOwner {
  final _formKey = GlobalKey<FormState>();
  final _recipientCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _tokenAmtCtrl = TextEditingController();

  /// Tokens beyond the picked asset that ride in the main recipient's box.
  final List<_TokenEntry> _extraTokens = [];
  bool _sending = false;
  String? _resultTxId;
  late String? _assetId = widget.initialAssetId;
  Set<String> _selectedSpendAddresses = {};

  /// Boxes the user chose to spend. Empty means automatic selection.
  final Set<String> _chosenBoxIds = {};
  List<InputBoxInput> _boxes = const [];
  bool _loadingBoxes = false;

  CoinSelection get _selection => summariseSelection(_boxes, _chosenBoxIds);

  /// Ids to spend: the per-box choice, or null for automatic selection.
  List<String>? get _inputBoxIds =>
      _chosenBoxIds.isEmpty ? null : _selection.boxes.map((b) => b.boxId).toList();

  Future<void> _openInputPicker() async {
    final spend = _selectedSpendAddresses.isNotEmpty
        ? _selectedSpendAddresses.toList()
        : _allSpendAddresses;
    if (spend.isEmpty) {
      _snack('No spendable addresses');
      return;
    }
    setState(() => _loadingBoxes = true);
    try {
      _boxes = await walletService.listUnspentBoxes(spend, nodeUrl: networkController.activeUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBoxes = false);
      showErrorSheet(context, title: 'Could not list your boxes', message: '$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadingBoxes = false;
      // Drop anything that has since been spent.
      _chosenBoxIds.retainAll(_boxes.map((b) => b.boxId));
    });
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => _InputPickerSheet(
          boxes: _boxes,
          chosen: _chosenBoxIds,
          amountNanoErg: parseErgToNano(_amountCtrl.text) ?? 0,
          feeNanoErg: parseErgToNano(_feeCtrl.text) ?? minerFeeNano,
          onToggle: (id) {
            setSheet(() {
              if (!_chosenBoxIds.remove(id)) _chosenBoxIds.add(id);
            });
            setState(() {});
          },
          onClear: () {
            setSheet(_chosenBoxIds.clear);
            setState(() {});
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }
  final _feeCtrl = TextEditingController();

  /// The token the miner fee is paid in through a babel box, or null
  /// for ERG.
  String? _feeTokenId;
  final List<_RecipientEntry> _extraRecipients = [];
  bool get _multiRecipient => _extraRecipients.isNotEmpty;

  /// Tip and fee factor for storage-rent hints; null until read (or when
  /// neither the node nor the dashboard knows a height).
  RentParameters? _rentParameters;

  /// Rent estimates by input. Every keystroke rebuilds the form, so each
  /// input is asked of the core once.
  final _rentEstimates = <String, OutputRentEstimate?>{};



  @override
  void initState() {
    super.initState();
    final r = widget.initialRecipient;
    if (r != null && r.isNotEmpty) {
      _recipientCtrl.text = r;
      _recipientTrusted = true;
    }
    final a = widget.initialAmountErg;
    if (a != null && a.isNotEmpty) _amountCtrl.text = a;
    storageRent
        .parametersOrFallback(
          nodeUrl: networkController.activeUrl,
          knownHeight: networkController.height,
        )
        .then((p) {
          if (mounted && p != null) setState(() => _rentParameters = p);
        });
  }

  @override
  void dispose() {
    _recipientCtrl.dispose();
    _amountCtrl.dispose();
    _tokenAmtCtrl.dispose();
    _feeCtrl.dispose();
    for (final e in _extraRecipients) e.dispose();
    for (final e in _extraTokens) e.dispose();
    super.dispose();
  }

  WalletRouteArgs get _args => WalletRouteArgs.of(context);

  TokenBalance? get _selectedToken {
    if (_assetId == null) return null;
    for (final t in _args.tokens) {
      if (t.id == _assetId) return t;
    }
    return null;
  }

  List<String> get _allSpendAddresses {
    final args = _args;
    return args.historyAddresses.isNotEmpty
        ? args.historyAddresses
        : [if (args.senderAddress.isNotEmpty) args.senderAddress];
  }

  bool get _recipientValid =>
      _recipientCtrl.text.trim().isNotEmpty &&
      looksLikeRecipient(_recipientCtrl.text.trim());

  /// True when the recipient came from a trusted source (contact picker or
  /// scanned payment URI) rather than free-typed/pasted text, so the
  /// clipboard-hijack gate can be skipped.
  bool _recipientTrusted = false;

  String? get _contactForRecipient {
    final addr = _recipientCtrl.text.trim();
    if (addr.isEmpty) return null;
    for (final c in contactsService.contacts) {
      if (c.address == addr) return 'Contact: ${c.name}';
    }
    return null;
  }

  void _applyMaxErg() {
    final spendable = _args.spendableNano;
    if (spendable == null) {
      _snack('Spendable balance is unknown');
      return;
    }
    final otherRecipients = _extraRecipients.fold<int>(0, (sum, recipient) {
      final text = recipient.amount;
      return sum + (recipient.tokenId != null && text.isEmpty
          ? minBoxNano : parseErgToNano(text) ?? 0);
    });
    final max = maxRecipientNanoErg(
      spendableNano: _chosenBoxIds.isEmpty ? spendable : _selection.totalNanoErg,
      minerFeeNano: parseErgToNano(_feeCtrl.text) ?? minerFeeNano,
      otherRecipientsNano: otherRecipients,
      feePaidInToken: _feeTokenId != null,
    );
    if (max < minBoxNano) {
      _snack('Not enough ERG for fee and change');
      return;
    }
    _amountCtrl.text = formatErg(max, unit: false);
    setState(() {});
  }

  void _applyMaxToken() {
    final token = _selectedToken;
    if (token == null || (token.amount == 1 && token.decimals == 0)) {
      _snack('No token selected');
      return;
    }
    _tokenAmtCtrl.text = formatTokenAmount(token.amount, token.decimals);
    setState(() {});
  }

  Future<void> _scan() async {
    final raw = await Navigator.push<String>(context, fadeRoute(const ScanScreen()));
    if (!mounted) return;
    if (raw == null) return;
    if (isErgoPayLink(raw)) {
      Navigator.push(
        context,
        fadeRoute(ErgoPayScreen(link: raw), settings: RouteSettings(arguments: _args)),
      );
      return;
    }
    final pay = parseErgoUri(raw);
    if (pay == null) {
      _snack('Not an Ergo address');
      return;
    }
    _recipientCtrl.text = pay.address;
    if (pay.amountErg != null && pay.amountErg!.isNotEmpty) {
      _amountCtrl.text = pay.amountErg!;
    }
    _recipientTrusted = true;
    setState(() {});
  }

  Future<void> _saveRecipientToContacts() async {
    final addr = _recipientCtrl.text.trim();
    if (!looksLikeRecipient(addr)) return;
    final name = (await showDialog<String>(
      context: context,
      builder: (ctx) => TextEntryDialog(
        title: 'Save to contacts',
        label: 'Name',
        textCapitalization: TextCapitalization.words,
        footer: Text(shorten(addr, head: 10, tail: 10), style: monoStyle(ctx, size: 11)),
      ),
    ))
        ?.trim();
    if (name == null || name.isEmpty) return;
    await contactsService.add(name, addr);
    _snack('Contact saved');
  }

  /// Every recipient as typed, main form first. A token send with a blank
  /// ERG field carries the minimum box value.
  List<RecipientDraft> _drafts() {
    final token = _selectedToken;
    final erg = _amountCtrl.text.trim();
    return [
      RecipientDraft(
        address: _recipientCtrl.text,
        ergText: erg,
        tokenId: token?.id,
        tokenAmountText: _tokenAmtCtrl.text,
        tokens: [
          for (final e in _extraTokens)
            if (e.tokenId case final id?) TokenDraft(id, e.amountCtrl.text),
        ],
      ),
      for (final e in _extraRecipients)
        RecipientDraft(
          address: e.address,
          ergText: e.amount,
          tokenId: e.tokenId,
          tokenAmountText: e.tokenAmtCtrl?.text,
        ),
    ];
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final args = _args;
    final spend = _selectedSpendAddresses.isNotEmpty
        ? _selectedSpendAddresses.toList()
        : _allSpendAddresses;
    if (spend.isEmpty) {
      _snack('No spendable addresses');
      return;
    }

    List<Map<String, dynamic>> recipients;
    try {
      recipients = buildRecipients(_drafts(), tokens: args.tokens);
    } on SendFormException catch (e) {
      showErrorSheet(context, message: e.message);
      return;
    }
    final spendable = args.spendableNano;
    final fee = parseErgToNano(_feeCtrl.text) ?? minerFeeNano;
    if (spendable != null && totalNanoErg(recipients) +
        (_feeTokenId == null ? fee : 0) > spendable) {
      _snack('Amount plus fee exceeds your ${formatErg(spendable, maxFrac: 4)}');
      return;
    }

    final changeAddress =
        args.changeAddress.isEmpty ? args.senderAddress : args.changeAddress;
    final isMulti = needsMultiBuilder(recipients);
    setState(() => _sending = true);
    try {
      final SendPreview preview;
      if (isMulti) {
        preview = await walletService.prepareSendMulti(
          senderAddress: args.senderAddress,
          spendAddresses: spend,
          changeAddress: changeAddress,
          recipients: recipients,
          nodeUrl: networkController.activeUrl,
          feeNanoErg: parseErgToNano(_feeCtrl.text),
          inputBoxIds: _inputBoxIds,
          babelTokenId: _feeTokenId,
        );
      } else {
        final r = recipients.single;
        preview = await walletService.prepareSend(
          senderAddress: args.senderAddress,
          spendAddresses: spend,
          changeAddress: changeAddress,
          recipientAddress: r['address'] as String,
          amountNanoErg: r['amount_nano_erg'] as int,
          tokenId: r['token_id'] as String?,
          tokenAmount: r['token_amount'] as int?,
          nodeUrl: networkController.activeUrl,
          feeNanoErg: parseErgToNano(_feeCtrl.text),
          inputBoxIds: _inputBoxIds,
          babelTokenId: _feeTokenId,
        );
      }
      await _confirmAndSend(preview: preview, isMulti: isMulti);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showErrorSheet(context, title: 'Could not prepare the send', message: '$e');
    }
  }

  /// Clipboard-hijack defense: if the OS clipboard holds a *different*
  /// Ergo address than any entered recipient, make the user acknowledge it
  /// before the confirmation dialog appears.
  ///
  /// Skipped for a single recipient from a trusted source (contact or scan).
  /// Additional recipients are typed, so still require the check.
  /// Residual risk for free-typed entries — malware that swaps the clipboard
  /// *before* the user pastes is indistinguishable from ordinary paste — is
  /// mitigated by the selectable full-address display in the confirm dialog
  /// and contact-book usage, not by this check.
  Future<bool> _clipboardMatchesIntent(BuildContext ctx, String recipient,
      {Set<String> others = const {}}) async {
    if (_recipientTrusted && others.isEmpty) return true;
    final recipients = {recipient.trim(), ...others.map((address) => address.trim())};
    final clip = await Clipboard.getData('text/plain');
    final clipText = clip?.text?.trim() ?? '';
    if (clipText.isEmpty || recipients.contains(clipText)) return true;
    if (!looksLikeErgoAddress(clipText)) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('Clipboard holds another address'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Something you copied earlier is an Ergo address that differs '
                'from ${others.isEmpty ? 'the recipient' : 'every recipient'}. '
                'Malware can swap addresses on the clipboard. Verify every character.',
              ),
              const SizedBox(height: 12),
              Text(others.isEmpty ? 'Recipient:' : 'Recipients:',
                  style: Theme.of(context).textTheme.titleSmall),
              SelectableText(recipients.join('\n\n'),
                  style: monoStyle(context, size: 12)),
              const SizedBox(height: 8),
              Text('Clipboard:', style: Theme.of(context).textTheme.titleSmall),
              SelectableText(clipText, style: monoStyle(context, size: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(others.isEmpty ? 'Recipient is correct' : 'Recipients are correct'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _confirmAndSend({
    required SendPreview preview,
    required bool isMulti,
  }) async {
    final clear = await _clipboardMatchesIntent(context, _recipientCtrl.text.trim(),
        others: _extraRecipients.map((e) => e.address).toSet());
    if (!clear) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    if (!mounted) return;
    final tokenId = preview.tokenId;
    final rows = <ConfirmTxRow>[
      if (isMulti)
        for (final r in preview.recipients ?? const <Map<String, dynamic>>[])
          ConfirmTxRow(
            shorten(r['address']?.toString() ?? '', head: 8, tail: 6),
            '${formatErg((r['amount_nano_erg'] as num?)?.toInt() ?? 0)}'
            '${_tokensSuffix(r)}',
          ),
      ConfirmTxRow(
        isMulti ? 'Total sent' : 'Amount',
        formatErg(preview.amountNanoErg),
        bold: true,
      ),
      if (!isMulti && tokenId != null && tokenId.isNotEmpty)
        ConfirmTxRow('Token', _tokenLabel(preview.tokenAmount ?? 0, tokenId), bold: true),
      if (preview.babel case final b?)
        ConfirmTxRow(
          'Miner fee paid in ${_tokenById(b.tokenId)?.label ?? 'token'}',
          '${_tokenLabel(b.tokensPaid, b.tokenId)} for ${formatErg(b.feeNano)}',
          bold: true,
        )
      else
        ConfirmTxRow('Miner fee', formatErg(preview.minerFee)),
      ConfirmTxRow('Change to you', formatErg(preview.changeNanoErg)),
    ];
    final fiat = networkController.fiatText(preview.amountNanoErg);
    final choice = await showConfirmTransactionChoice(
      context,
      title: (preview.recipients?.length ?? 1) > 1 ? 'Confirm multi-recipient send' : 'Confirm send',
      rows: rows,
      recipientAddress: isMulti
          ? (preview.recipients ?? const <Map<String, dynamic>>[])
              .map((r) => r['address']?.toString() ?? '').join('\n\n')
          : preview.recipient,
      detail: [
        if (fiat != null) fiat,
        networkController.activeUrl ?? 'Node not chosen yet',
      ].join('  ·  '),
      allowSignOnly: true,
      preparationId: preview.preparationId,
    );
    if (!mounted) return;
    switch (choice) {
      case ConfirmChoice.cancel:
        setState(() => _sending = false);
      case ConfirmChoice.signOnly:
        try {
          final rawTxJson = await walletService.signPreparation(
            preparationId: preview.preparationId,
          );
          if (!mounted) return;
          _showRawTx(rawTxJson);
          setState(() => _sending = false);
        } catch (e) {
          if (!mounted) return;
          setState(() => _sending = false);
          showErrorSheet(context, title: 'Signing failed', message: '$e');
        }
      case ConfirmChoice.broadcast:
        try {
          final txId = await walletService.sendErg(
            preparationId: preview.preparationId,
          );
          if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
            showTxResultSheet(receiptContext, txId: txId, headline: 'Sent!');
            return;
          }
          HapticFeedback.mediumImpact();
          setState(() {
            _resultTxId = txId;
            _sending = false;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() => _sending = false);
          await showTxFailureSheet(context, e);
        }
    }
  }

  String _tokenLabel(int amount, String tokenId) {
    for (final t in _args.tokens) {
      if (t.id == tokenId) return '${formatTokenAmount(amount, t.decimals)} ${t.label}';
    }
    return '$tokenId: $amount';
  }

  /// Raw amount of [token] typed in [text], or the whole holding while the
  /// field is blank or unreadable: the widest amount sizes the box safely.
  int _rawTokenAmount(TokenBalance token, String text) {
    if (token.amount == 1 && token.decimals == 0) return 1;
    final parsed = parseDecimalToBase(text, token.decimals);
    return parsed == null || parsed <= 0 ? token.amount : parsed;
  }

  /// The tokens riding in the main recipient's box, id → raw amount.
  Map<String, int> get _mainRecipientTokens => {
    for (final e in _heldAmounts.entries)
      if (_tokenById(e.key) case final t?) e.key: _rawTokenAmount(t, e.value.text),
  };

  /// Storage-rent advice for a recipient box carrying [tokens], with a
  /// one-tap fill of the suggested ERG into [erg]. Never blocks the send:
  /// any amount the form accepts stays allowed.
  Widget? _rentHint({
    required String address,
    required TextEditingController erg,
    required Map<String, int> tokens,
  }) {
    final parameters = _rentParameters;
    if (parameters == null || tokens.isEmpty) return null;
    final typed = address.trim();
    // Until a recipient is typed, size the box for an ordinary address.
    final sizeFor = looksLikeRecipient(typed) ? typed : _args.receiveAddress;
    if (sizeFor.isEmpty) return null;
    final text = erg.text.trim();
    final value = text.isEmpty ? minBoxNano : parseErgToNano(text);
    if (value == null) return null;
    final key = [
      sizeFor,
      value,
      jsonEncode(tokens),
      parameters.height,
      parameters.storageFeeFactor,
      parameters.factorFromNode,
    ].join('|');
    if (_rentEstimates.length >= 64 && !_rentEstimates.containsKey(key)) {
      _rentEstimates.remove(_rentEstimates.keys.first);
    }
    final estimate = _rentEstimates.putIfAbsent(
      key,
      () => storageRent.estimateOutput(
        address: sizeFor,
        valueNano: value,
        tokens: tokens,
        parameters: parameters,
      ),
    );
    if (estimate == null) return null;
    final suggested = estimate.suggestedNano;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: RentHint(
        estimate: estimate,
        onUseSuggested: suggested == null
            ? null
            : () => setState(() => erg.text = formatErg(suggested, unit: false)),
      ),
    );
  }

  /// "Available 12.3456 ERG" under the amount field.
  String? _availableLine() {
    final available = _args.spendableNano;
    if (available == null) return null;
    return 'Available ${formatErg(available, maxFrac: 4)}';
  }

  String _advancedSummary() {
    final all = _allSpendAddresses.length;
    final picked = _selectedSpendAddresses.length;
    final fee = parseErgToNano(_feeCtrl.text) ?? minerFeeNano;
    return [
      picked == 0 ? 'All $all addresses' : '$picked of $all addresses',
      if (_chosenBoxIds.isNotEmpty) '${_chosenBoxIds.length} boxes chosen',
      _feeTokenId == null
          ? 'Fee ${formatErg(fee, unit: false)} ERG'
          : 'Fee in ${_tokenById(_feeTokenId)?.label ?? 'token'}',
    ].join('  ·  ');
  }

  int _tokenPage = 0;

  Map<String, TextEditingController> get _heldAmounts => {
    if (_selectedToken case final t?) t.id: _tokenAmtCtrl,
    for (final e in _extraTokens) e.tokenId!: e.amountCtrl,
  };

  // Reconcile by identity before changing the primary slot used by the existing
  // serializer. In particular, removing the first token cannot erase the next.
  void _selectHeld(Set<String> ids) {
    final amounts = {for (final e in _heldAmounts.entries) e.key: e.value.text};
    final old = [..._extraTokens];
    setState(() {
      _extraTokens.clear();
      _assetId = ids.firstOrNull;
      _tokenAmtCtrl.text = amounts[_assetId] ?? '';
      for (final id in ids.skip(1)) {
        final entry =
            old.where((e) => e.tokenId == id).firstOrNull ??
            (_TokenEntry()..tokenId = id);
        entry.amountCtrl.text = amounts[id] ?? '';
        _extraTokens.add(entry);
      }
      _tokenPage = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final e in old) {
        if (!_extraTokens.contains(e)) e.dispose();
      }
    });
  }

  Widget _heldTokenRows() {
    final entries = _heldAmounts.entries.toList();
    const pageSize = 10;
    final pages = (entries.length / pageSize).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pages > 1)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entries.length} tokens selected · Page ${_tokenPage + 1} of $pages',
                ),
              ),
              IconButton(
                tooltip: 'Previous tokens',
                onPressed: _tokenPage > 0
                    ? () => setState(() => _tokenPage--)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next tokens',
                onPressed: _tokenPage + 1 < pages
                    ? () => setState(() => _tokenPage++)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        for (final e in entries.skip(_tokenPage * pageSize).take(pageSize))
          _heldTokenRow(_tokenById(e.key)!, e.value),
      ],
    );
  }

  Widget _heldTokenRow(TokenBalance token, TextEditingController controller) {
    return Padding(
      key: ValueKey('amount-row-${token.id}'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: (token.amount == 1 && token.decimals == 0)
                ? Text('Sends 1 ${token.label} · Available 1')
                : TextFormField(
                    key: ValueKey('amount-${token.id}'),
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: '${token.label} amount',
                      helperText:
                          'Available ${formatTokenAmount(token.amount, token.decimals)}',
                      suffixIcon: TextButton(
                        onPressed: () {
                          if (token.id == _assetId) {
                            _applyMaxToken();
                          } else {
                            setState(
                              () => controller.text = formatTokenAmount(
                                token.amount,
                                token.decimals,
                              ),
                            );
                          }
                        },
                        child: const Text('MAX'),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    // The rent hint sizes the box from this amount.
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = parseDecimalToBase(v ?? '', token.decimals);
                      if (n == null || n <= 0) return 'Enter an amount';
                      if (n > token.amount) return 'Too much';
                      return null;
                    },
                  ),
          ),
          IconButton(
            tooltip: 'Remove ${token.label}',
            icon: const Icon(Icons.close),
            onPressed: () =>
                _selectHeld(_heldAmounts.keys.toSet()..remove(token.id)),
          ),
        ],
      ),
    );
  }

  /// " + 5 kushti + 1 Ape" for a recipient's tokens, or nothing.
  String _tokensSuffix(Map<String, dynamic> r) {
    final list = r['tokens'];
    if (list is List && list.isNotEmpty) {
      if (list.length > 10) return ' + ${list.length} tokens';
      return [
        for (final t in list.cast<Map>()) ' + ${_tokenLabel((t['amount'] as num?)?.toInt() ?? 0, t['token_id'] as String)}',
      ].join();
    }
    if (r['token_id'] != null) {
      return ' + ${_tokenLabel((r['token_amount'] as num?)?.toInt() ?? 0, r['token_id'] as String)}';
    }
    return '';
  }

  TokenBalance? _tokenById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final t in _args.tokens) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showRawTx(String rawTxJson) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raw signed transaction'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Transaction is signed but not broadcast. Share or save the raw transaction '
                'to submit later via an explorer or another wallet.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: SelectableText(
                    rawTxJson,
                    style: monoStyle(ctx, size: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: rawTxJson)),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
          TextButton.icon(
                onPressed: () async {
                  final bytes = Uint8List.fromList(utf8.encode(rawTxJson));
                  await SharePlus.instance.share(ShareParams(
                    files: [XFile.fromData(bytes, name: 'signed_tx.json', mimeType: 'application/json')],
                  ));
                },
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Share'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = _selectedToken;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        actions: [
          IconButton(
            tooltip: 'Contacts',
            onPressed: () async {
              // Untyped on purpose: the app's routes are built untyped, and
              // a typed push throws before the picker even opens.
              final result = await Navigator.pushNamed(context, '/contacts', arguments: true);
              if (!mounted) return;
              if (result is WalletContact && result.address.isNotEmpty) {
                _recipientCtrl.text = result.address;
                _recipientTrusted = true;
                setState(() {});
              }
            },
            icon: const Icon(Icons.people_outline),
          ),
          IconButton(
            tooltip: 'Scan',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: _resultTxId != null
          ? Center(
              child: TxResultView(
                txId: _resultTxId!,
                headline: 'Sent!',
                onDismiss: () => Navigator.pop(context),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const OfflineBanner(),
                    const SectionLabel('Destination'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _recipientCtrl,
                      style: monoStyle(context, size: 13),
                      decoration: InputDecoration(
                        labelText: 'Recipient address',
                        hintText: 'Or tap contacts to pick a saved one',
                        helperText: _contactForRecipient,
                      ),
                      onChanged: (_) {
                        // Free-typed or re-pasted text loses trusted provenance.
                        _recipientTrusted = false;
                        setState(() {});
                      },
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!looksLikeRecipient(v)) return 'Not an Ergo address';
                        return null;
                      },
                    ),
                    if (_recipientValid)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _saveRecipientToContacts,
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: const Text('Save to contacts'),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const SectionLabel('Asset'),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
                      onPressed: () async {
                        final ids = await showHeldTokenPicker(context, tokens: _args.tokens, selected: _heldAmounts.keys.toSet());
                        if (ids != null && mounted) _selectHeld(ids);
                      },
                      icon: const Icon(Icons.checklist),
                      label: Text(_heldAmounts.isEmpty ? 'Choose tokens' : 'Choose tokens (${_heldAmounts.length})'),
                    )),
                    const SizedBox(height: 12),
                    if (token == null)
                      AmountEntry(
                        controller: _amountCtrl,
                        helperText: _availableLine(),
                        onMax: _applyMaxErg,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = parseErgToNano(v ?? '');
                          if (n == null || n < minBoxNano) return 'Minimum 0.001 ERG';
                          return null;
                        },
                      ),
                    _heldTokenRows(),
                    // A token send may carry ERG too, and more tokens: they
                    // all travel in the recipient's one box.
                    if (token != null) ...[
                      const SizedBox(height: 12),
                      AmountEntry(
                        controller: _amountCtrl,
                        label: 'ERG to send with it (optional)',
                        helperText: 'Blank funds the minimum ERG for these tokens. Review shows the exact amount. ${_availableLine() ?? ''}',
                        onMax: _applyMaxErg,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = parseErgToNano(v);
                          if (n == null || n < minBoxNano) return 'Minimum 0.001 ERG';
                          return null;
                        },
                      ),
                      if (_rentHint(
                        address: _recipientCtrl.text,
                        erg: _amountCtrl,
                        tokens: _mainRecipientTokens,
                      ) case final hint?)
                        hint,
                    ],
                    const SizedBox(height: 16),
                    if (_multiRecipient)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Additional recipients',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          ..._extraRecipients.asMap().entries.map((e) {
                            final idx = e.key;
                            final entry = e.value;
                            final entryToken = _tokenById(entry.tokenId);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextFormField(
                                      controller: entry.addressCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Recipient ${idx + 2} address',
                                        hintText: '9...',
                                      ),
                                      style: monoStyle(context, size: 13),
                                      onChanged: (_) => setState(() {}),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Required';
                                        if (!looksLikeRecipient(v)) {
                                          return 'Not an Ergo address';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    AmountEntry(
                                      controller: entry.amountCtrl,
                                      label: entryToken == null ? 'Amount (ERG)' : 'ERG to send with it (optional)',
                                      helperText: entryToken == null ? null : 'Blank funds the minimum ERG for this token.',
                                      onChanged: (_) => setState(() {}),
                                      validator: (v) {
                                        if (entryToken != null && (v == null || v.trim().isEmpty)) return null;
                                        final n = parseErgToNano(v ?? '');
                                        if (n == null || n < minBoxNano) return 'Minimum 0.001 ERG';
                                        return null;
                                      },
                                    ),
                                    if (_args.tokens.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String?>(
                                        initialValue: entry.tokenId,
                                        decoration: const InputDecoration(labelText: 'Token'),
                                        items: [
                                          const DropdownMenuItem(value: null, child: Text('None')),
                                          ..._args.tokens.map(
                                            (t) => DropdownMenuItem(value: t.id, child: Text(t.label)),
                                          ),
                                        ],
                                        onChanged: (v) {
                                          if (entry.tokenId != v) entry.tokenAmtCtrl?.clear();
                                          entry.tokenId = v;
                                          if (v != null && v.isNotEmpty && entry.tokenAmtCtrl == null) {
                                            entry.tokenAmtCtrl = TextEditingController();
                                          }
                                          setState(() {});
                                        },
                                      ),
                                      if (entryToken != null && entry.tokenAmtCtrl != null) ...[
                                        const SizedBox(height: 12),
                                        if (entryToken.amount == 1 && entryToken.decimals == 0)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('Sends 1 ${entryToken.label} · Available 1'),
                                          )
                                        else TextFormField(
                                          controller: entry.tokenAmtCtrl,
                                          decoration: InputDecoration(
                                            labelText: '${entryToken.label} amount',
                                            helperText:
                                                'Available ${formatTokenAmount(entryToken.amount, entryToken.decimals)}',
                                          ),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          onChanged: (_) => setState(() {}),
                                          validator: (v) {
                                            final n = parseDecimalToBase(v ?? '', entryToken.decimals);
                                            if (n == null || n <= 0) return 'Enter a token amount';
                                            if (n > entryToken.amount) {
                                              return 'You hold ${formatTokenAmount(entryToken.amount, entryToken.decimals)}';
                                            }
                                            return null;
                                          },
                                        ),
                                        if (_rentHint(
                                          address: entry.address,
                                          erg: entry.amountCtrl,
                                          tokens: {
                                            entryToken.id: _rawTokenAmount(
                                              entryToken,
                                              entry.tokenAmtCtrl!.text,
                                            ),
                                          },
                                        ) case final hint?)
                                          hint,
                                      ],
                                    ],
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          setState(() => _extraRecipients.removeAt(idx));
                                          WidgetsBinding.instance.addPostFrameCallback((_) => entry.dispose());
                                        },
                                        icon: const Icon(Icons.delete, size: 16),
                                        label: const Text('Remove'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _extraRecipients.add(_RecipientEntry());
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add another recipient'),
                          ),
                        ],
                      )
                    else
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _extraRecipients.add(_RecipientEntry());
                          });
                        },
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Add another recipient'),
                      ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: const Text('Advanced'),
                      subtitle: Text(
                        _advancedSummary(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      onExpansionChanged: (_) => setState(() {}),
                      children: [
                        if (token != null) ...[
                          TextFormField(
                            controller: _amountCtrl,
                            decoration: InputDecoration(
                              labelText: 'ERG carried with the token',
                              hintText: formatErg(minBoxNano, unit: false),
                              helperText:
                                  'Leave blank for the minimum box value of ${formatErg(minBoxNano)}.',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final n = parseErgToNano(v);
                              if (n == null || n < minBoxNano) return 'Minimum 0.001 ERG';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Inputs',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectionSummary(_selection),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              key: const Key('choose-inputs'),
                              onPressed: _loadingBoxes ? null : _openInputPicker,
                              child: Text(_loadingBoxes ? 'Loading…' : 'Choose'),
                            ),
                          ],
                        ),
                        if (selectionPrivacyNote(_selection) case final note?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(note,
                                style: TextStyle(fontSize: 12.5, color: rustFor(context))),
                          ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Spend from',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Deselected addresses are excluded from coin selection.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _allSpendAddresses.map((addr) {
                              final sel = _selectedSpendAddresses.contains(addr);
                              return FilterChip(
                                label: Text(
                                  shorten(addr, head: 4, tail: 4),
                                  style: monoStyle(context, size: 10),
                                ),
                                selected: sel,
                                onSelected: (_) {
                                  setState(() {
                                    if (sel) {
                                      _selectedSpendAddresses.remove(addr);
                                    } else {
                                      _selectedSpendAddresses.add(addr);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                        ),
                        if (_selectedSpendAddresses.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _selectedSpendAddresses.clear()),
                              child: const Text('Use all addresses'),
                            ),
                          ),
                        if (_args.tokens.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            key: const Key('send-fee-token'),
                            initialValue: _feeTokenId,
                            decoration: const InputDecoration(
                              labelText: 'Pay the miner fee in',
                              helperText: 'A token fee is bought from a babel box on chain at its posted price; the ERG fee below is what it buys.',
                              helperMaxLines: 3,
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('ERG')),
                              for (final t in _args.tokens)
                                DropdownMenuItem(value: t.id, child: Text(t.label, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => _feeTokenId = v),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _feeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Miner fee (ERG)',
                            hintText: formatErg(minerFeeNano, unit: false),
                            helperText: 'Leave blank for the default ${formatErg(minerFeeNano)}.',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = parseErgToNano(v);
                            if (n == null || n < minerFeeNano) return 'Minimum ${formatErg(minerFeeNano)}';
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _sending ? null : _send,
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Review'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InputPickerSheet extends StatelessWidget {
  const _InputPickerSheet({
    required this.boxes,
    required this.chosen,
    required this.amountNanoErg,
    required this.feeNanoErg,
    required this.onToggle,
    required this.onClear,
  });

  final List<InputBoxInput> boxes;
  final Set<String> chosen;
  final int amountNanoErg;
  final int feeNanoErg;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = ArgusColors.of(context);
    final selection = summariseSelection(boxes, chosen);
    final check = checkSelection(
      selection: selection,
      amountNanoErg: amountNanoErg,
      feeNanoErg: feeNanoErg,
    );
    final note = selectionPrivacyNote(selection);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Choose inputs',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (chosen.isNotEmpty)
                  TextButton(onPressed: onClear, child: const Text('Automatic')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              chosen.isEmpty
                  ? 'Argus will pick boxes for you. Choose some to control exactly what this transaction spends.'
                  : selectionSummary(selection),
              style: TextStyle(fontSize: 12.5, color: colors.muted),
            ),
            if (chosen.isNotEmpty && !check.covers) ...[
              const SizedBox(height: 6),
              Text(
                'Short by ${formatErg(check.shortfallNano, maxFrac: 4)} for this amount plus fees.',
                style: TextStyle(fontSize: 12.5, color: rustFor(context)),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note, style: TextStyle(fontSize: 12.5, color: rustFor(context))),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: boxes.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: colors.cardBorder),
                itemBuilder: (context, i) {
                  final b = boxes[i];
                  final on = chosen.contains(b.boxId);
                  final tokens = b.assets.length;
                  return CheckboxListTile(
                    key: Key('box-${b.boxId}'),
                    value: on,
                    onChanged: (_) => onToggle(b.boxId),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(formatErg(b.valueNanoErg.toInt(), maxFrac: 4)),
                    subtitle: Text(
                      [
                        if (b.address != null && b.address!.isNotEmpty)
                          shorten(b.address!, head: 6, tail: 4),
                        if (tokens > 0) '$tokens token${tokens == 1 ? '' : 's'}',
                        'block ${b.creationHeight}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: colors.muted),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
