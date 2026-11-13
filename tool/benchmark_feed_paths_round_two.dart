import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/account_feed_window.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/unread_topic_feed.dart';
import 'package:flutter/foundation.dart';

void main() {
  final window = AccountFeedWindow(
    packets: [
      for (var page = 0; page < 9; page++)
        AccountFeedPacket(
          start: page * 30,
          end: (page + 1) * 30,
          items: List.generate(30, (i) => page * 30 + i),
        ),
    ],
  );
  final incoming = List.generate(30, (i) => 267 + i);
  final expected = List.generate(297, (i) => i);
  final source = TopicFeed(
    topicIds: List.generate(512, (i) => i + 1),
    loaded: true,
  );
  final projection = UnreadTopicFeed();
  final counts = NotificationTypeCounts.fromWire({
    for (var i = 1; i <= 45; i++) '$i': i,
  });
  const excluded = [
    NotificationTypeId(1),
    NotificationTypeId(3),
    NotificationTypeId(3),
    NotificationTypeId(100),
  ];

  final values = {
    'account_feed_append_with_overlap': _measure(
      2400,
      (_) => window.withPage(
        incoming: incoming,
        start: 270,
        end: 300,
        prepend: false,
        identity: (id) => id,
        merge: (_, id) => id,
        estimate: (_) => 64,
      ),
      (_, actual) =>
          actual.start == 0 &&
          actual.end == 300 &&
          actual.packets.length == 10 &&
          identical(actual.packets.first, window.packets.first) &&
          listEquals(actual.items, expected),
    ),
    'unread_queue_no_hidden_topics': _measure(
      24000,
      (i) => projection.project(
        source,
        selectedTopicId: i.isEven ? 16 : null,
        isRead: (id) => id == 16 && i.isEven,
      ),
      (_, actual) => identical(actual, source),
    ),
    'grouped_notification_badge_totals': _measure(
      40000,
      (i) => counts.totalExcluding(i.isEven ? const [] : excluded),
      (i, actual) => actual == (i.isEven ? 1035 : 1031),
    ),
  };
  stdout.writeln(jsonEncode(values));
  exit(0);
}

double _measure<T>(
  int iterations,
  T Function(int) run,
  bool Function(int, T) validate,
) {
  final results = List<T?>.filled(iterations, null);
  final samples = <double>[];
  for (var batch = 0; batch < 10; batch++) {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      results[i] = run(i);
    }
    stopwatch.stop();
    for (var i = 0; i < iterations; i++) {
      if (!validate(i, results[i] as T)) throw StateError('Incorrect result');
    }
    if (batch >= 3) {
      samples.add(stopwatch.elapsedMicroseconds / iterations);
    }
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
