import 'package:discourse_native/src/shell/cooked_dom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'support/scaling_benchmark.dart';

void main() {
  test('finds direct child elements without crossing a nested boundary', () {
    final root = html
        .parseFragment(
          '<div>text<a id="1"></a><span><a id="2"></a></span><a id="3"></a></div>',
        )
        .children
        .single;

    expect(childElements(root).map((e) => e.localName), ['a', 'span', 'a']);
    expect(childWhere(root, (e) => e.localName == 'a')?.id, '1');
    expect(childrenWhere(root, (e) => e.localName == 'a').map((e) => e.id), [
      '1',
      '3',
    ]);
    expect(childWhere(root, (e) => e.localName == 'nothing'), isNull);
    expect(childrenWhere(root, (e) => e.localName == 'nothing'), isEmpty);
  });

  test('finds descendants in document order, skipping non-elements', () {
    final root = html
        .parseFragment(
          '<div>text<a id="1"></a><span>x<a id="2"></a></span><a id="3"></a></div>',
        )
        .children
        .single;

    expect(
      descendantWhere(root, (e) => e.localName == 'a')?.id,
      '1',
      reason: 'the first in document order, not the first child',
    );
    expect(descendantsWhere(root, (e) => e.localName == 'a').map((e) => e.id), [
      '1',
      '2',
      '3',
    ]);
    expect(descendantWhere(root, (e) => e.localName == 'nothing'), isNull);
    expect(descendantsWhere(root, (e) => e.localName == 'nothing'), isEmpty);
  });

  test('a wide element costs its width, not its square', () {
    // `children` is a `FilteredElementList` that rebuilds itself out of `nodes`
    // on every `length` and every `[]`, so walking it by index allocates a list
    // per child and is quadratic in their number. A GitHub onebox with a few
    // hundred rows in it was enough to feel, on the frame that draws the post.
    String rows(int count) {
      final cells = List.generate(
        count,
        (index) => '<div class="row"><span>$index</span></div>',
      ).join();
      return '<article>$cells</article>';
    }

    final smallRoot = html.parseFragment(rows(400)).children.single;
    final largeRoot = html.parseFragment(rows(3200)).children.single;
    final (:small, :large) = measureScaling(
      () => descendantWhere(smallRoot, (e) => e.localName == 'nothing') == null
          ? 0
          : 1,
      () => descendantWhere(largeRoot, (e) => e.localName == 'nothing') == null
          ? 0
          : 1,
    );

    // An 8x input takes ~8x for a linear scan and ~64x for a quadratic one.
    expect(
      large,
      lessThan(small * 25),
      reason: 'eight times the rows took ${large / small} times as long',
    );
  });

  test('a direct-child scan costs its width, not its square', () {
    String siblings(int count) =>
        '<article>${List.generate(count, (index) => '<span>$index</span>').join()}</article>';

    final smallRoot = html.parseFragment(siblings(400)).children.single;
    final largeRoot = html.parseFragment(siblings(3200)).children.single;
    final (:small, :large) = measureScaling(
      () => childrenWhere(smallRoot, (e) => e.localName == 'nothing').length,
      () => childrenWhere(largeRoot, (e) => e.localName == 'nothing').length,
    );

    expect(
      large,
      lessThan(small * 25),
      reason: 'eight times the siblings took ${large / small} times as long',
    );
  });
}
