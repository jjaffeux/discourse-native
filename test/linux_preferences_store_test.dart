import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:discourse_native/src/data/linux_preferences_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
// The Linux plugins this store replaces, to prove it reads and leaves their
// file exactly where and how they keep it.
// ignore: depend_on_referenced_packages
import 'package:path_provider_linux/path_provider_linux.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-linux-preferences-test-',
    );
    file = File('${directory.path}/$linuxSharedPreferencesFileName');
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  LinuxPreferencesStore store() => LinuxPreferencesStore(file: () => file);

  Future<Map<String, Object>> everything() =>
      store().getAllWithParameters(_everyKey);

  group('the shared_preferences_linux format', () {
    test('is found where the plugin kept it and read unchanged', () async {
      final previousPaths = PathProviderPlatform.instance;
      addTearDown(() => PathProviderPlatform.instance = previousPaths);
      PathProviderPlatform.instance = _SupportPath(directory.path);
      final plugin = SharedPreferencesLinux()
        ..pathProvider = _SupportPath(directory.path);
      await plugin.setValue(
        'String',
        'flutter.discourse_native.instances',
        '[{"url":"https://a.example"}]',
      );
      await plugin.setValue('Bool', 'flutter.flag', true);
      await plugin.setValue('Int', 'flutter.count', 3);
      await plugin.setValue('Double', 'flutter.width', 280.5);
      await plugin.setValue('StringList', 'flutter.list', ['a', 'b']);
      await plugin.setValue('String', 'another.prefix', 'untouched');
      final written = await file.readAsString();

      SharedPreferencesStorePlatform.instance = LinuxPreferencesStore();
      SharedPreferences.resetStatic();
      final preferences = await SharedPreferences.getInstance();

      expect(
        preferences.getString('discourse_native.instances'),
        '[{"url":"https://a.example"}]',
      );
      expect(preferences.getBool('flag'), isTrue);
      expect(preferences.getInt('count'), 3);
      expect(preferences.getDouble('width'), 280.5);
      expect(preferences.getStringList('list'), ['a', 'b']);
      expect(preferences.getKeys(), hasLength(5));
      expect(await file.readAsString(), written);

      expect(await preferences.setString('forum_tabs', '{}'), isTrue);
      expect(await preferences.remove('count'), isTrue);

      // The plugin still reads the result, so an older build keeps working.
      final reread = SharedPreferencesLinux()
        ..pathProvider = _SupportPath(directory.path);
      expect(await reread.getAllWithParameters(_everyKey), {
        'flutter.discourse_native.instances': '[{"url":"https://a.example"}]',
        'flutter.flag': true,
        'flutter.width': 280.5,
        'flutter.list': ['a', 'b'],
        'another.prefix': 'untouched',
        'flutter.forum_tabs': '{}',
      });
    });

    test('clears only the keys SharedPreferences owns', () async {
      await file.writeAsString(
        jsonEncode({'flutter.a': 'x', 'flutter.b': 'y', 'another.c': 'z'}),
      );

      expect(await store().clear(), isTrue);

      expect(await everything(), {'another.c': 'z'});
    });

    test('saves a value whose type is all that changed', () async {
      final preferences = store();
      await preferences.setValue('Int', 'flutter.width', 1);
      await preferences.setValue('Double', 'flutter.width', 1.0);

      expect((await everything())['flutter.width'], isA<double>());
    });
  });

  group('interrupted saves', () {
    test('a save the disk cuts short leaves the previous document', () async {
      final preferences = store();
      await preferences.setValue('String', 'flutter.instances', '["a"]');
      final previous = await file.readAsString();

      final saved = await IOOverrides.runWithIOOverrides(
        () => preferences.setValue('String', 'flutter.forum_tabs', '{"v":1}'),
        _FullDisk(file.path),
      );

      expect(saved, isFalse);
      expect(await file.readAsString(), previous);
      expect(await everything(), {'flutter.instances': '["a"]'});
      expect(
        directory.listSync().map((entity) => entity.path),
        isNot(contains(endsWith('.private-document.tmp'))),
      );
    });

    test('replaces the document owner-only', () async {
      await file.writeAsString('{"flutter.recent":"Private title"}');
      await Process.run('chmod', ['755', directory.path]);
      await Process.run('chmod', ['644', file.path]);

      expect(
        await store().setValue('String', 'flutter.recent', 'Later title'),
        isTrue,
      );

      expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
      expect((await directory.stat()).mode & 0x1ff, 0x1c0); // 0700
      expect(await everything(), {'flutter.recent': 'Later title'});
    });
  });

  group('damaged documents', () {
    for (final (name, bytes) in [
      // What an ENOSPC during the plugin's in-place rewrite left behind.
      (
        'a truncated document',
        utf8.encode('{"flutter.discourse_native.instances":"['),
      ),
      // The plugin read this as no preferences at all, silently.
      ('an empty file', <int>[]),
      ('a document that is not an object', utf8.encode('["flutter.a"]')),
      (
        'a document torn inside a character',
        [...utf8.encode('{"flutter.recent":"caf'), 0xc3],
      ),
    ]) {
      test('$name is set aside, reported once, and read as empty', () async {
        final diagnostics = await _installDiagnostics();
        await file.writeAsBytes(bytes);

        expect(await store().getAll(), isEmpty);
        expect(await store().getAll(), isEmpty);
        expect(await store().setValue('String', 'flutter.next', 'v'), isTrue);

        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
          isA<ErrorDiagnosticEvent>()
              .having(
                (event) => event.operation,
                'operation',
                'preferences.decode',
              )
              .having((event) => event.source, 'source', 'storage')
              .having(
                (event) => event.severity,
                'severity',
                DiagnosticSeverity.error,
              ),
        );
        expect(
          diagnostics.buildJsonReport(),
          isNot(contains('discourse_native.instances')),
        );
        final copies = [
          for (final entity in directory.listSync())
            if (entity.path.contains('.damaged-')) entity as File,
        ];
        expect(copies.single.readAsBytesSync(), bytes);
        expect((await copies.single.stat()).mode & 0x1ff, 0x180); // 0600
        expect(await everything(), {'flutter.next': 'v'});
      });
    }

    test('values SharedPreferences cannot hold are left out', () async {
      await file.writeAsString(
        jsonEncode({
          'flutter.kept': 'x',
          'flutter.null': null,
          'flutter.map': {'a': 1},
          'flutter.mixed': ['a', 1],
        }),
      );

      expect(await store().getAll(), {'flutter.kept': 'x'});
    });
  });

  group('concurrent writers', () {
    test('another process changes only the keys it writes', () async {
      final here = store();
      await here.setValue('String', 'flutter.instances', '["a"]');
      await here.getAll();

      final path = file.path;
      expect(
        await Isolate.run(
          () => _setElsewhere(path, 'flutter.instances', '["a","b"]'),
        ),
        isTrue,
      );
      await here.setValue('String', 'flutter.forum_tabs', '{}');

      expect(await everything(), {
        'flutter.instances': '["a","b"]',
        'flutter.forum_tabs': '{}',
      });
    });

    test('saves land in the order they were issued', () async {
      // Each lookup of the location resolves sooner than the one before it.
      var lookups = 0;
      final preferences = LinuxPreferencesStore(
        file: () async {
          await Future<void>.delayed(Duration(milliseconds: 20 - lookups++));
          return file;
        },
      );

      final saves = [
        for (var index = 0; index < 10; index++)
          preferences.setValue('String', 'flutter.anchor', '$index'),
      ];

      expect(await Future.wait(saves), everyElement(isTrue));
      expect(await everything(), {'flutter.anchor': '9'});
    });

    test('a location that could not be found is looked up again', () async {
      var lookups = 0;
      final preferences = LinuxPreferencesStore(
        file: () => lookups++ == 0
            ? throw const FileSystemException('No support directory')
            : file,
      );

      expect(await preferences.setValue('String', 'flutter.a', 'x'), isFalse);
      expect(await preferences.setValue('String', 'flutter.a', 'y'), isTrue);
      expect(await everything(), {'flutter.a': 'y'});
    });
  });

  test('installs only on Linux', () {
    final previous = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);

    LinuxPreferencesStore.install(isLinux: false);
    expect(SharedPreferencesStorePlatform.instance, same(previous));

    LinuxPreferencesStore.install(isLinux: true);
    expect(
      SharedPreferencesStorePlatform.instance,
      isA<LinuxPreferencesStore>(),
    );
  });
}

final GetAllParameters _everyKey = GetAllParameters(
  filter: PreferencesFilter(prefix: ''),
);

Future<bool> _setElsewhere(String path, String key, String value) =>
    LinuxPreferencesStore(
      file: () => File(path),
    ).setValue('String', key, value);

Future<DiagnosticsController> _installDiagnostics() async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: 'linux-preferences',
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

final class _SupportPath extends PathProviderLinux {
  _SupportPath(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Every write of the preferences document, staged or in place, gets a few
/// bytes out and then fails the way a full disk does.
final class _FullDisk extends IOOverrides {
  _FullDisk(this.document);

  final String document;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.startsWith(document) && !path.endsWith('.lock')
        ? _FullDiskFile(file)
        : file;
  }
}

final class _FullDiskFile extends Fake implements File {
  _FullDiskFile(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Directory get parent => _file.parent;

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _file.readAsString(encoding: encoding);

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _file.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await _file.writeAsString(contents.substring(0, 8));
    throw FileSystemException(
      'No space left on device',
      path,
      const OSError('No space left on device', 28),
    );
  }

  @override
  Future<File> rename(String newPath) => _file.rename(newPath);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);
}
