import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

void main() {
  final graph = LibraryGraph.load();
  // Parts carry their own text, so the scan cannot use the library graph.
  final sources = [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.startsWith('lib/l10n/generated/'))
        entity,
  ];

  Map<String, int> occurrences(RegExp pattern) => {
    for (final file in sources)
      if (pattern.allMatches(file.readAsStringSync()).length case final count
          when count > 0)
        file.path: count,
  };

  const owner = 'lib/src/foundation/retry_wait.dart';

  test('only the owner defaults a missing retry delay', () {
    expect(occurrences(RegExp(r'\bretryAfter\s*\?\?')), {owner: 1});
  });

  test('no wait is labelled by truncating its seconds', () {
    expect(occurrences(RegExp(r'\b(wait|retryAfter)\.inSeconds\b')), isEmpty);
  });

  test('every model and shell label reaches the owner directly', () {
    for (final library in const [
      'lib/src/data/write_failure.dart',
      'lib/src/models/composer_upload.dart',
      'lib/src/shell/post_mutation_feedback.dart',
      'lib/src/shell/profile_write_transactions.dart',
    ]) {
      expect(graph.edges[library], contains(owner), reason: library);
    }
  });
}
