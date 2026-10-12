import 'package:flutter/material.dart';

import '../../format.dart';
import '../../services/storage_rent.dart';
import '../../services/utxo_plans.dart';
import '../../theme/argus_theme.dart';
import '../../l10n/l10n.dart';

/// When a box's storage rent falls due, what it costs, and whether the
/// box can pay it.
///
/// A box worth no more than its rent is flagged "at risk" only when it
/// holds tokens, which a collector would take with it. An ERG-only box like
/// that is just dust its rent would use up, said plainly and without the
/// warning colour, so a wallet with many small boxes does not look
/// alarming.
class BoxRentLine extends StatelessWidget {
  const BoxRentLine({
    super.key,
    required this.rent,
    required this.parameters,
    required this.hasTokens,
  });

  final BoxRent rent;
  final RentParameters parameters;

  /// Whether a collector would take tokens along with the ERG.
  final bool hasTokens;

  @override
  Widget build(BuildContext context) {
    final colors = ArgusColors.of(context);
    // Unrounded: a voted factor can make any nanoERG amount.
    final fee = formatErg(rent.feeNano);
    final when = rentWhen(
      rent.blocksUntilDue,
      blockSeconds: parameters.blockSeconds,
    );
    final block = context.l10n.rentBlock(formatWithCommas(rent.dueHeight));
    // What a collector takes from a box worth no more than its rent: all of
    // it.
    final whole = formatErg(rent.chargeNano);
    final (IconData icon, Color color, String text) = switch (rent) {
      BoxRent(charge: RentCharge.none) => (
        Icons.hourglass_empty,
        colors.muted,
        parameters.noChargeReason,
      ),
      BoxRent(atRisk: true, collectableNow: true) when hasTokens => (
        Icons.warning_amber_rounded,
        rustFor(context),
        context.l10n.rentAtRiskNow(fee),
      ),
      BoxRent(atRisk: true) when hasTokens => (
        Icons.warning_amber_rounded,
        rustFor(context),
        context.l10n.rentAtRiskFrom(fee, block, when),
      ),
      BoxRent(atRisk: true, collectableNow: true) => (
        Icons.hourglass_bottom,
        colors.muted,
        context.l10n.rentWholeNow(whole),
      ),
      BoxRent(atRisk: true) => (
        Icons.hourglass_bottom,
        colors.muted,
        context.l10n.rentWholeFrom(whole, block, when),
      ),
      BoxRent(collectableNow: true) => (
        Icons.schedule,
        colors.accentText,
        context.l10n.rentChargeableNow(fee, block),
      ),
      BoxRent(dueSoon: true) => (
        Icons.schedule,
        colors.accentText,
        context.l10n.rentDue(fee, when, block),
      ),
      _ => (
        Icons.hourglass_bottom,
        colors.muted,
        context.l10n.rentDue(fee, when, block),
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }
}

/// The cleanup the screen proposes, at the top of the list.
class CleanupSuggestionCard extends StatelessWidget {
  const CleanupSuggestionCard({
    super.key,
    required this.suggestion,
    required this.resultingBoxes,
    required this.fragmented,
    this.highlight = false,
    this.onReview,
  });

  final CleanupSuggestion suggestion;

  /// Boxes the cleanup creates, or null when the layout is unknown.
  final int? resultingBoxes;

  /// The wallet has more boxes than the home screen calls tidy.
  final bool fragmented;

  /// Opened from the home screen to show this suggestion.
  final bool highlight;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final colors = ArgusColors.of(context);
    final s = suggestion;
    final n = s.boxes.length;
    final into = switch (resultingBoxes) {
      1 => context.l10n.rentIntoOne,
      final int count => context.l10n.rentIntoCount('$count'),
      null => s.tokens.isEmpty ? context.l10n.rentIntoOne : context.l10n.rentIntoOneOrMore,
    };
    final reasons = <String>[
      if (s.forRent) _rentReason(s),
      if (fragmented) context.l10n.rentFewerBoxes,
      if (!s.forRent)
        context.l10n.rentMovingRestarts,
    ];
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(
          color: highlight ? accentOf(context) : colors.cardBorder,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_fix_high_outlined,
                size: 18,
                color: accentTextOf(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.utxoSuggestedCleanup,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.leftAtAddress > 0
                ? context.l10n.rentMergeBoxesOf('$n', '${n + s.leftAtAddress}', shorten(s.address, head: 6, tail: 4), into)
                : context.l10n.rentMergeBoxes('$n', shorten(s.address, head: 6, tail: 4), into),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          for (final reason in reasons) ...[
            const SizedBox(height: 4),
            Text(reason, style: bodySmall),
          ],
          const SizedBox(height: 4),
          Text(
            context.l10n.rentCleanupFee(formatErg(s.feesNano)),
            style: bodySmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.merge_type, size: 18),
            label: Text(context.l10n.rentReviewCleanup),
            onPressed: onReview,
          ),
        ],
      ),
    );
  }

  static String _rentReason(CleanupSuggestion s) {
    final parts = <String>[
      if (s.atRiskCount > 0) appL10n.rentCantCover(s.atRiskCount),
      if (s.dueSoonCount > 0) appL10n.rentFallsDue(s.dueSoonCount, '$rentSoonDays'),
    ];
    return appL10n.rentReasonMoving(
      parts.length == 2 ? appL10n.rentReasonAnd(parts[0], parts[1]) : parts.join(),
    );
  }
}

/// One line on storage rent across the listed boxes: how many are at risk
/// or due soon, how many ERG-only boxes rent would take whole, how many
/// have no figures, and the rate they are judged at. Only the first two
/// are a warning.
class RentSummaryLine extends StatelessWidget {
  const RentSummaryLine({
    super.key,
    required this.parameters,
    required this.atRisk,
    this.wholeErgOnly = 0,
    required this.dueSoon,
    required this.unmeasured,
    required this.loading,
    required this.failed,
  });

  /// Null until a report arrives, or after one failed.
  final RentParameters? parameters;

  /// Listed boxes holding tokens that cannot pay their rent: a collector
  /// would take the tokens too.
  final int atRisk;

  /// Listed ERG-only boxes that cannot pay their rent: dust rent would use
  /// up whole. Counted apart from [atRisk] and not a warning.
  final int wholeErgOnly;

  /// Listed boxes due within [rentSoonDays] that can pay it.
  final int dueSoon;

  /// Listed boxes the report has no figures for: unparseable, or listed
  /// differently between the two reads.
  final int unmeasured;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final parameters = this.parameters;
    if (parameters == null) {
      if (loading) {
        return Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(context.l10n.rentChecking, style: style)),
          ],
        );
      }
      return Text(
        failed
            ? context.l10n.rentUnavailable
            : context.l10n.rentNotChecked,
        style: style,
      );
    }
    final parts = [
      if (atRisk > 0) context.l10n.rentAtRiskCount(atRisk),
      if (dueSoon > 0) context.l10n.rentDueWithin(dueSoon, '$rentSoonDays'),
    ];
    final missing = unmeasured == 0
        ? ''
        : ' ${context.l10n.rentUnmeasured(unmeasured)}';
    final rate = '${context.l10n.rentRateLine(parameters.rateLabel)}$missing';
    final dust = wholeErgOnly == 0
        ? ''
        : '${context.l10n.rentErgOnlyWhole(wholeErgOnly)} ';
    final measured = unmeasured != 0;
    final lead = parts.isNotEmpty
        ? context.l10n.rentLeadParts(parts.join(' · '))
        : wholeErgOnly == 0
        ? (measured ? context.l10n.rentLeadAllMeasuredCovered : context.l10n.rentLeadAllCovered)('$rentSoonDays')
        : (measured ? context.l10n.rentLeadNoMeasuredTokenRisk : context.l10n.rentLeadNoTokenRisk)('$rentSoonDays');
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: lead,
            style: parts.isEmpty
                ? null
                : TextStyle(
                    color: rustFor(context),
                    fontWeight: FontWeight.w700,
                  ),
          ),
          TextSpan(text: ' $dust$rate'),
        ],
      ),
      style: style,
    );
  }
}
