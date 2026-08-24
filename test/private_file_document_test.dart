import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/foundation/private_file_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File target;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-private-document-test-',
    );
    target = File('${directory.path}/state.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'no-op access leaves no document and commits owner-only files',
    () async {
      final document = _mapDocument(target.path);

      expect(
        await document.read((values) => PrivateFileResult(Map.of(values))),
        isEmpty,
      );
      await document.update<void>((_) => PrivateFileResult.done);
      expect(await target.exists(), isFalse);

      await document.update<void>((values) {
        values['secret'] = 'value';
        return PrivateFileResult.done;
      });

      expect(
        await document.read((values) => PrivateFileResult(Map.of(values))),
        {'secret': 'value'},
      );
      expect((await directory.stat()).mode & 0x1ff, 0x1c0); // 0700
      expect((await target.stat()).mode & 0x1ff, 0x180); // 0600
      expect((await File('${target.path}.lock').stat()).mode & 0x1ff, 0x180);
      expect(await _temporaryFiles(directory), isEmpty);
    },
  );

  test('serializes updates across document instances for one path', () async {
    final first = _mapDocument(target.path);
    final second = _mapDocument(target.path);

    await Future.wait([
      for (var index = 0; index < 40; index++)
        (index.isEven ? first : second).update<void>((values) {
          values['key-$index'] = 'value-$index';
          return PrivateFileResult.done;
        }),
    ]);

    final values = await first.read(
      (values) => PrivateFileResult(Map.of(values)),
    );
    expect(values, hasLength(40));
    for (var index = 0; index < 40; index++) {
      expect(values['key-$index'], 'value-$index');
    }
  });

  test(
    'a failed codec leaves the target intact and does not poison the queue',
    () async {
      final document = PrivateFileDocument<Map<String, String>>(
        target: () => target,
        empty: () => <String, String>{},
        decode: _decodeMap,
        encode: (values) {
          if (values.containsKey('refused')) {
            throw StateError('encoding refused');
          }
          return _encodeMap(values);
        },
      );
      await document.update<void>((values) {
        values['kept'] = 'original';
        return PrivateFileResult.done;
      });
      final original = await target.readAsString();

      await expectLater(
        document.update<void>((values) {
          values['refused'] = 'partial';
          return PrivateFileResult.done;
        }),
        throwsStateError,
      );

      expect(await target.readAsString(), original);
      await document.update<void>((values) {
        values['later'] = 'committed';
        return PrivateFileResult.done;
      });
      expect(
        await document.read((values) => PrivateFileResult(Map.of(values))),
        {'kept': 'original', 'later': 'committed'},
      );
      expect(await _temporaryFiles(directory), isEmpty);
    },
  );

  test('a corrupt document is never replaced by an update', () async {
    await target.writeAsString('not json');
    final document = _mapDocument(target.path);
    var mutationRan = false;

    await expectLater(
      document.update<void>((values) {
        mutationRan = true;
        values['secret'] = 'value';
        return PrivateFileResult.done;
      }),
      throwsFormatException,
    );

    expect(mutationRan, isFalse);
    expect(await target.readAsString(), 'not json');
  });

  test(
    'rejects a Future-valued transaction result without committing',
    () async {
      final document = _mapDocument(target.path);

      await expectLater(
        document.update((values) {
          return PrivateFileResult(
            Future<void>.delayed(Duration.zero, () {
              values['late'] = 'never committed';
            }),
          );
        }),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await target.exists(), isFalse);
    },
  );

  test('the sidecar lock coordinates independent isolates', () async {
    await Future.wait([
      Isolate.run(() => _writeSeries(target.path, 'first')),
      Isolate.run(() => _writeSeries(target.path, 'second')),
    ]);

    final values = await _setDocument(
      target.path,
    ).read((values) => PrivateFileResult(Set.of(values)));
    expect(values, hasLength(24));
    for (final series in ['first', 'second']) {
      for (var index = 0; index < 12; index++) {
        expect(values, contains('$series-$index'));
      }
    }
  });

  test('removes only abandoned stages owned by this protocol', () async {
    await target.parent.create(recursive: true);
    final abandoned = File(
      '${target.path}.1234.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      '.private-document.tmp',
    );
    final fixedTemporary = File('${target.path}.tmp');
    final similarlyNamed = File(
      '${target.path}.1234.gggggggggggggggggggggggggggggggg'
      '.private-document.tmp',
    );
    await abandoned.writeAsString('old secret');
    await fixedTemporary.writeAsString('another protocol');
    await similarlyNamed.writeAsString('not our random suffix');

    await _mapDocument(
      target.path,
    ).read((values) => PrivateFileResult(Map.of(values)));

    expect(await abandoned.exists(), isFalse);
    expect(await fixedTemporary.exists(), isTrue);
    expect(await similarlyNamed.exists(), isTrue);
  });

  test('a filesystem commit failure cleans its stage and queue', () async {
    await Directory(target.path).create(recursive: true);
    final document = _mapDocument(target.path);

    await expectLater(
      document.update<void>((values) {
        values['secret'] = 'first';
        return PrivateFileResult.done;
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(await Directory(target.path).exists(), isTrue);
    expect(await _temporaryFiles(directory), isEmpty);

    await Directory(target.path).delete();
    await document.update<void>((values) {
      values['secret'] = 'second';
      return PrivateFileResult.done;
    });
    expect(await document.read((values) => PrivateFileResult(Map.of(values))), {
      'secret': 'second',
    });
  });
}

PrivateFileDocument<Map<String, String>> _mapDocument(String path) =>
    PrivateFileDocument(
      target: () => File(path),
      empty: () => <String, String>{},
      decode: _decodeMap,
      encode: _encodeMap,
    );

Map<String, String> _decodeMap(String contents) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a string map');
  }
  final values = <String, String>{};
  for (final MapEntry(:key, :value) in decoded.entries) {
    if (value is! String) throw const FormatException('Expected strings');
    values[key] = value;
  }
  return values;
}

String _encodeMap(Map<String, String> values) {
  final keys = values.keys.toList()..sort();
  return jsonEncode({for (final key in keys) key: values[key]});
}

PrivateFileDocument<Set<String>> _setDocument(String path) =>
    PrivateFileDocument(
      target: () => File(path),
      empty: () => <String>{},
      decode: (contents) =>
          contents.split('\n').where((value) => value.isNotEmpty).toSet(),
      encode: (values) {
        final sorted = values.toList()..sort();
        return sorted.join('\n');
      },
    );

Future<void> _writeSeries(String path, String series) async {
  final document = _setDocument(path);
  for (var index = 0; index < 12; index++) {
    await document.update<void>((values) {
      values.add('$series-$index');
      return PrivateFileResult.done;
    });
  }
}

Future<List<File>> _temporaryFiles(Directory directory) async => [
  await for (final entity in directory.list())
    if (entity is File && entity.path.endsWith('.private-document.tmp')) entity,
];
