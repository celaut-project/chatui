import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'oracle_feeds.dart';

/// How far back an ERG price chart reaches.
enum PriceWindow {
  day('24h', Duration(hours: 24)),
  week('7d', Duration(days: 7)),
  month('30d', Duration(days: 30));

  const PriceWindow(this.label, this.span);
  final String label;
  final Duration span;

  /// Blocks in this window at Ergo's two-minute target.
  int get blocks => span.inMinutes ~/ minutesPerBlock;
}

/// Ergo's target block interval. Node history is indexed by height, so
/// heights become times at this rate.
const minutesPerBlock = 2;

class PricePoint {
  const PricePoint(this.at, this.price);
  final DateTime at;

  /// USD per ERG.
  final double price;
}

/// ERG's price over a window, from the source the user picked in Display
/// settings, or why it could not be read.
class ErgPriceHistory {
  const ErgPriceHistory({
    required this.window,
    required this.points,
    required this.sourceLabel,
    required this.currency,
    this.change24hPct,
    this.approximateTimes = false,
    this.stale = false,
  }) : unavailableReason = null;

  const ErgPriceHistory.unavailable({
    required this.window,
    required this.sourceLabel,
    required this.currency,
    required String reason,
  })  : points = const [],
        change24hPct = null,
        approximateTimes = false,
        stale = false,
        unavailableReason = reason;

  final PriceWindow window;

  /// Oldest first.
  final List<PricePoint> points;

  /// Percent change over the last 24 hours, when the history reaches back
  /// that far.
  final double? change24hPct;
  final String sourceLabel;

  /// Lower-case display currency code, e.g. `usd`.
  final String currency;

  /// True when times were derived from block heights at two minutes a
  /// block rather than read from the source.
  final bool approximateTimes;

  /// The newest point is older than the source normally publishes (the
  /// oracle stopped posting, for one).
  final bool stale;

  /// Why there is no history, or null when there is.
  final String? unavailableReason;

  bool get available => unavailableReason == null;
}

/// A price at a block height, in USD per ERG.
typedef HeightPrice = (int height, double usd);

int? _height(Map<String, dynamic> box) =>
    (box['inclusionHeight'] as num?)?.toInt() ?? (box['creationHeight'] as num?)?.toInt();

/// ERG/USD at each historical box of a single-rate oracle pool quoting
/// nanoERG per dollar (the SigmaUSD pool): R4 at the box's height. Boxes
/// without a positive `Long` in R4 are skipped.
List<HeightPrice> oracleRateHistory(List<Map<String, dynamic>> boxes) {
  final out = <HeightPrice>[
    for (final b in boxes)
      if (readingFromBox(b) case final r?) (r.height, usdPerErg(r)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// Heights as times, counting back from [tip] at [now].
List<PricePoint> pointsFromHeights(List<HeightPrice> prices, {required int tip, required DateTime now, double scale = 1}) => [
      for (final (h, usd) in prices)
        PricePoint(now.subtract(Duration(minutes: (tip - h) * minutesPerBlock)), usd * scale),
    ];

/// The price in force at [at]: the last point at or before it. Null when
/// the history does not reach back that far.
double? priceAt(List<PricePoint> points, DateTime at) {
  PricePoint? last;
  for (final p in points) {
    if (p.at.isAfter(at)) break;
    last = p;
  }
  return last?.price;
}

/// Percent change from the price in force [span] before [now] to the newest.
double? changeOver(List<PricePoint> points, Duration span, DateTime now) {
  if (points.isEmpty) return null;
  final then = priceAt(points, now.subtract(span));
  if (then == null || then <= 0) return null;
  return (points.last.price - then) / then * 100;
}

/// Keeps the points inside the window plus the one in force at its start,
/// moved to the start so a chart begins at the window's left edge.
List<PricePoint> clipToWindow(List<PricePoint> points, Duration span, DateTime now) {
  final start = now.subtract(span);
  final before = priceAt(points, start);
  return [
    if (before != null) PricePoint(start, before),
    for (final p in points)
      if (p.at.isAfter(start)) p,
  ];
}

/// A page of boxes that ever held [tokenId], newest first.
typedef BoxPage = Future<List<Map<String, dynamic>>> Function(String node, String tokenId, int offset, int limit);

class HistoryUnavailable implements Exception {
  const HistoryUnavailable(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

/// The node's history of [tokenId]'s boxes back past [windowBlocks] before
/// [tip], in a bounded number of requests.
///
/// The node lists boxes newest first. The first page usually covers a quiet
/// pool's whole window; when it does not, the box rate seen on it places
/// [samples] small pages evenly across the rest of the window, plus one
/// further back for the price in force at its start. A busy feed (oracle
/// operators post every few blocks) costs at most `samples + 2` requests
/// whatever the window.
Future<List<Map<String, dynamic>>> sampleHistory({
  required BoxPage page,
  required String node,
  required String tokenId,
  required int tip,
  required int windowBlocks,
  int firstPage = 100,
  int samplePage = 16,
  int samples = 12,
}) async {
  final first = await page(node, tokenId, 0, firstPage);
  final all = [...first];
  final heights = first.map(_height).whereType<int>().toList();
  if (heights.isEmpty || first.length < firstPage) return all;
  final start = tip - windowBlocks;
  final newest = heights.reduce(math.max);
  final oldest = heights.reduce(math.min);
  if (oldest <= start) return all;
  // Boxes per block on the first page, then where the window start falls.
  final rate = first.length / math.max(1, newest - oldest + 1);
  final toStart = ((newest - start) * rate).ceil();
  final stride = math.max(samplePage, ((toStart - firstPage) / samples).ceil());
  for (var k = 0; k <= samples; k++) {
    final got = await page(node, tokenId, firstPage + stride * k, samplePage);
    all.addAll(got);
    final h = got.map(_height).whereType<int>();
    if (got.length < samplePage || (h.isNotEmpty && h.reduce(math.min) <= start)) break;
  }
  // New boxes shift the node's pages while sampling; count each box once.
  final seen = <Object?>{};
  return [
    for (final b in all)
      if (seen.add(b['boxId'] ?? identityHashCode(b))) b,
  ];
}

/// The real node request behind [BoxPage]: `/blockchain/box/byTokenId`,
/// which needs the node's extra index.
Future<List<Map<String, dynamic>>> fetchBoxPage(
  String node,
  String tokenId,
  int offset,
  int limit, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final base = node.replaceAll(RegExp(r'/$'), '');
  final res = await c
      .get(Uri.parse('$base/blockchain/box/byTokenId/$tokenId?offset=$offset&limit=$limit'))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) {
    throw const HistoryUnavailable('This node cannot serve price history: it needs the extra index.');
  }
  final body = jsonDecode(res.body);
  final items = body is List ? body : (body as Map)['items'] as List? ?? const [];
  return items.map((e) => (e as Map).cast<String, dynamic>()).toList();
}
