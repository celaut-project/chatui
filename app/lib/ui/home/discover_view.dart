import 'package:flutter/material.dart';

import '../../theme/argus_theme.dart';
import '../widgets/discover_sheet.dart';
import 'home_style.dart';
import 'home_widgets.dart';

/// One tool on the Discover tab.
class DiscoverCardData {
  const DiscoverCardData(this.feature, {this.subtitle});

  final DiscoverFeature feature;

  /// A line about the wallet's own use of the feature, else its blurb is
  /// shown.
  final String? subtitle;
}

/// The Discover tab: every tool that acts on the wallet's coins, one row
/// each. A row opens the feature's explainer, whose button opens the
/// feature itself, so nothing that moves money opens from one tap.
class DiscoverView extends StatelessWidget {
  const DiscoverView({super.key, required this.tools, required this.onExplain});

  final List<DiscoverCardData> tools;
  final ValueChanged<DiscoverFeature> onExplain;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    return ListView(
      key: const Key('discover-list'),
      padding: EdgeInsets.only(top: 8, bottom: 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(homeGutter, 0, homeGutter, 8),
          child: Text(
            'What Argus can do beyond sending and receiving. Each one says what it is, '
            'what you can do with it, and what to watch for before it opens.',
            style: t.secondary.copyWith(height: 1.4),
          ),
        ),
        if (tools.isNotEmpty) ...[
          const HomeSectionHeader(title: 'Tools'),
          for (final card in tools) _row(context, card),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, DiscoverCardData card) {
    final t = HomeText.of(context);
    final e = discoverExplainers[card.feature]!;
    final line = card.subtitle ?? e.blurb;
    return HomeRow(
      inkKey: Key('discover-${card.feature.name}'),
      onTap: () => onExplain(card.feature),
      hint: 'What it is, and the way in',
      semanticLabel: '${e.title}, $line',
      leading: HomeDisc(child: Icon(e.icon, size: 18, color: ArgusColors.of(context).accentText)),
      title: Text(e.title, style: t.primary),
      subtitle: TextSpan(
        text: line,
        // The wallet's own position reads in ink; a blurb stays quiet.
        style: card.subtitle == null ? null : TextStyle(color: t.ink),
      ),
      subtitleLines: 2,
      trailing: Icon(Icons.chevron_right, size: 18, color: t.muted),
    );
  }
}
