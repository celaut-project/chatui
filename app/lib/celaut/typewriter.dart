import 'package:characters/characters.dart';

/// Shows a text that grows, a few characters at a time, so it does not appear in the
/// chunks in which the service sends it. The unit is the grapheme, so an emoji or an
/// accented letter is never cut.
///
/// The speed follows the backlog: it is at least [baseRate] characters each second, and
/// it is high enough that the part that is not shown yet is shown within [maxLag].
class Typewriter {
  Typewriter({
    String initial = '',
    this.baseRate = 45,
    this.maxLag = const Duration(milliseconds: 1500),
  }) {
    _target = initial;
    _ends = _graphemeEnds(initial, 0, []);
    _shown = _ends.length;
  }

  /// The least number of characters shown each second.
  final double baseRate;

  /// The time after which the text that has arrived is all shown.
  final Duration maxLag;

  String _target = '';

  /// The end offset (in UTF-16 units) of each grapheme of [_target]. A frame reads only
  /// this list, so its cost does not depend on the length of the text; only a new text
  /// splits the part after its first change.
  List<int> _ends = [];
  int _shown = 0;
  double _credit = 0;
  String? _cache;

  /// Adds to [out] the end offsets of the graphemes of [text] from [start], and returns it.
  static List<int> _graphemeEnds(String text, int start, List<int> out) {
    var at = start;
    for (final g in (start == 0 ? text : text.substring(start)).characters) {
      at += g.length;
      out.add(at);
    }
    return out;
  }

  /// The text that shows now.
  String get text =>
      _cache ??= _shown == 0 ? '' : _target.substring(0, _ends[_shown - 1]);

  /// Characters that have arrived and are not shown yet.
  int get backlog => _ends.length - _shown;

  /// All the text that has arrived is shown.
  bool get done => backlog == 0;

  /// The text so far. A text that does not continue the old one (a rewrite) shows at once
  /// up to the common start, then grows from there.
  void setTarget(String target) {
    if (target == _target) return;
    if (target.startsWith(_target)) {
      // The common case: the text grows. The last grapheme can take the new characters
      // (an emoji joiner, an accent), so the split starts one grapheme before the end.
      final keep = _ends.isEmpty ? 0 : _ends.length - 1;
      final from = keep == 0 ? 0 : _ends[keep - 1];
      final shownAt = _shown == 0 ? 0 : _ends[_shown - 1];
      if (_ends.isNotEmpty) _ends.removeLast();
      _graphemeEnds(target, from, _ends);
      _target = target;
      // The last grapheme, if it was all shown, stays shown unless the new characters
      // joined it.
      if (_shown > keep) _shown = _ends.length > keep && _ends[keep] == shownAt ? keep + 1 : keep;
    } else {
      var common = 0;
      final max = _target.length < target.length ? _target.length : target.length;
      while (common < max && _target.codeUnitAt(common) == target.codeUnitAt(common)) {
        common++;
      }
      _target = target;
      _ends = _graphemeEnds(target, 0, []);
      var whole = 0;
      while (whole < _ends.length && _ends[whole] <= common) {
        whole++;
      }
      if (_shown > whole) _shown = whole;
    }
    _cache = null;
  }

  /// Show all that has arrived.
  void finish() {
    _shown = _ends.length;
    _credit = 0;
    _cache = null;
  }

  /// Let [dt] of time pass. Returns how many characters it showed.
  int tick(Duration dt) {
    if (done) {
      _credit = 0;
      return 0;
    }
    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    final catchUp = backlog / (maxLag.inMicroseconds / Duration.microsecondsPerSecond);
    _credit += (catchUp > baseRate ? catchUp : baseRate) * seconds;
    final n = _credit.floor().clamp(0, backlog);
    _credit -= n;
    if (n > 0) {
      _shown += n;
      _cache = null;
    }
    return n;
  }
}

/// Decides when a small vibration goes with the text that appears: at most one each
/// [minGap], and only after [every] new characters.
class HapticPacer {
  HapticPacer({this.every = 4, this.minGap = const Duration(milliseconds: 80)});

  final int every;
  final Duration minGap;
  int _count = 0;
  Duration? _last;

  /// [chars] new characters showed at [now]. True if a vibration is due.
  bool feed(int chars, Duration now) {
    _count += chars;
    if (_count < every) return false;
    final last = _last;
    if (last != null && now - last < minGap) return false;
    _count = 0;
    _last = now;
    return true;
  }
}
