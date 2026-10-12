import '../services/watch_account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../services/address_label_service.dart';
import '../services/session_lock.dart';
import '../services/privacy_service.dart';
import '../services/wallet_service.dart';
import '../theme/argus_theme.dart';
import 'widgets/soft_card.dart';
import 'widgets/entry_dialogs.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _amountCtrl = TextEditingController();
  String _qrData = '';
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_updateQr);
    privacyService.addListener(_privacyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateQr();
  }

  @override
  void dispose() {
    privacyService.removeListener(_privacyChanged);
    _amountCtrl.removeListener(_updateQr);
    _amountCtrl.dispose();
    super.dispose();
  }

  void _privacyChanged() {
    if (mounted) setState(() {});
  }

  void _updateQr() {
    final request = receiveRequest(
      address: WalletRouteArgs.of(context).receiveAddress,
      amount: _amountCtrl.text,
    );
    if (request.payload != _qrData || request.error != _amountError) {
      setState(() {
        _qrData = request.payload;
        _amountError = request.error;
      });
    }
  }

  Future<void> _editLabel(String address) async {
    final label = await showAddressLabelDialog(
      context,
      address: address,
      existing: addressLabelService.labelFor(address) ?? '',
    );
    if (label == null) return;
    await addressLabelService.setLabel(address, label);
  }

  Widget _usedAddressRow(BuildContext context, String a) {
    final colors = ArgusColors.of(context);
    final label = addressLabelService.labelFor(a);
    return InkWell(
      onTap: () async {
        await sessionLock.run(() => Clipboard.setData(ClipboardData(text: a)));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${shorten(a, head: 8, tail: 6)} copied')),
          );
        }
      },
      onLongPress: () => _editLabel(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shorten(a, head: 12, tail: 10), style: monoStyle(context, size: 12)),
                  if (label != null && label.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(label, style: TextStyle(fontSize: 12, color: colors.muted)),
                  ],
                ],
              ),
            ),
            Icon(Icons.copy, size: 16, color: colors.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = WalletRouteArgs.of(context);
    final address = args.receiveAddress;
    final fresh = !args.watchOnly &&
        privacyService.useUnusedChangeAddress(walletService.activeWalletId);

    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
                28, 16, 28, 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          SectionLabel(fresh
              ? 'Unused address' : 'Receive address'),
          const SizedBox(height: 8),
          Text(
            args.watchOnly
                ? args.watchAccount
                    ? 'Unused payment address. A new one is offered after payment. $watchAccountLimitations'
                    : 'Payments to this address go to the watched wallet.'
                : fresh
                ? 'A new address is shown after this one is used.'
                : 'This address stays the same. Turn on Fresh addresses in Settings to use a new one after each payment.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('receive-amount'),
            controller: _amountCtrl,
            decoration: InputDecoration(
              labelText: 'Optional amount (ERG)',
              hintText: '0.001',
              errorText: _amountError,
              suffixIcon: const Icon(Icons.tag),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 28),
          if (address.isNotEmpty)
            Center(
              child: Container(
                // Scanners need dark-on-light; the pale card reads as a
                // deliberate "ticket" in both palettes.
                decoration: BoxDecoration(
                  color: paper,
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(color: accentOf(context).withValues(alpha: 0.45)),
                ),
                padding: const EdgeInsets.all(18),
                child: QrImageView(
                  data: _qrData.isEmpty ? address : _qrData,
                  semanticsLabel: _qrData.isEmpty ? address : _qrData,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: paper,
                  padding: EdgeInsets.zero,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: ink,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: ink,
                  ),
          ),
            ),
          ),
          const SizedBox(height: 28),
          if (address.isNotEmpty)
            ListenableBuilder(
              listenable: addressLabelService,
              builder: (context, _) {
                final label = addressLabelService.labelFor(address);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (label != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accentOf(context).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(label, style: TextStyle(color: accentTextOf(context), fontSize: 12)),
                      ),
                    if (label != null) const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _editLabel(address),
                      icon: const Icon(Icons.edit, size: 14),
                      label: Text(label == null ? 'Add label' : 'Edit label'),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 20),
          SelectableText(
            address,
            style: monoStyle(context, size: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: address.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: address));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Address copied')),
                    );
                  },
            child: const Text('Copy address'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: address.isEmpty || _amountError != null
                ? null
                : () => sessionLock.run(
                      () => SharePlus.instance.share(ShareParams(text: _qrData)),
                    ),
            child: const Text('Share'),
          ),
          if (!args.watchOnly && args.historyAddresses.where((a) => a != address).isNotEmpty) ...[
            const SizedBox(height: 28),
            const SectionLabel('Used addresses'),
            const SizedBox(height: 4),
            Text(
              'Older addresses keep working; tap one to copy it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: addressLabelService,
              builder: (context, _) => SoftCard(
                padding: EdgeInsets.zero,
                child: DividedColumn(
                  indent: 16,
                  children: [
                    for (final a in args.historyAddresses)
                      if (a != address) _usedAddressRow(context, a),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a receive request says: the string the QR encodes and Share sends,
/// and why an amount was rejected. Sharing the bare address would drop the
/// amount the payer is meant to see, so both carry the same payload.
({String payload, String? error}) receiveRequest({required String address, required String amount}) {
  final trimmed = amount.trim();
  if (trimmed.isEmpty) return (payload: address, error: null);
  final nano = parseErgToNano(trimmed);
  if (nano == null) {
    return (payload: address, error: 'Amount must be a decimal number, like 0.001');
  }
  if (nano <= 0) {
    return (payload: address, error: 'Amount must be greater than zero');
  }
  return (payload: 'ergo:$address?amount=${formatErg(nano, unit: false)}', error: null);
}
