// The home screens, rendered from sample data on a 390x844 phone in the
// dark (Celaut Teal), light (Celaut Cream) and teal (Harbor) palettes at normal
// text and in the dark one at 2x, and checked for layout errors, 48 dp
// touch targets, labelled controls, screen-reader sentences and hidden
// balances. Text contrast is checked from the palette tokens in
// home_contrast_test.dart; the screens as the app wires them, in
// home_wired_test.dart. To also save PNGs under <repo>/ui-renders/v3/:
//
//   ARGUS_UI_RENDERS=1 flutter test test/home_design_render_test.dart
//
// 2x is beyond what ships (the app clamps text at 1.6x) and is here as a
// stress test.

import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/home/home_models.dart';
import 'package:argus_wallet/ui/home/overview_screen.dart';
import 'package:argus_wallet/ui/home/wallet_nav_bar.dart';
import 'package:argus_wallet/ui/home/wallet_page.dart';
import 'package:argus_wallet/ui/home/wallet_tools_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/home_samples.dart';
import 'support/render_harness.dart';

/// The palettes rendered: the defaults, and Harbor for a teal accent.
const _looks = [
  (watchfulPalette, 1.0),
  (ledgerPalette, 1.0),
  (harborPalette, 1.0),
  (watchfulPalette, 2.0),
];

String _tag(PaletteSpec p, double scale) =>
    '${p == harborPalette ? 'teal' : p.isDark ? 'dark' : 'light'}-${scale.toStringAsFixed(0)}x';

String _file(String screen, PaletteSpec p, [double scale = 1, String suffix = '']) =>
    'v3/$screen-${_tag(p, scale)}$suffix';

void _noop([Object? _]) {}

/// The overview as the app would host it: every control wired, so links
/// draw enabled.
OverviewScreen _overview(OverviewData data) => OverviewScreen(
      data: data,
      onOpenWallet: _noop,
      onAdd: _noop,
      onSettings: _noop,
      onToggleHidden: _noop,
      onNetwork: _noop,
      onLearnMore: _noop,
      footnote: 'Long-press a wallet to change the order.',
    );

/// A wallet page framed as the app frames it: back, the wallet's name, the
/// scanner for a seed wallet, the page and the tabs.
Widget _walletPage(
  WalletPageData data, {
  VoidCallback? onBack,
  VoidCallback? onScan,
  ValueChanged<WalletTab>? onTab,
  VoidCallback? onToggleHidden,
  ValueChanged<WalletAction>? onAction,
  ValueChanged<WalletTool>? onTool,
  ValueChanged<String>? onAsset,
  VoidCallback? onAllAssets,
  ValueChanged<String>? onActivity,
  VoidCallback? onAllActivity,
  VoidCallback? onStatus,
  VoidCallback? onTidyUp,
  VoidCallback? onOtherAddresses,
}) =>
    WalletPageScreen(
      title: data.wallet.name,
      onBack: onBack ?? _noop,
      actions: [
        IconButton(
            key: const Key('wallet-scan'),
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan a QR code',
            onPressed: onScan ?? _noop,
          ),
      ],
      body: WalletPageView(
        data: data,
        onToggleHidden: onToggleHidden ?? _noop,
        onAction: onAction ?? _noop,
        onTool: onTool ?? _noop,
        onAsset: onAsset ?? _noop,
        onAllAssets: onAllAssets ?? _noop,
        onActivity: onActivity ?? _noop,
        onAllActivity: onAllActivity ?? _noop,
        onStatus: onStatus ?? _noop,
        onTidyUp: onTidyUp ?? _noop,
        onOtherAddresses: onOtherAddresses ?? _noop,
        onCopyAddress: _noop,
      ),
      navBar: WalletNavBar(
        current: WalletTab.wallet,
        onSelect: onTab ?? _noop,
        pendingCount: data.pendingCount,
      ),
    );

/// Scrolls [finder] into full view, building it first if the list hasn't,
/// and scrolling no further than that so a render keeps its context.
/// (scrollUntilVisible would also pin the target to the top.)
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pump();
  }
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await tester.pumpAndSettle();
}

Future<void> _accessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

/// Nothing the samples hold may be readable, on screen or to a screen
/// reader, while balances are hidden.
void _expectNoFigures(WidgetTester tester) {
  final shown = tester.widgetList<RichText>(find.byType(RichText)).map((t) => t.text.toPlainText()).join('\n');
  for (final figure in hiddenModeFigures) {
    // On screen a figure is joined to its unit by a no-break space.
    final pattern = RegExp(RegExp.escape(figure).replaceAll(' ', '[  ]'));
    expect(pattern.hasMatch(shown), isFalse, reason: '"$figure" is on screen with balances hidden');
    expect(find.bySemanticsLabel(pattern), findsNothing, reason: '"$figure" is read out with balances hidden');
  }
}

/// Holdings whose rows sit wholly above the tab bar.
int _assetsAboveFold(WidgetTester tester) {
  final fold = tester.getTopLeft(find.byType(NavigationBar)).dy;
  var shown = 0;
  for (final element in find.byWidgetPredicate((w) => w.key is Key && '${w.key}'.contains('home-asset-')).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (box.localToGlobal(Offset(0, box.size.height)).dy <= fold) shown++;
  }
  return shown;
}

void main() {
  setUpAll(loadRenderFonts);

  for (final (palette, scale) in _looks) {
    testWidgets('overview ${_tag(palette, scale)}', (tester) async {
      await pumpRender(tester, _overview(sampleOverview()), palette: palette, textScale: scale);
      expect(tester.takeException(), isNull);
      await saveRender(tester, _file('overview', palette, scale));
      expect(
        find.bySemanticsLabel(RegExp(r'^Total balance 25,529\.34 ERG, about A\$11,951\.52 AUD, 46 tokens unpriced, '
            r'\+2\.5 ERG pending · 25,526\.84 confirmed$')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('ERG price A\$0.47 AUD, up 2.4% over 24h, SigmaUSD oracle'), findsOneWidget);
      expect(find.bySemanticsLabel('Connected, Block 1,888,681'), findsOneWidget);
      await _accessible(tester);
      if (scale == 1) {
        // At 2x the list builds rows only as they near the screen.
        expect(
          find.bySemanticsLabel(RegExp(r'^Wallet details, unlocked, 107\.71 ERG, about A\$50\.43 AUD, 50 tokens, '
              r'\+2\.5 ERG pending · 105\.21 confirmed, incl\. 3\.2 ERG · 4 tokens on another address$')),
          findsOneWidget,
        );
      }
    });

    testWidgets('wallet ${_tag(palette, scale)}', (tester) async {
      final screen = _walletPage(sampleMainPage());
      await pumpRender(tester, screen, palette: palette, textScale: scale);
      expect(tester.takeException(), isNull);
      await saveRender(tester, _file('wallet', palette, scale));
      expect(
        find.bySemanticsLabel(RegExp(r'^Balance 107\.71 ERG, about A\$50\.43 AUD, 46 tokens unpriced, '
            r'\+2\.5 ERG pending · 105\.21 confirmed$')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('incl. 3.2 ERG · 4 tokens on 1 other address'), findsOneWidget);
      expect(find.byKey(const Key('home-price-sparkline')), findsNothing, reason: 'the price strip is overview-only');
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byKey(const Key('wallet-tab-discover')), findsOneWidget);
      if (scale == 1) {
        // The page opens on the scene: the balance, its pills and the
        // actions, then the tabs; the first holding is in view.
        expect(_assetsAboveFold(tester), greaterThanOrEqualTo(1), reason: 'the first holding is in view');
      }
      await _accessible(tester);

      await pumpFullLength(tester, screen, listKey: const Key('wallet-list'), palette: palette, textScale: scale);
      expect(tester.takeException(), isNull);
      if (scale == 1 && palette != harborPalette) {
        await saveRender(tester, _file('wallet', palette, scale, '-full'));
      }
      for (final action in ['send', 'receive', 'more']) {
        expect(find.byKey(Key('wallet-action-$action')), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Synced, Block 1,888,681, just now'), findsOneWidget);
      expect(find.bySemanticsLabel('165 UTXOs, fragmented. Tidy up'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^ERG, price A\$0\.47, up 2\.4% over 24h, 107\.71, about A\$50\.43 AUD$')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^COMET, verified, Comet, 69, about A\$0\.21 AUD$')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Kushti, Kushti token, 18,252,893,012, about A\$0\.87 AUD$')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Sent, −1\.81 ERG, −69 COMET \+ 1 more, contract 5vSUZR…SCqM, 10:08 pm$')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Received, pending, \+2\.5 ERG, from 9gF3uX…Wq7z, 10:41 pm$')),
          findsOneWidget);
      await _accessible(tester);
    });
  }

  for (final palette in [watchfulPalette, ledgerPalette]) {
    testWidgets('More ${_tag(palette, 1)}', (tester) async {
      WalletTool? picked;
      await pumpRender(tester, _walletPage(sampleMainPage(), onTool: (t) => picked = t), palette: palette);
      await _reveal(tester, find.byKey(const Key('wallet-action-more')));
      await tester.tap(find.byKey(const Key('wallet-action-more')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await saveRender(tester, _file('more', palette));
      for (final tool in WalletTool.values) {
        expect(find.byKey(Key('wallet-tool-${tool.name}')), findsOneWidget);
      }
      expect(find.bySemanticsLabel(RegExp(r'^UTXO management, Fragmented, ')), findsOneWidget);
      await _accessible(tester);
      await tester.tap(find.byKey(const Key('wallet-tool-utxos')));
      await tester.pumpAndSettle();
      expect(picked, WalletTool.utxos);
    });

  }

  testWidgets('overview hides every amount', (tester) async {
    await pumpRender(tester, _overview(sampleOverview(hidden: true)), palette: watchfulPalette);
    expect(tester.takeException(), isNull);
    await saveRender(tester, _file('overview', watchfulPalette, 1, '-hidden'));
    expect(find.bySemanticsLabel(RegExp(r'^Total balance hidden')), findsOneWidget);
    expect(find.byTooltip('Show balances'), findsOneWidget);
    _expectNoFigures(tester);
  });

  testWidgets('wallet hides every amount', (tester) async {
    final screen = _walletPage(sampleMainPage(hidden: true));
    await pumpRender(tester, screen, palette: watchfulPalette);
    expect(tester.takeException(), isNull);
    await saveRender(tester, _file('wallet', watchfulPalette, 1, '-hidden'));
    expect(find.bySemanticsLabel(RegExp(r'^Balance hidden')), findsOneWidget);
    await pumpFullLength(tester, screen, listKey: const Key('wallet-list'), palette: watchfulPalette);
    _expectNoFigures(tester);
  });

  testWidgets('with a wallet the overview offers no other wallet', (tester) async {
    await pumpRender(tester, OverviewScreen(data: sampleOverview(), onAdd: (_) {}), palette: watchfulPalette);
    expect(find.byKey(const Key('overview-add-wallet')), findsNothing);
    for (final choice in AddWalletChoice.values) {
      expect(find.byKey(Key(choice.keyName)), findsNothing);
    }
  });

  testWidgets('first launch', (tester) async {
    final taps = <AddWalletChoice>[];
    await pumpRender(
      tester,
      OverviewScreen(data: sampleOverview(wallets: const []), onAdd: taps.add, onSettings: _noop),
      palette: watchfulPalette,
    );
    expect(tester.takeException(), isNull);
    await saveRender(tester, _file('overview', watchfulPalette, 1, '-empty'));
    expect(find.text('Create a wallet'), findsOneWidget);
    expect(find.text('Restore from recovery phrase'), findsOneWidget);
    expect(find.text('Watch an address'), findsNothing);
    expect(find.text('Watch an account (xpub)'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget, reason: 'a node can be set before the first restore');
    await _accessible(tester);
    for (final choice in AddWalletChoice.values) {
      await tester.tap(find.byKey(Key(choice.keyName)));
    }
    expect(taps, AddWalletChoice.values);
  });

  testWidgets('overview reports what was tapped', (tester) async {
    final taps = <String>[];
    await pumpRender(
      tester,
      OverviewScreen(
        data: sampleOverview(),
        onOpenWallet: (ref) => taps.add('open ${ref.id}'),
        onSettings: () => taps.add('settings'),
        onToggleHidden: () => taps.add('hide'),
        onNetwork: () => taps.add('network'),
      ),
      palette: ledgerPalette,
    );
    for (final key in ['overview-row-seed-main', 'overview-settings', 'home-hide-balances', 'home-network']) {
      await _reveal(tester, find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
    }
    expect(taps, ['open main', 'settings', 'hide', 'network']);
  });

  testWidgets('wallet reports what was tapped', (tester) async {
    final taps = <String>[];
    await pumpRender(
      tester,
      _walletPage(
        sampleMainPage(),
        onBack: () => taps.add('back'),
        onScan: () => taps.add('scan'),
        onToggleHidden: () => taps.add('hide'),
        onAction: (a) => taps.add(a.name),
        onStatus: () => taps.add('status'),
        onTidyUp: () => taps.add('tidy'),
        onOtherAddresses: () => taps.add('addresses'),
        onTab: (t) => taps.add('tab ${t.name}'),
        onAsset: (id) => taps.add('asset $id'),
        onAllAssets: () => taps.add('all assets'),
        onActivity: (id) => taps.add('tx $id'),
        onAllActivity: () => taps.add('all activity'),
      ),
      palette: ledgerPalette,
    );
    await tester.tap(find.byKey(const Key('wallet-back')));
    await tester.tap(find.byKey(const Key('wallet-scan')));
    await tester.tap(find.byKey(const Key('home-hide-balances')));
    await tester.tap(find.byKey(const Key('wallet-tab-activity')));
    for (final key in [
      'wallet-action-send',
      'wallet-action-receive',
      'funds-elsewhere',
      'wallet-status',
      'utxo-fragmented',
      'home-asset-ERG',
      'wallet-all-assets',
      'home-activity-a2',
      'wallet-all-activity',
    ]) {
      await _reveal(tester, find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    expect(taps, [
      'back',
      'scan',
      'hide',
      'tab activity',
      'send',
      'receive',
      'addresses',
      'status',
      'tidy',
      'asset ERG',
      'all assets',
      'tx a2',
      'all activity',
    ]);
  });

  testWidgets('a screen reader can press what a finger can', (tester) async {
    final taps = <String>[];
    await pumpRender(
      tester,
      _walletPage(
        sampleMainPage(),
        onAction: (a) => taps.add(a.name),
        onTidyUp: () => taps.add('tidy'),
        onAsset: (id) => taps.add('asset $id'),
      ),
      palette: watchfulPalette,
    );
    for (final label in ['Send', '165 UTXOs, fragmented. Tidy up', RegExp(r'^ERG, price')]) {
      tester.semantics.tap(find.semantics.byLabel(label));
    }
    await tester.pump();
    expect(taps, ['send', 'tidy', 'asset ERG']);
  });

  testWidgets('the overview price strip reads complete without history', (tester) async {
    await pumpRender(
      tester,
      _overview(OverviewData(
        wallets: sampleOverview().wallets,
        currency: aud,
        network: connected,
        totalNano: sampleOverview().totalNano,
        price: ergPriceWithoutHistory,
      )),
      palette: watchfulPalette,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('home-price-sparkline')), findsNothing);
    expect(
      find.bySemanticsLabel(
          'ERG price A\$0.47 AUD, SigmaUSD oracle, This node has no price history for SigmaUSD oracle yet'),
      findsOneWidget,
    );
  });

  testWidgets('a stale price says how old it is, and no trend', (tester) async {
    await pumpRender(
      tester,
      _overview(OverviewData(
        wallets: sampleOverview().wallets,
        currency: aud,
        network: connected,
        totalNano: sampleOverview().totalNano,
        totalFiat: 11951.52,
        pricesNote: 'prices 3 h old',
        price: const ErgPriceView(fiatPerErg: 0.4682, source: 'SigmaUSD oracle', staleNote: '3 h old'),
      )),
      palette: watchfulPalette,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Total balance 25,529\.34 ERG, about A\$11,951\.52 AUD, prices 3 h old')),
        findsOneWidget);
    expect(find.bySemanticsLabel('ERG price A\$0.47 AUD, SigmaUSD oracle, 3 h old'), findsOneWidget);
  });

  testWidgets('a wallet still syncing shows a placeholder, not zero', (tester) async {
    await pumpRender(
      tester,
      _overview(const OverviewData(
        wallets: [WalletSummary(ref: WalletRef.seed('new'), name: 'Fresh restore', loading: true)],
        currency: aud,
        loading: true,
        notLoaded: 1,
        network: NetworkStatus(state: SyncState.syncing, blockHeight: 1888681),
        price: ErgPriceView(fiatPerErg: null, source: 'SigmaUSD oracle'),
      )),
      palette: ledgerPalette,
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Total balance loading'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Wallet details, loading…')), findsOneWidget);
    expect(find.bySemanticsLabel('Syncing…, Block 1,888,681'), findsOneWidget);
    expect(find.bySemanticsLabel('ERG price unavailable, SigmaUSD oracle'), findsOneWidget);
  });

  testWidgets('a wallet with no activity offers its address', (tester) async {
    final taps = <String>[];
    await pumpRender(
      tester,
      _walletPage(sampleMainPage(activity: const []), onAction: (a) => taps.add(a.name)),
      palette: watchfulPalette,
    );
    await _reveal(tester, find.byKey(const Key('wallet-no-activity')));
    await tester.tap(find.byKey(const Key('wallet-no-activity')));
    expect(taps, ['receive']);
  });
}
