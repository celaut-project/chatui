import 'package:argus_wallet/celaut/pinned_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int? find(
    List<int> pinned,
    int firstBuilt,
    Map<int, double> tops, {
    int count = 20,
    Map<int, double>? bottoms,
  }) =>
      pinnedIndexAbove(
        pinned: pinned,
        firstBuilt: firstBuilt,
        count: count,
        topOf: (i) => tops[i],
        bottomOf: bottoms == null ? null : (i) => bottoms[i],
      );

  test('no pinned message: nothing is pinned', () {
    expect(find([], 0, {}), isNull);
  });

  test('nothing built yet: nothing is pinned', () {
    expect(find([2], -1, {}), isNull);
  });

  test('a pinned message before the first built one is above the screen', () {
    expect(find([2], 5, {}), 2);
  });

  test('the last pinned message above wins', () {
    expect(find([2, 4], 6, {}), 4);
  });

  test('a built message above the visible part is pinned', () {
    expect(find([5], 3, {5: -10}), 5);
  });

  test('a built message whose top is visible is not pinned', () {
    expect(find([5], 3, {5: 0}), isNull);
    expect(find([5], 3, {5: 120}), isNull);
  });

  test('the previous one takes over when the user scrolls above the last', () {
    // The last pinned message is on the screen: the first one is above.
    expect(find([2, 5], 3, {5: 40}), 2);
    // Both are on the screen: none is pinned.
    expect(find([4, 5], 3, {4: 10, 5: 40}), isNull);
  });

  test('a pinned message below the built ones is not pinned', () {
    expect(find([9], 3, {}), isNull);
  });

  test('a built message with no position yet is skipped', () {
    expect(find([2, 5], 3, {}), 2);
  });

  test('the last message is never anchored', () {
    expect(find([5], 3, {5: -10}, count: 6), isNull);
    expect(find([2, 5], 3, {5: -10}, count: 6), 2);
    expect(find([5], 7, {}, count: 6), isNull);
  });

  test('a message whose bottom is visible is not anchored yet', () {
    expect(find([5], 3, {5: -10}, bottoms: {5: 80}), isNull);
    expect(find([5], 3, {5: -100}, bottoms: {5: 0}), 5);
    expect(find([5], 3, {5: -100}, bottoms: {5: -20}), 5);
    // The bottom is not known: the message is not anchored.
    expect(find([5], 3, {5: -100}, bottoms: {}), isNull);
  });

  test('the one before takes over while the last one still shows its bottom', () {
    expect(find([2, 5], 3, {5: -10}, bottoms: {5: 80}), 2);
  });

  test('the chat area is the screen less the bars', () {
    expect(chatAreaHeight(screen: 800, top: 100, bottom: 80), 620);
    expect(chatAreaHeight(screen: 100, top: 90, bottom: 80), 0);
    expect(pinnedExpandedFraction, greaterThan(0.5));
  });
}
