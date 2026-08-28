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

  test('bundled composition imports only feature module entrypoints', () {
    const manifestPath = 'lib/src/plugins/bundled_plugin_manifest.dart';
    final source = File(manifestPath).readAsStringSync();
    final imports = RegExp(
      r'''^\s*import\s+['"]([^'"]+)['"]''',
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!).toList();

    expect(File('lib/src/plugins/plugin_services.dart').existsSync(), isFalse);
    expect(
      imports,
      everyElement(
        anyOf(equals('plugin_manifest.dart'), endsWith('_module.dart')),
      ),
    );

    for (final feature in const [
      'reactions/reactions_module.dart',
      'local_dates/local_dates_module.dart',
      'poll/poll_module.dart',
      'gifs/gifs_module.dart',
      'discourse_ai/discourse_ai_module.dart',
      'assign/assign_module.dart',
      'chat/chat_module.dart',
      'resenha/resenha_module.dart',
    ]) {
      expect(
        File('lib/src/plugins/$feature').existsSync(),
        isTrue,
        reason: '$feature must own its production module',
      );
    }
  });
}
