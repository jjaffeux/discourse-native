import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _corePubspecPath = 'pubspec.yaml';
const _coreLockPath = 'pubspec.lock';
const _voicePackagePath = 'packages/discourse_voice';
const _fullProfilePath = 'profiles/full';

const _voiceGraphPackages = {
  'discourse_voice',
  'flutter_webrtc',
  'livekit_client',
};
const _voiceOwnedDependencies = {..._voiceGraphPackages, 'logger', 'logging'};

void main() {
  group('profile package graphs', () {
    test('the core app resolves the reviewed AVFoundation fork', () {
      final pubspec = File(_corePubspecPath).readAsStringSync();
      final lock = File(_coreLockPath).readAsStringSync();

      expect(
        _dependencyPath(
          pubspec,
          'dependency_overrides',
          'video_player_avfoundation',
        ),
        'packages/video_player_avfoundation',
      );
      expect(
        _dependencyPath(lock, 'packages', 'video_player_avfoundation'),
        'packages/video_player_avfoundation',
        reason:
            'The checked-in core lock must resolve the reviewed fork, not '
            'the hosted video_player_avfoundation archive.',
      );
    });

    test('the root app declares and resolves the complete Voice graph', () {
      final pubspec = File(_corePubspecPath).readAsStringSync();
      final declaredPackages = {
        ..._mappingKeys(pubspec, 'dependencies'),
        ..._mappingKeys(pubspec, 'dependency_overrides'),
      };
      final lockedPackages = _mappingKeys(
        File(_coreLockPath).readAsStringSync(),
        'packages',
      );

      expect(
        declaredPackages.intersection(_voiceOwnedDependencies),
        containsAll(_voiceOwnedDependencies),
        reason:
            'Every application build includes Voice, its native bridge, '
            'and both media SDKs.',
      );
      expect(
        lockedPackages.intersection(_voiceGraphPackages),
        containsAll(_voiceGraphPackages),
        reason:
            'The checked-in root lock must prove that ordinary builds '
            'resolve Voice and both media SDKs.',
      );
      expect(
        _dependencyPath(pubspec, 'dependencies', 'discourse_voice'),
        'packages/discourse_voice',
      );
      expect(
        _dependencyPath(pubspec, 'dependency_overrides', 'flutter_webrtc'),
        'packages/discourse_voice/third_party/flutter_webrtc',
      );
    });

    test('the Voice child package is only the native iOS bridge', () {
      const pubspecPath = '$_voicePackagePath/pubspec.yaml';
      final pubspec = File(pubspecPath).readAsStringSync();
      final dependencies = _mappingKeys(pubspec, 'dependencies');

      expect(dependencies, {'flutter'});

      final lock = File('$_voicePackagePath/pubspec.lock').readAsStringSync();
      expect(
        _mappingKeys(lock, 'packages').intersection(_voiceGraphPackages),
        isEmpty,
        reason:
            'The native bridge must not depend back on the main package or '
            'own the Dart media graph.',
      );
    });

    test(
      'the compatibility application inherits the same locked Voice graph',
      () {
        const pubspecPath = '$_fullProfilePath/pubspec.yaml';
        const lockPath = '$_fullProfilePath/pubspec.lock';
        final pubspec = File(pubspecPath).readAsStringSync();
        final dependencies = _mappingKeys(pubspec, 'dependencies');
        final lock = File(lockPath).readAsStringSync();
        final lockedPackages = _mappingKeys(lock, 'packages');

        expect(dependencies, contains('discourse_native'));
        expect(dependencies, isNot(contains('discourse_voice')));
        expect(
          _dependencyPath(pubspec, 'dependencies', 'discourse_native'),
          '../..',
        );
        expect(
          _dependencyPath(pubspec, 'dependency_overrides', 'flutter_webrtc'),
          '../../packages/discourse_voice/third_party/flutter_webrtc',
          reason:
              'Pub ignores transitive overrides, so every application which '
              'builds Voice must activate its reviewed WebRTC fork itself.',
        );
        expect(
          _dependencyPath(
            pubspec,
            'dependency_overrides',
            'video_player_avfoundation',
          ),
          '../../packages/video_player_avfoundation',
          reason:
              'Pub ignores transitive overrides, so the full application must '
              'activate the reviewed AVFoundation fork itself.',
        );
        expect(
          lockedPackages,
          containsAll(_voiceGraphPackages),
          reason:
              'Every application lock must resolve Voice and both media SDKs.',
        );
        expect(
          _dependencyPath(lock, 'packages', 'discourse_voice'),
          '../../packages/discourse_voice',
        );
        expect(
          _dependencyPath(lock, 'packages', 'flutter_webrtc'),
          '../../packages/discourse_voice/third_party/flutter_webrtc',
          reason:
              'The checked-in full lock must resolve the reviewed fork, not '
              'the hosted flutter_webrtc archive.',
        );
        expect(
          _dependencyPath(lock, 'packages', 'video_player_avfoundation'),
          '../../packages/video_player_avfoundation',
          reason:
              'The checked-in full lock must resolve the reviewed fork, not '
              'the hosted video_player_avfoundation archive.',
        );
      },
    );
  });

  group('source and native ownership', () {
    test('Voice Dart sources are owned by the main application package', () {
      final sources = _filesUnder(
        'lib/src/plugins/voice',
        extension: '.dart',
      ).toList(growable: false);

      expect(sources, isNotEmpty);
      expect(
        Directory('$_voicePackagePath/lib/src').existsSync(),
        isFalse,
        reason:
            'The native bridge must not contain a second copy of the Dart '
            'feature implementation.',
      );
    });

    test('every application entry point uses the Voice manifest', () {
      final bundledManifest = File(
        'lib/src/plugins/bundled_plugin_manifest.dart',
      ).readAsStringSync();
      final fullManifest = File(
        '$_fullProfilePath/lib/full_plugin_manifest.dart',
      ).readAsStringSync();
      final compatibilityTarget = File('lib/main_core.dart').readAsStringSync();

      expect(bundledManifest, contains("import 'voice/voice_module.dart'"));
      expect(bundledManifest, contains('voiceModule'));
      expect(fullManifest, contains('bundledPluginManifest'));
      expect(fullManifest, isNot(contains('voiceModule')));
      expect(compatibilityTarget, contains('bundledPluginManifest'));
      expect(compatibilityTarget, isNot(contains('corePluginManifest')));
    });

    test('Voice reaches Chat only through its declared contract edge', () {
      final module = File(
        'lib/src/plugins/voice/voice_module.dart',
      ).readAsStringSync();

      expect(
        module,
        contains('package:discourse_native/discourse_plugin_sdk.dart'),
      );
      expect(module, isNot(contains('package:discourse_native/src/')));
      expect(module, contains('PluginDependency(chatPluginId)'));
      expect(module, contains('dependencies.require(chatConversationService)'));

      final implementationImports = <String>[];
      final pluginImport = RegExp(
        r'''package:discourse_native/src/plugins/[^'"\s]+''',
      );
      for (final file in _filesUnder(
        'lib/src/plugins/voice',
        extension: '.dart',
      )) {
        for (final match in pluginImport.allMatches(file.readAsStringSync())) {
          final uri = match.group(0)!;
          implementationImports.add('${_relativePath(file)} imports $uri');
        }
      }
      expect(
        implementationImports,
        isEmpty,
        reason:
            'Voice may use Chat only through its '
            'approved contract.\n${implementationImports.join('\n')}',
      );
    });

    test('CallKit and its channel are implemented only by the iOS plugin', () {
      const nativeMarkers = {
        'import CallKit',
        'VoiceCallKit',
        'voice_callkit',
        'CXProvider',
      };
      final coreViolations = _nativeMarkerOccurrences('ios', nativeMarkers);
      final fullRunnerViolations = _nativeMarkerOccurrences(
        '$_fullProfilePath/ios',
        nativeMarkers,
      );

      expect(
        [...coreViolations, ...fullRunnerViolations],
        isEmpty,
        reason:
            'Application runners are shared infrastructure. Voice native '
            'channels and CallKit behavior must live in its plugin package.',
      );

      final voicePubspec = File(
        '$_voicePackagePath/pubspec.yaml',
      ).readAsStringSync();
      expect(
        _nestedScalar(voicePubspec, const [
          'flutter',
          'plugin',
          'platforms',
          'ios',
        ], 'pluginClass'),
        'DiscourseVoicePlugin',
      );

      final iosSources = _filesUnder('$_voicePackagePath/ios')
          .where(
            (file) =>
                const {'.swift', '.m', '.mm', '.h'}.contains(_extension(file)),
          )
          .toList(growable: false);
      final combinedSource = iosSources
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(combinedSource, contains('DiscourseVoicePlugin'));
      expect(combinedSource, contains('FlutterPlugin'));
      expect(combinedSource, contains('register(with'));
      for (final marker in nativeMarkers) {
        expect(
          combinedSource,
          contains(marker),
          reason: '$marker must be owned by the Voice iOS plugin.',
        );
      }

      final podspec = File(
        '$_voicePackagePath/ios/discourse_voice.podspec',
      ).readAsStringSync();
      expect(
        podspec,
        contains("'discourse_voice/Sources/discourse_voice/**/*'"),
      );
      expect(podspec, contains("'AVFoundation', 'CallKit'"));

      final swiftPackage = File(
        '$_voicePackagePath/ios/discourse_voice/Package.swift',
      ).readAsStringSync();
      expect(swiftPackage, contains('name: "discourse_voice"'));
      expect(swiftPackage, contains('name: "discourse-voice"'));
      expect(swiftPackage, contains('.iOS("15.0")'));
    });

    test('the WebRTC fork and provenance tooling stay visibly third-party', () {
      const vendorPath = '$_voicePackagePath/third_party/flutter_webrtc';
      final vendorPubspec = File('$vendorPath/pubspec.yaml');
      final vendorPatches = File('$vendorPath/PATCHES.md');
      final contract = File('$_voicePackagePath/tool/vendor_contract.json');
      final validator = File('tool/vendor_provenance_contract.dart');

      expect(vendorPubspec.existsSync(), isTrue);
      expect(
        _topLevelScalar(vendorPubspec.readAsStringSync(), 'name'),
        'flutter_webrtc',
      );
      expect(vendorPatches.existsSync(), isTrue);
      expect(contract.existsSync(), isTrue);
      expect(validator.existsSync(), isTrue);
      expect(Directory('third_party/flutter_webrtc').existsSync(), isFalse);
      expect(File('tool/flutter_webrtc_contract.dart').existsSync(), isFalse);

      final contractSource = contract.readAsStringSync();
      expect(contractSource, contains('third_party/flutter_webrtc'));
      expect(contractSource, contains('PATCHES.md'));
      expect(
        validator.readAsStringSync(),
        contains('loadVendorProvenanceContracts'),
      );
    });
  });

  group('generated native registrants', () {
    test('macOS registrants include Voice media SDKs in every app', () {
      _expectAllRegistrantMarkers(
        paths: const [
          'macos/Flutter/GeneratedPluginRegistrant.swift',
          '$_fullProfilePath/macos/Flutter/GeneratedPluginRegistrant.swift',
        ],
        markers: const {
          'flutter_webrtc': [
            'import flutter_webrtc',
            'FlutterWebRTCPlugin.register',
          ],
          'livekit_client': ['import livekit_client', 'LiveKitPlugin.register'],
        },
      );
    });

    test('Linux registrants include Voice media SDKs in every app', () {
      _expectAllRegistrantMarkers(
        paths: const [
          'linux/flutter/generated_plugins.cmake',
          '$_fullProfilePath/linux/flutter/generated_plugins.cmake',
        ],
        markers: const {
          'flutter_webrtc': ['flutter_webrtc'],
          'livekit_client': ['livekit_client'],
        },
      );
      _expectAllRegistrantMarkers(
        paths: const [
          'linux/flutter/generated_plugin_registrant.cc',
          '$_fullProfilePath/linux/flutter/generated_plugin_registrant.cc',
        ],
        markers: const {
          'flutter_webrtc': [
            '<flutter_webrtc/flutter_web_r_t_c_plugin.h>',
            'flutter_web_r_t_c_plugin_register_with_registrar',
          ],
          'livekit_client': [
            '<livekit_client/live_kit_plugin.h>',
            'live_kit_plugin_register_with_registrar',
          ],
        },
      );
    });

    test('iOS registration includes Voice in every app graph', () {
      _expectAllRegistrantMarkers(
        paths: const [
          'ios/Runner/GeneratedPluginRegistrant.m',
          '$_fullProfilePath/ios/Runner/GeneratedPluginRegistrant.m',
        ],
        markers: const {
          'discourse_voice': ['discourse_voice', 'DiscourseVoicePlugin'],
          'flutter_webrtc': ['flutter_webrtc', 'FlutterWebRTCPlugin'],
          'livekit_client': ['livekit_client', 'LiveKitPlugin'],
        },
      );

      for (final projectPath in const [
        'ios/Runner.xcodeproj/project.pbxproj',
        '$_fullProfilePath/ios/Runner.xcodeproj/project.pbxproj',
      ]) {
        final project = File(projectPath).readAsStringSync();
        expect(project, contains('FlutterGeneratedPluginSwiftPackage'));
      }

      final coreLock = _mappingKeys(
        File(_coreLockPath).readAsStringSync(),
        'packages',
      );
      final fullLock = _mappingKeys(
        File('$_fullProfilePath/pubspec.lock').readAsStringSync(),
        'packages',
      );
      expect(coreLock, containsAll(_voiceGraphPackages));
      expect(fullLock, containsAll(_voiceGraphPackages));

      final voicePubspec = File(
        '$_voicePackagePath/pubspec.yaml',
      ).readAsStringSync();
      expect(
        _nestedScalar(voicePubspec, const [
          'flutter',
          'plugin',
          'platforms',
          'ios',
        ], 'pluginClass'),
        isNotEmpty,
        reason:
            'Every graph must contribute the iOS CallKit bridge for generated '
            'registration.',
      );
    });
  });
}

void _expectAllRegistrantMarkers({
  required List<String> paths,
  required Map<String, List<String>> markers,
}) {
  for (final path in paths) {
    final source = File(path).readAsStringSync();
    for (final entry in markers.entries) {
      for (final marker in entry.value) {
        expect(
          source,
          contains(marker),
          reason: '$path must register ${entry.key}.',
        );
      }
    }
  }
}

List<String> _nativeMarkerOccurrences(String directory, Set<String> markers) {
  final occurrences = <String>[];
  for (final file in _filesUnder(directory)) {
    if (!const {'.swift', '.m', '.mm', '.h'}.contains(_extension(file))) {
      continue;
    }
    final source = file.readAsStringSync();
    for (final marker in markers) {
      if (source.contains(marker)) {
        occurrences.add('${_relativePath(file)} contains $marker');
      }
    }
  }
  return occurrences;
}

Set<String> _mappingKeys(String yaml, String section) {
  final lines = yaml.split('\n');
  final header = lines.indexWhere((line) => line.trimRight() == '$section:');
  if (header < 0) return const {};

  final keys = <String>{};
  for (final line in lines.skip(header + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indentation = line.length - line.trimLeft().length;
    if (indentation == 0) break;
    if (indentation != 2) continue;
    final match = RegExp(r'^([A-Za-z0-9_]+):').firstMatch(trimmed);
    if (match != null) keys.add(match.group(1)!);
  }
  return keys;
}

String? _dependencyPath(String yaml, String section, String dependency) {
  final lines = yaml.split('\n');
  final sectionHeader = lines.indexWhere(
    (line) => line.trimRight() == '$section:',
  );
  if (sectionHeader < 0) return null;

  var dependencyHeader = -1;
  for (var index = sectionHeader + 1; index < lines.length; index += 1) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indentation = line.length - line.trimLeft().length;
    if (indentation == 0) break;
    if (indentation == 2 && trimmed == '$dependency:') {
      dependencyHeader = index;
      break;
    }
  }
  if (dependencyHeader < 0) return null;

  for (var index = dependencyHeader + 1; index < lines.length; index += 1) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indentation = line.length - line.trimLeft().length;
    if (indentation <= 2) break;
    final match = RegExp(r'^path:\s*(.+)$').firstMatch(trimmed);
    if (match != null) return _unquote(match.group(1)!.trim());
  }
  return null;
}

String? _nestedScalar(String yaml, List<String> parents, String scalar) {
  final lines = yaml.split('\n');
  var start = 0;
  for (var depth = 0; depth < parents.length; depth += 1) {
    final indentation = depth * 2;
    final expected = '${' ' * indentation}${parents[depth]}:';
    final index = lines.indexWhere(
      (line) => line.trimRight() == expected,
      start,
    );
    if (index < 0) return null;
    start = index + 1;
  }

  final indentation = parents.length * 2;
  final prefix = '${' ' * indentation}$scalar:';
  for (var index = start; index < lines.length; index += 1) {
    final line = lines[index];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final actualIndentation = line.length - line.trimLeft().length;
    if (actualIndentation < indentation) break;
    if (line.trimLeft().startsWith('$scalar:')) {
      return _unquote(line.substring(prefix.length).trim());
    }
  }
  return null;
}

String? _topLevelScalar(String yaml, String key) {
  final prefix = '$key:';
  for (final line in yaml.split('\n')) {
    if (!line.startsWith(prefix)) continue;
    return _unquote(line.substring(prefix.length).trim());
  }
  return null;
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

Iterable<File> _filesUnder(String path, {String? extension}) sync* {
  final directory = Directory(path);
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File &&
        (extension == null || entity.path.endsWith(extension))) {
      yield entity;
    }
  }
}

String _extension(File file) {
  final name = file.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot);
}

String _relativePath(File file) {
  final root = Directory.current.absolute.path;
  final absolute = file.absolute.path;
  return absolute.startsWith('$root/')
      ? absolute.substring(root.length + 1)
      : absolute;
}
