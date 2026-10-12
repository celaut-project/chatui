import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/token_pricer.dart';
import '../../services/network_controller.dart';
import '../../services/privacy_service.dart';
import '../../services/token_metadata.dart';
import '../../services/token_pricing.dart';
import '../../services/verified_tokens.dart';
import '../../services/wallet_service.dart';
import '../../theme/argus_theme.dart';
import '../token_avatar.dart';
import 'asset_tile.dart';
import 'remote_preview.dart';
import '../../l10n/l10n.dart';

class TokenDetailSheet extends StatefulWidget {
  const TokenDetailSheet({
    super.key,
    required this.token,
    required this.explorerUrl,
    this.onSend,
  });
  final TokenBalance token;
  final String explorerUrl;
  final ValueChanged<TokenBalance>? onSend;
  @override
  State<TokenDetailSheet> createState() => _TokenDetailSheetState();
}

class _TokenDetailSheetState extends State<TokenDetailSheet>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _concealed = false;
  String? _error;
  late final String? _wallet = walletService.currentWalletId.value;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    walletService.unlocked.addListener(_securityChanged);
    walletService.currentWalletId.addListener(_securityChanged);
  }

  void _securityChanged() {
    if (!walletService.isUnlocked ||
        _wallet != walletService.currentWalletId.value) {
      walletService.clearSessionMetadata();
      if (mounted) setState(() => _concealed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      walletService.clearSessionMetadata();
      if (mounted) setState(() => _concealed = true);
    }
  }

  @override
  void dispose() {
    if (_loading) walletService.clearSessionMetadata();
    WidgetsBinding.instance.removeObserver(this);
    walletService.unlocked.removeListener(_securityChanged);
    walletService.currentWalletId.removeListener(_securityChanged);
    super.dispose();
  }

  Future<void> _load({bool node = false}) async {
    final provider = node
        ? networkController.activeUrl
        : networkController.explorer;
    if (provider == null) return;
    final host = Uri.tryParse(provider)?.host ?? '';
    if (host.isEmpty || host.runes.any((c) => c > 127)) {
      setState(
        () => _error = context.l10n.tokenMetaAsciiProvider,
      );
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tokenMetaLoadFrom(host)),
        content: Text(
          context.l10n.tokenMetaPrivacy,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tokenMetaLoad),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || _concealed) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await walletService.loadMetadata(
        widget.token,
        provider: provider,
        providerIsNode: node,
      );
    } catch (e) {
      // Losing the single metadata job to a background pass is contention,
      // not the provider failing. Saying "unavailable" would tell the user
      // their node is broken when another try would work. Typed, because
      // Dart and Rust word this differently and a substring check missed
      // the Dart one, which is the common case.
      final busy =
          e is MetadataBusyException ||
          e.toString().toLowerCase().contains('already running');
      if (mounted) {
        setState(
          () => _error = busy
              ? context.l10n.tokenMetaBusy
              : context.l10n.tokenMetaUnavailableFrom(host),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      privacyService,
      walletService.metadataChanges,
      networkController,
    ]),
    builder: (context, _) {
      if (_concealed || privacyService.hideBalances) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.tokenDetailsHidden),
          ),
        );
      }
      final token = walletService.displayMetadata(widget.token);
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TokenDetailBody(
              token: token,
              explorerUrl: widget.explorerUrl,
              onSend: widget.onSend,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  if (_error != null) Text(_error!),
                  if (networkController.activeUrl == null)
                    Text(context.l10n.tokenMetaOffline),
                  if (_loading)
                    TextButton(
                      onPressed: walletService.clearSessionMetadata,
                      child: Text(context.l10n.tokenMetaCancel),
                    ),
                  TextButton(
                    onPressed:
                        _loading ||
                            networkController.activeUrl == null ||
                            !walletService.isUnlocked
                        ? null
                        : () => _load(node: true),
                    child: Text(
                      context.l10n.tokenMetaLoadFromNode(Uri.tryParse(networkController.activeUrl ?? "")?.host ?? context.l10n.tokenMetaHostNode),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _loading ||
                            networkController.activeUrl == null ||
                            !walletService.isUnlocked
                        ? null
                        : () => _load(),
                    child: Text(
                      _loading
                          ? context.l10n.tokenMetaLoading
                          : context.l10n.tokenMetaLoadFrom(Uri.tryParse(networkController.explorer)?.host ?? context.l10n.tokenMetaHostProvider),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Everything about one held token: full id, amount, decimals, explorer
/// link, and a shortcut to send it.
class _TokenDetailBody extends StatelessWidget {
  const _TokenDetailBody({
    required this.token,
    required this.explorerUrl,
    this.onSend,
  });

  final TokenBalance token;
  final String explorerUrl;
  final ValueChanged<TokenBalance>? onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ArgusColors.of(context).muted;
    final ticker = tokenTicker(token);
    final scaled = hasKnownScale(token);
    // Raw units already name their unit; a ticker after them would read as
    // if they were whole tokens.
    final amount = holdingAmountText(token);
    final verified = verifiedToken(token.id);
    final caution = cautionedToken(token.id);
    final impersonates = impersonatedToken(tokenId: token.id, name: token.name);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TokenAvatar(
                  label: ticker,
                  tokenId: token.id,
                  iconUrl: token.iconUrl,
                  radius: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              token.label,
                              textDirection: TextDirection.ltr,
                              style: theme.textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (verified != null) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: accentTextOf(context),
                            ),
                          ],
                          if (caution != null) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: rust,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        verified != null
                            ? context.l10n.tokenCurated(verified.project)
                            : token.classification,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: verified != null ? accentTextOf(context) : muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!token.isCollectible) ...[
              const SizedBox(height: 12),
              _PriceLine(token: token),
            ],
            if (caution != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: rust.withValues(alpha: 0.1),
                  border: Border.all(color: rust.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: rust,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.tokenCaution(caution.note ?? context.l10n.tokenCautionDefault),
                        style: TextStyle(fontSize: 13, color: rustFor(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (impersonates != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: rust.withValues(alpha: 0.1),
                  border: Border.all(color: rust.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.gpp_bad_outlined, color: rust, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.tokenImpersonation(impersonates.ticker, impersonates.project),
                        style: TextStyle(fontSize: 13, color: rustFor(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (token.isCollectible || token.iconUrl != null) ...[
              Text(context.l10n.artworkTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              if (token.iconUrl != null)
                RemotePreview(
                  key: ValueKey(
                    '${token.id}:${token.iconUrl}:${token.issuanceHash}',
                  ),
                  token: token,
                )
              else
                Text(switch (token.mediaState) {
                  MediaState.absent => context.l10n.artworkNoMediaLink,
                  MediaState.unknown => context.l10n.artworkLoadBelow,
                  MediaState.unsupported => context.l10n.artworkPreviewUnsupported,
                  MediaState.notLoaded => context.l10n.artworkLinkUnavailable,
                }),
              const SizedBox(height: 16),
            ],
            if (token.description != null) ...[
              Text(context.l10n.tokenDescription, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                issuerText(token.description, limit: 4096),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 20),
            ],
            Text(
              context.l10n.tokenYouHold,
              style: theme.textTheme.titleSmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            Text(
              scaled ? '$amount $ticker' : amount,
              style: const TextStyle(
                fontFamily: headingFont,
                fontWeight: FontWeight.w700,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.tokenIdCaps,
              style: theme.textTheme.titleSmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ArgusColors.of(context).inset,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                token.id,
                style: monoStyle(context, size: 12),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: token.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.tokenIdCopied)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(context.l10n.commonCopyId),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(explorerUrl);
                    if (uri == null ||
                        uri.scheme != 'https' ||
                        uri.userInfo.isNotEmpty)
                      return;
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.l10n.tokenLeaveFor(uri.host)),
                        content: Text(
                          context.l10n.tokenExplorerPrivacy,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.l10n.commonCancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.l10n.tokenOpenExplorer),
                          ),
                        ],
                      ),
                    );
                    if (yes == true)
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                  },
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: Text(context.l10n.tokenExplorer),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.l10n.tokenMetaDetails),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(token.classification, textDirection: TextDirection.ltr),
                const SizedBox(height: 8),
                Text(
                  token.supplyEvidence == SupplyEvidence.originalEmission
                      ? context.l10n.tokenOriginalEmission('${token.emissionAmount}')
                      : context.l10n.tokenOriginalEmissionUnavailable,
                ),
                Text(
                  scaled
                      ? context.l10n.tokenDecimalsLine('${token.decimals}', switch (token.decimalsEvidence) {
                          DecimalsEvidence.valid => context.l10n.tokenDecimalsDeclared,
                          DecimalsEvidence.absent => context.l10n.tokenDecimalsNone,
                          DecimalsEvidence.listed => context.l10n.tokenDecimalsListed,
                          DecimalsEvidence.unknown || DecimalsEvidence.invalid => context.l10n.tokenDecimalsLastShown,
                        })
                      : context.l10n.tokenDecimalsUnknown,
                ),
                Text(context.l10n.tokenDeclaredKind(token.declaredAssetKind.name)),
                if (token.source != null)
                  Text(
                    context.l10n.tokenMetaSource('${token.source}'),
                    textDirection: TextDirection.ltr,
                  ),
                const SizedBox(height: 8),
                Text(switch (token.mediaState) {
                  MediaState.absent => context.l10n.artworkNoMediaLink,
                  MediaState.unknown => context.l10n.artworkMediaUnavailable,
                  MediaState.unsupported => context.l10n.artworkPreviewUnsupported,
                  MediaState.notLoaded => context.l10n.artworkConsent,
                }),
                if (token.iconUrl != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    token.issuanceHash == null
                        ? context.l10n.tokenMediaHashMissing
                        : context.l10n.tokenMediaHash('${token.issuanceHash}'),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    issuerText(token.iconUrl, limit: 2048),
                    textDirection: TextDirection.ltr,
                  ),
                  TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: token.iconUrl!)),
                    child: Text(context.l10n.tokenCopyMediaUri),
                  ),
                ],
                if (token.rawRegisters != null)
                  ExpansionTile(
                    title: Text(context.l10n.tokenIssuanceRegisters),
                    children: [
                      SelectableText(
                        token.rawRegisters!,
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
              ],
            ),
            if (onSend case final send?) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('token-send'),
                onPressed: () => send(token),
                icon: const Icon(Icons.north_east, size: 17),
                label: Text(context.l10n.tokenSend(token.label)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens [token]'s sheet. [onSend] is offered only for a wallet that can
/// sign.
Future<void> showTokenDetailSheet(
  BuildContext context, {
  required TokenBalance token,
  required String explorerUrl,
  ValueChanged<TokenBalance>? onSend,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
    ),
    builder: (ctx) => TokenDetailSheet(
      token: token,
      explorerUrl: explorerUrl,
      onSend: onSend == null
          ? null
          : (t) {
              Navigator.pop(ctx);
              onSend(t);
            },
    ),
  );
}

/// "≈ $0.0125 each · ≈ $2.50 held · AVL oracle", or why there is no price.
class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.token});
  final TokenBalance token;

  @override
  Widget build(BuildContext context) {
    final muted = ArgusColors.of(context).muted;
    final price = tokenPricer.priceOf(token.id);
    final unit = tokenPricer.unitFiatText(token.id);
    final held = tokenPricer.fiatTextFor(
      tokenId: token.id,
      amount: token.amount,
      decimals: token.decimals,
    );
    final String text;
    if (price == null || unit == null) {
      text = tokenPricer.result.ergUsd == null
          ? context.l10n.priceNoneYet(priceSourceLabel)
          : context.l10n.priceNoPool;
    } else {
      text = [
        context.l10n.priceEach(unit),
        if (held != null) context.l10n.priceHeld(held),
        price.via,
        if (!price.countsInTotal) context.l10n.priceNotCounted,
      ].join(' · ');
    }
    return Text(text, style: TextStyle(fontSize: 12.5, color: muted));
  }
}
