import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The mockup's category/tag budget, independent of the interactive links.
@immutable
class TopicCardTaxonomyLayout {
  const TopicCardTaxonomyLayout({
    required this.abridged,
    required this.leaf,
    required this.visibleTags,
    required this.stub,
    required this.remainingTags,
  });
  final bool abridged;
  final String leaf;
  final int visibleTags;
  final String? stub;
  final int remainingTags;

  static TopicCardTaxonomyLayout calculate({
    required double width,
    required double countsWidth,
    required List<String> categories,
    required List<String> tags,
    required double Function(String) measure,
    List<double>? categoryMarkWidths,
  }) {
    assert(
      categoryMarkWidths == null ||
          categoryMarkWidths.length == categories.length,
    );
    const gap = 5.0;
    // Keep the mockup's minimum, but allow for scaled text and multi-digit +N.
    final plus = math.max(16.0, measure('+${tags.length}'));
    final marks = categoryMarkWidths ?? List.filled(categories.length, 9.0);
    double pathWidth(List<String> path, List<double> marks, bool lead) {
      if (path.isEmpty) return 0;
      return path.fold(0.0, (sum, name) => sum + measure(name)) +
          marks.fold(0.0, (sum, width) => sum + width) +
          7 * (path.length - 1 + (lead ? 1 : 0)) +
          (lead ? measure('…') : 0) +
          gap * (1 + 3 * (path.length - 1) + (lead ? 2 : 0));
    }

    final runWidth = math.max(0.0, width - countsWidth);
    final budget = runWidth * .55;
    final abridged =
        categories.length > 1 && pathWidth(categories, marks, false) > budget;
    final path = abridged
        ? categories.sublist(categories.length - 1)
        : categories;
    final leaf = path.isEmpty ? '' : path.last;
    final chrome = path.isEmpty
        ? 0.0
        : pathWidth(path, abridged ? [marks.last] : marks, abridged) -
              measure(leaf);
    final clipTo = math.max(
      0.0,
      math.min(
        math.max(82.0, budget - chrome),
        runWidth - chrome - (tags.isEmpty ? 0 : gap + plus),
      ),
    );
    final clipped = _clip(leaf, clipTo, measure, middle: true);
    final pathRoom = path.isEmpty ? 0.0 : chrome + measure(clipped) + gap;
    final available = runWidth - pathRoom;
    double tagsWidth(int n) =>
        tags.take(n).fold(0.0, (sum, tag) => sum + measure('#$tag')) +
        math.max(0, n - 1) * gap;
    var fits = 0;
    if (tagsWidth(tags.length) <= available) {
      fits = tags.length;
    } else {
      var used = 0.0;
      while (fits < tags.length) {
        final next = used + measure('#${tags[fits]}') + (fits > 0 ? gap : 0);
        if (next + gap + plus > available) break;
        used = next;
        fits++;
      }
    }
    final spare =
        runWidth -
        pathRoom -
        tagsWidth(fits) -
        (fits > 0 ? gap : 0) -
        gap -
        plus;
    final stub = tags.length > fits && spare >= 30
        ? _clip('#${tags[fits]}', spare, measure, middle: false)
        : null;
    return TopicCardTaxonomyLayout(
      abridged: abridged,
      leaf: clipped,
      visibleTags: fits,
      stub: stub,
      remainingTags: tags.length - fits - (stub == null ? 0 : 1),
    );
  }

  static String _clip(
    String text,
    double width,
    double Function(String) measure, {
    required bool middle,
  }) {
    if (measure(text) <= width) return text;
    final chars = text.characters.toList();
    var low = 1;
    var high = middle ? chars.length - 1 : chars.length;
    var best = middle ? '…' : '';
    while (low <= high) {
      final kept = (low + high) ~/ 2;
      final candidate = middle
          ? '${chars.take((kept + 1) ~/ 2).join()}…${chars.skip(chars.length - kept ~/ 2).join()}'
          : '${chars.take(kept).join()}…';
      if (measure(candidate) <= width) {
        best = candidate;
        low = kept + 1;
      } else {
        high = kept - 1;
      }
    }
    return best;
  }
}
