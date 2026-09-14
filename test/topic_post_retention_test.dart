import 'package:discourse_native/src/shell/topic_post_retention.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ordinary replies share the bounded cache with at most three large posts',
    () {
      final retention = TopicPostRetention();
      addTearDown(retention.dispose);
      for (var id = 0; id < 21; id++) {
        retention.retain(id, 1000);
      }
      for (var id = 21; id < 25; id++) {
        retention.retain(id, 20000, large: true);
      }
      expect(retention.contains(0), isTrue);
      expect(retention.contains(21), isFalse);
      expect(retention.contains(24), isTrue);
      retention.touch(0);
      retention.retain(25, 1000);
      expect(retention.contains(0), isTrue);
      expect(retention.contains(1), isFalse);
    },
  );

  test(
    'edits transfer posts between size limits without losing accounting',
    () {
      final retention = TopicPostRetention(
        maxLargePosts: 1,
        maxCharacters: 30000,
      );
      addTearDown(retention.dispose);
      retention.retain('first', 1000);
      retention.retain('second', 15000, large: true);
      retention.retain('first', 15000, large: true);
      expect(retention.contains('second'), isFalse);
      retention.retain('first', 1000);
      retention.retain('third', 15000, large: true);
      expect(retention.contains('first'), isTrue);
      expect(retention.contains('third'), isTrue);
      retention.release('third');
      retention.retain('fourth', 29000, large: true);
      expect(retention.contains('first'), isTrue);
      retention.clear();
      retention.retain('fifth', 30000, large: true);
      expect(retention.contains('fifth'), isTrue);
    },
  );

  test('evicts the least recently viewed long post at the row limit', () {
    final retention = TopicPostRetention(maxPosts: 2);
    addTearDown(retention.dispose);
    retention.retain('first', 15000);
    retention.retain('second', 89000);
    retention.touch('first');
    retention.retain('third', 20000);
    expect(retention.contains('first'), isTrue);
    expect(retention.contains('second'), isFalse);
    expect(retention.contains('third'), isTrue);
  });

  test('also bounds total HTML and accounts for edits and released rows', () {
    final retention = TopicPostRetention(maxCharacters: 100000);
    addTearDown(retention.dispose);
    retention.retain('first', 15000);
    retention.retain('second', 89000);
    expect(retention.contains('first'), isFalse);
    retention.retain('second', 20000);
    retention.retain('third', 75000);
    expect(retention.contains('second'), isTrue);
    retention.release('third');
    retention.retain('fourth', 80000);
    expect(retention.contains('second'), isTrue);
    retention.retain('fourth', 100001);
    expect(retention.contains('fourth'), isFalse);
    expect(retention.contains('second'), isTrue);
    retention.retain('second', 0);
    expect(retention.contains('second'), isFalse);
  });

  test('reset clears owners and does not reserve budget for another topic', () {
    final retention = TopicPostRetention(maxCharacters: 100000);
    addTearDown(retention.dispose);
    retention.retain('old', 90000);
    retention.clear();
    retention.release('old');
    retention.retain('new', 90000);
    expect(retention.contains('old'), isFalse);
    expect(retention.contains('new'), isTrue);
  });

  testWidgets('eviction notifies keep-alive owners after layout', (
    tester,
  ) async {
    final retention = TopicPostRetention(maxPosts: 1);
    addTearDown(retention.dispose);
    retention.retain('first', 15000);
    var notifications = 0;
    retention.addListener(() => notifications++);
    await tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          retention.retain('second', 89000);
          expect(notifications, 0);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(notifications, 1);
    expect(retention.contains('first'), isFalse);
    expect(retention.contains('second'), isTrue);
  });
}
