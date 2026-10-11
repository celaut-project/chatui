import 'oracle_feeds.dart';
import 'oracle_pool.dart';

/// The label of the only price source: on-chain oracle pools, read from the
/// user's node.
const priceSourceLabel = 'Oracle pools';

/// What [priceSourceLabel] prices, for the settings page.
const priceSourceBlurb =
    'On-chain: ERG from the SigmaUSD oracle pool (the ERG/USD oracle pool), gold from the Dexy gold oracle, '
    'wrapped majors from the AVL multi-oracle. An old price is shown with its age, never as current. '
    'Reads only your node. Other tokens have no price.';

/// DexyGold: one milligram of gold, priced from the gold oracles.
const dexyGoldTokenId = '6122f7289e7bb2df2de273e09d4b2756cda6aeb0f40438dc9d257688f45183ad';

/// Rosen-wrapped majors and the AVL oracle feed that tracks them 1:1.
const wrappedOrigins = <String, String>{
  '7a51950e5f548549ec1aa63ffdc38279505b11e7e803d01bcf8347e0123c88b0': 'BTC_USD',
  '203ef3066a912f35c488487cc2cb94bdb0d30680dab22551c7e6fdbc70dfcc8e': 'ETH_USD',
  '050322548722d36f094e341f59ed93eb22118b363eb4efe8c461a52c4d93e2c3': 'BNB_USD',
  '48132396ebd00831e603c73cf01e01f248dd1966d2cc976caf52ef76f7ac6e36': 'DOGE_USD',
  'e023c5f382b6e96fbd878f6811aac73345489032157ad5affb84aefd4956c297': 'ADA_USD',
  '581d7df25808881b2b8b9b4e03e2f637c46a94f74a69a5da36434125bacb4e08': 'FIRO_USD',
};

class TokenPrice {
  const TokenPrice({
    required this.usd,
    required this.via,
    this.countsInTotal = true,
    this.staleAge,
    this.decimals,
  });

  /// A price whose only source has stopped publishing: shown with its age
  /// on the row, never counted in totals.
  const TokenPrice.stale({required this.usd, required String source, required String age, this.decimals})
      : via = '$source, $age old',
        countsInTotal = false,
        staleAge = age;

  /// USD per whole token (decimals applied).
  final double usd;

  /// The token's decimals [usd] is per whole token at, from the one token
  /// lookup. A holding is valued by its base units at this scale
  /// ([holdingUsd]), so one recorded before its token's scale was learned,
  /// or in another wallet's older snapshot, cannot be valued at a wrong
  /// one. Null for a price whose scale nothing reported; such a holding
  /// falls back to its own decimals.
  final int? decimals;

  /// Human label of the source, e.g. "SigmaUSD oracle", "AVL oracle"; a
  /// stale price says its age here too.
  final String via;

  /// False for stale prices: shown on the row, excluded from portfolio
  /// totals.
  final bool countsInTotal;

  /// How old a stale price is ("22 days"); null when current.
  final String? staleAge;
}

class PricingInputs {
  const PricingInputs({
    this.oracle,
    this.oracles = const {},
    this.tipHeight,
    required this.decimalsOf,
  });

  /// The AVL multi-oracle: gold, ERG and the wrapped majors.
  final OracleSnapshot? oracle;

  /// The single-rate oracle pools read this refresh: SigmaUSD and Dexy USD
  /// (nanoERG per dollar), Dexy gold (nanoERG per kilogram).
  final Map<OracleFeed, OracleReading> oracles;

  /// The chain tip, for how old each reading is. Unknown means none can be
  /// judged stale.
  final int? tipHeight;

  /// A token's decimals from the one token lookup, or null when nothing
  /// knows its scale.
  final int? Function(String tokenId) decimalsOf;
}

class PricingResult {
  const PricingResult({required this.ergUsd, required this.ergVia, required this.prices, this.ergStaleAge});
  final double? ergUsd;

  /// Where the ERG rate came from; says how old it is when it is stale.
  final String? ergVia;
  final Map<String, TokenPrice> prices;

  /// How old the ERG rate is when no source for it is current ("3 h").
  final String? ergStaleAge;

  bool get ergStale => ergStaleAge != null;

  TokenPrice? operator [](String id) => prices[id];
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// One source's value for a feed, with how old it is.
class _Quote {
  const _Quote(this.usd, this.via, this.ageBlocks, {required this.fresh});
  final double usd;
  final String via;

  /// Null when the tip is unknown and age cannot be told.
  final int? ageBlocks;
  final bool fresh;
}

/// The first current quote in preference order; when none is current, the
/// youngest, to be shown as stale with its age. Null when there is none.
_Quote? _pick(List<_Quote> quotes) {
  for (final q in quotes) {
    if (q.fresh) return q;
  }
  if (quotes.isEmpty) return null;
  return quotes.reduce((a, b) => (b.ageBlocks ?? 0) < (a.ageBlocks ?? 0) ? b : a);
}

/// The whole pricing policy, pure so every branch is testable: which oracle
/// wins for each price, converted to USD.
///
/// No price is presented as current when its source has stopped: a stale
/// quote is used only when nothing current exists, says its age, and never
/// counts towards a total.
PricingResult priceTokens(PricingInputs inp) {
  // A box seen at some height proves the chain is at least that tall, so
  // ages can be told even before the node height is known.
  final tip = [
    inp.tipHeight ?? 0,
    for (final r in inp.oracles.values) r.height,
  ].reduce((a, b) => a > b ? a : b);
  final int? knownTip = tip > 0 ? tip : null;

  _Quote? fromFeed(OracleFeed feed, double Function(OracleReading) usd) {
    final r = inp.oracles[feed];
    if (r == null) return null;
    final age = knownTip == null ? null : r.ageAt(knownTip);
    return _Quote(usd(r), feed.label, age, fresh: age == null || age <= feed.staleAfterBlocks);
  }

  final avl = inp.oracle;
  final avlAge = avl == null || knownTip == null ? null : (knownTip > avl.poolHeight ? knownTip - avl.poolHeight : 0);
  final avlFresh = avl != null && !avl.isStale(knownTip);
  _Quote? fromAvl(String feed, {double scale = 1}) {
    final v = avl?[feed];
    if (v == null || v <= 0) return null;
    return _Quote(v * scale, 'AVL oracle', avlAge, fresh: avlFresh);
  }

  // The SigmaUSD pool first: it is the ERG/USD oracle pool.
  final ergPick = _pick([
    if (fromFeed(OracleFeed.sigmaUsd, usdPerErg) case final q?) q,
    if (fromFeed(OracleFeed.dexyUsd, usdPerErg) case final q?) q,
    if (fromAvl('ERG_USD') case final q?) q,
  ]);
  if (ergPick == null || ergPick.usd <= 0) {
    return const PricingResult(ergUsd: null, ergVia: null, prices: {});
  }
  final usdPerErgNow = ergPick.usd;
  String? ergStaleAge;
  var ergVia = ergPick.via;
  if (!ergPick.fresh) {
    ergStaleAge = ageText(ergPick.ageBlocks ?? 0);
    ergVia = '${ergPick.via}, $ergStaleAge old';
  }

  final prices = <String, TokenPrice>{};
  // Prices from a feed are per whole token by definition; their scale
  // still comes from the lookup, for valuing holdings at it.
  TokenPrice priced(String id, _Quote q) => q.fresh
      ? TokenPrice(usd: q.usd, via: q.via, decimals: inp.decimalsOf(id))
      : TokenPrice.stale(usd: q.usd, source: q.via, age: ageText(q.ageBlocks ?? 0), decimals: inp.decimalsOf(id));

  // DexyGold is one milligram of gold: the Dexy oracle quotes nanoERG per
  // kilogram, the AVL oracle USD per troy ounce. The fresher current one
  // wins.
  final gold = [
    if (fromFeed(OracleFeed.dexyGold, (r) => r.rate / 1e6 / 1e9 * usdPerErgNow) case final q?) q,
    if (fromAvl('XAU_USD', scale: 1 / mgPerTroyOunce) case final q?) q,
  ]..sort((a, b) => (a.ageBlocks ?? 0).compareTo(b.ageBlocks ?? 0));
  if (_pick(gold) case final q?) prices[dexyGoldTokenId] = priced(dexyGoldTokenId, q);

  // Wrapped majors: the AVL oracle, with its age when it is stale.
  for (final entry in wrappedOrigins.entries) {
    if (fromAvl(entry.value) case final q?) prices[entry.key] = priced(entry.key, q);
  }
  return PricingResult(ergUsd: usdPerErgNow, ergVia: ergVia, prices: prices, ergStaleAge: ergStaleAge);
}

/// Fiat summary of one wallet's holdings.
class HoldingsValue {
  const HoldingsValue({required this.usd, required this.priced, required this.unpriced, required this.excluded});

  /// ERG plus every counted token, in USD.
  final double usd;
  final int priced;

  /// Tokens with no price at all: no source prices them, or nothing knows
  /// their scale.
  final int unpriced;

  /// Tokens with a price that is not counted (stale).
  final int excluded;
}

HoldingsValue holdingsValue({
  required int? ergNano,
  required Iterable<({String id, int amount, int decimals})> tokens,
  required PricingResult result,
}) {
  final ergUsd = result.ergUsd;
  if (ergUsd == null) return const HoldingsValue(usd: 0, priced: 0, unpriced: 0, excluded: 0);
  var usd = (ergNano ?? 0) / 1e9 * ergUsd;
  var priced = 0;
  var unpriced = 0;
  var excluded = 0;
  for (final t in tokens) {
    final p = result[t.id];
    if (p == null) {
      unpriced++;
      continue;
    }
    if (!p.countsInTotal) {
      excluded++;
      continue;
    }
    priced++;
    usd += t.amount / _pow10(p.decimals ?? t.decimals) * p.usd;
  }
  return HoldingsValue(usd: usd, priced: priced, unpriced: unpriced, excluded: excluded);
}

/// USD value of one holding, or null when unpriced. [amount] is base
/// units; they are scaled by the price's own decimals when it has them,
/// else by the holding's [decimals].
double? holdingUsd({required int amount, required int decimals, required TokenPrice? price}) =>
    price == null ? null : amount / _pow10(price.decimals ?? decimals) * price.usd;
