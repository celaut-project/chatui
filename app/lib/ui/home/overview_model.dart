import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/address_holdings.dart';
import '../../services/address_label_service.dart';
import '../../services/pending_balance.dart';
import '../../services/portfolio.dart';
import '../../services/public_wallet_sync.dart';
import '../../services/wallet_database_service.dart';
import '../../services/wallet_service.dart';
import '../../services/wallet_sync_controller.dart';
import '../../l10n/l10n.dart';

/// The wallet of the app: what the home screen has open, when it has one.
@immutable
class WalletRef {
  const WalletRef.seed(this.id);

  /// The wallet id.
  final String id;

  @override
  bool operator ==(Object other) => other is WalletRef && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'WalletRef($id)';
}

enum OverviewRowState {
  /// The seed wallet whose key is in memory now.
  unlocked,

  /// A seed wallet shown from its last public snapshot.
  locked,
}

/// One overview row with every figure already decided, so the row widget
/// only lays it out. Balances are display figures, exactly as each wallet's
/// own page shows them, and the overview total is the sum of these.
@immutable
class OverviewEntry {
  const OverviewEntry({
    required this.ref,
    required this.name,
    required this.state,
    this.address,
    this.balanceNano,
    this.loading = false,
    this.tokens = const [],
    this.tokensKnown = false,
    this.asOf,
    this.elsewhere,
    this.unavailable,
    this.pending,
  });

  final WalletRef ref;
  final String name;
  final OverviewRowState state;

  /// The address the wallet is shown as: the pinned address or index 0.
  final String? address;

  /// Null when unknown: never shown, and never added, as zero.
  final int? balanceNano;
  final bool loading;
  final List<({String id, int amount, int decimals})> tokens;

  /// False when the source cannot say which tokens the wallet holds; the
  /// row then shows no count rather than "0 tokens".
  final bool tokensKnown;

  /// Age of a snapshot figure. Null for live figures.
  final Duration? asOf;

  /// Funds on addresses other than [address].
  final FundsElsewhere? elsewhere;

  /// Why [balanceNano] is null, when the row should say so.
  final String? unavailable;

  /// What transactions still in the mempool do to [balanceNano], split
  /// against it (see [PendingBalance.under]). Null when nothing valued it:
  /// no read since pending summaries, or one that could not value the
  /// mempool.
  final PendingBalance? pending;
}

/// The overview's headline: the sum of the rows it can see.
class OverviewTotals {
  const OverviewTotals({
    required this.total,
    required this.wallets,
    required this.tokens,
    this.pending,
  });
  final PortfolioTotal total;
  final int wallets;

  /// Every counted row's tokens, for the fiat valuation of the total.
  final List<({String id, int amount, int decimals})> tokens;

  /// What is pending across the counted rows, split against the total; null
  /// when no row has a split.
  final PendingBalance? pending;
}

OverviewTotals overviewTotals(List<OverviewEntry> entries) {
  final total = portfolioTotal([for (final e in entries) e.balanceNano]);
  PendingBalance? pending;
  for (final e in entries) {
    final split = e.pending;
    if (e.balanceNano == null || split == null) continue;
    pending = pending == null ? split : pending.plus(split);
  }
  return OverviewTotals(
    total: total,
    wallets: entries.length,
    tokens: [
      for (final e in entries)
        if (e.balanceNano != null) ...e.tokens,
    ],
    // Rows without a split add nothing pending: as far as anything here
    // knows, their figures are in blocks.
    pending: pending?.under(total.totalNano),
  );
}

/// Live figures of the unlocked wallet, read from the sync controller.
class ActiveWalletFigures {
  const ActiveWalletFigures({
    required this.walletId,
    required this.balanceNano,
    required this.syncing,
    required this.tokens,
    required this.holdings,
    this.pending,
  });

  /// The controller's view, when it owns [walletId]; null otherwise.
  static ActiveWalletFigures? of(WalletSyncController sync, String? walletId) {
    if (walletId == null || !sync.ownsWallet(walletId)) return null;
    return ActiveWalletFigures(
      walletId: walletId,
      balanceNano: sync.balanceNano,
      syncing: sync.isSyncing,
      tokens: [
        for (final t in sync.tokens) (id: t.id, amount: t.amount, decimals: t.decimals),
      ],
      holdings: sync.addressHoldings,
      pending: sync.pending,
    );
  }

  final String walletId;

  /// ERG on the wallet's addresses; null before the first read.
  final int? balanceNano;
  final bool syncing;
  final List<({String id, int amount, int decimals})> tokens;
  final List<AddressHolding> holdings;

  /// The sync's split of [balanceNano], this app's unseen broadcasts
  /// included.
  final PendingBalance? pending;

  /// What the wallet is worth, as its page shows it.
  int? get totalNano => balanceNano;
}

/// The overview rows, in the user's order of the wallets.
List<OverviewEntry> buildOverviewEntries({
  required List<WalletInfo> wallets,
  required Map<String, LastKnownBalance> lastKnown,
  Map<String, PendingBalance> lastPending = const {},
  required String? unlockedWalletId,
  ActiveWalletFigures? active,
}) {
  return [
    for (final w in wallets)
      if (active != null && active.walletId == w.walletId)
        _activeEntry(w, active)
      else
        _lockedEntry(
          w,
          lastKnown[w.walletId],
          lastPending[w.walletId],
          unlocked: w.walletId == unlockedWalletId,
        ),
  ];
}

OverviewEntry _activeEntry(WalletInfo w, ActiveWalletFigures active) {
  final identity = w.displayAddress;
  return OverviewEntry(
    ref: WalletRef.seed(w.walletId),
    // The app holds one wallet and shows no name for it.
    name: appL10n.commonWallet,
    state: OverviewRowState.unlocked,
    address: identity,
    balanceNano: active.totalNano,
    loading: active.balanceNano == null && active.syncing,
    tokens: active.tokens,
    tokensKnown: active.balanceNano != null,
    pending: switch (active.totalNano) {
      final shown? => active.pending?.under(shown),
      null => null,
    },
    elsewhere: fundsElsewhere(
      withWalletIndexes(
        active.holdings,
        address0: w.address0,
        pinnedAddress: w.pinnedAddress,
        pinnedIndex: w.pinnedAddressIndex,
      ),
      identity: identity,
    ),
  );
}

OverviewEntry _lockedEntry(
  WalletInfo w,
  LastKnownBalance? known,
  PendingBalance? pending, {
  required bool unlocked,
}) {
  final identity = w.displayAddress;
  return OverviewEntry(
    ref: WalletRef.seed(w.walletId),
    // The app holds one wallet and shows no name for it.
    name: appL10n.commonWallet,
    state: unlocked ? OverviewRowState.unlocked : OverviewRowState.locked,
    address: identity,
    balanceNano: known?.balanceNano,
    tokens: known?.tokens ?? const [],
    tokensKnown: known != null && known.tokensKnown,
    asOf: known?.age,
    // Saved with the figure, so exactly as old as it is.
    pending: known == null
        ? null
        : pending?.under(known.balanceNano),
    elsewhere: known == null
        ? null
        : fundsElsewhere(
            withWalletIndexes(
              known.addressHoldings,
              address0: w.address0,
              pinnedAddress: w.pinnedAddress,
              pinnedIndex: w.pinnedAddressIndex,
            ),
            identity: identity,
          ),
    unavailable: known != null
        ? null
        : identity == null
        ? appL10n.overviewOpenToLoad
        : appL10n.overviewNotLoadedYet,
  );
}

/// Feeds the launch overview: the wallet list, each wallet's last public
/// snapshot, and the refresh schedule that keeps them current without an
/// unlock.
///
/// Locked seed wallets refresh through [PublicWalletSync] (known addresses
/// only, five-minute floor, one request at a time).
class WalletsOverviewModel extends ChangeNotifier {
  WalletsOverviewModel({
    PublicWalletSync? publicSync,
    DateTime Function()? clock,
  }) : _public = publicSync ?? publicWalletSync,
       _clock = clock ?? DateTime.now;

  final PublicWalletSync _public;
  final DateTime Function() _clock;

  List<WalletInfo> _wallets = const [];
  List<WalletInfo> get wallets => _wallets;

  final Map<String, LastKnownBalance> _lastKnown = {};
  final Map<String, PendingBalance> _lastPending = {};
  Future<void>? _refresh;
  int _loadGeneration = 0;
  bool _attached = false;
  bool _disposed = false;

  bool get refreshing => _refresh != null;

  WalletInfo? wallet(String walletId) {
    for (final w in _wallets) {
      if (w.walletId == walletId) return w;
    }
    return null;
  }

  LastKnownBalance? lastKnown(String walletId) => _lastKnown[walletId];

  /// The pending split saved with [lastKnown]'s snapshot, if any.
  PendingBalance? lastPending(String walletId) => _lastPending[walletId];

  bool get isEmpty => _wallets.isEmpty;

  /// Starts listening to the services the rows are drawn from.
  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    addressLabelService.addListener(notifyListeners);
    walletSyncController.addListener(notifyListeners);
    _public.addListener(_onPublicChanged);
  }

  @override
  void dispose() {
    if (_attached) {
      addressLabelService.removeListener(notifyListeners);
      walletSyncController.removeListener(notifyListeners);
      _public.removeListener(_onPublicChanged);
    }
    _disposed = true;
    super.dispose();
  }

  /// Reads finish after the screen is gone; they must not reach a disposed
  /// notifier.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Rows for the current state of every source.
  List<OverviewEntry> entries() {
    final unlocked = walletService.isUnlocked
        ? walletService.activeWalletId
        : null;
    return buildOverviewEntries(
      wallets: _wallets,
      lastKnown: _lastKnown,
      lastPending: _lastPending,
      unlockedWalletId: unlocked,
      active: ActiveWalletFigures.of(walletSyncController, unlocked),
    );
  }

  /// Reads the wallet list and every wallet's last snapshot from disk: no
  /// network, so the overview paints at once.
  Future<void> loadWallets() async {
    final generation = ++_loadGeneration;
    final wallets = await walletService.listWallets();
    final snapshots = await _snapshots(wallets);
    if (generation != _loadGeneration || _disposed) return;
    _wallets = wallets;
    _remember(snapshots);
    notifyListeners();
  }

  /// Every wallet's last figures, and the pending split saved with them.
  static Future<_Snapshots> _snapshots(List<WalletInfo> wallets) async {
    final known = <String, LastKnownBalance>{};
    final pending = <String, PendingBalance>{};
    for (final w in wallets) {
      final k = await WalletDatabaseService.lastKnownBalance(w.walletId);
      if (k != null) known[w.walletId] = k;
      final p = await lastKnownPending(w.walletId);
      if (p != null) pending[w.walletId] = p;
    }
    return (known: known, pending: pending);
  }

  void _remember(_Snapshots snapshots) {
    _lastKnown
      ..clear()
      ..addAll(snapshots.known);
    _lastPending
      ..clear()
      ..addAll(snapshots.pending);
  }

  /// Saves the order the user dragged the seed wallets into.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final ids = [for (final w in _wallets) w.walletId];
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    final moved = ids.removeAt(oldIndex);
    ids.insert(
      (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, ids.length),
      moved,
    );
    // Paint the new order at once; the reload confirms it from storage.
    final byId = {for (final w in _wallets) w.walletId: w};
    _wallets = [for (final id in ids) byId[id]!];
    notifyListeners();
    await walletService.setWalletOrder(ids);
    await loadWallets();
  }

  /// The launch pass: the locked wallets.
  Future<void> refreshOnLaunch() => refresh();

  /// Pull to refresh: the locked wallets, when due. Completes when they have.
  Future<void> refresh() {
    final running = _refresh;
    if (running != null) return running;
    final op = _refreshPublic().whenComplete(() {
      _refresh = null;
      notifyListeners();
    });
    _refresh = op;
    notifyListeners();
    return op;
  }

  /// The poll's share: whatever is due.
  Future<void> refreshIfDue() async {
    if (_refresh != null || _disposed) return;
    if (_public.isDue(_clock())) await _refreshPublic();
  }

  Future<void> _refreshPublic() async {
    await _public.tick(
      wallets: {for (final w in _wallets) w.walletId: w.displayAddress},
      recordedAddresses: {
        for (final w in _wallets)
          w.walletId: [
            if (w.address0 != null) w.address0!,
            if (w.pinnedAddress != null) w.pinnedAddress!,
          ],
      },
      controller: walletSyncController,
      activeId: walletService.isUnlocked ? walletService.activeWalletId : null,
      unlocked: () => walletService.isUnlocked,
      whileLocked: true,
    );
    await _reloadSnapshots();
  }

  Future<void> _reloadSnapshots() async {
    final generation = _loadGeneration;
    final snapshots = await _snapshots(_wallets);
    if (generation != _loadGeneration || _disposed) return;
    _remember(snapshots);
    notifyListeners();
  }

  void _onPublicChanged() => unawaited(_reloadSnapshots());

}

typedef _Snapshots = ({
  Map<String, LastKnownBalance> known,
  Map<String, PendingBalance> pending,
});
