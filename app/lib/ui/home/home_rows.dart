import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../format.dart';
import '../../services/token_amounts.dart';
import '../../services/token_evidence.dart';
import '../../theme/argus_theme.dart';
import '../../theme/argus_tones.dart';
import '../token_avatar.dart';
import 'home_format.dart';
import 'home_hero.dart';
import 'home_models.dart';
import 'home_style.dart';
import 'home_widgets.dart';
import '../../l10n/l10n.dart';

/// One wallet on the overview: name and balance, then a line of facts and
/// the balance's value. What it keeps on other addresses and what is
/// pending follow as quiet footnotes when there is any.
class OverviewWalletRow extends StatelessWidget {
  const OverviewWalletRow({
    super.key,
    required this.wallet,
    required this.currency,
    this.hidden = false,
    this.onTap,
    this.onLongPress,
    this.semanticActions,
  });

  final WalletSummary wallet;

  /// Actions a screen reader offers on the row, e.g. Stop watching.
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;
  final FiatCurrency currency;
  final bool hidden;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The row's key, by kind and id, for whoever needs to find it.
  static Key keyFor(WalletRef ref) => ValueKey('overview-row-${ref.kind.name}-${ref.id}');

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    final w = wallet;
    final nano = w.nanoErg;
    final tokens = w.tokenCount;
    final empty = nano == 0 && (tokens ?? 0) == 0;

    final facts = <InlineSpan>[];
    void fact(String text, [TextStyle? style]) {
      if (facts.isNotEmpty) facts.add(const TextSpan(text: '  ·  '));
      facts.add(TextSpan(text: text, style: style));
    }

    // Watched rows are often unnamed: the address tells them apart.
    final address = w.watchOnly && w.address != null ? shorten(w.address!, head: 6, tail: 4) : null;
    // Hidden balances drop "Empty" and the token count as well as the
    // figures: either tells an onlooker as much as an amount would.
    final String? holds;
    if (nano == null) {
      holds = w.loading ? context.l10n.homeLoading : (w.unavailable ?? context.l10n.commonBalanceUnavailable);
    } else if (!hidden && empty) {
      holds = context.l10n.homeEmpty;
    } else if (!hidden && tokens != null && tokens > 0) {
      holds = context.l10n.homeTokenCount(tokens, groupThousands('$tokens'));
    } else {
      holds = null;
    }
    final asOf = w.asOf != null && nano != null ? context.l10n.homeAsOfCompact('${w.asOf}') : null;

    // Only the open wallet is marked: "Locked" on every other row would be
    // noise, and the eye and the Watched heading already mark a watched
    // one (a screen reader still hears it).
    if (w.unlocked) {
      facts.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 5),
          child: Icon(Icons.lock_open_rounded, size: 14, color: mossFor(context)),
        ),
      ));
      facts.add(TextSpan(text: context.l10n.homeUnlocked, style: TextStyle(color: mossFor(context))));
    }
    if (address != null) fact(address);
    if (holds != null) fact(holds);
    if (asOf != null) fact(asOf);

    final amount = nano == null ? (w.loading ? '…' : '—') : (hidden ? maskedFigure : summaryErg(nano));
    final fiatValue = w.fiatValue;
    final fiat = fiatValue == null || empty || nano == null
        ? null
        : (hidden ? '≈$nbsp$maskedFigure' : fiatFigure(fiatValue, currency));
    final other = w.otherAddresses == null ? null : otherAddressLine(w.otherAddresses!, hidden: hidden, compact: true);
    final pending = nano == null ? null : pendingText(w.pending, hidden: hidden);

    Widget note(IconData icon, Widget text) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: t.muted)),
              const SizedBox(width: 4),
              Expanded(child: text),
            ],
          ),
        );

    final footnotes = [
      if (other != null) note(Icons.subdirectory_arrow_right, Text(other, style: t.secondary)),
      if (pending != null) HomePendingLine(pending: w.pending, hidden: hidden),
    ];

    return HomeRow(
      inkKey: keyFor(w.ref),
      onTap: onTap,
      onLongPress: onLongPress,
      semanticActions: semanticActions,
      hint: context.l10n.homeOpensWallet,
      semanticLabel: spoken([
        w.name,
        if (w.unlocked) context.l10n.homeSpokenUnlocked,
        if (w.watchOnly) context.l10n.homeSpokenWatchOnly,
        ?address,
        if (nano != null) hidden ? context.l10n.homeSpokenBalanceHidden : '$amount ERG',
        if (fiat != null && !hidden) context.l10n.homeSpokenAbout(fiatFigure(fiatValue!, currency, approximate: false), currency.code),
        if (holds != null) holds.toLowerCase(),
        ?asOf,
        if (pending != null) hidden ? context.l10n.homeSpokenSomethingPending : pending,
        if (other != null) context.l10n.homeSpokenIncl(other),
      ].join(', ')),
      leading: WalletMark(name: w.name, kind: w.kind),
      // Each wallet's name in the serif, as its own page's title is.
      title: Text(
        w.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.primary.copyWith(fontFamily: headingFont, fontSize: 16.5, fontWeight: FontWeight.w500, height: 1.25),
      ),
      subtitle: facts.isEmpty ? null : TextSpan(children: facts),
      figure: TextSpan(
        children: [
          TextSpan(text: amount),
          TextSpan(text: '${nbsp}ERG', style: t.secondary.copyWith(fontSize: 14)),
        ],
      ),
      subfigure: fiat == null ? null : TextSpan(text: fiat),
      footnote: footnotes.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: footnotes),
      trailing: onTap == null ? null : homeChevron(context),
    );
  }
}

/// One holding: mark, ticker and name, then the amount and its value on
/// the shared right edge. ERG's detail line is its price and 24h change.
class HomeAssetRow extends StatelessWidget {
  const HomeAssetRow({super.key, required this.asset, required this.currency, this.hidden = false, this.onTap});

  final AssetRowData asset;
  final FiatCurrency currency;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    final colors = ArgusColors.of(context);
    final isErg = asset.kind == AssetKind.erg;
    // Names are the issuer's words: stripped of bidi and control characters
    // before display, as the token sheet does.
    final ticker = hidden ? maskedFigure : issuerText(asset.ticker, limit: 64);
    final name = hidden ? maskedFigure : issuerText(asset.name ?? '', limit: 96);
    final decimals = asset.decimals;
    // A token nothing knows the scale of is shown in the raw units it is,
    // and says so, never as if they were whole tokens.
    final amount = hidden
        ? maskedFigure
        : decimals == null
            ? rawUnitsText(asset.amount)
            : summaryAmount(asset.amount, decimals);
    final value = asset.fiatValue;
    final fiat = value == null ? null : (hidden ? '≈$nbsp$maskedFigure' : fiatFigure(value, currency));
    final unit = asset.unitFiat;
    final change = asset.changePercent;
    final stale = asset.priceNote;

    final InlineSpan? detail;
    if (!hidden && unit != null) {
      detail = TextSpan(
        children: [
          TextSpan(text: ergPriceFigure(unit, currency)),
          // A price that is not current says how old it is instead of
          // showing a change it cannot vouch for.
          if (stale != null)
            TextSpan(text: '  $stale', style: TextStyle(color: rustFor(context)))
          else if (change != null)
            TextSpan(
              text: '  ${percentChange(change)}',
              style: TextStyle(color: change >= 0 ? mossFor(context) : rustFor(context), fontWeight: FontWeight.w700),
            ),
        ],
      );
    } else if (!hidden && stale != null) {
      detail = TextSpan(text: context.l10n.homePriceNote(stale), style: TextStyle(color: rustFor(context)));
    } else {
      // A name that only repeats the ticker ("SigUSD" under "SigUSD") says
      // nothing; the row keeps to one line instead.
      final same = name.trim().toLowerCase() == ticker.trim().toLowerCase();
      detail = name.isEmpty || (same && !hidden) ? null : TextSpan(text: name);
    }

    return HomeRow(
      inkKey: Key('home-asset-${asset.id}'),
      onTap: hidden ? null : onTap,
      semanticLabel: hidden
          ? context.l10n.homeAssetHidden
          : spoken([
              ticker,
              if (asset.verified && !isErg) context.l10n.homeSpokenVerified,
              if (asset.caution) context.l10n.homeSpokenCaution,
              if (unit != null)
                '${context.l10n.homeSpokenPrice(fiatFigure(unit, currency, approximate: false))}'
                    '${stale != null ? ', $stale' : change == null ? '' : ', ${(change >= 0 ? context.l10n.homeSpokenUp : context.l10n.homeSpokenDown)(change.abs().toStringAsFixed(1), '24h')}'}'
              else ...[
                if (name.isNotEmpty && name != ticker) name,
                if (stale != null) context.l10n.homeSpokenPrice(stale),
              ],
              amount,
              if (value != null) 'about ${fiatFigure(value, currency, approximate: false)} ${currency.code}',
            ].join(', ')),
      leading: ExcludeSemantics(
        child: TokenAvatar(
          label: hidden ? '?' : asset.ticker,
          tokenId: hidden || isErg ? null : asset.id,
          isErg: isErg && !hidden,
          radius: homeMarkSize / 2,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(ticker, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.primary)),
          if (!hidden && asset.verified && !isErg) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified, size: 14, color: colors.accentText),
          ],
          if (!hidden && asset.caution) ...[
            const SizedBox(width: 4),
            const Icon(Icons.warning_amber_rounded, size: 14, color: rust),
          ],
        ],
      ),
      subtitle: detail,
      figure: TextSpan(text: amount),
      subfigure: fiat == null ? null : TextSpan(text: fiat),
      trailing: onTap == null ? null : homeChevron(context),
    );
  }
}

/// One transaction, read like a statement line: what happened, when and
/// with whom on the left, what moved on the right. The time comes before
/// the counterparty so that a long address, not the time, gives way.
class HomeActivityRow extends StatelessWidget {
  const HomeActivityRow({super.key, required this.item, this.hidden = false, this.onTap});

  final ActivityRowData item;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    // Same marks and tints as the Activity tab's rows; only direction is
    // coloured.
    final (IconData icon, Color tint) = switch (item.kind) {
      ActivityKind.received => (Icons.arrow_downward, mossFor(context)),
      ActivityKind.sent => (Icons.arrow_upward, rustFor(context)),
      ActivityKind.selfTransfer => (Icons.sync_alt, t.muted),
      ActivityKind.contract => (Icons.code, t.muted),
    };
    final legs = item.legs;
    final primary = hidden
        ? maskedFigure
        : item.figure ?? (legs.isEmpty ? '0${nbsp}ERG' : legText(legs.first));
    final incoming = legs.isNotEmpty && legs.first.amount > BigInt.zero;
    final secondary = hidden
        ? null
        : item.figure != null
            ? item.subfigure
            : legs.length < 2
                ? null
                : legs.length > 2
                    ? context.l10n.homeLegsMore(legText(legs[1]), '${legs.length - 2}')
                    : legText(legs[1]);
    final when = [if (item.pending) context.l10n.commonPending, if (item.time.isNotEmpty) item.time, ?item.counterparty];

    return HomeRow(
      inkKey: Key('home-activity-${item.id}'),
      onTap: onTap,
      semanticLabel: spoken([
        item.title,
        if (item.pending) context.l10n.homeSpokenPending,
        if (hidden) context.l10n.homeSpokenAmountHidden else ...[primary, ?secondary],
        ?item.counterparty,
        if (item.time.isNotEmpty) item.time,
      ].join(', ')),
      leading: HomeDisc(fill: tint.withValues(alpha: 0.16), child: Icon(icon, size: 20, color: tint)),
      title: Text(item.title, style: t.primary),
      subtitle: when.isEmpty
          ? null
          : TextSpan(
              children: [
                for (final (i, part) in when.indexed)
                  TextSpan(
                    text: i == 0 ? part : '  ·  $part',
                    style: i == 0 && item.pending ? TextStyle(color: t.ink, fontWeight: FontWeight.w700) : null,
                  ),
              ],
            ),
      figure: TextSpan(text: primary, style: incoming && !hidden ? TextStyle(color: mossFor(context)) : null),
      subfigure: secondary == null ? null : TextSpan(text: secondary),
      trailing: onTap == null ? null : homeChevron(context),
    );
  }
}
