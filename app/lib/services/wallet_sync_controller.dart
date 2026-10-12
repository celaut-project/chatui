import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'address_holdings.dart';
import 'network_controller.dart';
import 'pending_balance.dart';
import 'privacy_service.dart';
import 'wallet_database_service.dart';
import 'wallet_service.dart';

/// Where the active wallet's on-chain view stands.
enum SyncPhase {
  /// Nothing loaded (locked, or before the first hydrate).
  idle,

  /// A refresh is in flight.
  syncing,

  /// Every balance and history call succeeded.
  synced,

  /// Balances succeeded but at least one address history failed.
  historyPartial,

  /// Some address balance calls failed; totals may be low.
  balancesStale,

  /// Every balance call failed. Previous values are kept on screen.
  failed,

  /// The wallet has no derivable address to sync.
  noAddresses,
}

/// The slice of wallet, network and cache services the sync controller
/// needs. Kept narrow so tests can drive the controller with a fake.
abstract class WalletSyncGateway {
  bool get isUnlocked;
  String? get activeWalletId;
  Future<String> discoverAddresses();
  Future<int> getPinnedAddressIndex();
  Future<String?> tryDeriveAddress(int index);
  Future<String> deriveAddress(int index);
  bool useUnusedChangeAddress(String? walletId);
  Future<Map<String, dynamic>> getBalance(String address);
  Future<List<TokenBalance>> hydrateTokens(dynamic raw);

  /// Resolves names for holdings, after balances publish. Returns what it
  /// resolved, so the caller can apply it to holdings already on screen.
  Future<Map<String, TokenBalance>> resolveTokenNames(
    Iterable<String> ids, {
    required String walletId,
    required String servedBy,
    required bool Function() stillCurrent,
  });

  /// Keeps missing-address status attached to the request that produced the rows.
  Future<HistoryResult> loadHistory(List<String> addresses, {int limit = 20});
  Future<int> countUnspentBoxes(List<String> addresses);
  Future<Map<String, dynamic>?> loadCachedState(String walletKey);
  Future<void> saveCachedState(Map<String, dynamic> snapshot);
  void probeNetwork();
}

/// One refresh owns this read; it is never reused by a later refresh.
abstract interface class WalletSyncRead {
  Future<Map<String, dynamic>> balance(String address);
  Future<HistoryResult> history();
  Future<int> count();

  /// The node that actually answered this read. `connect` falls back past
  /// the preferred URL, so this is not necessarily the configured one — and
  /// it is the only endpoint that has already been shown these addresses and
  /// the token ids in their boxes. Null when it cannot be established.
  Future<String?> servedBy();
}

abstract interface class WalletSyncBatchGateway {
  WalletSyncRead startRead(List<String> addresses);
}

/// A read that also values the mempool across all the wallet's addresses at
/// once. Per-address balances summed count a payment between two of the
/// wallet's addresses, or a chain of spends across them, more than once;
/// this does not.
abstract interface class WalletSyncPendingRead {
  /// Null when a confirmed listing failed: a missing listing hides spent
  /// inputs, so nothing pending can be valued.
  Future<PendingBalance?> pending();

  /// Ids of the pending transactions the node listed in this read. A
  /// broadcast of this app's among them is already in the node's figures.
  Future<Set<String>> pendingIds();
}

class _LiveSyncRead implements WalletSyncRead, WalletSyncPendingRead {
  _LiveSyncRead(List<String> addresses) {
    final inputs = walletService.loadSyncInputs(
      addresses,
      nodeUrl: networkController.activeUrl,
    );
    _inputs = inputs;
    _history = walletService.loadHistory(
      addresses,
      pending: inputs.then((value) {
        final pending = value['pending'];
        if (pending == null) throw StateError('Pending values unavailable');
        return pending as List;
      }),
    );
  }
  late final Future<Map<String, dynamic>> _inputs;
  late final Future<HistoryResult> _history;
  @override
  Future<Map<String, dynamic>> balance(String address) async {
    final raw = (await _inputs)['balances'][address];
    if (raw == null) throw StateError('Address balance unavailable');
    return Map<String, dynamic>.from(raw as Map);
  }

  @override
  Future<HistoryResult> history() async {
    final history = await _history;
    if ((await _inputs)['pending'] == null) {
      // Keep the last activity snapshot when input values cannot be verified.
      throw StateError('Pending values unavailable');
    }
    return history;
  }

  @override
  Future<int> count() async {
    final count = (await _inputs)['utxo_count'] as int?;
    if (count == null) throw StateError('UTXO listing incomplete');
    return count;
  }

  @override
  Future<PendingBalance?> pending() async =>
      PendingBalance.fromJson((await _inputs)['summary']);

  @override
  Future<Set<String>> pendingIds() async => {
    for (final row in ((await _inputs)['pending'] as List? ?? const []))
      if (row is Map && row['tx_id'] is String) row['tx_id'] as String,
  };

  @override
  Future<String?> servedBy() async {
    try {
      final url = (await _inputs)['served_by'];
      return url is String && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }
}

/// Production gateway over the app's singleton services.
class LiveWalletSyncGateway
    implements WalletSyncGateway, WalletSyncBatchGateway {
  @override
  WalletSyncRead startRead(List<String> addresses) => _LiveSyncRead(addresses);
  const LiveWalletSyncGateway();

  @override
  bool get isUnlocked => walletService.isUnlocked;

  @override
  String? get activeWalletId => walletService.activeWalletId;

  @override
  Future<String> discoverAddresses() => walletService.discoverAddresses();

  @override
  Future<int> getPinnedAddressIndex() => walletService.getPinnedAddressIndex();

  @override
  Future<String?> tryDeriveAddress(int index) =>
      walletService.tryDeriveAddress(index);

  @override
  Future<String> deriveAddress(int index) => walletService.deriveAddress(index);

  @override
  bool useUnusedChangeAddress(String? walletId) =>
      privacyService.useUnusedChangeAddress(walletId);

  @override
  Future<Map<String, dynamic>> getBalance(String address) =>
      walletService.getBalance(address);

  @override
  Future<List<TokenBalance>> hydrateTokens(dynamic raw) =>
      walletService.hydrateTokens(raw);

  @override
  Future<Map<String, TokenBalance>> resolveTokenNames(
    Iterable<String> ids, {
    required String walletId,
    required String servedBy,
    required bool Function() stillCurrent,
  }) => walletService.prefetchTokenMeta(
    ids,
    walletId: walletId,
    servedBy: servedBy,
    stillCurrent: stillCurrent,
  );

  /// Passes request-local completeness through without consulting shared state.
  @override
  Future<HistoryResult> loadHistory(List<String> addresses, {int limit = 20}) =>
      walletService.loadHistory(addresses, limit: limit);

  @override
  Future<int> countUnspentBoxes(List<String> addresses) async {
    final boxes = await walletService.listUnspentBoxes(
      addresses,
      nodeUrl: networkController.activeUrl,
    );
    return boxes.length;
  }

  @override
  Future<Map<String, dynamic>?> loadCachedState(String walletKey) =>
      WalletDatabaseService.loadCachedState(expectedWalletId: walletKey);

  /// Preserves sync validity separately from the time the snapshot is written.
  @override
  Future<void> saveCachedState(Map<String, dynamic> snapshot) =>
      WalletDatabaseService.saveCachedState(
        walletId: snapshot['wallet_id'] as String,
        frontierAddresses: (snapshot['frontier_addresses'] as List? ?? const [])
            .cast<String>(),
        discoveredAt: snapshot['discovered_at'] as int?,
        discoveryPinnedIndex: snapshot['discovery_pinned_index'] as int?,
        discoveryUnusedChange: snapshot['discovery_unused_change'] as bool?,
        changeAddress: snapshot['change_address'] as String?,
        primaryAddress: snapshot['primary_address'] as String?,
        usedAddresses: (snapshot['used_addresses'] as List)
            .cast<Map<String, dynamic>>(),
        balanceNano: snapshot['balance_nano_erg'] as int?,
        pending: (snapshot['pending'] as Map?)?.cast<String, dynamic>(),
        tokens: (snapshot['tokens'] as List).cast<Map<String, dynamic>>(),
        transactions: (snapshot['transactions'] as List)
            .cast<Map<String, dynamic>>(),
        utxoCount: snapshot['utxo_count'] as int,
        publicOnly: snapshot['public_only'] == true,
        syncPhase: snapshot['sync_phase'] as String?,
        lastSuccessfulSyncAt: (snapshot['last_successful_sync_at'] as num?)
            ?.toInt(),
        addressHoldings:
            (snapshot['address_holdings'] as List? ?? const [])
                .cast<Map<String, dynamic>>(),
      );

  @override
  void probeNetwork() {
    networkController.probe();
  }
}

/// Owns the unlocked wallet's synced view: addresses, balances, activity and
/// UTXO count, plus the cache that makes the next launch instant.
///
/// The dashboard drives it (hydrate on unlock, full refresh on pull, light
/// refresh on the poll timer) and renders from its fields. Polls reuse known
/// addresses until discovery expires; manual refresh forces a rescan.
/// Remembered views are scoped to a wallet and cleared on security lock.
/// Tokens in a stable order for display: fungible before NFTs, then by
/// name, then by id. The balance answer lists them in whatever order the
/// node's map iterates, which changes from one poll to the next and made
/// the asset tiles shuffle while the screen sat idle.
List<TokenBalance> orderTokensForDisplay(List<TokenBalance> tokens) {
  final out = List<TokenBalance>.of(tokens);
  out.sort((a, b) {
    if (a.isCollectible != b.isCollectible) return a.isCollectible ? 1 : -1;
    final byName = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return out;
}

class WalletSyncController extends ChangeNotifier {
  WalletSyncController(this._gw);

  final WalletSyncGateway _gw;
  final Map<String, _WalletView> _remembered = {};
  String? _viewWalletId;
  bool ownsWallet(String? walletId) =>
      walletId != null &&
      walletId == _viewWalletId &&
      walletId == _gw.activeWalletId &&
      _gw.isUnlocked;
  DateTime? discoveredAt;
  int? _discoveryPinnedIndex;
  bool? _discoveryUnusedChange;
  static const discoveryFreshness = Duration(minutes: 15);

  /// Called synchronously before the service publishes a new wallet identity.
  void activateWallet(String walletId) {
    if (_viewWalletId == walletId) return;
    deactivate();
    _viewWalletId = walletId;
    _remembered.remove(walletId)?.restore(this);
    final warm = _publicWarm.remove(walletId);
    if (warm != null) _applyPublic(warm);
    notifyListeners();
  }

  /// A switch drops the visible view but retains public data until session lock.
  void deactivate() {
    _publicGeneration++;
    final id = _viewWalletId;
    if (id != null) _remembered[id] = _WalletView(this);
    _clearView();
    _viewWalletId = null;
  }

  void forgetWallet(String walletId) {
    _publicGeneration++;
    _publicWarm.remove(walletId);
    _remembered.remove(walletId);
    if (_viewWalletId == walletId) {
      _clearView();
      _viewWalletId = null;
    }
  }

  final Map<String, Map<String, dynamic>> _publicWarm = {};
  int _publicGeneration = 0;
  int get publicGeneration => _publicGeneration;
  bool publicSnapshotOnly = false;

  bool rememberPublic(
    String id,
    Map<String, dynamic> snapshot,
    int generation,
  ) {
    if (generation != publicGeneration ||
        !_gw.isUnlocked ||
        id == _gw.activeWalletId ||
        snapshot['wallet_id'] != id)
      return false;
    _publicWarm[id] = snapshot;
    return true;
  }

  void _applyPublic(Map<String, dynamic> snapshot) {
    publicSnapshotOnly = true;
    balanceNano = snapshot['balance_nano_erg'] as int;
    _nodePending = PendingBalance.fromJson(snapshot['pending']);
    recentTxs = _mapList(snapshot['transactions']);
    tokens = orderTokensForDisplay([
      for (final t in snapshot['tokens'] as List)
        TokenBalance(
          id: t['id'],
          amount: t['amount'],
          name: t['name'],
          decimals: t['decimals'],
          iconUrl: t['iconUrl'],
          emissionAmount: t['emissionAmount'],
        ),
    ]);
    addressHoldings = AddressHolding.listFrom(snapshot['address_holdings']);
    phase = SyncPhase.idle;
  }

  SyncPhase phase = SyncPhase.idle;
  String? receiveAddress;
  String? changeAddress;
  String? senderAddress;

  /// The balance once everything pending confirms: confirmed boxes, less
  /// what pending transactions spend, plus what they pay in (incoming
  /// payments and change alike). [pending] splits it.
  int? balanceNano;
  List<TokenBalance> tokens = const [];

  /// The node's wallet-wide pending summary from the last sync that could
  /// value it.
  PendingBalance? _nodePending;

  /// How [balanceNano] splits into confirmed and pending, with this app's
  /// broadcasts the node has not listed yet folded in. Null when the last
  /// sync could not value the mempool (a listing failed) or nothing has
  /// synced yet. See [pendingBalanceText] for the line screens show.
  PendingBalance? get pending {
    final node = _nodePending;
    if (node == null) return null;
    _dropExpiredBroadcasts();
    var delta = 0;
    for (final b in _broadcasts.values) {
      delta += b.valueNano ?? 0;
    }
    return node.withUnseenBroadcasts(delta, _broadcasts.length);
  }
  List<Map<String, dynamic>> recentTxs = const [];
  List<Map<String, dynamic>> usedAddresses = const [];

  /// Derived addresses from index 0 to the usage frontier, set by
  /// discovery. Always included in balance queries.
  List<String> frontierAddresses = const [];

  /// What each address held in the last balance read in which every
  /// address answered, so the home screen can say how much of the total
  /// sits away from the address the wallet is shown as. A partial read
  /// leaves the previous split: it would misplace funds between addresses.
  List<AddressHolding> addressHoldings = const [];
  int utxoCount = 0;
  DateTime? lastSyncedAt;

  /// Activity as the user should see it, newest first.
  List<Map<String, dynamic>> get displayActivity => recentTxs;

  /// Non-null when the stored pinned address index can't be derived.
  String? pinIssue;

  Future<void>? _inFlight;
  int _generation = 0;
  String? _refreshWalletId;

  /// Rejects work from a wallet or refresh that no longer owns the screen.
  bool _current(int generation, String? walletId) {
    if (generation != _generation || walletId != _gw.activeWalletId)
      return false;
    if (!_gw.isUnlocked) {
      reset();
      return false;
    }
    return true;
  }

  /// Reserves success for a completed wallet sync, even when a node is online.
  String statusLabel({required bool online}) {
    final t = appL10n;
    if (publicSnapshotOnly)
      return t.syncPublicKnownOnly;
    if (isSyncing) return t.syncSyncing;
    if (isStale) return t.syncOutOfSync;
    if (!online) return t.commonOffline;
    if (phase == SyncPhase.historyPartial) return t.syncHistoryIncomplete;
    if (phase == SyncPhase.synced && lastSyncedAt != null) return t.syncSynced;
    return t.syncNotSynced;
  }

  /// Transactions this app broadcast recently, by id: when, and the
  /// balance change they carry. A row for each is shown at once, and kept
  /// until the node's own view has it or [broadcastGrace] passes.
  final Map<String, _Broadcast> _broadcasts = {};

  /// How long a broadcast row and its balance delta stand in for the
  /// node's view. Mempool propagation takes seconds; a transaction still
  /// unseen after this was most likely dropped, and the node's view wins.
  static const broadcastGrace = Duration(seconds: 90);

  /// True while something is unconfirmed: a Pending row in the activity, or
  /// a broadcast still inside its grace. The home screen polls faster then.
  bool get hasPending {
    _dropExpiredBroadcasts();
    if (_broadcasts.isNotEmpty) return true;
    return recentTxs.any((tx) => ((tx['height'] as num?)?.toInt() ?? 0) == 0);
  }

  /// A transaction this app just broadcast. Shows it as Pending at once and
  /// moves the balance by [valueNano] (negative for a spend) when known,
  /// then refreshes now and again shortly after, by which time the node's
  /// mempool has it. Calling twice for one id merges the value in.
  void noteBroadcast(String txId, {int? valueNano}) {
    if (txId.isEmpty) return;
    final prior = _broadcasts[txId];
    final known = prior?.valueNano;
    final note = _Broadcast(DateTime.now(), valueNano ?? known);
    _broadcasts[txId] = note;
    final idx = recentTxs.indexWhere((tx) => tx['tx_id'] == txId);
    final row = {
      'tx_id': txId,
      'height': 0,
      'timestamp': note.at.millisecondsSinceEpoch,
      'value_nano_erg': note.valueNano ?? 0,
      'token_ids': const <String>[],
      'tokens_received': const <Map<String, dynamic>>[],
      'confirmed': false,
      'broadcast': true,
    };
    if (idx < 0) {
      recentTxs = [row, ...recentTxs];
    } else if (recentTxs[idx]['broadcast'] == true) {
      recentTxs = [...recentTxs]..[idx] = row;
    }
    // Apply the delta once: on the first note that carries a value.
    if (valueNano != null && known == null && balanceNano != null) {
      balanceNano = (balanceNano! + valueNano).clamp(0, 1 << 62);
    }
    notifyListeners();
    unawaited(refresh(discover: false, quiet: true));
    final broadcastWalletId = _gw.activeWalletId;
    Future.delayed(const Duration(seconds: 4), () {
      if (_gw.activeWalletId == broadcastWalletId &&
          _broadcasts.containsKey(txId)) {
        unawaited(refresh(discover: false, quiet: true));
      }
    });
  }

  void _dropExpiredBroadcasts() {
    final now = DateTime.now();
    _broadcasts.removeWhere((_, b) => now.difference(b.at) > broadcastGrace);
  }

  /// Rows from the node, with the broadcasts it has not seen yet put back
  /// in front; a broadcast the node does show is settled and forgotten.
  List<Map<String, dynamic>> _withBroadcasts(List<Map<String, dynamic>> txs) {
    _dropExpiredBroadcasts();
    if (_broadcasts.isEmpty) return txs;
    final ids = {for (final tx in txs) tx['tx_id']?.toString()};
    for (final id in ids) {
      if (id != null) _broadcasts.remove(id);
    }
    final unseen = <Map<String, dynamic>>[
      for (final tx in recentTxs)
        if (tx['broadcast'] == true && _broadcasts.containsKey(tx['tx_id'])) tx,
    ];
    return [...unseen, ...txs];
  }

  /// The node's balance omits a broadcast its mempool has not seen yet;
  /// the deltas of those are carried until it does.
  int _withBroadcastDeltas(int nodeBalance) {
    var out = nodeBalance;
    for (final b in _broadcasts.values) {
      out += b.valueNano ?? 0;
    }
    return out < 0 ? 0 : out;
  }

  bool get isStale =>
      phase == SyncPhase.failed ||
      phase == SyncPhase.balancesStale ||
      phase == SyncPhase.noAddresses;

  bool get isSyncing => phase == SyncPhase.syncing;

  /// True while a refresh is in flight; the dashboard poll skips ticks.
  bool get busy => _inFlight != null;

  /// Wallet context for pushed screens, mirroring the synced state.
  WalletRouteArgs get routeArgs {
    final receive = receiveAddress ?? '';
    return WalletRouteArgs(
      senderAddress: senderAddress ?? receive,
      receiveAddress: receive,
      changeAddress: changeAddress ?? receive,
      historyAddresses: historyAddresses,
      tokens: tokens,
      spendableNano: balanceNano,
    );
  }

  /// Addresses whose activity and balances make up the wallet view.
  List<String> get historyAddresses {
    final out = <String>[];
    for (final used in usedAddresses) {
      final a = used['address']?.toString();
      if (a != null && a.isNotEmpty) out.add(a);
    }
    for (final a in frontierAddresses) {
      if (!out.contains(a)) out.add(a);
    }
    final receive = receiveAddress;
    if (receive != null && !out.contains(receive)) out.add(receive);
    return out;
  }

  /// Clears everything back to the locked state.
  void reset() {
    _publicGeneration++;
    _publicWarm.clear();
    _remembered.clear();
    _viewWalletId = null;
    _clearView();
  }

  void _clearView() {
    _generation++;
    _inFlight = null;
    _refreshWalletId = null;
    discoveredAt = null;
    _discoveryPinnedIndex = null;
    _discoveryUnusedChange = null;
    publicSnapshotOnly = false;
    phase = SyncPhase.idle;
    receiveAddress = null;
    changeAddress = null;
    senderAddress = null;
    balanceNano = null;
    _nodePending = null;
    tokens = const [];
    recentTxs = const [];
    usedAddresses = const [];
    frontierAddresses = const [];
    addressHoldings = const [];
    utxoCount = 0;
    pinIssue = null;
    lastSyncedAt = null;
    _broadcasts.clear();
    notifyListeners();
  }

  /// Derives the main address locally and hydrates from the cache so the
  /// ledger paints before any network call. Returns false when no address
  /// could be derived (or the wallet locked meanwhile).
  Future<bool> hydrateAfterUnlock() async {
    if (!_gw.isUnlocked) return false;
    final id = _gw.activeWalletId;
    if (id != null) activateWallet(id);
    final generation = _generation;
    final walletId = _gw.activeWalletId;
    final pinned = await _gw.getPinnedAddressIndex();
    if (!_current(generation, walletId)) return false;
    final unusedChange = _gw.useUnusedChangeAddress(walletId);
    if (receiveAddress != null) {
      if (_discoveryPinnedIndex == pinned &&
          _discoveryUnusedChange == unusedChange) {
        return true;
      }
      discoveredAt = null;
      receiveAddress = null;
      changeAddress = null;
      senderAddress = null;
      notifyListeners();
    }
    var derived = await _gw.tryDeriveAddress(pinned);
    if (!_current(generation, walletId)) return false;
    if (derived == null && pinned != 0) {
      pinIssue = _pinIssueFor(pinned);
      derived = await _gw.tryDeriveAddress(0);
    } else {
      pinIssue = null;
    }
    if (!_current(generation, walletId)) return false;
    if (derived == null) {
      phase = SyncPhase.noAddresses;
      notifyListeners();
      return false;
    }
    final receive = derived;
    receiveAddress ??= receive;
    changeAddress ??= receive;

    final cached = await _gw.loadCachedState(_cacheKey(receive));
    if (!_current(generation, walletId)) return false;
    if (cached != null) {
      publicSnapshotOnly = cached['public_only'] == true;
      final stamp = (cached['last_successful_sync_at'] as num?)?.toInt();
      lastSyncedAt = stamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(stamp);
      // Older snapshots have no evidence of a complete successful sync.
      phase = SyncPhase.values.firstWhere(
        (p) => p.name == cached['sync_phase'] && p != SyncPhase.syncing,
        orElse: () => SyncPhase.idle,
      );
      if (phase == SyncPhase.synced && lastSyncedAt == null)
        phase = SyncPhase.idle;
      frontierAddresses = (cached['frontier_addresses'] as List? ?? const [])
          .cast<String>();
      final discoveryStamp = (cached['discovered_at'] as num?)?.toInt();
      discoveredAt = discoveryStamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(discoveryStamp);
      _discoveryPinnedIndex = cached['discovery_pinned_index'] as int?;
      _discoveryUnusedChange = cached['discovery_unused_change'] as bool?;
      if (_discoveryPinnedIndex == pinned &&
          _discoveryUnusedChange == unusedChange) {
        receiveAddress = cached['primary_address'] as String? ?? receive;
        changeAddress = cached['change_address'] as String? ?? receiveAddress;
      } else {
        // A pin/privacy change invalidates routing, but known addresses can refresh.
        discoveredAt = null;
      }
      usedAddresses = _mapList(cached['used_addresses']);
      addressHoldings = AddressHolding.listFrom(cached['address_holdings']);
      balanceNano = (cached['balance_nano_erg'] as num?)?.toInt();
      _nodePending = PendingBalance.fromJson(cached['pending']);
      recentTxs = _mapList(cached['transactions']);
      tokens = orderTokensForDisplay([
        for (final t in (cached['tokens'] as List? ?? const []))
          if (t is Map)
            TokenBalance(
              id: t['id']?.toString() ?? '',
              amount: (t['amount'] as num?)?.toInt() ?? 0,
              name: t['name']?.toString(),
              decimals: (t['decimals'] as num?)?.toInt() ?? 0,
              iconUrl: t['iconUrl']?.toString(),
              emissionAmount: (t['emissionAmount'] as num?)?.toInt(),
            ),
      ]);
      utxoCount = (cached['utxo_count'] as num?)?.toInt() ?? 0;
    }
    // A pinned wallet is still the wallet at index 0. With nothing recorded
    // yet (first unlock on this device, or a cache from before snapshots
    // were per wallet) its only known address would be the pinned one, so
    // the first pass — and every pass, should discovery fail — would leave
    // out what index 0 holds.
    if (pinned != 0 && frontierAddresses.isEmpty && usedAddresses.isEmpty) {
      final zero = await _gw.tryDeriveAddress(0);
      if (!_current(generation, walletId)) return false;
      if (zero != null && zero != receive) frontierAddresses = [zero];
    }
    senderAddress ??= _bestSender(receiveAddress ?? receive);
    notifyListeners();
    return true;
  }

  /// Refreshes balances, activity and UTXO count. With [discover] the
  /// address set is rescanned first and the node list re-probed.
  /// Concurrent callers in the same wallet generation share the operation.
  /// [quiet] is for the background poll: it refreshes without announcing
  /// itself, so the status strip does not flip to "Syncing…" and back every
  /// 20 seconds. The result still updates the phase, so a failure or stale
  /// balance is reported as soon as it happens.
  Future<void> refresh({
    required bool discover,
    bool quiet = false,
    bool forceDiscovery = true,
  }) {
    if (!_gw.isUnlocked) return Future.value();
    final walletId = _gw.activeWalletId;
    // Legacy/test callers can seed a view before the first refresh.
    _viewWalletId ??= walletId;
    if (walletId != null && _viewWalletId != walletId) activateWallet(walletId);
    final running = _inFlight;
    if (running != null && _refreshWalletId == walletId) return running;
    final generation = ++_generation;
    _refreshWalletId = walletId;
    late final Future<void> op;
    final age = discoveredAt == null
        ? null
        : DateTime.now().difference(discoveredAt!);
    final expired = age == null || age.isNegative || age >= discoveryFreshness;
    final needsDiscovery =
        (discover && (forceDiscovery || expired)) ||
        (quiet && discoveredAt != null && expired);
    op = _refreshScheduled(needsDiscovery, generation, walletId, quiet: quiet)
        .whenComplete(() {
          if (identical(_inFlight, op)) _inFlight = null;
        });
    _inFlight = op;
    return op;
  }

  Future<void> _refreshScheduled(
    bool discover,
    int generation,
    String? walletId, {
    required bool quiet,
  }) async {
    if (!discover || historyAddresses.isEmpty) {
      await _refresh(discover, generation, walletId, quiet: quiet);
      return;
    }
    // Publish remembered-address results before discovery can change the set.
    // Discovery starts after this pass: it never delays known holdings.
    await _refresh(false, generation, walletId, quiet: quiet);
    if (!_current(generation, walletId)) return;
    final before = historyAddresses.toSet();
    _gw.probeNetwork();
    await _discover(generation, walletId);
    if (!_current(generation, walletId)) return;
    if (!setEquals(before, historyAddresses.toSet())) {
      await _refresh(
        false,
        generation,
        walletId,
        quiet: true,
      );
    } else {
      await _saveSnapshot(walletId);
    }
  }

  /// Keeps publication and cache writes tied to the wallet that started the work.
  Future<void> _refresh(
    bool discover,
    int generation,
    String? walletId, {
    bool quiet = false,
  }) async {
    // A first load has nothing to show yet, so it always announces itself.
    if (!quiet || phase == SyncPhase.idle) {
      phase = SyncPhase.syncing;
      notifyListeners();
    }

    if (discover) {
      _gw.probeNetwork();
      final ok = await _discover(generation, walletId);
      if (!ok || !_current(generation, walletId)) return;
    }

    final addresses = historyAddresses;
    if (addresses.isEmpty) {
      phase = SyncPhase.noAddresses;
      notifyListeners();
      return;
    }

    // Balances, activity and UTXO count don't depend on each other. The
    // balance is the fast leg and is shown as soon as it lands; the
    // history, which can take ten seconds on a public node, follows.
    final gateway = _gw;
    final read = gateway is WalletSyncBatchGateway
        ? (gateway as WalletSyncBatchGateway).startRead(addresses)
        : null;
    final balancesFuture = _fetchBalances(addresses, read);
    final pendingFuture = read is WalletSyncPendingRead
        ? (read as WalletSyncPendingRead).pending().catchError(
            (Object _) => null,
          )
        : Future<PendingBalance?>.value();
    final listedFuture = read is WalletSyncPendingRead
        ? (read as WalletSyncPendingRead).pendingIds().catchError(
            (Object _) => <String>{},
          )
        : Future<Set<String>>.value(const {});
    final historyFuture = _fetchHistory(addresses, read);
    final countFuture = (read?.count() ?? _gw.countUnspentBoxes(addresses))
        .catchError((_) => utxoCount);

    final balances = await balancesFuture;
    final summary = await pendingFuture;
    final listed = await listedFuture;
    if (!_current(generation, walletId)) return;
    final failed = balances.failed;
    // A broadcast the node now lists as pending is in its figures already;
    // carrying the delta too would count it twice until history caught up.
    _broadcasts.removeWhere((id, _) => listed.contains(id));
    // The wallet-wide valuation wins over the per-address sum whenever the
    // node could make it; it is null exactly when a listing failed.
    final nodeErg = summary?.netNano ?? balances.erg;
    if (failed < addresses.length) {
      _nodePending = summary;
      balanceNano = _withBroadcastDeltas(nodeErg);
      tokens = orderTokensForDisplay(
        summary == null
            ? balances.tokens
            : _summaryAmounts(balances.tokens, summary),
      );
      notifyListeners();
    }
    if (failed == 0) {
      addressHoldings = [
        for (final h in balances.perAddress)
          h.withIndex(
            recordedAddressIndex(
              h.address,
              frontier: frontierAddresses,
              used: usedAddresses,
            ),
          ),
      ];
    }

    final results = await Future.wait<Object?>([
      historyFuture,
      countFuture,
    ]);
    if (!_current(generation, walletId)) return;
    final history = results[0] as HistoryResult?;
    final txs = history?.rows;
    final boxes = results[1] as int;

    // Replace only when trustworthy: an empty result with no failures means
    // pending entries dropped from the mempool and must leave the list; an
    // empty result alongside failures is unreliable, keep what we had.
    if (txs != null && (txs.isNotEmpty || failed == 0)) {
      recentTxs = _withBroadcasts(txs).take(5).toList();
      // The node now vouches for what it shows; a broadcast it lists no
      // longer needs its delta carried.
      if (failed < addresses.length) {
        balanceNano = _withBroadcastDeltas(nodeErg);
      }
    }
    utxoCount = boxes;

    if (failed == addresses.length) {
      phase = SyncPhase.failed;
    } else if (failed > 0) {
      phase = SyncPhase.balancesStale;
    } else if (history == null || history.partial) {
      phase = SyncPhase.historyPartial;
    } else {
      publicSnapshotOnly = false;
      phase = SyncPhase.synced;
      lastSyncedAt = DateTime.now();
    }
    notifyListeners();
    if (!_current(generation, walletId)) return;

    // Names. Candidates come only from balance responses that SUCCEEDED in
    // this refresh — `tokens` is retained on failure, so using the field
    // could send a previous wallet state to a node that never returned it.
    // Ids seen moving in recent activity are deliberately excluded: history
    // is fetched through a separate client that can resolve to a different
    // node, so those ids were not necessarily served by `servedBy`.
    final ordinaryIds = <String>{
      if (failed < addresses.length) for (final t in balances.tokens) t.id,
    };
    final servedBy = read == null ? null : await read.servedBy();
    if (!_current(generation, walletId)) return;
    if (ordinaryIds.isNotEmpty && servedBy != null && walletId != null) {
      _startNameResolution(ordinaryIds, generation, walletId, servedBy);
    }

    if (!_current(generation, walletId)) return;
    await _saveSnapshot(walletId);
  }

  /// Name resolution owned by the controller rather than awaited by the
  /// refresh. A slow node must not hold `_inFlight`: polls, manual
  /// refreshes, post-broadcast refreshes and scheduled discovery all join
  /// that future, and forty 15-second timeouts would block them for ten
  /// minutes. Cancellation is by generation, checked inside the pass.
  Future<void>? _nameResolution;

  /// Exposed so tests can await the pass instead of racing it.
  @visibleForTesting
  Future<void>? get pendingNameResolution => _nameResolution;

  void _startNameResolution(
    Set<String> ids,
    int generation,
    String walletId,
    String servedBy,
  ) {
    _nameResolution = _gw
        .resolveTokenNames(
          ids,
          walletId: walletId,
          servedBy: servedBy,
          stillCurrent: () => _current(generation, walletId),
        )
        .then((resolved) async {
          if (resolved.isEmpty || !_current(generation, walletId)) return;
          _applyResolved(resolved);
          notifyListeners();
          // The snapshot was written before this pass finished, so it still
          // carries the pre-resolution scale. Without re-saving, a wallet
          // locked before its next sync keeps a persisted holding of five
          // base units reading as five rather than 0.05 — and a later public
          // refresh carries that zero forward indefinitely.
          if (!_current(generation, walletId)) return;
          await _saveSnapshot(walletId);
        })
        .catchError((_) {})
        .whenComplete(() => _nameResolution = null);
  }

  /// Folds resolved descriptors into the holdings already on screen. Without
  /// this a completed refresh keeps showing truncated ids and zero-decimal
  /// amounts until some later hydration happens to pick them up.
  void _applyResolved(Map<String, TokenBalance> resolved) {
    List<TokenBalance> apply(List<TokenBalance> current) => [
      for (final t in current)
        resolved[t.id]?.withHolding(t.amount) ??
            t,
    ];
    tokens = apply(tokens);
  }

  Future<void> _saveSnapshot(String? walletId) async {
    final receive = receiveAddress;
    if (receive != null &&
        (phase != SyncPhase.failed || discoveredAt != null)) {
      await _gw.saveCachedState({
        'wallet_id': walletId ?? receive,
        'public_only': publicSnapshotOnly,
        'sync_phase': phase.name,
        'last_successful_sync_at': lastSyncedAt?.millisecondsSinceEpoch,
        'primary_address': receive,
        'used_addresses': usedAddresses,
        'frontier_addresses': frontierAddresses,
        'discovered_at': discoveredAt?.millisecondsSinceEpoch,
        'discovery_pinned_index': _discoveryPinnedIndex,
        'discovery_unused_change': _discoveryUnusedChange,
        'change_address': changeAddress,
        'balance_nano_erg': balanceNano,
        // The split behind balance_nano_erg, so the two always agree.
        'pending': pending?.toJson(),
        'tokens': [
          for (final t in tokens)
            {
              'id': t.id,
              'amount': t.amount,
              'name': t.name,
              'decimals': t.decimals,
              'iconUrl': t.iconUrl,
              'emissionAmount': t.emissionAmount,
            },
        ],
        'transactions': recentTxs,
        'utxo_count': utxoCount,
        'address_holdings': [for (final h in addressHoldings) h.toJson()],
      });
    }
  }

  /// Rescans the address set. Returns false when the wallet locked meanwhile.
  /// Discovery failures fall through so balances still refresh on the
  /// addresses already known.
  Future<bool> _discover(int generation, String? walletId) async {
    try {
      final raw = await _gw.discoverAddresses();
      if (!_current(generation, walletId)) return false;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final used = _mapList(map['addresses']);
      final next = (map['next_unused_index'] as num?)?.toInt() ?? 0;

      final pinned = await _gw.getPinnedAddressIndex();
      if (!_current(generation, walletId)) return false;
      final pinnedReceive = pinned > 0
          ? await _gw.tryDeriveAddress(pinned)
          : null;
      if (!_current(generation, walletId)) return false;
      pinIssue = pinned > 0 && pinnedReceive == null
          ? _pinIssueFor(pinned)
          : null;

      // Reuse mode (default): everything goes to the main address, which is
      // the pinned one or index 0. Fresh mode (Nautilus-style): receive and
      // change move to the next unused address, except that a pinned
      // address at or beyond the frontier stays the receive address.
      final main = pinnedReceive ?? await _gw.deriveAddress(0);
      if (!_current(generation, walletId)) return false;
      final fresh = _gw.useUnusedChangeAddress(walletId);
      final String receive;
      final String change;
      if (!fresh) {
        receive = main;
        change = main;
      } else {
        if (pinnedReceive != null && pinned >= next) {
          receive = pinnedReceive;
        } else {
          receive = next == 0 ? main : await _gw.deriveAddress(next);
        }
        change = await _gw.deriveAddress(next);
      }
      // Every index up to the frontier is queried for balances even when
      // discovery saw no confirmed history there: a node whose index lags
      // would otherwise hide funds the wallet itself just sent to a new
      // address.
      final frontier = <String>[
        for (var i = 0; i <= next && i < 64; i++) await _gw.deriveAddress(i),
      ];
      if (!_current(generation, walletId)) return false;
      _discoveryPinnedIndex = pinned;
      _discoveryUnusedChange = fresh;
      discoveredAt = DateTime.now();
      usedAddresses = used;
      frontierAddresses = frontier;
      receiveAddress = receive;
      changeAddress = change;
      senderAddress = _bestSender(receive);
      notifyListeners();
    } catch (_) {
      // Fall through to a balance refresh with the addresses we know.
    }
    return true;
  }

  Future<_BalanceResult> _fetchBalances(
    List<String> addresses,
    WalletSyncRead? read,
  ) async {
    final maps = await Future.wait(
      addresses.map((address) async {
        try {
          return await (read?.balance(address) ?? _gw.getBalance(address));
        } catch (_) {
          return null;
        }
      }),
    );
    var erg = 0;
    var failed = 0;
    final merged = <String, TokenBalance>{};
    for (final map in maps) {
      if (map == null) {
        failed++;
        continue;
      }
      erg += (map['balance_nano_erg'] as num?)?.toInt() ?? 0;
      for (final t in await _gw.hydrateTokens(map['tokens'])) {
        final prev = merged[t.id];
        merged[t.id] = t.withHolding((prev?.amount ?? 0) + t.amount);
      }
    }
    final perAddress = [
      for (var i = 0; i < maps.length; i++)
        if (maps[i] case final map?) AddressHolding.fromBalance(addresses[i], map),
    ];
    return _BalanceResult(erg, merged.values.toList(), failed, perAddress);
  }

  /// Holdings with the wallet-wide amounts: the per-address answers carry
  /// names and scales, the summary amounts that count a transfer between
  /// two of the wallet's addresses once.
  static List<TokenBalance> _summaryAmounts(
    List<TokenBalance> tokens,
    PendingBalance summary,
  ) => [
    for (final t in tokens)
      if ((summary.token(t.id)?.amount ?? t.amount) > 0)
        t.withHolding(summary.token(t.id)?.amount ?? t.amount),
  ];

  /// Null when the history call itself failed.
  Future<HistoryResult?> _fetchHistory(
    List<String> addresses,
    WalletSyncRead? read,
  ) async {
    try {
      return await (read?.history() ?? _gw.loadHistory(addresses, limit: 20));
    } catch (_) {
      return null;
    }
  }

  String _bestSender(String receive) {
    var best = receive;
    var bestNano = -1;
    for (final used in usedAddresses) {
      final addr = used['address']?.toString();
      final nano = (used['balance_nano_erg'] as num?)?.toInt() ?? 0;
      if (addr != null && addr.isNotEmpty && nano >= bestNano) {
        best = addr;
        bestNano = nano;
      }
    }
    return best;
  }

  /// Snapshots are stored per wallet id; older code keyed them by address.
  String _cacheKey(String receive) => _gw.activeWalletId ?? receive;

  static String _pinIssueFor(int index) =>
      appL10n.syncPinIssue('$index', '${WalletService.maxAddressIndex}');

  static List<Map<String, dynamic>> _mapList(dynamic raw) =>
      (raw as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
}

class _Broadcast {
  const _Broadcast(this.at, this.valueNano);
  final DateTime at;
  final int? valueNano;
}

class _BalanceResult {
  const _BalanceResult(this.erg, this.tokens, this.failed, this.perAddress);
  final int erg;
  final List<TokenBalance> tokens;
  final int failed;

  /// One entry per address that answered, in query order.
  final List<AddressHolding> perAddress;
}

/// The app's one sync controller: the home screen drives it and the
/// navigator-level [WalletArgsScope] in `main.dart` reads from it.
final walletSyncController = WalletSyncController(
  const LiveWalletSyncGateway(),
);

class _WalletView {
  _WalletView(WalletSyncController c)
    : data = (
        publicSnapshotOnly: c.publicSnapshotOnly,
        phase: c.phase,
        receiveAddress: c.receiveAddress,
        changeAddress: c.changeAddress,
        senderAddress: c.senderAddress,
        balanceNano: c.balanceNano,
        nodePending: c._nodePending,
        tokens: c.tokens,
        recentTxs: c.recentTxs,
        usedAddresses: c.usedAddresses,
        frontierAddresses: c.frontierAddresses,
        addressHoldings: c.addressHoldings,
        utxoCount: c.utxoCount,
        lastSyncedAt: c.lastSyncedAt,
        pinIssue: c.pinIssue,
        discoveredAt: c.discoveredAt,
        discoveryPinnedIndex: c._discoveryPinnedIndex,
        discoveryUnusedChange: c._discoveryUnusedChange,
        broadcasts: Map<String, _Broadcast>.of(c._broadcasts),
      );
  final ({
    bool publicSnapshotOnly,
    SyncPhase phase,
    String? receiveAddress,
    String? changeAddress,
    String? senderAddress,
    int? balanceNano,
    PendingBalance? nodePending,
    List<TokenBalance> tokens,
    List<Map<String, dynamic>> recentTxs,
    List<Map<String, dynamic>> usedAddresses,
    List<String> frontierAddresses,
    List<AddressHolding> addressHoldings,
    int utxoCount,
    DateTime? lastSyncedAt,
    String? pinIssue,
    DateTime? discoveredAt,
    int? discoveryPinnedIndex,
    bool? discoveryUnusedChange,
    Map<String, _Broadcast> broadcasts,
  })
  data;
  void restore(WalletSyncController c) {
    c.publicSnapshotOnly = data.publicSnapshotOnly;
    c.phase = data.phase;
    c.receiveAddress = data.receiveAddress;
    c.changeAddress = data.changeAddress;
    c.senderAddress = data.senderAddress;
    c.balanceNano = data.balanceNano;
    c._nodePending = data.nodePending;
    c.tokens = data.tokens;
    c.recentTxs = data.recentTxs;
    c.usedAddresses = data.usedAddresses;
    c.frontierAddresses = data.frontierAddresses;
    c.addressHoldings = data.addressHoldings;
    c.utxoCount = data.utxoCount;
    c.lastSyncedAt = data.lastSyncedAt;
    c.pinIssue = data.pinIssue;
    c.discoveredAt = data.discoveredAt;
    c._discoveryPinnedIndex = data.discoveryPinnedIndex;
    c._discoveryUnusedChange = data.discoveryUnusedChange;
    if (c.phase == SyncPhase.syncing) c.phase = SyncPhase.idle;
    c._broadcasts.addAll(data.broadcasts);
  }
}
