import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _genericComposerFiles = <String>[
  'lib/src/plugin_api/composer_syntax.dart',
  'lib/src/plugin_api/core_plugin_host.dart',
  'lib/src/plugin_api/plugin_registry.dart',
  'lib/src/plugin_api/shell_extensions.dart',
  'lib/src/plugin_api/site_plugin_api.dart',
  'lib/src/shell/composer/controller.dart',
  'lib/src/shell/composer/markdown_editing_controller.dart',
];

const _forbiddenComposerVocabulary = <String>[
  'ChatPreview',
  'ComposerMaximumOptionsPlugin',
  'ComposerUploadPolicyPlugin',
  'TrustedGifPreviewSeed',
  'allowsComposerUploads',
  'insertPluginTranscriptIntoNewTopic',
  'isChat',
  'localDateAccountTimezone',
  'pollMaximumOptions',
];

void main() {
  test(
    'core composer modules do not import bundled plugin implementations',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib/src/shell/composer',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final directive in RegExp(
          r'''(?:import|export)\s+['"]([^'"]+)['"]''',
        ).allMatches(file.readAsStringSync())) {
          if (directive.group(1)!.contains('/plugins/')) {
            violations.add('${file.path}: ${directive.group(1)}');
          }
        }
      }
      expect(violations, isEmpty);
    },
  );

  test('generic composer and preview contracts remain surface-neutral', () {
    final violations = <String>[];
    for (final path in _genericComposerFiles) {
      final source = File(path).readAsStringSync();
      for (final token in _forbiddenComposerVocabulary) {
        if (source.contains(token)) violations.add('$path contains $token');
      }
    }

    final shell = File(
      'lib/src/shell/shell_controller.dart',
    ).readAsStringSync();
    for (final token in const [
      "'create-poll'",
      'insertPluginTranscriptIntoNewTopic',
      'localDateAccountTimezone',
      'pollMaximumOptions',
    ]) {
      if (shell.contains(token)) {
        violations.add('lib/src/shell/shell_controller.dart contains $token');
      }
    }

    expect(
      File('lib/src/plugin_api/chat_preview.dart').existsSync(),
      isFalse,
      reason: 'The preview document and projector are owned by Chat.',
    );
    expect(
      violations,
      isEmpty,
      reason:
          'Feature configuration and semantics belong to namespaced policies '
          'and plugin-owned contracts.\n${violations.join('\n')}',
    );
  });
}
