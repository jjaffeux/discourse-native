import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ObservedTags extends SetBase<int> {
  _ObservedTags(this.values);
  final Set<int> values;
  static int visits = 0;
  @override
  Iterator<int> get iterator {
    visits += values.length;
    return values.iterator;
  }

  @override
  bool contains(Object? value) {
    visits++;
    return values.contains(value);
  }

  @override
  int get length => values.length;
  @override
  bool add(int value) => values.add(value);
  @override
  int? lookup(Object? value) => values.lookup(value);
  @override
  bool remove(Object? value) => values.remove(value);
  @override
  Set<int> toSet() => values.toSet();
}

void main() {
  test('bulk dismissal avoids per-topic work in warmed tag memberships', () {
    final tracking = TopicTrackingState([
      for (var id = 1; id <= 250; id++)
        TrackedTopicState(
          topicId: id,
          highestPostNumber: 5,
          lastReadPostNumber: 1,
          notificationLevel: 2,
          tagIds: _ObservedTags({1}),
        ),
    ]);
    expect(tracking.newActivityCounts.newReplies, 250);
    expect(tracking.newActivityCountsFor(tagIds: {1}).newReplies, 250);
    _ObservedTags.visits = 0;
    expect(
      tracking.applyMessage({
        'message_type': 'dismiss_new_posts',
        'payload': {
          'topic_ids': [for (var id = 1; id <= 250; id++) id],
        },
      }),
      isTrue,
    );
    expect(_ObservedTags.visits, 0);
    expect(tracking.newActivityCounts.newReplies, 0);
    expect(tracking.newActivityCountsFor(tagIds: {1}).newReplies, 0);
  });

  test('live tracking mutation and sidebar projection workload', () {
    final reports = <Map<String, Object?>>[];
    for (final size in [20, 5000]) {
      final categories = [
        for (var id = 1; id <= 10; id++)
          TopicCategory(id: id, name: '$id', color: '123456'),
      ];
      final samples = <Map<String, int>>[];
      for (var sample = 0; sample < 6; sample++) {
        final tracking = TopicTrackingState([
          for (var i = 1; i <= size; i++)
            TrackedTopicState(
              topicId: i,
              categoryId: (i - 1) % 10 + 1,
              highestPostNumber: 5,
              lastReadPostNumber: 1,
              notificationLevel: 2,
              tagIds: _ObservedTags({(i - 1) % 10 + 1}),
            ),
        ]);
        int project() {
          var sum = tracking.newActivityCounts.newReplies;
          for (var id = 1; id <= 10; id++) {
            sum += tracking
                .newActivityCountsFor(categoryId: id, categories: categories)
                .newReplies;
            sum += tracking.newActivityCountsFor(tagIds: {id}).newReplies;
          }
          sum += tracking
              .newActivityCountsFor(
                categoryId: 1,
                categories: categories,
                tagIds: {1},
              )
              .newReplies;
          return sum;
        }

        expect(project(), size * 3 + (size + 9) ~/ 10);
        _ObservedTags.visits = 0;
        var micros = 0;
        var checksum = 0;
        for (var event = 0; event < 100; event++) {
          final watch = Stopwatch()..start();
          final changed = tracking.applyMessage({
            'topic_id': 1,
            'message_type': 'notification_level_change',
            'payload': {'notification_level': event.isEven ? 1 : 2},
          });
          final count = project();
          watch.stop();
          micros += watch.elapsedMicroseconds;
          checksum += count;
          expect(changed, isTrue);
          expect(count, size * 3 + (size + 9) ~/ 10 - (event.isEven ? 4 : 0));
        }
        expect(
          _ObservedTags.visits,
          lessThan(10000),
          reason:
              'Live updates must not rebuild unrelated topic tag memberships',
        );
        if (sample > 0) {
          samples.add({
            'microseconds': micros,
            'tagVisits': _ObservedTags.visits,
            'checksum': checksum,
            'events': 100,
          });
        }
      }
      reports.add({'topics': size, 'samples': samples, 'errors': 0});
    }
    final output = Platform.environment['TRACKING_LIVE_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(jsonEncode(reports));
    // ignore: avoid_print
    print('TRACKING_LIVE ${jsonEncode(reports)}');
  });
}
