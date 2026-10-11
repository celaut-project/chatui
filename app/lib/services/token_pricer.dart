import 'dart:async';

import 'package:flutter/foundation.dart';

import 'erg_price_history.dart';
import 'network_controller.dart';
import 'oracle_feeds.dart';
import 'oracle_pool.dart';
import 'token_metadata.dart';
import 'token_pricing.dart';
import 'wallet_service.dart';

/// Everything the pricer needs from the outside, injectable for tests.
class PricerDeps {
  PricerDeps({
    required this.nodeUrl,
    required this.tipHeight,
    required this.oracle,
    required this.onRate,
    Future<OracleReading?> Function(String node, OracleFeed feed)? oracleReading,
    BoxPage? boxPage,
    DateTime Function()? clock,
    int? Function(String tokenId)? decimalsOf,
    Listenable? metadataChanges,
    Timer Function(Duration delay, void Function() run)? timer,
  })  : timer = timer ?? Timer.new,
        oracleReading = oracleReading ?? ((node, feed) => fetchOracleReading(node, feed)),
        boxPage = boxPage ?? fetchBoxPage,
        clock = clock ?? DateTime.now,
        decimalsOf = decimalsOf ?? ((id) => tokenDecimals(id)),
        metadataChanges = metadataChanges ?? walletService.metadataChanges;

  final String? Function() nodeUrl;
  final int? Function() tipHeight;
  final Future<OracleSnapshot?> Function(String node) oracle;

  /// The newest box of a single-rate oracle pool on the node.
  final Future<OracleReading?> Function(String node, OracleFeed feed) oracleReading;

  /// Publishes the ERG rate in USD (null when unknown).
  final void Function(double? usdPerErg) onRate;

  /// Pages of a token's box history from the node, for price history.
  final BoxPage boxPage;
  final DateTime Function() clock;

  /// A token's decimals from the one token lookup (this wallet's
  /// descriptors, the curated registry, the legacy table, and this
  /// session's explicit loads), or null when none of them knows its scale.
  /// Every price is converted at this scale.
  final int? Function(String tokenId) decimalsOf;

  /// Fires when the lookup learns a name or a scale, so prices it held back
  /// are worked out again without another read.
  final Listenable metadataChanges;

  /// Schedules a retry after a refresh that came back without a usable
  /// rate.
  final Timer Function(Duration delay, void Function() run) timer;
}

/// Prices ERG and the tokens the oracle pools quote, in USD, from the
/// user's node.
class TokenPricer extends ChangeNotifier {
  TokenPricer(this._deps) {
    _deps.metadataChanges.addListener(_reprice);
  }

  static const refreshTtl = Duration(minutes: 5);

  /// Prices shown from an earlier read are said to be old only past this
  /// age. A refresh is due every [refreshTtl]; one that fails leaves the
  /// last good prices up, and while those are under three refresh periods
  /// old they are as current as a wallet's prices need to be. Saying "as of
  /// just now" beside them would flag a price that is not stale.
  static const oldAfter = Duration(minutes: 15);

  /// The first retry after a refresh without a usable rate; each further
  /// failure doubles it, up to [refreshTtl].
  static const firstRetry = Duration(seconds: 15);

  final PricerDeps _deps;

  PricingResult result = const PricingResult(ergUsd: null, ergVia: null, prices: {});
  DateTime? asOf;
  bool stale = false;

  /// True when the last refresh produced no rate and the previous prices
  /// are still being shown.
  bool pricesAreOld = false;
  String? lastError;
  bool refreshing = false;

  DateTime? _fetchedAt;

  /// Refreshes in a row that came back without a usable rate, and the
  /// retry waiting after them.
  int _failures = 0;
  Timer? _retry;

  /// A retry is waiting: the screen can say the price is being asked for
  /// again rather than that it is gone.
  bool get retrying => _retry != null;

  /// [pricesAreOld], and old enough to say so ([oldAfter]).
  bool get pricesLookOld {
    if (!pricesAreOld) return false;
    final at = asOf;
    return at == null || _deps.clock().difference(at) > oldAfter;
  }
  bool _pendingForcedRefresh = false;

  /// What the visible prices were last worked out from: when the token
  /// lookup learns a scale, the prices are worked out again from these
  /// instead of waiting for the next read.
  PricingInputs? _lastInputs;

  /// A token whose scale was unknown at the last refresh was left unpriced;
  /// once the lookup knows it, price it from the same quotes.
  void _reprice() {
    final inputs = _lastInputs;
    if (inputs == null) return;
    final fresh = priceTokens(inputs);
    if (fresh.ergUsd == null) return;
    result = fresh;
    stale = pricesAreOld || result.ergStale;
    notifyListeners();
  }

  @override
  void dispose() {
    _deps.metadataChanges.removeListener(_reprice);
    _retry?.cancel();
    super.dispose();
  }

  /// After a refresh: retry soon while it left no usable rate, backing
  /// off, else stand down.
  void _scheduleRetry({required bool usable}) {
    _retry?.cancel();
    _retry = null;
    if (usable) {
      _failures = 0;
      return;
    }
    final delay = firstRetry * (1 << _failures.clamp(0, 5));
    _failures++;
    _retry = _deps.timer(delay > refreshTtl ? refreshTtl : delay, () {
      _retry = null;
      refresh(force: true);
    });
  }

  TokenPrice? priceOf(String tokenId) => result[tokenId];

  /// "Oracle pools · ERG via SigmaUSD oracle" for the settings row. "stale"
  /// goes before the details: the row is cut to two lines, and at large
  /// text sizes only the start survives.
  String get sourceLine {
    final via = result.ergVia;
    if (via == null) return priceSourceLabel;
    return '$priceSourceLabel${stale ? ' · stale' : ''} · ERG via $via';
  }

  /// "≈ $12.30" for a token holding, or null.
  String? fiatTextFor({required String tokenId, required int amount, required int decimals}) =>
      networkController.fiatFromUsd(usdOf(tokenId, amount, decimals));

  /// "≈ $0.0125" per whole token, or null when unpriced.
  String? unitFiatText(String tokenId) {
    final p = result[tokenId];
    if (p == null) return null;
    return networkController.fiatFromUsd(p.usd, maxFrac: 6);
  }

  /// Fiat text for a USD total, or null.
  String? fiatTextForUsd(double? usd) => networkController.fiatFromUsd(usd);

  /// USD value of [amount] of [tokenId], or null when unpriced.
  double? usdOf(String tokenId, int amount, int decimals) =>
      holdingUsd(amount: amount, decimals: decimals, price: result[tokenId]);

  /// Publishes usable rates as each branch settles and retains forced
  /// requests made during a fetch.
  Future<void> refresh({bool force = false}) async {
    final now = _deps.clock();
    if (!force && _fetchedAt != null && now.difference(_fetchedAt!) < refreshTtl) return;
    if (refreshing) {
      _pendingForcedRefresh |= force;
      return;
    }
    final node = _deps.nodeUrl();
    if (node == null) return;
    refreshing = true;
    final errors = <String>[];

    Future<T?> attempt<T>(String what, Future<T?> Function() f) async {
      try {
        return await f();
      } catch (e) {
        errors.add('$what: $e');
        return null;
      }
    }

    final results = List<Object?>.filled(2, null);

    /// Each branch publishes as it settles, so prices show as soon as any
    /// oracle has them; whether the refresh left the prices old is decided
    /// once, when every branch has settled ([last]), not by whichever
    /// branch answered first.
    void publish({bool last = false}) {
      final inputs = PricingInputs(
        oracle: results[0] as OracleSnapshot?,
        oracles: (results[1] as Map<OracleFeed, OracleReading>?) ?? const {},
        tipHeight: _deps.tipHeight(),
        // The one token lookup, read when the prices are worked out.
        decimalsOf: _deps.decimalsOf,
      );
      final fresh = priceTokens(inputs);
      // An oracle that momentarily answers with nothing must not blank
      // every price in the wallet. Keep the last good result and, once the
      // whole refresh is in, say it is old.
      if (fresh.ergUsd != null) {
        result = fresh;
        pricesAreOld = false;
        _lastInputs = inputs;
        // Only a read that produced a rate makes the prices current.
        asOf = now;
        _fetchedAt = now;
      } else if (result.ergUsd == null) {
        result = fresh;
      } else if (last) {
        pricesAreOld = true;
      }
      // Stale only when the ERG rate itself has no current source: a
      // stopped feed for one token is said on that token's row instead.
      stale = pricesAreOld || result.ergStale;
      lastError = errors.isEmpty ? null : errors.join('; ');
      _deps.onRate(result.ergUsd);
      notifyListeners();
    }

    final branches = <Future<Object?>>[
      attempt('oracle', () => _deps.oracle(node)),
      attempt('oracle pools', () async {
        const feeds = OracleFeed.values;
        final got = await Future.wait([
          for (final f in feeds)
            _deps.oracleReading(node, f).catchError((Object e) {
              errors.add('${f.label}: $e');
              return null;
            }),
        ]);
        return <OracleFeed, OracleReading>{
          for (var i = 0; i < feeds.length; i++)
            if (got[i] case final r?) feeds[i]: r,
        };
      }),
    ];
    try {
      await Future.wait([
        for (var i = 0; i < branches.length; i++)
          branches[i].then((value) {
            results[i] = value;
            publish();
          }),
      ]);
      publish(last: true);
      _scheduleRetry(usable: !pricesAreOld && result.ergUsd != null);
    } finally {
      refreshing = false;
      if (_pendingForcedRefresh) {
        _pendingForcedRefresh = false;
        await refresh(force: true);
      } else {
        notifyListeners();
      }
    }
  }

  final Map<String, (DateTime, ErgPriceHistory)> _history = {};

  /// How long an answer saying history is unavailable is kept: short, so a
  /// node that was still starting up is asked again soon.
  static const _unavailableTtl = Duration(seconds: 30);

  /// The label of the price history: the oracle pool that prices ERG.
  static const historyLabel = 'SigmaUSD oracle';

  /// ERG's price over [window] in USD, from the SigmaUSD oracle pool's past
  /// boxes (needs the node's extra index), with its 24-hour change.
  ///
  /// Read on demand and kept in memory for [refreshTtl]; nothing polls in
  /// the background. Times come from block heights at two minutes a block
  /// ([ErgPriceHistory.approximateTimes]). When history cannot be read the
  /// answer says why ([ErgPriceHistory.unavailableReason]) instead of
  /// throwing.
  Future<ErgPriceHistory> ergPriceHistory(PriceWindow window) async {
    final node = _deps.nodeUrl();
    final key = '${window.name}|$node';
    final now = _deps.clock();
    final cached = _history[key];
    if (cached != null) {
      final ttl = cached.$2.available ? refreshTtl : _unavailableTtl;
      if (now.difference(cached.$1) < ttl) return cached.$2;
    }

    ErgPriceHistory answer;
    try {
      answer = await _nodeHistory(window, now, node);
    } catch (e) {
      final reason = e is HistoryUnavailable ? e.reason : 'Price history could not be read: $e';
      answer = ErgPriceHistory.unavailable(window: window, sourceLabel: historyLabel, currency: 'usd', reason: reason);
    }
    _history[key] = (now, answer);
    return answer;
  }

  Future<ErgPriceHistory> _nodeHistory(PriceWindow window, DateTime now, String? node) async {
    if (node == null) throw const HistoryUnavailable('No node is connected.');
    final tip = _deps.tipHeight();
    if (tip == null) throw const HistoryUnavailable('The node height is not known yet.');
    final boxes = await sampleHistory(
      page: _deps.boxPage,
      node: node,
      tokenId: OracleFeed.sigmaUsd.nft,
      tip: tip,
      // Every window is at least a day, so the 24-hour change is covered.
      windowBlocks: window.blocks,
    );
    final byHeight = oracleRateHistory(boxes);
    if (byHeight.isEmpty) throw const HistoryUnavailable('This node has no price history for $historyLabel yet.');
    final points = pointsFromHeights(byHeight, tip: tip, now: now, scale: 1.0);
    return ErgPriceHistory(
      window: window,
      points: clipToWindow(points, window.span, now),
      sourceLabel: historyLabel,
      currency: 'usd',
      change24hPct: changeOver(points, const Duration(hours: 24), now),
      approximateTimes: true,
      stale: tip - byHeight.last.$1 > OracleFeed.sigmaUsd.staleAfterBlocks,
    );
  }
}

final tokenPricer = TokenPricer(PricerDeps(
  nodeUrl: () => networkController.activeUrl,
  tipHeight: () => networkController.height,
  oracle: (node) => OraclePoolClient().fetch(node),
  onRate: (usdPerErg) => networkController.setErgRate(usdPerErg),
));
