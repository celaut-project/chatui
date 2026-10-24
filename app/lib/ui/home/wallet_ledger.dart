import 'package:flutter/material.dart';

import '../../format.dart';
import '../../services/address_holdings.dart';
import '../../services/address_label_service.dart';
import '../../services/network_controller.dart';
import '../../services/privacy_service.dart';
import '../../services/token_pricer.dart';
import '../../services/wallet_service.dart';
import '../../services/wallet_sync_controller.dart';
import '../utxo_management_screen.dart';
import '../widgets/discover_sheet.dart';
import 'address_breakdown.dart';
import 'discover_view.dart';
import 'erg_price_feed.dart';
import 'home_data.dart';
import 'home_models.dart';
import 'wallet_page.dart';
import '../../l10n/l10n.dart';

/// What the wallet tab's taps do. The home screen owns navigation, the
/// unlock state and the other tabs, so it supplies these.
class WalletLedgerActions {
  const WalletLedgerActions({
    required this.go,
    required this.showActivity,
    required this.showSettings,
    required this.viewAssets,
    required this.openTx,
    required this.openToken,
    required this.labelAddress,
    required this.lock,
    this.openDeposit,
  });

  /// Pushes a named route with this wallet's arguments ('/send', '/utxos'...).
  final void Function(String route) go;
  final VoidCallback showActivity;
  final VoidCallback showSettings;
  final VoidCallback viewAssets;
  final ValueChanged<Map<String, dynamic>> openTx;
  final ValueChanged<TokenBalance> openToken;
  final ValueChanged<String> labelAddress;
  final VoidCallback lock;

  /// "Deposit to a node", from the More sheet. Null: the tool does nothing.
  final VoidCallback? openDeposit;
}

/// The unlocked seed wallet's Wallet tab: its balance, its actions, what it
/// holds and what it did, read from the sync controller and the services
/// around it into one [WalletPageData] and laid out by [WalletPageView].
///
/// The portfolio total and the list of wallets are not here: they live on
/// the overview, one level up.
class WalletLedger extends StatelessWidget {
  const WalletLedger({
    super.key,
    required this.sync,
    required this.wallet,
    required this.actions,
    this.priceFeed,
  });

  final WalletSyncController sync;

  /// The wallet list's record of this wallet: its name, index 0 and pin.
  final WalletInfo? wallet;
  final WalletLedgerActions actions;

  /// ERG's day of prices, for the ERG row's 24h change.
  final ErgPriceFeed? priceFeed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        sync,
        privacyService,
        addressLabelService,
        networkController,
        tokenPricer,
        walletService.metadataChanges,
        ?priceFeed,
      ]),
      builder: (context, _) {
        final hidden = privacyService.hideBalances;
        final w = wallet;
        final holdings = sync.tokens.map(walletService.displayMetadata).toList();
        // The identity is the wallet's own record (the pinned address, else
        // index 0), not today's receive address, which moves in fresh mode.
        final identity = w?.displayAddress ?? sync.receiveAddress;
        final addresses = withWalletIndexes(
          sync.addressHoldings,
          address0: w?.address0,
          pinnedAddress: w?.pinnedAddress,
          pinnedIndex: w?.pinnedAddressIndex,
        );
        final activity = sync.displayActivity;
        final shown = activity.take(WalletPageView.activityLimit).toList();
        final data = _data(holdings: holdings, identity: identity, addresses: addresses, shown: shown, hidden: hidden);
        void breakdown({required bool all}) => showAddressBreakdownSheet(
              context,
              walletName: appL10n.commonThisWallet,
              holdings: addresses,
              identity: identity,
              hidden: hidden,
              listEmpty: all,
              labelFor: addressLabelService.labelFor,
              onLabel: actions.labelAddress,
              labels: addressLabelService,
            );
        return WalletPageView(
          data: data,
          onRefresh: () => sync.refresh(discover: true),
          onToggleHidden: () => privacyService.setHideBalances(!hidden),
          onAction: (a) => switch (a) {
            WalletAction.send => actions.go('/send'),
            WalletAction.receive => actions.go('/receive'),
            WalletAction.more => null,
          },
          onTool: (tool) => switch (tool) {
            WalletTool.tokens => actions.go('/tokens'),
            WalletTool.utxos => actions.go('/utxos'),
            WalletTool.addresses => breakdown(all: true),
            WalletTool.deposit => actions.openDeposit?.call(),
            WalletTool.lock => actions.lock(),
          },
          onAsset: (id) {
            if (id == 'ERG') return actions.viewAssets();
            for (final t in holdings) {
              if (t.id == id) return actions.openToken(t);
            }
          },
          onAllAssets: actions.viewAssets,
          onActivity: (id) {
            for (final (i, tx) in shown.indexed) {
              if (activityRowId(tx, i) == id) return actions.openTx(tx);
            }
          },
          onAllActivity: actions.showActivity,
          // The status line leads to the UTXO tools; while the wallet is
          // fragmented, its own line goes straight to the suggested cleanup.
          onStatus: () => actions.go('/utxos'),
          onTidyUp: () => actions.go(UtxoManagementScreen.cleanupRoute),
          onOtherAddresses: () => breakdown(all: false),
          onReceive: () => actions.go('/receive'),
          onPinIssue: actions.showSettings,
          onRetry: networkController.probe,
        );
      },
    );
  }

  WalletPageData _data({
    required List<TokenBalance> holdings,
    required String? identity,
    required List<AddressHolding> addresses,
    required List<Map<String, dynamic>> shown,
    required bool hidden,
  }) {
    final w = wallet;
    final price = ergPriceView(priceFeed?.history);
    final headline = sync.balanceNano;
    final value = holdingsFiat(headline, [
      for (final t in holdings) (id: t.id, amount: t.amount, decimals: t.decimals),
    ]);
    final online = networkController.activeUrl != null;
    final label = sync.statusLabel(online: online);
    final state = label == appL10n.syncSynced
        ? SyncState.synced
        : sync.isStale
            ? SyncState.stale
            : sync.isSyncing
                ? SyncState.syncing
                : label == appL10n.commonOffline
                    ? SyncState.offline
                    : SyncState.partial;
    // Kept while the next sync is in flight: "Syncing… · 5m ago".
    final age = formatSyncAge(sync.lastSyncedAt);
    return WalletPageData(
      wallet: WalletSummary(
        ref: WalletRef.seed(w?.walletId ?? sync.receiveAddress ?? ''),
        name: w?.name ?? appL10n.commonWallet,
        nanoErg: headline,
        loading: sync.balanceNano == null && sync.isSyncing,
        fiatValue: value.fiat,
        tokenCount: holdings.length,
        pending: headline == null ? null : sync.pending?.under(headline),
        otherAddresses: fundsElsewhere(addresses, identity: identity),
        unlocked: true,
        address: identity,
        pinnedIndex: w?.pinnedAddressIndex,
      ),
      currency: homeCurrency(),
      status: NetworkStatus(
        state: state,
        blockHeight: networkController.height,
        age: age.isEmpty ? null : age,
        label: label,
      ),
      offline: networkOffline(),
      assets: headline == null ? const [] : assetRows(headline, holdings, price),
      assetCount: (headline == null ? 0 : 1) + holdings.length,
      activity: [for (final (i, tx) in shown.indexed) activityRow(tx, id: activityRowId(tx, i))],
      activityLoading: shown.isEmpty && sync.isSyncing && sync.lastSyncedAt == null,
      utxoCount: sync.utxoCount,
      fragmented: sync.utxoCount > utxoFragmentationThreshold,
      unpricedCount: value.unpriced,
      pricesNote: pricesNote(),
      hidden: hidden,
      pendingCount: sync.displayActivity.where(isPendingTx).length,
      pinIssue: sync.pinIssue,
    );
  }
}

/// The unlocked wallet's Discover tab: every tool, one row each.
class WalletDiscover extends StatelessWidget {
  const WalletDiscover({super.key, required this.onExplain});

  final ValueChanged<DiscoverFeature> onExplain;

  @override
  Widget build(BuildContext context) {
    return DiscoverView(
      onExplain: onExplain,
      tools: [for (final f in discoverTools) DiscoverCardData(f)],
    );
  }
}
