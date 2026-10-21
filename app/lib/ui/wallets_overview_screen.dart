import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n/l10n.dart';
import '../services/erg_price_history.dart';
import '../services/network_controller.dart';
import '../services/privacy_service.dart';
import '../services/public_wallet_sync.dart';
import '../services/token_pricer.dart';
import '../services/wallet_service.dart';
import 'home/erg_price_feed.dart';
import 'home/home_data.dart';
import 'home/home_models.dart';
import 'home/overview_model.dart';
import 'home/overview_screen.dart';
import 'home/wallet_tools_sheet.dart';

/// The launch screen: the wallet of the app with its balance. Nothing here
/// needs an unlock: a locked wallet shows its public snapshot. Tapping the
/// wallet opens its page; that is where its key is asked for.
///
/// The app holds one wallet. With none, this screen offers to create or
/// restore it; renaming and removing it live in its own settings. The screen itself is [OverviewScreen]; this reads the overview
/// model, the pricer and the network into its figures.
class WalletsOverviewScreen extends StatelessWidget {
  const WalletsOverviewScreen({
    super.key,
    required this.model,
    required this.onOpen,
    required this.onCreate,
    required this.onRestore,
    required this.onSettings,
    this.onNetwork,
    this.priceFeed,
    this.notice,
    this.noticeIsError = false,
    this.onAction,
    this.extra,
  });

  /// A row under the wallet, such as "Deposit to a node" in the Wallet tab of the home
  /// screen.
  final Widget? extra;

  final WalletsOverviewModel model;

  /// Send, Receive and More from the overview's own row.
  final ValueChanged<WalletAction>? onAction;
  final ValueChanged<WalletRef> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onRestore;
  final VoidCallback onSettings;

  /// The network line, while a node answers: its settings.
  final VoidCallback? onNetwork;

  /// ERG's day of prices for the strip under the total.
  final ErgPriceFeed? priceFeed;

  /// A parked link waiting for an unlock, or a startup error.
  final String? notice;
  final bool noticeIsError;

  void _add(AddWalletChoice choice) => switch (choice) {
        AddWalletChoice.create => onCreate(),
        AddWalletChoice.restore => onRestore(),
      };

  Future<void> _refresh() async {
    await Future.wait<void>([model.refresh(), ?priceFeed?.refresh()]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        model,
        privacyService,
        tokenPricer,
        networkController,
        walletService.metadataChanges,
        ?priceFeed,
      ]),
      builder: (context, _) {
        final hidden = privacyService.hideBalances;
        final data = overviewData(model, hidden: hidden, history: priceFeed?.history);
        final offline = networkOffline();
        return OverviewScreen(
          data: data,
          onOpenWallet: onOpen,
          onAdd: _add,
          onSettings: onSettings,
          onToggleHidden: () => privacyService.setHideBalances(!hidden),
          // With no node the line looks again; otherwise it opens the
          // network settings.
          onNetwork: offline ? networkController.probe : onNetwork,
          networkAction: offline ? context.l10n.commonRetry : null,
          onRefresh: _refresh,
          footnote: data.wallets.isEmpty ? null : lockedWalletsExplainer,
          notice: notice,
          noticeIsError: noticeIsError,
          onAction: onAction,
          extra: extra,
        );
      },
    );
  }
}

/// The overview's figures for the model's current rows.
///
/// The total is the sum of what the rows show; a row whose balance is
/// unknown is left out of it and counted as not loaded, never added as
/// zero. What is pending is split against each figure it sits under
/// ([PendingBalance.under]), so the total's line counts every other
/// wallet's funds as confirmed.
OverviewData overviewData(WalletsOverviewModel model, {required bool hidden, ErgPriceHistory? history}) {
  final entries = model.entries();
  final totals = overviewTotals(entries);
  final now = DateTime.now();
  WalletSummary summary(OverviewEntry e) {
    final value = holdingsFiat(e.balanceNano, e.tokens);
    return WalletSummary(
      ref: e.ref,
      name: e.name,
      nanoErg: e.balanceNano,
      loading: e.loading,
      unavailable: e.unavailable,
      fiatValue: value.fiat,
      tokenCount: e.tokensKnown ? e.tokens.where((t) => t.amount > 0).map((t) => t.id).toSet().length : null,
      pending: e.pending,
      otherAddresses: e.elsewhere,
      unlocked: e.state == OverviewRowState.unlocked,
      asOf: e.asOf == null ? null : formatSyncAge(now.subtract(e.asOf!)),
      address: e.address,
    );
  }

  final known = totals.total.known > 0;
  final value = known ? holdingsFiat(totals.total.totalNano, totals.tokens) : (fiat: null, unpriced: 0);
  return OverviewData(
    wallets: [for (final e in entries) summary(e)],
    currency: homeCurrency(),
    network: overviewNetwork(),
    totalNano: known ? totals.total.totalNano : null,
    loading: !known && model.refreshing,
    notLoaded: totals.total.unknown,
    totalFiat: value.fiat,
    unpricedCount: value.unpriced,
    pricesNote: pricesNote(),
    pending: totals.pending,
    price: ergPriceView(history),
    hidden: hidden,
  );
}
