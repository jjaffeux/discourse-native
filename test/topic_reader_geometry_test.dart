import 'package:discourse_native/src/shell/topic_post_sliver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final hasHeader in [false, true]) {
    test(
      'post and separator keys share one mapping with header=$hasHeader',
      () {
        final window = TopicPostWindow([41, 42, 43], hasHeader: hasHeader);
        final first = hasHeader ? 2 : 0;
        expect(window.childIndexForKey(const ValueKey(41)), first);
        expect(window.childIndexForKey(const ValueKey(42)), first + 2);
        expect(window.childIndexForKey(const ValueKey(43)), first + 4);
        expect(window.childIndexForKey(const ValueKey(99)), isNull);
        expect(window.childIndexForKey(const ValueKey('unknown')), isNull);
        expect(
          window.childIndexForKey(const ValueKey(('topic-post-separator', 41))),
          hasHeader ? 1 : null,
        );
        expect(
          window.childIndexForKey(const ValueKey(('topic-post-separator', 42))),
          first + 1,
        );
        expect(
          window.childIndexForKey(
            const ValueKey(('topic-trailing-separator', 0)),
          ),
          first + 5,
        );
        expect(window.postIndexesInRange((0, first + 6)), [0, 1, 2]);
        expect(window.postIndexesInRange((0, first + 6), reverse: true), [
          2,
          1,
          0,
        ]);
        expect(window.postIndexesInRange(null), isEmpty);
      },
    );
  }

  test('separator identity follows its next post through a prepend', () {
    final before = TopicPostWindow([41, 42], hasHeader: true);
    final after = TopicPostWindow([39, 40, 41, 42], hasHeader: false);
    final separator = before.separatorKeyAfterItem(0);
    expect(separator, const ValueKey(('topic-post-separator', 41)));
    expect(after.separatorKeyAfterItem(1), separator);
    expect(before.childIndexForKey(separator), 1);
    expect(after.childIndexForKey(separator), 3);
    expect(before.childIndexForKey(const ValueKey(41)), 2);
    expect(after.childIndexForKey(const ValueKey(41)), 4);
    expect(after.postIndexesInRange((3, 5)), [2]);
  });

  test('loading placeholders do not become visible post anchors', () {
    final window = TopicPostWindow([61, 62], hasHeader: true);
    expect(window.postIndexesInRange((0, 1)), isEmpty);
    expect(window.postIndexesInRange((5, 6)), isEmpty);
    expect(window.postIndexesInRange((1, 3)), [0]);
    expect(
      window.separatorKeyAfterItem(2),
      const ValueKey(('topic-trailing-separator', 0)),
    );
  });
}
