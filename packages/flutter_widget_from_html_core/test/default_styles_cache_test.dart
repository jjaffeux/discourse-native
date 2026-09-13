import 'package:csslib/visitor.dart' as css;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/src/internal/default_styles_cache.dart';

void main() {
  test('reuses parsing but isolates mutable declarations for each element', () {
    final cache = DefaultStylesCache();
    final first = cache.parse('display: block; margin: 1em 0');
    final second = cache.parse('display: block; margin: 1em 0');
    expect(second.first.span, same(first.first.span));
    expect(second.first, isNot(same(first.first)));
    final firstMargin = first.last.expression! as css.Expressions;
    final secondMargin = second.last.expression! as css.Expressions;
    expect(secondMargin, isNot(same(firstMargin)));
    final firstDisplay = (first.first.expression! as css.Expressions)
        .expressions
        .first as css.LiteralTerm;
    (firstDisplay.value as css.Identifier).name = 'none';
    final firstDartStyle = first.last.dartStyle! as css.MarginExpression;
    firstDartStyle.priority = 99;
    (firstMargin.expressions.first as css.LiteralTerm).value = 99;
    firstMargin.expressions.clear();
    final thirdMargin = cache
        .parse('display: block; margin: 1em 0')
        .last
        .expression! as css.Expressions;
    expect(thirdMargin.expressions, hasLength(2));
    expect((thirdMargin.expressions.first as css.LiteralTerm).value, 1);
    expect((secondMargin.expressions.first as css.LiteralTerm).value, 1);
    final secondDisplay = (second.first.expression! as css.Expressions)
        .expressions
        .first as css.LiteralTerm;
    expect((secondDisplay.value as css.Identifier).name, 'block');
    expect((second.last.dartStyle! as css.MarginExpression).box!.top,
        firstDartStyle.box!.top);
    expect(second.last.dartStyle!.priority, isNot(99));
  });

  test('keys by full style output and retains order and importance', () {
    final cache = DefaultStylesCache();
    final first = cache.parse('color: red; color: blue !important');
    final changed = cache.parse('color: blue; color: red !important');
    expect(first.first.span, isNot(same(changed.first.span)));
    expect(first.map((d) => d.property), ['color', 'color']);
    expect(first.map((d) => d.important), [false, true]);
    final again = cache.parse('color: red; color: blue !important');
    expect(again.first.span, same(first.first.span));
    expect(again.last.important, isTrue);
  });

  test('does not share cached defaults between bodies', () {
    final first = DefaultStylesCache().parse('display: block');
    final second = DefaultStylesCache().parse('display: block');
    expect(first.first.span, isNot(same(second.first.span)));
  });

  test('bounds retained entries and ignores very large style strings', () {
    final cache = DefaultStylesCache();
    final first = cache.parse('width: 0px');
    for (var i = 1; i < 64; i++) {
      cache.parse('width: ${i}px');
    }
    final overflow = cache.parse('width: 64px');
    expect(cache.parse('width: 0px').first.span, same(first.first.span));
    expect(cache.parse('width: 64px').first.span,
        isNot(same(overflow.first.span)));
    final longStyle = 'width: 1px;/*${'x' * 4096}*/';
    final largeCache = DefaultStylesCache();
    final large = largeCache.parse(longStyle);
    expect(
        largeCache.parse(longStyle).first.span, isNot(same(large.first.span)));
  });

  test('keeps complex expressions and legacy declarations on parser path', () {
    final cache = DefaultStylesCache();
    for (final style in [
      'width: calc(100% - 1em)',
      'color: rgb(10, 20, 30)',
      '*width: 3px',
      'font-family: serif, monospace',
    ]) {
      final first = cache.parse(style);
      final second = cache.parse(style);
      expect(first, isNotEmpty, reason: style);
      expect(second.first.span, isNot(same(first.first.span)), reason: style);
    }
  });
}
