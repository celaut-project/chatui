import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_deposit.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_strings.dart';
import '../../celaut/deposit_strings.dart';
import '../../celaut/host_port.dart';
import '../../format.dart';
import '../../services/network_controller.dart';
import '../../services/wallet_service.dart';
import '../../theme/argus_theme.dart';
import '../confirm_transaction_sheet.dart';
import '../settings/settings_shared.dart';
import '../widgets/soft_card.dart';
import 'deposit_confirm.dart';

/// The smallest deposit: the minimum value of an Ergo box.
const minDepositNano = 1000000;

/// What the deposit screen needs from the wallet. The app uses [AppDepositWallet];
/// tests give their own.
abstract class DepositWallet {
  /// Why this wallet cannot make a deposit, or null if it can.
  String? cannotSign(BuildContext context);

  /// Prepare the deposit (`celaut_deposit_prepare`) with the addresses of the wallet.
  Future<DepositPreparedView> prepare(
    BuildContext context,
    NodeAddress node,
    int amountNanoErg,
  );

  /// Sign and send the preparation, as every send of the wallet. Gives the
  /// transaction id.
  Future<String> send(int preparationId);
}

/// The open wallet of the app.
class AppDepositWallet implements DepositWallet {
  const AppDepositWallet();

  @override
  String? cannotSign(BuildContext context) {
    final args = WalletRouteArgs.of(context);
    return args.watchOnly || args.watchAccount ? DepositStrings.watchOnly : null;
  }

  @override
  Future<DepositPreparedView> prepare(
    BuildContext context,
    NodeAddress node,
    int amountNanoErg,
  ) {
    final args = WalletRouteArgs.of(context);
    return walletService.prepareCelautDeposit(
      node: node,
      senderAddress: args.senderAddress,
      spendAddresses: args.historyAddresses,
      changeAddress: args.changeAddress,
      amountNanoErg: amountNanoErg,
      nodeUrl: networkController.activeUrl,
    );
  }

  @override
  Future<String> send(int preparationId) async {
    final sent = await walletService.sendErgDetailed(preparationId: preparationId);
    return sent['tx_id'] as String? ?? '';
  }
}

/// Debug screen of milestone M3: deposit ERG to a node from this wallet. Check the
/// node, prepare the deposit, confirm it in the confirmation sheet of the wallet, wait
/// until the explorer shows the box, then the node checks it once (`Payable`).
class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key, this.wallet = const AppDepositWallet()});

  final DepositWallet wallet;

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  final _nodeCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '0.01');

  String? _nodeError;
  String? _limitError;
  String? _amountError;
  bool _checking = false;
  bool _preparing = false;
  bool _waiting = false;

  NodeAddress? _node;
  DepositNodeView? _info;
  DepositPreparedView? _sent;
  String? _txId;
  DepositDoneView? _done;
  String? _note;
  CelautError? _error;

  @override
  void dispose() {
    _nodeCtrl.dispose();
    _limitCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final parsed = parseHostPort(_nodeCtrl.text);
    if (parsed.value == null) {
      setState(() => _nodeError = switch (parsed.error) {
            HostPortError.empty => CelautStrings.addressEmpty,
            HostPortError.port => CelautStrings.portInvalid,
            _ => CelautStrings.addressInvalid,
          });
      return;
    }
    final node = NodeAddress(host: parsed.value!.host, port: parsed.value!.port);
    setState(() {
      _nodeError = null;
      _checking = true;
      _error = null;
    });
    try {
      final info = await celautDepositNode(node: node);
      if (!mounted) return;
      setState(() {
        _node = node;
        _info = info;
        _limitCtrl.text = formatErg(info.limitNanoErg.toInt(), unit: false);
      });
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _setLimit() async {
    final info = _info;
    if (info == null) return;
    final limit = parseErgToNano(_limitCtrl.text.trim());
    if (limit == null || limit < 0) {
      setState(() => _limitError = DepositStrings.limitInvalid);
      return;
    }
    setState(() => _limitError = null);
    try {
      await celautSetDepositLimit(peerId: info.peerId, limitNanoErg: BigInt.from(limit));
      await _check();
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _deposit() async {
    final node = _node;
    if (node == null) return;
    final amount = parseErgToNano(_amountCtrl.text.trim());
    if (amount == null || amount < minDepositNano) {
      setState(() => _amountError = DepositStrings.amountInvalid);
      return;
    }
    final cannot = widget.wallet.cannotSign(context);
    setState(() {
      _amountError = cannot;
      _error = null;
      _note = null;
      _done = null;
      _txId = null;
      _sent = null;
    });
    if (cannot != null) return;

    setState(() => _preparing = true);
    DepositPreparedView prepared;
    try {
      prepared = await widget.wallet.prepare(context, node, amount);
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    } catch (e) {
      if (mounted) setState(() => _note = '$e');
      return;
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
    if (!mounted) return;

    final choice = await showDepositConfirmation(context, prepared);
    if (!mounted) return;
    if (choice != ConfirmChoice.broadcast) {
      try {
        await celautDepositCancel(depositId: prepared.depositId);
      } on CelautError catch (_) {
        // A deposit that was not sent always cancels; nothing else to do.
      }
      if (mounted) setState(() => _note = DepositStrings.cancelled);
      return;
    }

    String txId;
    try {
      txId = await widget.wallet.send(prepared.preparationId.toInt());
    } catch (e) {
      if (mounted) setState(() => _note = DepositStrings.sendFailed('$e'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _sent = prepared;
      _txId = txId;
    });
    await _wait();
  }

  Future<void> _wait() async {
    final sent = _sent;
    final txId = _txId;
    if (sent == null || txId == null) return;
    setState(() {
      _waiting = true;
      _error = null;
    });
    try {
      final done = await celautDepositNotify(depositId: sent.depositId, txId: txId);
      if (mounted) setState(() => _done = done);
    } on CelautError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return SettingsPage(
      title: DepositStrings.screenTitle,
      children: [
        SettingsNote(DepositStrings.intro),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('deposit-node'),
                controller: _nodeCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: DepositStrings.nodeLabel,
                  hintText: DepositStrings.nodeHint,
                  errorText: _nodeError,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('deposit-check'),
                onPressed: _checking ? null : _check,
                child: Text(_checking ? DepositStrings.checking : DepositStrings.check),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_error != null) _errorCard(context, _error!),
        if (_note != null)
          SoftCard(child: SelectableText(_note!, key: const Key('deposit-note'))),
        if (_txId != null) _statusCard(context),
        if (info != null) ..._nodeCards(context, info),
      ],
    );
  }

  List<Widget> _nodeCards(BuildContext context, DepositNodeView info) {
    final muted = ArgusColors.of(context).muted;
    final busy = _preparing || _waiting;
    return [
      const SizedBox(height: 10),
      SectionLabel(DepositStrings.nodeTitle),
      const SizedBox(height: 10),
      SoftCard(
        child: Column(
          key: const Key('deposit-info'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(info.peerId, style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 6),
            SelectableText(DepositStrings.payTo(info.payToAddress)),
            Text(DepositStrings.rate(groupMu(info.muPerNanoErg))),
            Text(DepositStrings.balance(groupMu(info.clientBalanceMu)),
                key: const Key('deposit-balance')),
            Text(
              DepositStrings.used(
                formatErg(info.depositedNanoErg.toInt()),
                formatErg(info.limitNanoErg.toInt()),
              ),
              key: const Key('deposit-used'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('deposit-limit'),
                    controller: _limitCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: DepositStrings.limitLabel,
                      errorText: _limitError,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  key: const Key('deposit-set-limit'),
                  onPressed: busy ? null : _setLimit,
                  child: Text(DepositStrings.setLimit),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('deposit-amount'),
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: DepositStrings.amountLabel,
                hintText: DepositStrings.amountHint,
                errorText: _amountError,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('deposit-prepare'),
              onPressed: busy ? null : _deposit,
              child: Text(_preparing ? DepositStrings.preparing : DepositStrings.prepare),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _statusCard(BuildContext context) {
    final muted = ArgusColors.of(context).muted;
    final done = _done;
    return SoftCard(
      child: Column(
        key: const Key('deposit-status'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(DepositStrings.tx(_txId!), style: TextStyle(fontSize: 12, color: muted)),
          if (done != null) ...[
            SelectableText(DepositStrings.box(done.boxId),
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 6),
            Text(
              done.accepted
                  ? DepositStrings.accepted(groupMu(done.clientBalanceMu))
                  : DepositStrings.refused(done.nodeMessage ?? ''),
              key: const Key('deposit-done'),
              style: done.accepted ? null : TextStyle(color: rustFor(context)),
            ),
          ] else if (_waiting) ...[
            const SizedBox(height: 6),
            Text(DepositStrings.waiting, key: const Key('deposit-waiting')),
          ] else ...[
            const SizedBox(height: 6),
            OutlinedButton(
              key: const Key('deposit-wait-again'),
              onPressed: _wait,
              child: Text(DepositStrings.waitAgain),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, CelautError e) {
    return SoftCard(
      child: Column(
        key: const Key('deposit-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(CelautStrings.errorText(e.kind),
              style: TextStyle(fontSize: 14, color: rustFor(context))),
          if (e.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(CelautStrings.detailLabel(e.message),
                style: TextStyle(fontSize: 12, color: ArgusColors.of(context).muted)),
          ],
        ],
      ),
    );
  }
}
