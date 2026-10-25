import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Darwin cache directory record decoding', () {
    List<ByteCacheFileMetadata>? decode(Uint8List bytes, {int count = 1}) =>
        decodeDarwinCacheDirectoryBatches('/cache', [
          (bytes: bytes, count: count),
        ]);

    test('copies names, logical sizes and microsecond timestamps', () {
      final bytes = _record(
        name: '船-é.bin',
        size: 1048576,
        seconds: -2,
        nanoseconds: 765432999,
      );
      final files = decode(bytes)!;

      bytes.fillRange(0, bytes.length, 0);

      expect(files.single.file.path, '/cache${Platform.pathSeparator}船-é.bin');
      expect(files.single.bytes, 1048576);
      expect(files.single.usedAt.microsecondsSinceEpoch, -1234568);
    });

    test('supports non-file records without a file attribute group', () {
      final bytes = Uint8List.fromList([
        ..._record(name: 'directory.bin', type: 2),
        ..._record(name: 'link.tmp', type: 5),
        ..._record(name: 'notes.txt'),
        ..._record(name: 'entry.bin', size: 12),
      ]);

      final files = decode(bytes, count: 4)!;

      expect(files.map((entry) => entry.file.path), [
        '/cache${Platform.pathSeparator}entry.bin',
      ]);
      expect(files.single.bytes, 12);
    });

    test('a failed later batch discards every earlier record', () {
      final valid = _record(name: 'stale.tmp');

      expect(
        decodeDarwinCacheDirectoryBatches('/cache', [
          (bytes: valid, count: 1),
          (bytes: Uint8List(0), count: -1),
        ]),
        isNull,
      );
      expect(
        decodeDarwinCacheDirectoryBatches('/cache', [
          (bytes: valid, count: 1),
          (bytes: Uint8List(64), count: 1),
        ]),
        isNull,
      );
      expect(decodeDarwinCacheDirectoryBatches('/cache', []), isEmpty);
    });

    for (final length in [0, 1, 55, 65, 0xffffffff]) {
      test('rejects invalid record length $length', () {
        final bytes = _record();
        ByteData.sublistView(bytes).setUint32(0, length, Endian.host);

        expect(decode(bytes), isNull);
      });
    }

    test('rejects truncated storage and impossible record counts', () {
      final bytes = _record();

      expect(decode(Uint8List.sublistView(bytes, 0, 55)), isNull);
      expect(decode(bytes, count: 2), isNull);
      expect(decode(bytes, count: 0), isNull);
      expect(decode(bytes, count: -1), isNull);
    });

    for (final mask in [
      0,
      0x20000409,
      0xa0000408,
      0xa0000401,
      0xa0000009,
      0xa000040b,
    ]) {
      test('rejects missing or unexpected common attributes $mask', () {
        final bytes = _record();
        ByteData.sublistView(bytes).setUint32(4, mask, Endian.host);

        expect(decode(bytes), isNull);
      });
    }

    for (final field in [8, 12, 16, 20]) {
      test('rejects unexpected returned attribute group at $field', () {
        final bytes = _record();
        ByteData.sublistView(bytes).setUint32(field, 1, Endian.host);

        expect(decode(bytes), isNull);
      });
    }

    test('rejects a missing logical size and per-entry errors', () {
      final missingSize = _record();
      ByteData.sublistView(missingSize).setUint32(16, 0, Endian.host);
      final failed = _record();
      ByteData.sublistView(failed).setUint32(24, 2, Endian.host);

      expect(decode(missingSize), isNull);
      expect(decode(failed), isNull);
    });

    for (final offset in [-100, 0, 28, 1000]) {
      test('rejects a name reference outside its record $offset', () {
        final bytes = _record();
        ByteData.sublistView(bytes).setInt32(28, offset, Endian.host);

        expect(decode(bytes), isNull);
      });
    }

    for (final name in ['', '.', '..', 'nested/entry.bin', 'a\u0000.bin']) {
      test('rejects unsafe or empty name ${jsonEncode(name)}', () {
        expect(decode(_record(name: name)), isNull);
      });
    }

    test('rejects malformed UTF-8, terminators and name lengths', () {
      final invalidUtf8 = _record();
      invalidUtf8[64] = 0xff;
      final unterminated = _record(name: 'a.bin');
      unterminated[69] = 1;
      final excessiveLength = _record();
      ByteData.sublistView(
        excessiveLength,
      ).setUint32(32, 0xffffffff, Endian.host);
      final emptyLength = _record();
      ByteData.sublistView(emptyLength).setUint32(32, 0, Endian.host);

      expect(decode(invalidUtf8), isNull);
      expect(decode(unterminated), isNull);
      expect(decode(excessiveLength), isNull);
      expect(decode(emptyLength), isNull);
    });

    test('rejects invalid size and timestamp fields without integer wrap', () {
      expect(decode(_record(size: -1)), isNull);
      expect(decode(_record(nanoseconds: -1)), isNull);
      expect(decode(_record(nanoseconds: 1000000000)), isNull);
      expect(decode(_record(seconds: 0x7fffffffffffffff)), isNull);
      expect(decode(_record(seconds: -0x7fffffffffffffff)), isNull);
      expect(
        decode(_record(seconds: 8640000000000, nanoseconds: 1000)),
        isNull,
      );
    });

    test('falls back for a relevant special node', () {
      expect(decode(_record(name: 'pipe.bin', type: 6)), isNull);
      expect(decode(_record(name: 'pipe.txt', type: 6)), isEmpty);
    });
  });

  group('cache directory filesystem scans', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'byte-cache-directory-',
      );
    });

    tearDown(() => directory.delete(recursive: true));

    test('portable scan keeps current metadata for recognized files', () async {
      final bin = File('${directory.path}/entry.bin');
      final temporary = File('${directory.path}/live.tmp');
      await bin.writeAsBytes([1, 2, 3]);
      await temporary.writeAsBytes([4]);
      await File('${directory.path}/notes.txt').writeAsBytes([5]);
      await Directory('${directory.path}/nested.bin').create();
      final timestamp = DateTime.fromMicrosecondsSinceEpoch(1700000000123456);
      await bin.setLastModified(timestamp);

      final scanned = scanPortableByteCacheDirectory(directory);

      expect(scanned.map((entry) => entry.file.path).toSet(), {
        bin.path,
        temporary.path,
      });
      expect(_metadata(scanned), _metadataFromStat([bin, temporary]));

      await bin.writeAsBytes([6, 7, 8, 9]);
      await bin.setLastModified(timestamp.subtract(const Duration(days: 1)));
      await temporary.delete();

      expect(
        _metadata(scanPortableByteCacheDirectory(directory)),
        _metadataFromStat([bin]),
      );
    });

    test('portable scan ignores files removed after enumeration', () async {
      final file = File('${directory.path}/removed.bin');
      await file.writeAsBytes([1]);
      final missing = File('${directory.path}/missing.bin').statSync();

      final files = IOOverrides.runZoned(
        () => scanPortableByteCacheDirectory(directory),
        statSync: (path) {
          expect(path, file.path);
          file.deleteSync();
          return missing;
        },
      );

      expect(files, isEmpty);
      expect(await file.exists(), isFalse);
    });

    test(
      'native scan matches FileStat across batches, node types and timestamps',
      () async {
        final plain = File('${directory.path}/entry.bin');
        final empty = File('${directory.path}/empty.bin');
        final sparse = File('${directory.path}/sparse.bin');
        final unicode = File('${directory.path}/船-é.bin');
        final cutoff = File('${directory.path}/cutoff.tmp');
        await plain.writeAsBytes([1, 2, 3]);
        await empty.writeAsBytes([]);
        final sparseHandle = await sparse.open(mode: FileMode.write);
        try {
          await sparseHandle.truncate(1024 * 1024);
        } finally {
          await sparseHandle.close();
        }
        await unicode.writeAsBytes([4]);
        await cutoff.writeAsBytes([5, 6]);
        await plain.setLastModified(
          DateTime.fromMicrosecondsSinceEpoch(-1234567),
        );
        await unicode.setLastModified(
          DateTime.fromMicrosecondsSinceEpoch(1700000000123456),
        );
        await cutoff.setLastModified(DateTime.utc(2026, 10, 22, 11));
        await Directory('${directory.path}/nested.bin').create();
        await Link('${directory.path}/linked.bin').create(plain.path);
        await File('${directory.path}/unrelated.txt').writeAsBytes([7]);
        for (var index = 0; index < 1100; index++) {
          await File(
            '${directory.path}/${index.toString().padLeft(64, '0')}.bin',
          ).writeAsBytes([index % 251]);
        }

        final native = tryReadDarwinByteCacheDirectory(directory.path);
        final portable = scanPortableByteCacheDirectory(directory);

        expect(native, isNotNull);
        expect(native, hasLength(1105));
        expect(_metadata(native!), _metadata(portable));
        expect(
          _metadata(native),
          _metadataFromStat(portable.map((entry) => entry.file)),
        );
        expect(
          native.singleWhere((entry) => entry.file.path == sparse.path).bytes,
          1024 * 1024,
        );
        expect(
          native
              .singleWhere((entry) => entry.file.path == plain.path)
              .usedAt
              .microsecondsSinceEpoch,
          -1234567,
        );
      },
      skip: !(Platform.isMacOS || Platform.isIOS),
    );

    test(
      'native scan excludes resource fork bytes from the logical limit',
      () async {
        final file = File('${directory.path}/fork.bin');
        await file.writeAsBytes([1, 2, 3]);
        await File(
          '${file.path}/..namedfork/rsrc',
        ).writeAsBytes(List.filled(4096, 4));

        final files = tryReadDarwinByteCacheDirectory(directory.path);

        expect(files, isNotNull);
        expect(files!.single.bytes, 3);
        expect(_metadata(files), _metadataFromStat([file]));
      },
      skip: !Platform.isMacOS,
    );

    test(
      'native failure preserves files and uses complete portable metadata',
      () async {
        final entry = File('${directory.path}/entry.bin');
        final other = File('${directory.path}/other.bin');
        final stale = File('${directory.path}/stale.tmp');
        final pipe = File('${directory.path}/pipe.bin');
        await entry.writeAsBytes([1, 2, 3]);
        await other.writeAsBytes([4, 5]);
        await stale.writeAsBytes([6]);
        await stale.setLastModified(
          DateTime.now().subtract(const Duration(hours: 2)),
        );
        final created = await Process.run('mkfifo', [pipe.path]);
        expect(created.exitCode, 0, reason: created.stderr.toString());
        final expected = _metadataFromStat([entry, other, stale, pipe]);

        expect(tryReadDarwinByteCacheDirectory(directory.path), isNull);
        final portable = scanPortableByteCacheDirectory(directory);
        final recovered = scanByteCacheDirectory(directory);

        expect(portable, hasLength(4));
        expect(_metadata(portable), expected);
        expect(_metadata(recovered), expected);
        expect(await directory.list().map((file) => file.path).toSet(), {
          entry.path,
          other.path,
          stale.path,
          pipe.path,
        });
        expect(await entry.readAsBytes(), [1, 2, 3]);
        expect(await other.readAsBytes(), [4, 5]);
        expect(await stale.readAsBytes(), [6]);
        expect(
          FileSystemEntity.typeSync(pipe.path, followLinks: false),
          FileSystemEntityType.pipe,
        );
      },
      skip: !Platform.isMacOS,
    );

    test(
      'native scan accepts an empty directory and a symlinked root',
      () async {
        expect(tryReadDarwinByteCacheDirectory(directory.path), isEmpty);
        expect(
          tryReadDarwinByteCacheDirectory('${directory.path}/missing'),
          isNull,
        );
        final target = await Directory('${directory.path}/target').create();
        final file = File('${target.path}/entry.bin');
        await file.writeAsBytes([1, 2]);
        final root = await Link('${directory.path}/root').create(target.path);

        final files = tryReadDarwinByteCacheDirectory(root.path);

        expect(files, isNotNull);
        expect(files, hasLength(1));
        expect(await files!.single.file.readAsBytes(), [1, 2]);
        expect(files.single.bytes, 2);
      },
      skip: !(Platform.isMacOS || Platform.isIOS),
    );
  });
}

Map<String, (int, int)> _metadata(Iterable<ByteCacheFileMetadata> entries) => {
  for (final entry in entries)
    entry.file.path: (entry.bytes, entry.usedAt.microsecondsSinceEpoch),
};

Map<String, (int, int)> _metadataFromStat(Iterable<File> files) => {
  for (final file in files)
    file.path: (
      file.statSync().size,
      file.statSync().modified.microsecondsSinceEpoch,
    ),
};

Uint8List _record({
  String name = 'entry.bin',
  int type = 1,
  int size = 3,
  int seconds = 1700000000,
  int nanoseconds = 123456000,
}) {
  final nameBytes = utf8.encode(name);
  final prefix = type == 2 || type == 5 ? 56 : 64;
  final length = (prefix + nameBytes.length + 1 + 7) & ~7;
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, length, Endian.host);
  data.setUint32(4, 0xa0000409, Endian.host);
  data.setUint32(16, prefix == 64 ? 0x200 : 0, Endian.host);
  data.setInt32(28, prefix - 28, Endian.host);
  data.setUint32(32, nameBytes.length + 1, Endian.host);
  data.setUint32(36, type, Endian.host);
  data.setInt64(40, seconds, Endian.host);
  data.setInt64(48, nanoseconds, Endian.host);
  if (prefix == 64) data.setInt64(56, size, Endian.host);
  bytes.setRange(prefix, prefix + nameBytes.length, nameBytes);
  return bytes;
}
