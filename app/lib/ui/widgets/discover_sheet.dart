import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/argus_theme.dart';

/// Everything the Discover row and page can open.
enum DiscoverFeature { tokens, utxos }

/// The tools that act on the wallet's own coins, in the order the Discover
/// tab lists them.
const discoverTools = [
  DiscoverFeature.tokens,
  DiscoverFeature.utxos,
];

/// What a feature is, what you can do with it, and what to watch for.
class DiscoverExplainer {
  const DiscoverExplainer({
    required this.title,
    required this.blurb,
    required this.icon,
    required this.what,
    required this.can,
    required this.risks,
    required this.go,
    required this.route,
  });

  final String title;

  /// One line for a card or a list row.
  final String blurb;
  final IconData icon;
  final String what;
  final List<String> can;
  final List<String> risks;

  /// The button that opens the feature.
  final String go;

  /// The route that opens the feature.
  final String route;
}

Map<DiscoverFeature, DiscoverExplainer> get discoverExplainers => <DiscoverFeature, DiscoverExplainer>{
  DiscoverFeature.tokens: DiscoverExplainer(
    title: appL10n.commonTokens,
    blurb: appL10n.discoverTokensBlurb,
    icon: Icons.token_outlined,
    route: '/tokens',
    what: appL10n.discoverTokensWhat,
    can: [
      appL10n.discoverTokensCanIssue,
      appL10n.discoverTokensCanNft,
      appL10n.discoverTokensCanBurn,
    ],
    risks: [
      appL10n.discoverTokensRiskName,
      appL10n.discoverTokensRiskBurn,
      appL10n.discoverTokensRiskCost,
    ],
    go: appL10n.discoverTokensGo,
  ),
  DiscoverFeature.utxos: DiscoverExplainer(
    title: appL10n.homeUtxoManagement,
    blurb: appL10n.discoverUtxosBlurb,
    icon: Icons.grid_view_outlined,
    route: '/utxos',
    what: appL10n.discoverUtxosWhat,
    can: [
      appL10n.discoverUtxosCanConsolidate,
      appL10n.discoverUtxosCanSplit,
      appL10n.discoverUtxosCanRestructure,
    ],
    risks: [
      appL10n.discoverUtxosRiskPublic,
      appL10n.discoverUtxosRiskLinks,
      appL10n.discoverUtxosRiskMinimum,
    ],
    go: appL10n.discoverUtxosGo,
  ),
};

/// What a tool is, what you can do with it, and what to watch for, with
/// one button to go there.
Future<void> showDiscoverSheet(BuildContext context, {required DiscoverFeature feature, required VoidCallback onGo}) {
  final e = discoverExplainers[feature]!;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius))),
    builder: (ctx) {
      final colors = ArgusColors.of(ctx);
      Widget bullets(List<String> items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 10),
                        child: Container(width: 5, height: 5, decoration: BoxDecoration(color: accentOf(context), shape: BoxShape.circle)),
                      ),
                      Expanded(child: Text(t, style: const TextStyle(fontSize: 14, height: 1.4))),
                    ],
                  ),
                ),
            ],
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(e.what, style: const TextStyle(fontSize: 14.5, height: 1.45)),
              const SizedBox(height: 18),
              Text(ctx.l10n.discoverWhatYouCanDo, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(color: colors.muted)),
              const SizedBox(height: 8),
              bullets(e.can),
              const SizedBox(height: 12),
              Text(ctx.l10n.discoverWatchFor, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(color: colors.muted)),
              const SizedBox(height: 8),
              bullets(e.risks),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onGo();
                },
                child: Text(e.go),
              ),
            ],
          ),
        ),
      );
    },
  );
}
