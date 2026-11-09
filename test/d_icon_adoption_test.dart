import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/control_adoption.dart';

final _frameworkIconUse = RegExp(
  r'(?<![A-Za-z0-9_.])(?:Icons\.|CupertinoIcons\.|Icon\s*\(|IconData\b)',
);

/// Kalender's `MultiDayOverlayStyle.closeIcon` is typed `Icon?`, so its one
/// close glyph cannot be a DIcon.
const _frameworkDemandedUses = {'lib/src/ui/components/d_calendar.dart': 2};

void main() {
  test('application icons use DIcon with the Font Awesome sets', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = controlCode(entity.readAsStringSync());
      final matches = _frameworkIconUse.allMatches(code);
      if (matches.length == (_frameworkDemandedUses[entity.path] ?? 0)) {
        continue;
      }
      for (final match in matches) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line: ${match[0]}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Draw icons with DIcon and a DIcons or DNativeIcons glyph. Material '
          'and Cupertino icons do not follow the DIconSet preference or the '
          'mockup vocabulary; only a third-party API typed to Icon is excepted.',
    );
  });
}
