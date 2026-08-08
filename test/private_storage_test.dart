import 'dart:io';

import 'package:discourse_native/src/data/private_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LinuxFileStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-storage-test-',
    );
    storage = LinuxFileStorage(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists values across storage instances', () async {
    await storage.write('api_key::https://one.example', 'first-key');
    await storage.write('draft::42', 'unfinished thought');

    final reopened = LinuxFileStorage(directory: directory);

    expect(await reopened.read('api_key::https://one.example'), 'first-key');
    expect(await reopened.readAll(), {
      'api_key::https://one.example': 'first-key',
      'draft::42': 'unfinished thought',
    });
  });

  test('restricts the directory and file to their owner', () async {
    await storage.write('secret', 'value');

    final file = File('${directory.path}/private-storage.json');
    final directoryMode = (await directory.stat()).mode & 0x1ff;
    final fileMode = (await file.stat()).mode & 0x1ff;

    expect(directoryMode, 0x1c0); // 0700
    expect(fileMode, 0x180); // 0600
  });

  test('serializes overlapping updates without losing values', () async {
    await Future.wait([
      storage.write('first', 'one'),
      storage.write('second', 'two'),
      storage.write('third', 'three'),
    ]);

    expect(await storage.readAll(), {
      'first': 'one',
      'second': 'two',
      'third': 'three',
    });
  });

  test('deletes one value without disturbing the rest', () async {
    await storage.write('first', 'one');
    await storage.write('second', 'two');

    await storage.delete('first');

    expect(await storage.readAll(), {'second': 'two'});
  });

  test('does not overwrite a corrupt store', () async {
    final file = File('${directory.path}/private-storage.json');
    await file.writeAsString('not json');

    await expectLater(
      storage.write('secret', 'value'),
      throwsA(isA<FormatException>()),
    );
    expect(await file.readAsString(), 'not json');
  });
}
