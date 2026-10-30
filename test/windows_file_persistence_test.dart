import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/foundation/private_file_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('windows-document-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('serializes document updates across independent isolates', () async {
    final path = '${directory.path}/counter.json';
    await Future.wait(
      List.generate(
        4,
        (_) => Isolate.run(() async {
          final document = _counter(path);
          for (var n = 0; n < 8; n++) {
            await document.update((values) {
              values['count'] = values['count']! + 1;
              return PrivateFileResult.done;
            });
          }
        }),
      ),
    );
    expect(
      await _counter(path).read((values) => PrivateFileResult(values['count'])),
      32,
    );
  });

  test(
    'replaces an existing draft document and retains deletions after reopening',
    () async {
      final file = File('${directory.path}/drafts.json');
      final first = ApplicationSupportDraftPersistence(file: file);
      await first.write('draft-one', 'original');
      await first.write('draft-two', 'kept');
      await first.write('draft-one', 'replacement');
      final reopened = ApplicationSupportDraftPersistence(file: file);
      expect((await reopened.read('draft-one')).value, 'replacement');
      await reopened.delete('draft-one');
      final afterDelete = ApplicationSupportDraftPersistence(file: file);
      expect((await afterDelete.read('draft-one')).value, isNull);
      expect((await afterDelete.read('draft-two')).value, 'kept');
    },
  );
}

PrivateFileDocument<Map<String, int>> _counter(String path) =>
    PrivateFileDocument(
      target: () => File(path),
      empty: () => {'count': 0},
      decode: (contents) =>
          (jsonDecode(contents) as Map<String, dynamic>).cast<String, int>(),
      encode: jsonEncode,
    );
