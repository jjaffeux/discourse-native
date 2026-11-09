import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _owner = 'lib/src/models/topic.dart';

final _publicRead = RegExp(r'(?<![_\w])lastUnreadPostNumber\b');

/// A hand-written "next post after the reader's position".
final _handSum = RegExp(
  r'lastReadPostNumber(?:!|\s*\?\?\s*0\s*\))?\s*\+\s*1\b',
);

void main() {
  final sources = {
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };

  test('only Topic answers which post a list opens', () {
    final publicReads = [
      for (final entry in sources.entries)
        ..._publicRead.allMatches(entry.value).map((_) => entry.key),
    ];
    final handSums = [
      for (final entry in sources.entries)
        if (entry.key != _owner && _handSum.hasMatch(entry.value)) entry.key,
    ];
    // ignore: avoid_print
    print(
      'PERF_PROOF opening-post-owner public_reads=${publicReads.length} '
      'hand_sums=${handSums.length}',
    );

    expect(
      publicReads,
      isEmpty,
      reason:
          'Read Topic.listOpeningPostNumber(category). A caller without the '
          'category skips navigate_to_first_post_after_read.',
    );
    expect(handSums, isEmpty, reason: 'Topic owns the resume position.');
  });

  test('the scan still recognises what it rejects', () {
    expect(_publicRead.hasMatch('topic.lastUnreadPostNumber ?? 1'), isTrue);
    expect(_publicRead.hasMatch('_lastUnreadPostNumber'), isFalse);
    for (final copy in [
      '(topic.lastReadPostNumber ?? 0) + 1',
      'topic.lastReadPostNumber! + 1',
      'lastReadPostNumber + 1',
    ]) {
      expect(_handSum.hasMatch(copy), isTrue, reason: copy);
    }
  });
}
