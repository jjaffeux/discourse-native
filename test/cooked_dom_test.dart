import 'package:discourse_native/src/shell/cooked_dom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
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

    int cost(int count) {
      final root = html.parseFragment(rows(count)).children.single;
      var best = -1;
      for (var run = 0; run < 3; run += 1) {
        final elapsed = Stopwatch()..start();
        descendantWhere(root, (element) => element.localName == 'nothing');
        elapsed.stop();
        if (best < 0 || elapsed.elapsedMicroseconds < best) {
          best = elapsed.elapsedMicroseconds;
        }
      }
      return best;
    }

    final small = cost(400);
    final large = cost(3200);

    expect(
      large,
      lessThan(small * 25),
      reason: 'eight times the rows took ${large / small} times as long',
    );
  });
}
