import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _other = 'https://other.example';

SiteOutbox<List<String>> _outbox(File file) => SiteOutbox(
  file: () => file,
  codec: SiteOutboxCodec(
    encode: (entries) => entries,
    decode: (json) => json is List && json.every((entry) => entry is String)
        ? json.cast<String>()
        : null,
  ),
);

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('site-outbox-test-');
    file = File('${directory.path}/outbox/entries.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('entries survive a new instance for the same account', () async {
    await _outbox(file).save(_site, 'user:sam', ['one', 'two']);

    final reopened = _outbox(file);
    expect(await reopened.sites(), {_site});
    expect(await reopened.restore(_site, 'user:sam'), ['one', 'two']);
    expect(await reopened.restore(_other, 'user:sam'), isNull);
  });

  test('the file is readable by its owner only', () async {
    await _outbox(file).save(_site, 'user:sam', ['one']);

    expect(file.statSync().mode & 0x1ff, 0x180);
    expect(file.parent.statSync().mode & 0x1ff, 0x1c0);
  }, skip: Platform.isWindows);

  test(
    'another account is given nothing and the entries are removed',
    () async {
      final outbox = _outbox(file);
      await outbox.save(_site, 'user:sam', ['one']);

      expect(await outbox.restore(_site, 'user:kris'), isNull);
      expect(await outbox.restore(_site, 'user:sam'), isNull);
      expect(await outbox.sites(), isEmpty);
    },
  );

  test('saving nothing and forgetting both remove a site', () async {
    final outbox = _outbox(file);
    await outbox.save(_site, 'user:sam', ['one']);
    await outbox.save(_other, 'user:sam', ['two']);

    await outbox.save(_site, 'user:sam', null);
    expect(await outbox.sites(), {_other});
    await outbox.forget(_other);
    expect(await outbox.sites(), isEmpty);
    expect(jsonDecode(await file.readAsString()), {
      'version': 1,
      'sites': <String, Object?>{},
    });
  });

  test('operations commit in the order they were called', () async {
    final outbox = _outbox(file);
    final operations = [
      outbox.save(_site, 'user:sam', ['one']),
      outbox.forget(_site),
      outbox.save(_site, 'user:sam', ['two']),
    ];
    final restored = outbox.restore(_site, 'user:sam');
    await Future.wait(operations);

    expect(await restored, ['two']);
  });

  for (final (name, bytes) in [
    ('truncated JSON', utf8.encode('{"version":1,"sites":{"https://fo')),
    ('bytes that are not UTF-8', [0x7b, 0xff, 0xfe, 0x22]),
    ('a document that is not an object', utf8.encode('[1,2,3]')),
    (
      'an older format version',
      utf8.encode(
        jsonEncode({
          'version': 0,
          'sites': {
            _site: {
              'account': 'user:sam',
              'entries': ['stale'],
            },
          },
        }),
      ),
    ),
    (
      'a newer format version',
      utf8.encode(jsonEncode({'version': 2, 'sites': <String, Object?>{}})),
    ),
  ]) {
    test('$name is discarded without throwing', () async {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      final outbox = _outbox(file);

      expect(await outbox.sites(), isEmpty);
      expect(await outbox.restore(_site, 'user:sam'), isNull);
      await outbox.save(_site, 'user:sam', ['fresh']);
      expect(await _outbox(file).restore(_site, 'user:sam'), ['fresh']);
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .map((entity) => entity.path.split('/').last)
            .where((name) => name.contains('damaged')),
        isEmpty,
        reason: 'user content must not linger in a set-aside copy',
      );
    });
  }

  test('a damaged section is dropped and the other sites are kept', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'sites': {
          _site: {'account': 'user:sam', 'entries': 42},
          _other: {
            'account': 'user:sam',
            'entries': ['kept'],
          },
          'https://no-account.example': {
            'entries': ['orphan'],
          },
        },
      }),
    );
    final outbox = _outbox(file);

    expect(await outbox.restore(_site, 'user:sam'), isNull);
    expect(await outbox.restore(_other, 'user:sam'), ['kept']);
    expect(await outbox.sites(), {_other});
  });

  test('a storage failure costs durability and nothing else', () async {
    final blocked = File('${directory.path}/blocked');
    await blocked.writeAsString('not a directory');
    final outbox = _outbox(File('${blocked.path}/entries.json'));

    await outbox.save(_site, 'user:sam', ['one']);
    await outbox.forget(_site);
    expect(await outbox.restore(_site, 'user:sam'), isNull);
    expect(await outbox.sites(), isEmpty);
  });
}
