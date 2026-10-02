import 'package:discourse_native/src/shell/topic_card_taxonomy_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double measure(String text) => text.characters.length * 10.0;
  TopicCardTaxonomyLayout layout(
    double width, {
    List<String> categories = const ['Parent', 'Category'],
    List<String> tags = const ['alpha', 'beta', 'gamma'],
  }) => TopicCardTaxonomyLayout.calculate(
    width: width,
    countsWidth: 100,
    categories: categories,
    tags: tags,
    measure: measure,
  );

  test('full path and every tag fit when there is room', () {
    final result = layout(500);
    expect(result.abridged, isFalse);
    expect(result.leaf, 'Category');
    expect(result.visibleTags, 3);
    expect(result.stub, isNull);
    expect(result.remainingTags, 0);
  });

  test('path gives way at 55 percent, before tags are shortened', () {
    expect(layout(437).abridged, isFalse);
    expect(layout(436).abridged, isTrue);
  });

  test(
    'whole tags precede an end-clipped stub and an exact remaining count',
    () {
      final result = layout(350);
      expect(result.abridged, isTrue);
      expect(result.leaf, 'Category');
      expect(result.visibleTags, 1);
      expect(result.stub, '#b…');
      expect(result.remainingTags, 1);
    },
  );

  test('a stub needs at least 30px after reserving the overflow count', () {
    // The measured +N is 20px in this font, exceeding the 16px minimum.
    expect(layout(346).stub, '#b…');
    final result = layout(345);
    expect(result.stub, isNull);
    expect(result.visibleTags, 1);
    expect(result.remainingTags, 2);
  });

  test('private category artwork reduces the space available to tags', () {
    final result = TopicCardTaxonomyLayout.calculate(
      width: 330,
      countsWidth: 100,
      categories: ['Parent', 'HubSpot'],
      categoryMarkWidths: [9, 26],
      tags: ['in-progress'],
      measure: measure,
    );
    expect(result.leaf, 'HubSpot');
    expect(result.stub, '#in-pr…');
    expect(result.remainingTags, 0);
  });

  test('multi-digit overflow reserves its full rendered width', () {
    final result = layout(
      290,
      categories: ['Category'],
      tags: List.generate(12, (i) => 'long-tag-number-$i'),
    );
    expect(result.visibleTags, 0);
    expect(result.stub, '#lon…');
    expect(result.remainingTags, 11);
  });

  test('category clipping preserves its distinguishing suffix', () {
    final result = layout(
      350,
      categories: ['Parent', 'translations-equipment'],
    );
    expect(result.leaf, 'tran…ment');
    expect(result.abridged, isTrue);
  });

  test('category can use at least 82px but never exceeds remaining space', () {
    expect(
      layout(290, categories: ['translations-equipment']).leaf,
      'tran…ment',
    );
    expect(layout(170, categories: ['translations-equipment']).leaf, 't…t');
  });

  test('clipping preserves emoji and combining graphemes', () {
    final result = layout(230, categories: ['Café👩🏽‍💻👩🏽‍💻equipment']);
    expect(result.leaf, contains('…'));
    expect(result.leaf, isNot(contains('�')));
    expect(result.leaf, endsWith('ent'));
  });

  test('empty taxonomy and extremely small widths are bounded', () {
    for (final width in [0.0, 20.0, 100.0]) {
      final result = layout(width);
      expect(result.visibleTags, 0);
      expect(result.remainingTags, 3);
      expect(result.stub, isNull);
    }
    expect(layout(500, categories: [], tags: []).remainingTags, 0);
  });
}
