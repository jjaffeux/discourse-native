import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _owner = 'lib/src/foundation/elapsed_time.dart';

/// Every file that judges a window through [_owner]. An entry's set names the
/// differences that stay in that file because they are amounts or countdowns,
/// which a comparison-only answer would corrupt.
const Map<String, Set<String>> _windowSites = {
  'lib/src/data/byte_cache.dart': {},
  'lib/src/data/byte_cache_store.dart': {
    // An HTTP response's own freshness lifetime, measured between two of its
    // headers. No reading of the device clock is involved.
    'expires.difference(responseDate)',
  },
  'lib/src/data/custom_sidebar_sections.dart': {},
  'lib/src/plugins/chat/chat_controller.dart': {},
  'lib/src/plugins/chat/chat_conversation_stream.dart': {},
  'lib/src/plugins/gamification/gamification_controller.dart': {},
  'lib/src/plugins/nested_replies/nested_replies_reader_memory.dart': {},
  'lib/src/plugins/prometheus_alert_receiver/alert_data.dart': {},
  'lib/src/shell/account_totals_refresh.dart': {},
  'lib/src/shell/composer/composer_identity_directory.dart': {},
  'lib/src/shell/composer/controller.dart': {
    // Accumulated typing time, which already drops a negative step.
    'now.difference(last)',
    // How long the composer was open, reported as an amount.
    '_now().difference(_openedAt)',
  },
  'lib/src/shell/shell_controller.dart': {},
  'lib/src/shell/topic_prefetch_controller.dart': {},
  'lib/src/shell/update_controller.dart': {},
};

const _ownedClocks = [
  'lib/src/data/byte_cache.dart',
  'lib/src/plugins/nested_replies/nested_replies_reader_memory.dart',
];

/// A receiver chain followed by `.difference(...)`, with one level of nested
/// parentheses in the argument.
final _difference = RegExp(
  r'(?:[\w!.]|\(\))*\.difference\((?:[^()]|\([^()]*\))*\)',
);

/// A difference compared on the spot, the shape of the unguarded window.
final _comparedDifference = RegExp(
  r'\.difference\((?:[^()]|\([^()]*\))*\)\s*(?:<=?|>=?)\s',
);

String _code(String path) => File(
  path,
).readAsLinesSync().map((line) => line.split('//').first).join('\n');

void main() {
  for (final site in _windowSites.entries) {
    test('${site.key} measures only its named exceptions', () {
      expect(
        _difference.allMatches(_code(site.key)).map((m) => m[0]).toSet(),
        site.value,
      );
    });
  }

  for (final path in _ownedClocks) {
    test('$path reads only its injected clock', () {
      expect(_code(path), isNot(contains('DateTime.now()')));
    });
  }

  test('no library compares a time difference against a window itself', () {
    final compared = {
      for (final entity in Directory('lib/src').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          for (final match in _comparedDifference.allMatches(
            _code(entity.path),
          ))
            '${entity.path}: ${match[0]}',
    };

    expect(compared, isEmpty);
  });

  test('the owner of the answer depends on no other library', () {
    expect(LibraryGraph.load().closureOf(_owner), {_owner});
  });
}
