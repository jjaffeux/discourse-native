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

    test(
      'the core app declares no Resenha packages and resolves no media SDKs',
      () {
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
          isEmpty,
          reason:
              'Selecting a Dart target cannot remove native plugins. The root '
              'pubspec is the core build boundary and must not resolve Resenha.',
        );
        expect(
          lockedPackages.intersection(_resenhaGraphPackages),
          isEmpty,
          reason:
              'The checked-in core lock must describe the same SDK-free graph '
              'as the core pubspec.',
        );
      },
    );

    test('Resenha owns its SDK dependencies and reviewed WebRTC fork', () {
      const pubspecPath = '$_resenhaPackagePath/pubspec.yaml';
      final pubspec = File(pubspecPath).readAsStringSync();
      final dependencies = _mappingKeys(pubspec, 'dependencies');
      final overrides = _mappingKeys(pubspec, 'dependency_overrides');

      expect(
        dependencies,
        containsAll({
          'discourse_native',
          'flutter_webrtc',
          'livekit_client',
          'logger',
          'logging',
        }),
      );
      expect(
        _dependencyPath(pubspec, 'dependencies', 'discourse_native'),
        '../..',
        reason:
            'Resenha extends the core package; core must never depend back on '
            'Resenha.',
      );
      expect(overrides, contains('flutter_webrtc'));
      expect(
        _dependencyPath(pubspec, 'dependency_overrides', 'flutter_webrtc'),
        'third_party/flutter_webrtc',
      );

      final lock = File('$_resenhaPackagePath/pubspec.lock').readAsStringSync();
      expect(
        _mappingKeys(lock, 'packages'),
        containsAll({'flutter_webrtc', 'livekit_client'}),
      );
      expect(
        _dependencyPath(lock, 'packages', 'flutter_webrtc'),
        'third_party/flutter_webrtc',
      );
    });

    test(
      'the full application composes Resenha in a separate locked graph',
      () {
        const pubspecPath = '$_fullProfilePath/pubspec.yaml';
        const lockPath = '$_fullProfilePath/pubspec.lock';
        final pubspec = File(pubspecPath).readAsStringSync();
        final dependencies = _mappingKeys(pubspec, 'dependencies');
        final lock = File(lockPath).readAsStringSync();
        final lockedPackages = _mappingKeys(lock, 'packages');

        expect(
          dependencies,
          containsAll({'discourse_native', 'discourse_resenha'}),
        );
        expect(
          _dependencyPath(pubspec, 'dependencies', 'discourse_native'),
          '../..',
        );
        expect(
          _dependencyPath(pubspec, 'dependencies', 'discourse_resenha'),
          '../../packages/discourse_resenha',
        );
        expect(
          _dependencyPath(pubspec, 'dependency_overrides', 'flutter_webrtc'),
          '../../packages/discourse_resenha/third_party/flutter_webrtc',
          reason:
              'Pub ignores transitive overrides, so every application which '
              'enables Resenha must activate its reviewed WebRTC fork itself.',
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
              'The full lock is a build artifact: it must prove that the full '
              'profile, unlike core, resolves Resenha and both media SDKs.',
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
    test(
      'core production sources do not reach across the Resenha boundary',
      () {
        expect(Directory('lib/src/plugins/resenha').existsSync(), isFalse);

        final violations = <String>[];
        for (final file in _filesUnder('lib', extension: '.dart')) {
          final source = file.readAsStringSync();
          for (final package in _resenhaGraphPackages) {
            if (source.contains('package:$package/')) {
              violations.add('${_relativePath(file)} imports package:$package');
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Core production Dart must be independently analyzable without '
              'the Resenha package graph.\n${violations.join('\n')}',
        );
      },
    );

    test('Resenha Dart sources have one package owner', () {
      final sources = _filesUnder(
        '$_resenhaPackagePath/lib/src',
        extension: '.dart',
      ).toList(growable: false);
      final staleImports = <String>[];
      for (final file in sources) {
        if (file.readAsStringSync().contains(
          'package:discourse_native/src/plugins/resenha/',
        )) {
          staleImports.add(_relativePath(file));
        }
      }

      expect(sources, isNotEmpty);
      expect(
        staleImports,
        isEmpty,
        reason:
            'Resenha may depend on core contracts, but must never import a '
            'second copy of itself from the core package.\n'
            '${staleImports.join('\n')}',
      );
    });

    test('the outer full composition is the only app which adds Resenha', () {
      final coreManifest = File(
        'lib/src/plugins/bundled_plugin_manifest.dart',
      ).readAsStringSync();
      final fullManifest = File(
        '$_fullProfilePath/lib/full_plugin_manifest.dart',
      ).readAsStringSync();

      expect(coreManifest, isNot(contains('resenha')));
      expect(fullManifest, contains('package:discourse_resenha/'));
      expect(fullManifest, contains('resenhaModule'));
    });

    test('Resenha reaches Chat only through its declared contract edge', () {
      final module = File(
        '$_resenhaPackagePath/lib/src/resenha_module.dart',
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
        '$_resenhaPackagePath/lib',
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
            'The separately packaged plugin may use Chat only through its '
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
    test(
      'macOS registrants exclude SDKs from core and include them in full',
      () {
        _expectRegistrantMarkers(
          corePath: 'macos/Flutter/GeneratedPluginRegistrant.swift',
          fullPath:
              '$_fullProfilePath/macos/Flutter/GeneratedPluginRegistrant.swift',
          markers: const {
            'flutter_webrtc': [
              'import flutter_webrtc',
              'FlutterWebRTCPlugin.register',
            ],
            'livekit_client': [
              'import livekit_client',
              'LiveKitPlugin.register',
            ],
          },
        );
      },
    );

    test(
      'Linux registrants exclude SDKs from core and include them in full',
      () {
        _expectRegistrantMarkers(
          corePath: 'linux/flutter/generated_plugins.cmake',
          fullPath: '$_fullProfilePath/linux/flutter/generated_plugins.cmake',
          markers: const {
            'flutter_webrtc': ['flutter_webrtc'],
            'livekit_client': ['livekit_client'],
          },
        );
        _expectRegistrantMarkers(
          corePath: 'linux/flutter/generated_plugin_registrant.cc',
          fullPath:
              '$_fullProfilePath/linux/flutter/generated_plugin_registrant.cc',
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
      },
    );

    test('iOS registration is selected by each independent package graph', () {
      _expectRegistrantMarkers(
        corePath: 'ios/Runner/GeneratedPluginRegistrant.m',
        fullPath: '$_fullProfilePath/ios/Runner/GeneratedPluginRegistrant.m',
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
      expect(coreLock.intersection(_resenhaGraphPackages), isEmpty);
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
            'The full graph must contribute an iOS plugin for generated '
            'registration; the core graph cannot see this package.',
      );
    });
  });
}

void _expectRegistrantMarkers({
  required String corePath,
  required String fullPath,
  required Map<String, List<String>> markers,
}) {
  final core = File(corePath).readAsStringSync();
  final full = File(fullPath).readAsStringSync();

  for (final entry in markers.entries) {
    for (final marker in entry.value) {
      expect(
        core,
        isNot(contains(marker)),
        reason: '$corePath must not register ${entry.key}.',
      );
      expect(
        full,
        contains(marker),
        reason: '$fullPath must register ${entry.key}.',
      );
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
