import 'package:flutter/material.dart';

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

const discoverExplainers = <DiscoverFeature, DiscoverExplainer>{
  DiscoverFeature.tokens: DiscoverExplainer(
    title: 'Tokens',
    blurb: 'Issue a token or an NFT, or burn tokens you hold.',
    icon: Icons.token_outlined,
    route: '/tokens',
    what: 'Any Ergo transaction can create a new token: its id is the id of the first input box, its name, decimals and description live in the registers of the box that carries it (EIP-4). An NFT is a token with one unit and a link to its media.',
    can: [
      'Issue a fungible token with a name, decimals and supply',
      'Issue an NFT pointing at an image, audio or video',
      'Burn tokens you hold so they leave circulation',
    ],
    risks: [
      'A token\'s name is not unique: anyone can issue one with the same name',
      'Burning is final; the supply cannot be restored',
      'Issuing costs a miner fee and locks the minimum box value with the token',
    ],
    go: 'Open tokens',
  ),
  DiscoverFeature.utxos: DiscoverExplainer(
    title: 'UTXO management',
    blurb: 'Consolidate, split and restructure the boxes your money sits in.',
    icon: Icons.grid_view_outlined,
    route: '/utxos',
    what: 'On Ergo your balance is a set of boxes, each a separate coin. Many small boxes make every send bigger and slower to build; one huge box links everything you own in one place. This tool reshapes them.',
    can: [
      'Consolidate many small boxes into one',
      'Split a box into several of a chosen size',
      'Restructure holdings so tokens sit in boxes of their own',
    ],
    risks: [
      'Every reshape is a transaction: it costs a miner fee and is public',
      'Consolidating links every box it spends to one owner',
      'A box below the minimum value cannot be made',
    ],
    go: 'Open UTXO management',
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
              Text('WHAT YOU CAN DO', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(color: colors.muted)),
              const SizedBox(height: 8),
              bullets(e.can),
              const SizedBox(height: 12),
              Text('WATCH FOR', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(color: colors.muted)),
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
