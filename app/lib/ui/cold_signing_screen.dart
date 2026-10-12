import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../bridge/api.dart' as api;
import '../l10n/l10n.dart';
import '../services/cold_signing_service.dart';
import '../services/network_controller.dart';
import '../services/watch_account_service.dart';
import '../services/wallet_service.dart';
import 'scan_screen.dart';

class ColdSigningScreen extends StatefulWidget {
  const ColdSigningScreen({
    super.key,
    required this.controller,
    required this.onDiscard,
    this.scan,
    this.handle,
  });
  final ColdSigningController controller;
  final VoidCallback onDiscard;
  final Future<String?> Function(BuildContext)? scan;
  final BigInt? Function()? handle;
  @override
  State<ColdSigningScreen> createState() => _ColdSigningScreenState();
}

class _ColdSigningScreenState extends State<ColdSigningScreen> {
  bool approved = false;
  ColdSigningController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    if (c.stage == ColdStage.requestQr && c.qrPages.isEmpty)
      unawaited(c.loadPages());
  }

  BigInt? get handle =>
      widget.handle != null ? widget.handle!() : walletService.handleId;
  Future<void> scan() async {
    final value =
        await (widget.scan?.call(context) ??
            Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const ScanScreen()),
            ));
    if (value != null) await c.addPage(value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(c.hot ? context.l10n.coldTitleHot : context.l10n.coldTitleOffline),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(context.l10n.coldSessionNote),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.l10n.coldRefused('${c.error}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.stage == ColdStage.requestQr ||
              c.stage == ColdStage.responseQr) ...[
            Text(
              c.stage == ColdStage.requestQr
                  ? context.l10n.coldScanRequestCodes
                  : context.l10n.coldSignedScanResponse,
            ),
            if (c.qrPages.isNotEmpty) ColdQrSequence(pages: c.qrPages),
            if (c.qrPages.isEmpty && !c.busy)
              OutlinedButton(
                onPressed: c.loadPages,
                child: Text(context.l10n.coldLoadQrCodes),
              ),
            if (c.hot)
              FilledButton(
                onPressed: c.busy ? null : c.scanResponse,
                child: Text(context.l10n.coldScanSignedResponse),
              ),
          ],
          if (c.stage == ColdStage.scan) ...[
            if (c.hot)
              TextButton(
                onPressed: c.busy ? null : c.showRequest,
                child: Text(context.l10n.coldShowRequestAgain),
              ),
            Text(
              c.hot
                  ? context.l10n.coldCollectResponse
                  : context.l10n.coldCollectRequest,
            ),
            Text(
              context.l10n.coldScannedProgress('${c.received}', '${c.total ?? '?'}'),
              key: const Key('page-progress'),
            ),
            if (c.missing.isNotEmpty)
              Text(context.l10n.coldMissingPages(c.missing.join(', '))),
            if (c.refused)
              Text(context.l10n.coldScanRefused),
            FilledButton.icon(
              onPressed: c.busy || c.refused || c.complete ? null : scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(c.received == 0 ? context.l10n.coldScanACode : context.l10n.coldScanNextCode),
            ),
            OutlinedButton(
              onPressed: c.busy
                  ? null
                  : () {
                      approved = false;
                      c.reset();
                    },
              child: Text(context.l10n.coldResetPages),
            ),
            FilledButton(
              onPressed: c.busy || !c.complete ? null : () => c.finish(handle),
              child: Text(
                c.hot ? context.l10n.coldVerifySigned : context.l10n.coldReviewTransaction,
              ),
            ),
          ],
          if (c.stage == ColdStage.review ||
              c.stage == ColdStage.verified ||
              c.stage == ColdStage.requestQr) ...[
            if (c.reviewData != null)
              ColdTransactionReview(data: c.reviewData!),
          ],
          if (c.stage == ColdStage.review) ...[
            Text(context.l10n.coldReviewWarning),
            CheckboxListTile(
              value: approved,
              onChanged: c.busy
                  ? null
                  : (v) => setState(() => approved = v ?? false),
              title: Text(context.l10n.coldCheckedEverything),
            ),
            FilledButton(
              onPressed: approved && !c.busy ? () => c.sign(handle) : null,
              child: Text(context.l10n.coldConfirmSign),
            ),
            OutlinedButton(
              onPressed: c.busy
                  ? null
                  : () {
                      approved = false;
                      c.reset();
                    },
              child: Text(context.l10n.coldRejectReset),
            ),
          ],
          if (c.stage == ColdStage.verified) ...[
            Text(context.l10n.coldVerifiedMatch),
            SelectableText(context.l10n.coldTransactionId('${c.transactionId}')),
            FilledButton(
              onPressed: c.busy ? null : c.broadcast,
              child: Text(context.l10n.coldBroadcastVerified),
            ),
            Text(context.l10n.coldRetryNote),
          ],
          if (c.stage == ColdStage.broadcast) ...[
            Text(context.l10n.coldSubmitted),
            SelectableText(c.transactionId!),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: c.busy
                ? null
                : () async {
                    await c.backend.discard(c.session);
                    widget.onDiscard();
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Text(context.l10n.coldDiscardSession),
          ),
        ],
      ),
    ),
  );
}

class ColdTransactionReview extends StatelessWidget {
  const ColdTransactionReview({super.key, required this.data});
  final Map<String, dynamic> data;
  static String erg(String nano) {
    final n = BigInt.parse(nano);
    return '${n ~/ BigInt.from(1000000000)}.${(n % BigInt.from(1000000000)).toString().padLeft(9, '0')} ERG';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text(
        context.l10n.coldReviewNetwork('${data['network']}'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(context.l10n.coldMinerFeeValue(erg(data['fee_nano'] as String))),
      Text(context.l10n.coldOutputsNote),
      for (final output in data['outputs'] as List)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  output['is_fee'] == true
                      ? context.l10n.commonMinerFee
                      : output['owned'] == true
                      ? context.l10n.coldYourAddress
                      : context.l10n.coldExternalRecipient,
                ),
                if (output['address'] != null)
                  SelectableText(output['address'] as String),
                Text(erg(output['nano_erg'] as String)),
                for (final token in output['tokens'] as List) ...[
                  SelectableText(context.l10n.coldTokenId('${token['id']}')),
                  Text(context.l10n.coldQuantityBaseUnits('${token['amount']}')),
                ],
              ],
            ),
          ),
        ),
      for (final kind in ['burns', 'mints']) ...[
        Text(
          (kind == 'burns' ? context.l10n.coldTokenBurns : context.l10n.coldTokenCreation)(
            (data[kind] as List).isEmpty ? context.l10n.coldNone : '',
          ),
        ),
        for (final token in data[kind] as List)
          SelectableText(context.l10n.coldTokenAmountBaseUnits('${token['id']}', '${token['amount']}')),
      ],
    ],
  );
}

class ColdQrSequence extends StatefulWidget {
  const ColdQrSequence({super.key, required this.pages});
  final List<String> pages;
  @override
  State<ColdQrSequence> createState() => _ColdQrSequenceState();
}

class _ColdQrSequenceState extends State<ColdQrSequence> {
  int page = 0;
  Timer? timer;
  void toggle() {
    if (timer != null) {
      timer!.cancel();
      setState(() => timer = null);
    } else {
      setState(
        () => timer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (mounted) setState(() => page = (page + 1) % widget.pages.length);
        }),
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(context.l10n.coldCodeOf('${page + 1}', '${widget.pages.length}')),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: QrImageView(
          data: widget.pages[page],
          size: 280,
          errorCorrectionLevel: QrErrorCorrectLevel.L,
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            onPressed: () => setState(
              () =>
                  page = (page - 1 + widget.pages.length) % widget.pages.length,
            ),
            child: Text(context.l10n.coldPrevious),
          ),
          TextButton(
            onPressed: toggle,
            child: Text(timer == null ? context.l10n.coldAutoRepeat : context.l10n.coldPause),
          ),
          TextButton(
            onPressed: () =>
                setState(() => page = (page + 1) % widget.pages.length),
            child: Text(context.l10n.coldNext),
          ),
        ],
      ),
    ],
  );
}

Future<void> openColdSigner(BuildContext context) async {
  try {
    pendingColdSigner ??= ColdSigningController(
      session: await api.coldStart(),
      hot: false,
    );
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ColdSigningScreen(
          controller: pendingColdSigner!,
          onDiscard: () => pendingColdSigner = null,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

class ColdWatchSendScreen extends StatefulWidget {
  const ColdWatchSendScreen({super.key, required WatchAccount this.account})
    : address = null;
  const ColdWatchSendScreen.address({super.key, required String this.address})
    : account = null;
  final WatchAccount? account;
  final String? address;
  @override
  State<ColdWatchSendScreen> createState() => _ColdWatchSendScreenState();
}

class _ColdWatchSendScreenState extends State<ColdWatchSendScreen> {
  String get sourceKey => widget.account?.key ?? 'address:${widget.address}';
  final recipient = TextEditingController();
  final amount = TextEditingController();
  final token = TextEditingController();
  final quantity = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    recipient.dispose();
    amount.dispose();
    token.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> prepare() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final snapshot = widget.account?.snapshot;
      if (widget.account != null && snapshot == null)
        throw StateError(appL10n.coldRefreshWatchedFirst);
      final node = networkController.activeUrl;
      if (node == null) throw StateError(appL10n.coldChooseNodeFirst);
      final amountNano = int.tryParse(amount.text.trim());
      if (amountNano == null || amountNano <= 0) {
        setState(() => error = appL10n.coldAmountPositive);
        return;
      }
      final tokenId = token.text.trim();
      final tokenAmount = BigInt.tryParse(quantity.text.trim());
      if ((tokenId.isNotEmpty || quantity.text.trim().isNotEmpty) &&
          (tokenAmount == null || tokenAmount <= BigInt.zero)) {
        setState(() => error = appL10n.coldTokenQuantityPositive);
        return;
      }
      final raw =
          jsonDecode(
                widget.address != null
                    ? await api.coldPrepareAddress(
                        address: widget.address!,
                        recipient: recipient.text.trim(),
                        amountNano: amountNano,
                        tokenId: tokenId.isEmpty ? null : tokenId,
                        tokenAmount: tokenAmount,
                        nodeUrl: node,
                      )
                    : await api.coldPrepareWatch(
                        key: widget.account!.key,
                        addressCount: snapshot!.addresses.length,
                        changeIndex: snapshot.highestUsed + 1,
                        recipient: recipient.text.trim(),
                        amountNano: amountNano,
                        tokenId: tokenId.isEmpty ? null : tokenId,
                        tokenAmount: tokenAmount,
                        nodeUrl: node,
                      ),
              )
              as Map<String, dynamic>;
      if (networkController.activeUrl != node) {
        await api.coldDiscard(session: raw['session'] as String);
        throw StateError(appL10n.coldNodeChanged);
      }
      pendingColdSends[sourceKey] = ColdSigningController(
        session: raw['session'] as String,
        hot: true,
        reviewData: raw['review'] as Map<String, dynamic>,
      );
      if (mounted) await resume();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resume() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ColdSigningScreen(
          controller: pendingColdSends[sourceKey]!,
          onDiscard: () => pendingColdSends.remove(sourceKey),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.coldSendTitle)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(context.l10n.coldWatchIntro),
        if (widget.address != null) ...[
          Text(context.l10n.coldChangeNote),
          SelectableText(widget.address!),
          Text(context.l10n.coldSignerMustOwn),
        ],
        if (pendingColdSends.containsKey(sourceKey))
          FilledButton(
            onPressed: busy ? null : resume,
            child: Text(context.l10n.coldResumeSend),
          )
        else ...[
          TextField(
            controller: recipient,
            decoration: InputDecoration(
              labelText: context.l10n.coldRecipientLabel,
            ),
          ),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.coldAmountNanoLabel,
            ),
          ),
          TextField(
            controller: token,
            decoration: InputDecoration(labelText: context.l10n.coldTokenIdOptional),
          ),
          TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.coldTokenQuantityLabel,
            ),
          ),
          FilledButton(
            onPressed: busy ? null : prepare,
            child: Text(context.l10n.coldPrepareRequest),
          ),
        ],
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(context.l10n.coldRefused('$error')),
      ],
    ),
  );
}
