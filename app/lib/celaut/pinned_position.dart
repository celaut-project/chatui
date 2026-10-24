/// Which pinned message of a chat is anchored at the top (`docs/celaut/chat.md`, section
/// 5.3). A pinned message anchors only the conversation that comes after it: it is the LAST
/// pinned message that lies above the visible part of the list. When the user scrolls up
/// until the top of that message is visible again, it stops being pinned, and the pinned
/// message before it takes over.
///
/// The list builds only the messages near the screen. [firstBuilt] is the index of the first
/// message that the list has built. A pinned message before it is above the screen. For a
/// built message, [topOf] gives the distance from the top edge of the visible part to the
/// top of the message: below zero, the top of the message is above the visible part.
/// [topOf] can give null for a message that has no position yet.
///
/// A pinned message anchors only what comes after it. So it is not anchored while it is the
/// last message ([count] is the number of messages), or while its bottom is still visible
/// ([bottomOf] gives the distance from the top edge of the visible part to the bottom of the
/// message: zero or less means the message is all above). Without [bottomOf], the top is
/// the only test.
///
/// Returns the index in the list of messages, or null if no pinned message is above.
int? pinnedIndexAbove({
  required List<int> pinned,
  required int firstBuilt,
  required int count,
  required double? Function(int index) topOf,
  double? Function(int index)? bottomOf,
}) {
  if (firstBuilt < 0) return null;
  for (var k = pinned.length - 1; k >= 0; k--) {
    final index = pinned[k];
    if (index >= count - 1) continue;
    if (index < firstBuilt) return index;
    final top = topOf(index);
    if (top == null || top >= 0) continue;
    if (bottomOf != null) {
      final bottom = bottomOf(index);
      if (bottom == null || bottom > 0) continue;
    }
    return index;
  }
  return null;
}

/// The part of the chat area that a pinned message that is expanded can take. The part
/// that it takes before the user taps it is a setting (`ChatPrefs.pinnedMaxFraction`).
const double pinnedExpandedFraction = 0.6;

/// The height of the chat area: the part of the screen between the bar at the top and the
/// input at the bottom. A pinned message takes a fraction of this height, not of the screen.
double chatAreaHeight({required double screen, required double top, required double bottom}) {
  final h = screen - top - bottom;
  return h < 0 ? 0 : h;
}
