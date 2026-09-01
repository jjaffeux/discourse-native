import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _corePubspecPath = 'pubspec.yaml';
const _coreLockPath = 'pubspec.lock';
const _resenhaPackagePath = 'packages/discourse_resenha';
const _fullProfilePath = 'profiles/full';

const _resenhaGraphPackages = {
  'discourse_resenha',
  'flutter_webrtc',
  'livekit_client',
};
const _resenhaOwnedDependencies = {
  ..._resenhaGraphPackages,
  'logger',
  'logging',
};

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

    test('the root app declares and resolves the complete Resenha graph', () {
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
        declaredPackages.intersection(_resenhaOwnedDependencies),
        containsAll(_resenhaOwnedDependencies),
        reason:
            'Every application build includes Resenha, its native bridge, '
            'and both media SDKs.',
      );
      expect(
        lockedPackages.intersection(_resenhaGraphPackages),
        containsAll(_resenhaGraphPackages),
        reason:
            'The checked-in root lock must prove that ordinary builds '
            'resolve Resenha and both media SDKs.',
      );
      expect(
        _dependencyPath(pubspec, 'dependencies', 'discourse_resenha'),
        'packages/discourse_resenha',
      );
      expect(
        _dependencyPath(pubspec, 'dependency_overrides', 'flutter_webrtc'),
        'packages/discourse_resenha/third_party/flutter_webrtc',
      );
    });

    test('the Resenha child package is only the native iOS bridge', () {
      const pubspecPath = '$_resenhaPackagePath/pubspec.yaml';
      final pubspec = File(pubspecPath).readAsStringSync();
      final dependencies = _mappingKeys(pubspec, 'dependencies');

      expect(dependencies, {'flutter'});

      final lock = File('$_resenhaPackagePath/pubspec.lock').readAsStringSync();
      expect(
        _mappingKeys(lock, 'packages').intersection(_resenhaGraphPackages),
        isEmpty,
        reason:
            'The native bridge must not depend back on the main package or '
            'own the Dart media graph.',
      );
    });

    test(
      'the compatibility application inherits the same locked Resenha graph',
      () {
        const pubspecPath = '$_fullProfilePath/pubspec.yaml';
        const lockPath = '$_fullProfilePath/pubspec.lock';
        final pubspec = File(pubspecPath).readAsStringSync();
        final dependencies = _mappingKeys(pubspec, 'dependencies');
        final lock = File(lockPath).readAsStringSync();
        final lockedPackages = _mappingKeys(lock, 'packages');

        expect(dependencies, contains('discourse_native'));
        expect(dependencies, isNot(contains('discourse_resenha')));
        expect(
          _dependencyPath(pubspec, 'dependencies', 'discourse_native'),
          '../..',
        );
        expect(
          _dependencyPath(pubspec, 'dependency_overrides', 'flutter_webrtc'),
          '../../packages/discourse_resenha/third_party/flutter_webrtc',
          reason:
              'Pub ignores transitive overrides, so every application which '
              'builds Resenha must activate its reviewed WebRTC fork itself.',
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
          containsAll(_resenhaGraphPackages),
          reason:
              'Every application lock must resolve Resenha and both media SDKs.',
        );
        expect(
          _dependencyPath(lock, 'packages', 'discourse_resenha'),
          '../../packages/discourse_resenha',
        );
        expect(
          _dependencyPath(lock, 'packages', 'flutter_webrtc'),
          '../../packages/discourse_resenha/third_party/flutter_webrtc',
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
    test('Resenha Dart sources are owned by the main application package', () {
      final sources = _filesUnder(
        'lib/src/plugins/resenha',
        extension: '.dart',
      ).toList(growable: false);

      expect(sources, isNotEmpty);
      expect(
        Directory('$_resenhaPackagePath/lib/src').existsSync(),
        isFalse,
        reason:
            'The native bridge must not contain a second copy of the Dart '
            'feature implementation.',
      );
    });

    test('every application entry point uses the Resenha manifest', () {
      final bundledManifest = File(
        'lib/src/plugins/bundled_plugin_manifest.dart',
      ).readAsStringSync();
      final fullManifest = File(
        '$_fullProfilePath/lib/full_plugin_manifest.dart',
      ).readAsStringSync();
      final compatibilityTarget = File('lib/main_core.dart').readAsStringSync();

      expect(bundledManifest, contains("import 'resenha/resenha_module.dart'"));
      expect(bundledManifest, contains('resenhaModule'));
      expect(fullManifest, contains('bundledPluginManifest'));
      expect(fullManifest, isNot(contains('resenhaModule')));
      expect(compatibilityTarget, contains('bundledPluginManifest'));
      expect(compatibilityTarget, isNot(contains('corePluginManifest')));
    });

    test('Resenha reaches Chat only through its declared contract edge', () {
      final module = File(
        'lib/src/plugins/resenha/resenha_module.dart',
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
        'lib/src/plugins/resenha',
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
            'Resenha may use Chat only through its '
            'approved contract.\n${implementationImports.join('\n')}',
      );
    });

    test('CallKit and its channel are implemented only by the iOS plugin', () {
      const nativeMarkers = {
        'import CallKit',
        'ResenhaCallKit',
        'resenha_callkit',
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
            'Application runners are shared infrastructure. Resenha native '
            'channels and CallKit behavior must live in its plugin package.',
      );

      final resenhaPubspec = File(
        '$_resenhaPackagePath/pubspec.yaml',
      ).readAsStringSync();
      expect(
        _nestedScalar(resenhaPubspec, const [
          'flutter',
          'plugin',
          'platforms',
          'ios',
        ], 'pluginClass'),
        'DiscourseResenhaPlugin',
      );

      final iosSources = _filesUnder('$_resenhaPackagePath/ios')
          .where(
            (file) =>
                const {'.swift', '.m', '.mm', '.h'}.contains(_extension(file)),
          )
          .toList(growable: false);
      final combinedSource = iosSources
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(combinedSource, contains('DiscourseResenhaPlugin'));
      expect(combinedSource, contains('FlutterPlugin'));
      expect(combinedSource, contains('register(with'));
      for (final marker in nativeMarkers) {
        expect(
          combinedSource,
          contains(marker),
          reason: '$marker must be owned by the Resenha iOS plugin.',
        );
      }

      final podspec = File(
        '$_resenhaPackagePath/ios/discourse_resenha.podspec',
      ).readAsStringSync();
      expect(
        podspec,
        contains("'discourse_resenha/Sources/discourse_resenha/**/*'"),
      );
      expect(podspec, contains("'AVFoundation', 'CallKit'"));

      final swiftPackage = File(
        '$_resenhaPackagePath/ios/discourse_resenha/Package.swift',
      ).readAsStringSync();
      expect(swiftPackage, contains('name: "discourse_resenha"'));
      expect(swiftPackage, contains('name: "discourse-resenha"'));
      expect(swiftPackage, contains('.iOS("15.0")'));
    });

    test('the WebRTC fork and provenance tooling stay visibly third-party', () {
      const vendorPath = '$_resenhaPackagePath/third_party/flutter_webrtc';
      final vendorPubspec = File('$vendorPath/pubspec.yaml');
      final vendorPatches = File('$vendorPath/PATCHES.md');
      final contract = File('$_resenhaPackagePath/tool/vendor_contract.json');
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
    test('macOS registrants include Resenha media SDKs in every app', () {
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

    test('Linux registrants include Resenha media SDKs in every app', () {
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

    test('iOS registration includes Resenha in every app graph', () {
      _expectAllRegistrantMarkers(
        paths: const [
          'ios/Runner/GeneratedPluginRegistrant.m',
          '$_fullProfilePath/ios/Runner/GeneratedPluginRegistrant.m',
        ],
        markers: const {
          'discourse_resenha': ['discourse_resenha', 'DiscourseResenhaPlugin'],
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
      expect(coreLock, containsAll(_resenhaGraphPackages));
      expect(fullLock, containsAll(_resenhaGraphPackages));

      final resenhaPubspec = File(
        '$_resenhaPackagePath/pubspec.yaml',
      ).readAsStringSync();
      expect(
        _nestedScalar(resenhaPubspec, const [
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
