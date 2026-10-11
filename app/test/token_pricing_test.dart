import 'package:argus_wallet/services/oracle_feeds.dart';
import 'package:argus_wallet/services/oracle_pool.dart';
import 'package:argus_wallet/services/token_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

const rsBtc = '7a51950e5f548549ec1aa63ffdc38279505b11e7e803d01bcf8347e0123c88b0';
const spf = '9a06d9e545a41fd51eeffc5e20d818073bf820c635e2a9d922269913e0de369d';

final oracle = OracleSnapshot(epoch: 1, poolHeight: 100, operators: 3, usd: {
  'ERG_USD': 0.25,
  'BTC_USD': 80000,
  'XAU_USD': 4600,
});

int decimals(String id) => switch (id) {
      spf => 6,
      rsBtc => 8,
      _ => 0,
    };

void main() {
  _rowValueTests();
  test('with only a current AVL oracle: ERG and rsBTC from it', () {
    final r = priceTokens(PricingInputs(oracle: oracle, decimalsOf: decimals));
    expect(r.ergUsd, 0.25);
    expect(r.ergVia, 'AVL oracle');
    expect(r.ergStale, isFalse);
    expect(r[rsBtc]!.usd, 80000);
    expect(r[rsBtc]!.via, 'AVL oracle');
  });

  test('with no oracle reading nothing is priced', () {
    final r = priceTokens(PricingInputs(decimalsOf: decimals));
    expect(r.ergUsd, isNull);
    expect(r.prices, isEmpty);
  });

  test('a holding recorded at another scale is valued at the price\'s own', () {
    final r = priceTokens(PricingInputs(oracle: oracle, decimalsOf: decimals));
    expect(r[rsBtc]!.decimals, 8);
    // A holding published before the scale was known says 0 decimals; its
    // base units are still 0.001 BTC.
    expect(holdingUsd(amount: 100000, decimals: 0, price: r[rsBtc]), closeTo(80, 1e-9));
    final v = holdingsValue(ergNano: 0, tokens: [(id: rsBtc, amount: 100000, decimals: 0)], result: r);
    expect(v.usd, closeTo(80, 1e-9));
  });

  test('a token no oracle quotes has no price', () {
    final r = priceTokens(PricingInputs(oracle: oracle, decimalsOf: decimals));
    expect(r[spf], isNull);
  });

  test('holdingsValue sums ERG and counted tokens and reports the rest', () {
    final r = priceTokens(PricingInputs(oracle: oracle, decimalsOf: decimals));
    final v = holdingsValue(
      ergNano: 100 * 1000000000,
      tokens: [
        (id: rsBtc, amount: 100000, decimals: 8), // 0.001 BTC = $80
        (id: 'unknown', amount: 5, decimals: 0),
      ],
      result: r,
    );
    expect(v.usd, closeTo(25 + 80, 1e-9));
    expect(v.priced, 1);
    expect(v.excluded, 0);
    expect(v.unpriced, 1);
  });

  group('oracle freshness', () {
    // Heights as on 2026-10-06: the AVL pool last refreshed at 1,872,818,
    // the SigmaUSD pool two blocks before the tip.
    const tip = 1888757;
    final staleAvl = OracleSnapshot(epoch: 14780, poolHeight: 1872818, operators: 4, usd: {
      'ERG_USD': 0.288,
      'BTC_USD': 80000,
      'XAU_USD': 4000,
    });
    const sigmaUsd = OracleReading(rate: 3123969090, height: tip - 2); // $0.3201
    const goldPerKg = 417524904977633; // nanoERG per kilogram

    PricingResult price({
      Map<OracleFeed, OracleReading> oracles = const {},
      OracleSnapshot? avl,
    }) =>
        priceTokens(PricingInputs(
          oracle: avl,
          oracles: oracles,
          tipHeight: tip,
          decimalsOf: decimals,
        ));

    test('a current SigmaUSD pool prices ERG even when the AVL oracle stopped', () {
      final r = price(oracles: {OracleFeed.sigmaUsd: sigmaUsd}, avl: staleAvl);
      expect(r.ergUsd, closeTo(0.32011, 0.00001));
      expect(r.ergVia, 'SigmaUSD oracle');
      expect(r.ergStale, isFalse, reason: 'a weeks-old AVL feed must not flag a current ERG rate');
    });

    test('when every ERG source is stale, the freshest is shown as stale with its age', () {
      final r = price(
        oracles: {OracleFeed.sigmaUsd: const OracleReading(rate: 3123969090, height: tip - 90)},
        avl: staleAvl,
      );
      expect(r.ergUsd, closeTo(0.32011, 0.00001), reason: '3 hours beats 22 days');
      expect(r.ergStale, isTrue);
      expect(r.ergStaleAge, '3 h');
      expect(r.ergVia, 'SigmaUSD oracle, 3 h old');
      final onlyAvl = price(avl: staleAvl);
      expect(onlyAvl.ergUsd, 0.288);
      expect(onlyAvl.ergVia, 'AVL oracle, 22 days old');
    });

    test('a stale SigmaUSD pool gives way to a current Dexy USD pool', () {
      final r = price(oracles: {
        OracleFeed.sigmaUsd: const OracleReading(rate: 3000000000, height: tip - 500),
        OracleFeed.dexyUsd: const OracleReading(rate: 3123845338, height: tip - 4),
      });
      expect(r.ergVia, 'Dexy USD oracle');
      expect(r.ergUsd, closeTo(0.32012, 0.00001));
      expect(r.ergStale, isFalse);
    });

    test('wrapped majors from a stopped AVL oracle show its age and stay out of totals', () {
      final r = price(oracles: {OracleFeed.sigmaUsd: sigmaUsd}, avl: staleAvl);
      final btc = r[rsBtc]!;
      expect(btc.usd, 80000);
      expect(btc.via, 'AVL oracle, 22 days old');
      expect(btc.staleAge, '22 days');
      expect(btc.countsInTotal, isFalse, reason: 'a weeks-old price never counts');
      final v = holdingsValue(ergNano: 0, tokens: [(id: rsBtc, amount: 100000000, decimals: 8)], result: r);
      expect(v.usd, 0);
      expect(v.excluded, 1);
    });

    test('gold comes from the fresher of the Dexy gold oracle and the AVL oracle', () {
      // Dexy gold current, AVL stopped: Dexy, converted per milligram.
      final dexy = price(
        oracles: {OracleFeed.sigmaUsd: sigmaUsd, OracleFeed.dexyGold: const OracleReading(rate: goldPerKg, height: tip - 7)},
        avl: staleAvl,
      );
      final gold = dexy[dexyGoldTokenId]!;
      expect(gold.via, 'Dexy gold oracle');
      expect(gold.usd, closeTo(goldPerKg / 1e6 / 1e9 * 0.3201, 0.0001));
      expect(gold.countsInTotal, isTrue);

      // Both current, AVL fresher: the AVL ounce price per milligram.
      final freshAvl = OracleSnapshot(epoch: 1, poolHeight: tip - 2, operators: 4, usd: {'XAU_USD': 4000});
      final avlWins = price(
        oracles: {OracleFeed.sigmaUsd: sigmaUsd, OracleFeed.dexyGold: const OracleReading(rate: goldPerKg, height: tip - 30)},
        avl: freshAvl,
      );
      expect(avlWins[dexyGoldTokenId]!.via, 'AVL oracle');
      expect(avlWins[dexyGoldTokenId]!.usd, closeTo(4000 / mgPerTroyOunce, 1e-9));

      // Both stopped: the younger, with its age, out of totals.
      final stale = price(
        oracles: {OracleFeed.sigmaUsd: sigmaUsd, OracleFeed.dexyGold: const OracleReading(rate: goldPerKg, height: tip - 720)},
        avl: staleAvl,
      );
      expect(stale[dexyGoldTokenId]!.via, 'Dexy gold oracle, 24 h old');
      expect(stale[dexyGoldTokenId]!.countsInTotal, isFalse);
    });

    test('ages are told from the boxes seen even before the node height is known', () {
      final r = priceTokens(PricingInputs(
        oracles: {
          OracleFeed.sigmaUsd: const OracleReading(rate: 3000000000, height: 1000000 - 400),
          OracleFeed.dexyUsd: const OracleReading(rate: 3123845338, height: 1000000),
        },
        decimalsOf: decimals,
      ));
      expect(r.ergVia, 'Dexy USD oracle', reason: 'the SigmaUSD box is 400 blocks behind another box');
    });
  });
}

// A wallet row's worth is ERG plus its tokens
void _rowValueTests() {
  test('token value is counted, not just the ERG', () {
    final r = priceTokens(PricingInputs(
      oracle: OracleSnapshot(epoch: 1, poolHeight: 1, operators: 3, usd: {'ERG_USD': 0.25, 'BTC_USD': 80000}),
      decimalsOf: decimals,
    ));
    // 100 ERG at $0.25 is $25; 0.000125 BTC is $10 on top.
    final v = holdingsValue(
      ergNano: 100 * 1000000000,
      tokens: [(id: rsBtc, amount: 12500, decimals: 8)],
      result: r,
    );
    expect(v.usd, closeTo(35, 1e-9));
  });

  test('a wallet holding only unpriced tokens still reports its ERG', () {
    final r = priceTokens(PricingInputs(
      oracle: OracleSnapshot(epoch: 1, poolHeight: 1, operators: 3, usd: {'ERG_USD': 0.25}),
      decimalsOf: (_) => 0,
    ));
    final v = holdingsValue(
      ergNano: 4 * 1000000000,
      tokens: [(id: 'unknown-token', amount: 70000, decimals: 0)],
      result: r,
    );
    expect(v.usd, closeTo(1, 1e-9));
    expect(v.unpriced, 1);
  });
}
