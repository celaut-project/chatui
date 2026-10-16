// The home screens in Spanish, whose texts run longer than the English
// ones: rendered at normal text and at the 1.6x the app allows, and
// checked for layout errors.

import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/home/home_models.dart';
import 'package:argus_wallet/ui/home/overview_screen.dart';
import 'package:argus_wallet/ui/home/wallet_nav_bar.dart';
import 'package:argus_wallet/ui/home/wallet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/home_samples.dart';
import 'support/render_harness.dart';

const _spanish = Locale('es');

void _noop([Object? _]) {}

Widget _walletPage(WalletPageData data) => WalletPageScreen(
      title: data.wallet.name,
      onBack: _noop,
      body: WalletPageView(
        data: data,
        onToggleHidden: _noop,
        onAction: _noop,
        onTool: _noop,
        onAsset: _noop,
        onAllAssets: _noop,
        onActivity: _noop,
        onAllActivity: _noop,
        onStatus: _noop,
        onTidyUp: _noop,
        onOtherAddresses: _noop,
        onCopyAddress: _noop,
      ),
      navBar: WalletNavBar(
        current: WalletTab.wallet,
        onSelect: _noop,
        pendingCount: data.pendingCount,
      ),
    );

void main() {
  setUpAll(loadRenderFonts);

  for (final scale in [1.0, 1.6]) {
    testWidgets('the overview in Spanish at ${scale}x', (tester) async {
      await pumpRender(
        tester,
        OverviewScreen(
          data: sampleOverview(),
          onOpenWallet: _noop,
          onAdd: _noop,
          onSettings: _noop,
          onToggleHidden: _noop,
          onNetwork: _noop,
          onLearnMore: _noop,
        ),
        palette: watchfulPalette,
        textScale: scale,
        locale: _spanish,
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('^Saldo total ')), findsOneWidget);
      expect(find.byTooltip('Ajustes'), findsOneWidget);
    });

    testWidgets('a wallet page in Spanish at ${scale}x', (tester) async {
      await pumpRender(
        tester,
        _walletPage(sampleMainPage()),
        palette: watchfulPalette,
        textScale: scale,
        locale: _spanish,
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('^Saldo ')), findsOneWidget);
    });
  }
}
