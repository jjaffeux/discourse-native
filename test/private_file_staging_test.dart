import 'dart:io';

import 'package:discourse_native/src/foundation/private_file_staging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory parent;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('private-staging-test-');
  });
  tearDown(() => parent.delete(recursive: true));

  Future<String> stagedName(String filename) => withStagedPrivateFile(
    parent,
    const [1],
    prefix: 'staging-',
    filename: filename,
    use: (file) async {
      expect(file.parent.parent.path, parent.path);
      return file.uri.pathSegments.last;
    },
  );

  test('stages owner-only bytes and deletes them afterwards', () async {
    final staged = await withStagedPrivateFile(
      parent,
      const [1, 2, 3],
      prefix: 'staging-',
      filename: 'report.txt',
      use: (file) async {
        expect(file.parent.path, startsWith('${parent.path}/staging-'));
        if (!Platform.isWindows) {
          expect((await file.parent.stat()).mode & 0x1ff, 0x1c0); // 0700
          expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
        }
        return file.readAsBytes();
      },
    );

    expect(staged, [1, 2, 3]);
    expect(parent.listSync(), isEmpty);
  });

  test('deletes the staged file when its consumer fails', () async {
    await expectLater(
      withStagedPrivateFile<void>(
        parent,
        const [1],
        prefix: 'staging-',
        filename: 'report.txt',
        use: (_) async => throw StateError('share failed'),
      ),
      throwsStateError,
    );

    expect(parent.listSync(), isEmpty);
  });

  test('reduces a display name to one path component', () async {
    expect(await stagedName(r'a/b\c.txt'), 'a_b_c.txt');
    expect(await stagedName('../x.txt'), '.._x.txt');
    expect(await stagedName('nul\x00.txt'), 'nul_.txt');
    for (final name in ['', '.', '..']) {
      expect(await stagedName(name), 'file');
    }
    expect(parent.listSync(), isEmpty);
  });
}
