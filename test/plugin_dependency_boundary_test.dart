import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core never imports or exports a plugin implementation', () {
    final violations = <String>[];
    final directives = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.startsWith('lib/src/plugins/') ||
          path == 'lib/main.dart' ||
          path == 'lib/discourse_full.dart') {
        continue;
      }

      final source = entity.readAsStringSync();
      for (final match in directives.allMatches(source)) {
        final uri = match.group(1)!;
        if (uri.startsWith('package:discourse_native/src/plugins/') ||
            RegExp(r'^(?:\.\./)+plugins/').hasMatch(uri)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          violations.add('$path:$line imports $uri');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plugin implementations may depend on core, but core must extend '
          'through lib/src/plugin_api instead of importing a plugin. Only the '
          'full-build composition roots may assemble bundled plugins.\n'
          '${violations.join('\n')}',
    );
  });
}
