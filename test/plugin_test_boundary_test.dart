import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _bundledTransportModules = <String>{
  'lib/src/plugins/chat/chat_module.dart',
  'lib/src/plugins/gifs/gifs_module.dart',
  'lib/src/plugins/poll/poll_module.dart',
  'lib/src/plugins/reactions/reactions_module.dart',
};

final _runtimeOptionalApiCast = RegExp(
  r'\b(?:is!?|as)\s+'
  r'(?:ChatApi|GifsApi|PollsApi|ReactionsApi|ReactionsWriteApi)\b',
);
final _directTransportImplementation = RegExp(
  r'\bimplements\b[^\{;]*\b'
  r'(?:PluginApiTransport|PluginJsonListTransport)\b',
  dotAll: true,
);
final _directiveUri = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  test('the plugin API owns the supported recording transport fake', () {
    final transport = RecordingPluginTransport();
    final PluginApiTransport _ = transport;
    final PluginJsonListTransport _ = transport;

    expect(
      File('packages/discourse_plugin_api/lib/testing.dart').existsSync(),
      isTrue,
    );
    expect(
      File('lib/discourse_plugin_test.dart').readAsStringSync(),
      contains("export 'package:discourse_plugin_api/testing.dart'"),
    );
  });

  test('Resenha tests are owned by the application suite', () {
    final violations = <String>[];
    final tests = Directory('test')
        .listSync()
        .whereType<File>()
        .where(
          (file) => file.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('resenha_'),
        )
        .toList(growable: false);

    for (final file in tests) {
      final source = file.readAsStringSync();
      if (_directTransportImplementation.hasMatch(source)) {
        violations.add(
          '${_workspacePath(file)} implements the transport instead of '
          'extending RecordingPluginTransport',
        );
      }
      for (final match in _directiveUri.allMatches(source)) {
        final uri = match.group(1)!;
        if (uri.startsWith('package:discourse_native/test/')) {
          violations.add('${_workspacePath(file)} imports $uri');
        }
      }
    }

    expect(tests, isNotEmpty);
    expect(Directory('packages/discourse_resenha/test').existsSync(), isFalse);
    expect(
      violations,
      isEmpty,
      reason:
          'Bundled Resenha tests use the application test graph and must not '
          'reimplement the shared plugin transport.\n'
          '${violations.join('\n')}',
    );
  });

  test('bundled modules do not infer optional APIs from the transport', () {
    final violations = <String>[];

    for (final path in _bundledTransportModules) {
      final source = File(path).readAsStringSync();
      for (final match in _runtimeOptionalApiCast.allMatches(source)) {
        violations.add('$path runtime-checks `${match.group(0)}`');
      }
      if (RegExp(r'\bswitch\s*\(\s*transport\s*\)').hasMatch(source) ||
          RegExp(r'\bif\s*\(\s*transport\s+case\b').hasMatch(source)) {
        violations.add('$path pattern-matches the transport at runtime');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Modules must build their owned API adapter from PluginApiTransport '
          'or receive an explicit typed factory; the transport must remain a '
          'narrow wire port.\n${violations.join('\n')}',
    );
  });
}

String _workspacePath(File file) => file.path.replaceFirst(
  '${Directory.current.path}${Platform.pathSeparator}',
  '',
);
