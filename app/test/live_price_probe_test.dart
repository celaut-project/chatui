// A probe of the live price services, off unless ARGUS_LIVE is set: each
// oracle the pricer reads, against a real node, and one whole refresh with
// every rate it publishes on the way.
//
//   ARGUS_LIVE=1 ARGUS_NODE=https://node.kadia.io flutter test test/live_price_probe_test.dart

import 'dart:io';

import 'package:argus_wallet/services/oracle_feeds.dart';
import 'package:argus_wallet/services/oracle_pool.dart';
import 'package:argus_wallet/services/token_pricer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final live = Platform.environment['ARGUS_LIVE'] != null;
  final node = Platform.environment['ARGUS_NODE'] ?? 'https://node.kadia.io';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each oracle, live', () async {
    for (final feed in OracleFeed.values) {
      try {
        final r = await fetchOracleReading(node, feed);
        debugPrint('reading ${feed.name}: rate=${r?.rate} height=${r?.height}');
      } catch (e) {
        debugPrint('reading ${feed.name}: FAILED $e');
      }
    }
    try {
      final s = await OraclePoolClient().fetch(node);
      debugPrint('oracle snapshot: ${s == null ? 'null' : 'ok'}');
    } catch (e) {
      debugPrint('oracle snapshot: FAILED $e');
    }
  }, skip: !live);

  test('one refresh, live', () async {
    final rates = <String>[];
    final pricer = TokenPricer(PricerDeps(
      nodeUrl: () => node,
      tipHeight: () => null,
      oracle: (n) => OraclePoolClient().fetch(n),
      onRate: (usd) => rates.add('usd=$usd'),
      metadataChanges: ChangeNotifier(),
    ));
    await pricer.refresh(force: true);
    debugPrint('rates published $rates');
    debugPrint('ergUsd=${pricer.result.ergUsd} via=${pricer.result.ergVia} '
        'old=${pricer.pricesAreOld} stale=${pricer.stale} error=${pricer.lastError}');
  }, skip: !live);
}
