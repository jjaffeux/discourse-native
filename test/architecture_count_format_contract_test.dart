import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _owner = 'lib/src/foundation/short_number.dart';

/// A count suffixed by hand, or a direct read of the owner's localized labels.
final _handCopy = RegExp(r"""\}[kKM]['"]|\.compact(?:Thousands|Millions)\b""");

void main() {
  final sources = {
    for (final file in Directory('lib/src').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };

  test('only shortNumber abbreviates a count', () {
    final copies = [
      for (final entry in sources.entries)
        if (entry.key != _owner)
          for (final match in _handCopy.allMatches(entry.value))
            '${entry.key}: ${match[0]}',
    ];
    // ignore: avoid_print
    print('PERF_PROOF card-count-owner hand_copies=${copies.length}');
    expect(copies, isEmpty, reason: 'Use shortNumber.');
  });

  test('the scan still recognises what it rejects', () {
    for (final copy in [
      r"'${(count / 1000).round()}k'",
      r"'${value}M'",
      'appL10n.compactThousands(label)',
    ]) {
      expect(_handCopy.hasMatch(copy), isTrue, reason: copy);
    }
    expect(_handCopy.hasMatch(r"'${seconds}s'"), isFalse);
  });
}
