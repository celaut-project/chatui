import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:argus_wallet/services/erg_price_history.dart';
import 'package:argus_wallet/services/oracle_feeds.dart';
import 'package:argus_wallet/services/oracle_pool.dart';
import 'package:argus_wallet/services/token_pricer.dart';
import 'package:argus_wallet/services/token_pricing.dart';
import 'package:argus_wallet/services/verified_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rsBtc = '7a51950e5f548549ec1aa63ffdc38279505b11e7e803d01bcf8347e0123c88b0';

/// A positive value as a serialized sigma Long: type 05, then the zigzag
/// VLQ of the value.
String _sigmaLong(int v) {
  var z = v * 2;
  final out = StringBuffer('05');
  do {
    var byte = z & 0x7f;
    z >>= 7;
    if (z > 0) byte |= 0x80;
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  } while (z > 0);
  return out.toString();
}

/// A box of the SigmaUSD oracle pool at [height] pricing ERG at [usd]: R4 is
/// nanoERG per dollar.
Map<String, dynamic> _oracleBox(int height, double usd) => {
      'boxId': 'b$height',
      'value': 1000000000,
      'inclusionHeight': height,
      'assets': [
        {'tokenId': OracleFeed.sigmaUsd.nft, 'amount': 1},
      ],
      'additionalRegisters': {'R4': _sigmaLong((1e9 / usd).round())},
    };

class _Fakes {
  int? tip = 1000;
  int oracleCalls = 0;
  int boxPageCalls = 0;
  String? lastBoxToken;
  double? rate;
  bool oracleFails = false;
  bool readingsFail = false;
  int readingCalls = 0;

  /// Holds the single-rate oracle pools back until completed.
  Completer<void>? readingsGate;

  /// Retries the pricer asked for, by delay; [runRetry] fires the last.
  final retryDelays = <Duration>[];
  void Function()? _pendingRetry;
  void runRetry() {
    final run = _pendingRetry!;
    _pendingRetry = null;
    run();
  }

  /// Blocks behind the tip of each single-rate pool's newest box; a feed
  /// left out has no box. SigmaUSD quotes 0.50 USD (2 ERG per dollar).
  Map<OracleFeed, int> readingAges = {OracleFeed.sigmaUsd: 1};
  DateTime now = DateTime.utc(2026, 10, 6, 12);

  /// The node's box history, newest first; null makes it fail like a node
  /// without the extra index.
  List<Map<String, dynamic>>? boxHistory = [
    _oracleBox(990, 0.32),
    _oracleBox(700, 0.31),
    _oracleBox(100, 0.25), // 30 hours before the tip
  ];

  late final PricerDeps deps = PricerDeps(
    clock: () => now,
    decimalsOf: (id) => knownToken(id)?.decimals,
    oracleReading: (node, feed) async {
      readingCalls++;
      if (readingsGate != null) await readingsGate!.future;
      if (readingsFail) throw Exception('pool box unreadable');
      final age = readingAges[feed];
      if (age == null) return null;
      return OracleReading(rate: 2000000000, height: (tip ?? 1000) - age);
    },
    boxPage: (node, token, offset, limit) async {
      boxPageCalls++;
      lastBoxToken = token;
      final h = boxHistory;
      if (h == null) throw const HistoryUnavailable('This node cannot serve price history: it needs the extra index.');
      return h.skip(offset).take(limit).toList();
    },
    nodeUrl: () => 'http://node',
    tipHeight: () => tip,
    oracle: (_) async {
      oracleCalls++;
      if (oracleFails) throw Exception('boom');
      return OracleSnapshot(epoch: 1, poolHeight: 990, operators: 3, usd: {'ERG_USD': 0.5, 'BTC_USD': 80000});
    },
    timer: (delay, run) {
      retryDelays.add(delay);
      _pendingRetry = run;
      return _FakeTimer(() => _pendingRetry = null);
    },
    onRate: (u) => rate = u,
  );
}

/// A retry that never fires by itself: the test fires it.
class _FakeTimer implements Timer {
  _FakeTimer(this._onCancel);
  final void Function() _onCancel;
  bool _active = true;
  @override
  void cancel() {
    if (_active) _onCancel();
    _active = false;
  }

  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the AVL oracle prices publish while the oracle pools are still pending', () async {
    final f = _Fakes()..readingsGate = Completer<void>();
    final p = TokenPricer(f.deps);
    final op = p.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(p.refreshing, isTrue);
    expect(p.result.ergUsd, 0.5);
    expect(f.rate, 0.5);
    expect(p.priceOf(rsBtc)?.usd, 80000);
    f.readingsGate!.complete();
    await op;
    expect(p.refreshing, isFalse);
  });

  test('publishes the ERG rate in USD', () async {
    final f = _Fakes();
    final p = TokenPricer(f.deps);
    await p.refresh();
    expect(p.result.ergUsd, 0.5);
    expect(p.priceOf(rsBtc)!.usd, 80000);
    expect(f.rate, 0.5);
    expect(p.stale, isFalse);
  });

  test('the ERG rate comes from the SigmaUSD pool, and survives the AVL oracle failing', () async {
    final f = _Fakes()..oracleFails = true;
    final p = TokenPricer(f.deps);
    await p.refresh();
    expect(p.result.ergUsd, 0.5);
    expect(p.result.ergVia, 'SigmaUSD oracle');
    expect(p.lastError, contains('oracle'));
  });

  test('when no oracle answers there is no rate and the errors are recorded', () async {
    final f = _Fakes()
      ..oracleFails = true
      ..readingsFail = true;
    final p = TokenPricer(f.deps);
    await p.refresh();
    expect(p.result.ergUsd, isNull);
    expect(f.rate, isNull);
    expect(p.lastError, contains('SigmaUSD oracle'));
  });

  test('a stopped AVL oracle no longer flags a current ERG rate as stale', () async {
    // The AVL pool box (height 990) is 200 blocks old; SigmaUSD is current.
    final f = _Fakes()..tip = 990 + 200;
    final p = TokenPricer(f.deps);
    await p.refresh();
    expect(p.stale, isFalse);
    expect(p.result.ergVia, 'SigmaUSD oracle');
    expect(p.priceOf(rsBtc)!.via, 'AVL oracle, 6 h old', reason: 'the major says its own age');
    expect(p.priceOf(rsBtc)!.countsInTotal, isFalse);
    expect(p.sourceLine, 'Oracle pools · ERG via SigmaUSD oracle');
  });

  test('with every ERG source stopped, the rate is shown stale with its age', () async {
    final f = _Fakes()
      ..tip = 990 + 200
      ..readingAges = {OracleFeed.sigmaUsd: 150};
    final p = TokenPricer(f.deps);
    await p.refresh();
    expect(p.stale, isTrue);
    expect(p.result.ergUsd, 0.5);
    expect(p.result.ergVia, 'SigmaUSD oracle, 5 h old');
    // The settings row is cut to two lines; "stale" leads so it survives.
    expect(p.sourceLine, 'Oracle pools · stale · ERG via SigmaUSD oracle, 5 h old');
  });

  test('the price source says what it reads', () {
    expect(priceSourceLabel, 'Oracle pools');
    expect(priceSourceBlurb, contains('ERG from the SigmaUSD oracle pool'));
    expect(priceSourceBlurb, contains('gold from the Dexy gold oracle'));
    expect(priceSourceBlurb, contains('never as current'));
    final p = TokenPricer(_Fakes().deps);
    expect(p.sourceLine, 'Oracle pools', reason: 'no rate yet, no source details');
  });

  test('every oracle pool is read', () async {
    final f = _Fakes();
    await TokenPricer(f.deps).refresh();
    expect(f.readingCalls, OracleFeed.values.length);
  });

  test('refresh is throttled unless forced', () async {
    final f = _Fakes();
    final p = TokenPricer(f.deps);
    await p.refresh();
    await p.refresh();
    expect(f.oracleCalls, 1);
    await p.refresh(force: true);
    expect(f.oracleCalls, 2);
  });

  group('ERG price history', () {
    test('reads the SigmaUSD pool past boxes, with a 24h change', () async {
      final f = _Fakes();
      final h = await TokenPricer(f.deps).ergPriceHistory(PriceWindow.day);
      expect(h.available, isTrue);
      expect(f.lastBoxToken, OracleFeed.sigmaUsd.nft);
      expect(h.sourceLabel, 'SigmaUSD oracle');
      expect(h.approximateTimes, isTrue);
      // In force a day ago (720 blocks before the tip): 0.25; newest 0.32.
      expect(h.change24hPct, closeTo(28, 0.01));
      expect(h.points.first.at, f.now.subtract(const Duration(hours: 24)));
      expect(h.points.last.price, closeTo(0.32, 0.0001));
    });

    test('reads the recorded SigmaUSD pool history', () async {
      final raw = jsonDecode(File('test/fixtures/sigmausd_oracle_pool_history.json').readAsStringSync()) as Map;
      final f = _Fakes()
        ..tip = 1888757
        ..boxHistory = [for (final b in raw['items'] as List) (b as Map).cast<String, dynamic>()];
      final h = await TokenPricer(f.deps).ergPriceHistory(PriceWindow.day);
      expect(f.lastBoxToken, OracleFeed.sigmaUsd.nft);
      expect(h.available, isTrue);
      expect(h.sourceLabel, 'SigmaUSD oracle');
      expect(h.points.last.price, closeTo(0.32011, 0.00001));
      expect(h.stale, isFalse);
      expect(h.change24hPct, isNull, reason: 'sixteen recorded boxes do not reach back a day');
    });

    test('is cached for the refresh period, with no polling', () async {
      final f = _Fakes();
      final p = TokenPricer(f.deps);
      await p.ergPriceHistory(PriceWindow.day);
      final calls = f.boxPageCalls;
      await p.ergPriceHistory(PriceWindow.day);
      expect(f.boxPageCalls, calls);
      f.now = f.now.add(TokenPricer.refreshTtl);
      await p.ergPriceHistory(PriceWindow.day);
      expect(f.boxPageCalls, greaterThan(calls));
    });

    test('a node without the extra index degrades to a reason, briefly cached', () async {
      final f = _Fakes()..boxHistory = null;
      final p = TokenPricer(f.deps);
      final h = await p.ergPriceHistory(PriceWindow.week);
      expect(h.available, isFalse);
      expect(h.points, isEmpty);
      expect(h.unavailableReason, contains('extra index'));
      final calls = f.boxPageCalls;
      await p.ergPriceHistory(PriceWindow.week);
      expect(f.boxPageCalls, calls, reason: 'not hammered');
      f.now = f.now.add(const Duration(seconds: 31));
      f.boxHistory = [_oracleBox(990, 0.3)];
      expect((await p.ergPriceHistory(PriceWindow.week)).available, isTrue, reason: 'asked again soon');
    });

    test('no node, no history', () async {
      final f = _Fakes();
      final deps = PricerDeps(
        nodeUrl: () => null,
        tipHeight: f.deps.tipHeight,
        oracle: f.deps.oracle,
        oracleReading: f.deps.oracleReading,
        onRate: f.deps.onRate,
        clock: () => f.now,
        boxPage: f.deps.boxPage,
      );
      final h = await TokenPricer(deps).ergPriceHistory(PriceWindow.day);
      expect(h.available, isFalse);
      expect(h.unavailableReason, contains('No node'));
    });
  });

  group('a failed refresh', () {
    test('prices from a moment ago are not called old; past the threshold they are', () async {
      final f = _Fakes();
      final p = TokenPricer(f.deps);
      await p.refresh();
      final at = p.asOf;
      f
        ..oracleFails = true
        ..readingsFail = true
        ..now = f.now.add(const Duration(minutes: 6));
      await p.refresh(force: true);
      expect(p.pricesAreOld, isTrue, reason: 'this read produced no rate');
      expect(p.asOf, at, reason: 'an old price does not move the time it was read');
      expect(p.pricesLookOld, isFalse, reason: 'six minutes old is still current enough');
      f.now = f.now.add(TokenPricer.oldAfter);
      expect(p.pricesLookOld, isTrue);
    });

    test('is retried soon, backing off, and stands down once a rate comes back', () async {
      final f = _Fakes()
        ..oracleFails = true
        ..readingsFail = true;
      final p = TokenPricer(f.deps);
      await p.refresh();
      expect(p.result.ergUsd, isNull);
      expect(p.retrying, isTrue);
      expect(f.retryDelays, [TokenPricer.firstRetry]);
      /// Waits, a bounded number of turns, for the retried refresh to finish.
      Future<void> settled() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(Duration.zero);
          if (!p.refreshing) return;
        }
        fail('the retried refresh never finished');
      }

      f.runRetry();
      await settled();
      expect(f.retryDelays, [TokenPricer.firstRetry, TokenPricer.firstRetry * 2]);
      f
        ..oracleFails = false
        ..readingsFail = false;
      f.runRetry();
      await settled();
      expect(p.result.ergUsd, 0.5);
      expect(p.retrying, isFalse);
    });

    test('a branch that answers before the rate does not flag the prices old', () async {
      final f = _Fakes();
      final p = TokenPricer(f.deps);
      await p.refresh();
      // The next refresh: the oracle pools are held back, the AVL oracle
      // answers first. Neither alone has the whole picture.
      f.readingsGate = Completer<void>();
      final run = p.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(p.pricesAreOld, isFalse);
      f.readingsGate!.complete();
      await run;
      expect(p.pricesAreOld, isFalse);
    });
  });
}
