import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  final expiresAt = now.add(const Duration(days: 1));
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-byte-cache-store-',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  Future<File> seed(String key, List<int> body, DateTime usedAt) async {
    final before = await directory.list().map((file) => file.path).toSet();
    await FileByteCacheStore(
      directory,
      clock: () => now,
    ).write(_url(key), Uint8List.fromList(body), expiresAt: expiresAt);
    final file = await directory
        .list()
        .where((file) => !before.contains(file.path))
        .cast<File>()
        .single;
    await file.setLastModified(usedAt);
    return file;
  }

  group('FileByteCacheStore maintenance', () {
    test('reconciles same-name external growth and mtime changes', () async {
      final original = await seed(
        'grown',
        List.filled(8, 1),
        now.subtract(const Duration(hours: 3)),
      );
      final retained = await seed(
        'retained',
        List.filled(8, 2),
        now.subtract(const Duration(hours: 2)),
      );
      final store = FileByteCacheStore(
        directory,
        maxBytes: 40,
        clock: () => now,
      );
      await store.initialize();

      final encoded = await original.readAsBytes();
      await original.writeAsBytes([
        ...encoded.sublist(0, 12),
        ...List.filled(35, 3),
      ]);
      await original.setLastModified(now);

      await store.initialize();

      expect(await original.exists(), isFalse);
      expect(await retained.exists(), isTrue);
      expect(
        await store.read(_url('retained')),
        orderedEquals(List.filled(8, 2)),
      );
      expect(
        await directory
            .list()
            .where((file) => file.path.endsWith('.bin'))
            .length,
        1,
      );
    });

    test(
      'reconciles an existing name becoming the most recently used',
      () async {
        final oldest = await seed('oldest', [
          1,
        ], now.subtract(const Duration(hours: 3)));
        final middle = await seed('middle', [
          2,
        ], now.subtract(const Duration(hours: 2)));
        final store = FileByteCacheStore(
          directory,
          maxEntries: 2,
          clock: () => now,
        );
        await store.initialize();
        final newer = await seed('newer', [
          3,
        ], now.subtract(const Duration(hours: 1)));
        await oldest.setLastModified(now);

        await store.initialize();

        expect(await oldest.exists(), isTrue);
        expect(await middle.exists(), isFalse);
        expect(await newer.exists(), isTrue);
      },
    );

    test(
      'concurrent stores converge within both limits with complete entries',
      () async {
        final stores = [
          FileByteCacheStore(
            directory,
            maxEntries: 16,
            maxBytes: 320,
            clock: () => now,
          ),
          FileByteCacheStore(
            directory,
            maxEntries: 16,
            maxBytes: 320,
            clock: () => now,
          ),
        ];
        await Future.wait(stores.map((store) => store.initialize()));

        await Future.wait([
          for (var index = 0; index < 128; index++)
            stores[index % stores.length].write(
              _url('parallel-$index'),
              Uint8List.fromList(List.filled(8, index)),
              expiresAt: expiresAt,
            ),
        ]);
        await stores.first.initialize();

        final files = await directory
            .list()
            .where((entry) => entry.path.endsWith('.bin'))
            .cast<File>()
            .toList();
        expect(files, hasLength(16));
        expect(files.fold(0, (size, file) => size + file.lengthSync()), 320);
        var readable = 0;
        for (var index = 0; index < 128; index++) {
          final bytes = await stores.last.read(_url('parallel-$index'));
          if (bytes == null) continue;
          readable++;
          expect(bytes, orderedEquals(List.filled(8, index)));
        }
        expect(readable, 16);
        expect(
          await directory
              .list()
              .where((entry) => entry.path.endsWith('.tmp'))
              .isEmpty,
          isTrue,
        );
      },
    );

    test('keeps the most recently used files within maxEntries', () async {
      final oldest = await seed('oldest', [
        1,
      ], now.subtract(const Duration(hours: 3)));
      final newest = await seed('newest', [
        3,
      ], now.subtract(const Duration(hours: 1)));
      final middle = await seed('middle', [
        2,
      ], now.subtract(const Duration(hours: 2)));
      final store = FileByteCacheStore(
        directory,
        maxEntries: 2,
        clock: () => now,
      );

      await store.initialize();

      expect(await oldest.exists(), isFalse);
      expect(await middle.exists(), isTrue);
      expect(await newest.exists(), isTrue);
      expect(await store.read(_url('oldest')), isNull);
      expect(await store.read(_url('middle')), orderedEquals([2]));
      expect(await store.read(_url('newest')), orderedEquals([3]));
    });

    test(
      'counts headers and skips an oversized newest file while retaining older files that fit',
      () async {
        final olderBody = List<int>.filled(8, 1);
        final newerBody = List<int>.filled(8, 2);
        final older = await seed(
          'older',
          olderBody,
          now.subtract(const Duration(hours: 3)),
        );
        final newer = await seed(
          'newer',
          newerBody,
          now.subtract(const Duration(hours: 2)),
        );
        final oversized = await seed(
          'oversized',
          List<int>.filled(35, 3),
          now.subtract(const Duration(hours: 1)),
        );
        final store = FileByteCacheStore(
          directory,
          maxBytes: 40,
          clock: () => now,
        );

        await store.initialize();

        expect(await oversized.exists(), isFalse);
        expect(await older.length(), 20);
        expect(await newer.length(), 20);
        expect(await store.read(_url('older')), orderedEquals(olderBody));
        expect(await store.read(_url('newer')), orderedEquals(newerBody));
        expect(await store.read(_url('oversized')), isNull);
      },
    );

    test('removes temporary files at or before the stale cutoff', () async {
      final stale = File('${directory.path}/stale.tmp');
      final cutoff = File('${directory.path}/cutoff.tmp');
      final live = File('${directory.path}/live.tmp');
      for (final file in [stale, cutoff, live]) {
        await file.writeAsBytes([1]);
      }
      await stale.setLastModified(now.subtract(const Duration(hours: 2)));
      await cutoff.setLastModified(now.subtract(const Duration(hours: 1)));
      await live.setLastModified(now.subtract(const Duration(minutes: 59)));

      await FileByteCacheStore(directory, clock: () => now).initialize();

      expect(await stale.exists(), isFalse);
      expect(await cutoff.exists(), isFalse);
      expect(await live.readAsBytes(), orderedEquals([1]));
    });

    test('ignores directories, symbolic links, and unrelated files', () async {
      final oldest = await seed('oldest', [
        1,
      ], now.subtract(const Duration(hours: 2)));
      final newest = await seed('newest', [
        2,
      ], now.subtract(const Duration(hours: 1)));
      final nested = await Directory('${directory.path}/nested.bin').create();
      final nestedFile = File('${nested.path}/entry.bin');
      final unrelated = File('${directory.path}/notes.txt');
      await nestedFile.writeAsBytes([4]);
      await unrelated.writeAsBytes([5]);
      final link = await Link(
        '${directory.path}/linked.bin',
      ).create(unrelated.path);
      final store = FileByteCacheStore(
        directory,
        maxEntries: 1,
        maxBytes: 13,
        clock: () => now,
      );

      await store.initialize();

      expect(await oldest.exists(), isFalse);
      expect(await newest.exists(), isTrue);
      expect(await store.read(_url('newest')), orderedEquals([2]));
      expect(await nestedFile.readAsBytes(), orderedEquals([4]));
      expect(await unrelated.readAsBytes(), orderedEquals([5]));
      expect(await link.exists(), isTrue);
      expect(await link.target(), unrelated.path);
    });

    test(
      'reconciles externally created temporary files on the 64th write',
      () async {
        final store = FileByteCacheStore(directory, clock: () => now);
        await store.initialize();
        final stale = File('${directory.path}/external.tmp');
        await stale.writeAsBytes([1]);
        await stale.setLastModified(now.subtract(const Duration(hours: 2)));

        for (var index = 0; index < 63; index++) {
          await store.write(
            _url('entry-$index'),
            Uint8List.fromList([index]),
            expiresAt: expiresAt,
          );
        }
        expect(await stale.exists(), isTrue);

        await store.write(
          _url('entry-63'),
          Uint8List.fromList([63]),
          expiresAt: expiresAt,
        );

        expect(await stale.exists(), isFalse);
        expect(
          await directory
              .list()
              .where((entity) => entity is File && entity.path.endsWith('.bin'))
              .length,
          64,
        );
        expect(await store.read(_url('entry-0')), orderedEquals([0]));
        expect(await store.read(_url('entry-63')), orderedEquals([63]));
      },
    );

    test('handles OS deletion and discovers entries on restart', () async {
      final deleted = await seed('deleted', [
        1,
      ], now.subtract(const Duration(hours: 3)));
      await seed('retained', [2], now.subtract(const Duration(hours: 2)));
      final store = FileByteCacheStore(
        directory,
        maxEntries: 2,
        clock: () => now,
      );
      await store.initialize();

      await deleted.delete();
      expect(await store.read(_url('deleted')), isNull);
      await seed('external', [3], now.subtract(const Duration(hours: 1)));
      final restarted = FileByteCacheStore(
        directory,
        maxEntries: 2,
        clock: () => now,
      );
      await restarted.initialize();

      expect(await restarted.read(_url('deleted')), isNull);
      expect(await restarted.read(_url('retained')), orderedEquals([2]));
      expect(await restarted.read(_url('external')), orderedEquals([3]));
      await restarted.write(
        _url('fresh'),
        Uint8List.fromList([4]),
        expiresAt: expiresAt,
      );
      expect(await restarted.read(_url('fresh')), orderedEquals([4]));
    });

    test(
      'concurrent initialization, distinct writes, and reads preserve complete entries',
      () async {
        await seed('existing', [
          9,
          8,
          7,
        ], now.subtract(const Duration(hours: 1)));
        final store = FileByteCacheStore(directory, clock: () => now);
        final operations = <Future<void>>[
          for (var index = 0; index < 8; index++) store.initialize(),
          for (var index = 0; index < 16; index++)
            store.write(
              _url('concurrent-$index'),
              Uint8List.fromList([index, 42]),
              expiresAt: expiresAt,
            ),
          for (var index = 0; index < 8; index++)
            store.read(_url('existing')).then((bytes) {
              expect(bytes, orderedEquals([9, 8, 7]));
            }),
        ];

        await Future.wait(operations);

        for (var index = 0; index < 16; index++) {
          expect(
            await store.read(_url('concurrent-$index')),
            orderedEquals([index, 42]),
          );
        }
        expect(await store.read(_url('existing')), orderedEquals([9, 8, 7]));
        expect(
          await directory
              .list()
              .where((entity) => entity.path.endsWith('.tmp'))
              .toList(),
          isEmpty,
        );
      },
    );
  });
}

String _url(String key) => 'https://cdn.test/$key.png';
