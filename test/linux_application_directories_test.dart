import 'dart:io';

import 'package:discourse_native/src/data/linux_application_directories.dart';
import 'package:discourse_native/src/data/linux_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory support;
  late Directory cache;
  late File preferences;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'discourse-native-application-directories-test-',
    );
    support = Directory('${root.path}/data/org.discourse.native');
    cache = Directory('${root.path}/cache/org.discourse.native');
    preferences = File('${support.path}/$linuxSharedPreferencesFileName');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> restrict({required bool isLinux}) =>
      restrictLinuxApplicationDirectories(
        isLinux: isLinux,
        supportDirectory: () async => support,
        cacheDirectory: () async => cache,
      );

  test('makes the directories and preferences owner-only on Linux', () async {
    // Mirrors what the plugins leave behind under a umask of 022.
    await support.create(recursive: true);
    await preferences.writeAsString('{"flutter.recent":"Private title"}');
    await Directory('${cache.path}/http-media-v1').create(recursive: true);
    await _setMode(support.path, '755');
    await _setMode(preferences.path, '644');
    await _setMode(cache.path, '755');

    await restrict(isLinux: true);

    expect(await _mode(support), 0x1c0); // 0700
    expect(await _mode(preferences), 0x180); // 0600
    expect(await _mode(cache), 0x1c0); // 0700
    expect(
      await preferences.readAsString(),
      '{"flutter.recent":"Private title"}',
    );

    // Saves replace the file by rename rather than rewriting it in place, and
    // each replacement is made owner-only itself.
    expect(
      await LinuxPreferencesStore(
        file: () => preferences,
      ).setValue('String', 'flutter.recent', 'Later title'),
      isTrue,
    );
    expect(await _mode(preferences), 0x180); // 0600
    expect(
      await preferences.readAsString(),
      '{"flutter.recent":"Later title"}',
    );
  });

  test('creates missing directories without inventing preferences', () async {
    await restrict(isLinux: true);

    expect(await _mode(support), 0x1c0); // 0700
    expect(await _mode(cache), 0x1c0); // 0700
    expect(await preferences.exists(), isFalse);
  });

  test('restricts the cache even when support cannot be resolved', () async {
    final failure = StateError('no support directory');

    await expectLater(
      restrictLinuxApplicationDirectories(
        isLinux: true,
        supportDirectory: () async => throw failure,
        cacheDirectory: () async => cache,
      ),
      throwsA(same(failure)),
    );
    expect(await _mode(cache), 0x1c0); // 0700
  });

  test('leaves other platforms untouched', () async {
    await support.create(recursive: true);
    await preferences.writeAsString('{}');
    await _setMode(support.path, '755');
    await _setMode(preferences.path, '644');
    var resolved = false;

    await restrictLinuxApplicationDirectories(
      isLinux: false,
      supportDirectory: () async {
        resolved = true;
        return support;
      },
      cacheDirectory: () async {
        resolved = true;
        return cache;
      },
    );

    expect(resolved, isFalse);
    expect(await _mode(support), 0x1ed); // 0755
    expect(await _mode(preferences), 0x1a4); // 0644
    expect(await cache.exists(), isFalse);
  });
}

Future<int> _mode(FileSystemEntity entity) async =>
    (await entity.stat()).mode & 0x1ff;

Future<void> _setMode(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  expect(
    result.exitCode,
    0,
    reason: 'chmod $mode $path failed: ${result.stderr}',
  );
}
