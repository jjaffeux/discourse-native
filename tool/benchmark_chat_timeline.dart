import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_timeline.dart';

void main() {
  final held = List.generate(1000, (i) => _message(100 + i));
  final lookup = {for (final message in held) message.id: message};
  final snapshot = ChatTimelineSnapshot(
    ids: lookup.keys.toList(),
    messageById: (id) => lookup[id],
  );

  final page = List.generate(50, (i) => _message(75 + i)).reversed.toList();
  final skewed = _message(1500, seconds: 600);
  final result = {
    'chat_prepend_50_held_1000_us': _measure(
      () => ChatMessageTimeline.merge(
        held: snapshot,
        arrived: page,
        mode: ChatTimelineMergeMode.prependPage,
      ),
      List.generate(1025, (i) => 75 + i),
    ),
    'chat_sorted_union_held_1000_us': _measure(
      () => ChatMessageTimeline.admitLive(held: snapshot, message: skewed),
      [...snapshot.ids.take(501), 1500, ...snapshot.ids.skip(501)],
    ),
  };
  stdout.writeln(jsonEncode(result));
  exit(0);
}

ChatMessage _message(int id, {int? seconds}) => ChatMessage(
  id: id,
  channelId: 1,
  cooked: '<p>Message $id</p>',
  author: const ChatMessageAuthor(id: 1, username: 'sam'),
  createdAt: DateTime.utc(2026, 11, 13, 0, 0, seconds ?? id),
);

double _measure(List<int> Function() merge, List<int> expected) {
  const iterations = 900;
  final samples = <double>[];
  final outputs = List<List<int>>.filled(iterations, const []);
  for (var batch = 0; batch < 12; batch++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      outputs[i] = merge();
    }
    watch.stop();
    for (final ids in outputs) {
      if (ids.length != expected.length) throw StateError('Wrong window size');
      for (var i = 0; i < ids.length; i++) {
        if (ids[i] != expected[i]) throw StateError('Wrong message at $i');
      }
    }
    if (batch >= 5) samples.add(watch.elapsedMicroseconds / iterations);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
