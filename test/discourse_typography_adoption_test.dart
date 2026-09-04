import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _literalFontSize = RegExp(
  r'\bfontSize\s*(?::|\?\?)\s*(-?(?:\d+(?:\.\d*)?|\.\d+))',
);
final _literalCssFontSize = RegExp(
  r'''["']font-size["']\s*:\s*["']\s*(-?(?:\d+(?:\.\d*)?|\.\d+))px''',
);

void main() {
  test('visible app font-size literals use Discourse typography tokens', () {
    final violations = <String>[];

    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      for (final pattern in [_literalFontSize, _literalCssFontSize]) {
        for (final match in pattern.allMatches(source)) {
          final value = double.parse(match.group(1)!);
          // Zero-sized spans preserve source offsets while hiding syntax in
          // projected editors. They are not visible typography.
          if (value == 0) continue;

          final lineNumber =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          final lineStart = source.lastIndexOf('\n', match.start - 1) + 1;
          final lineEnd = source.indexOf('\n', match.end);
          final line = source.substring(
            lineStart,
            lineEnd == -1 ? source.length : lineEnd,
          );
          violations.add('${entity.path}:$lineNumber: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Direct app-owned font-size literals must use '
          'DiscourseTypography. '
          'Relative authored content may derive from its surrounding style.\n'
          '${violations.join('\n')}',
    );
  });
}
