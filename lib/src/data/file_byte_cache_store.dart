import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import '../foundation/elapsed_time.dart';
import 'byte_cache_directory.dart';
import 'byte_cache_store.dart';

/// The URL is hashed before it becomes a filename. Each file carries its
/// absolute HTTP expiry followed by the response body, so an expired or
/// corrupt entry can be discarded without a separate metadata database.
final class FileByteCacheStore implements ByteCacheStore {
  FileByteCacheStore(
    this.directory, {
    this.maxEntries = 10000,
    this.maxBytes = 128 * 1024 * 1024,
    this.maxEntryBytes = 4 * 1024 * 1024,
    DateTime Function()? clock,
  }) : assert(maxEntries > 0),
       assert(maxBytes > 0),
       assert(maxEntryBytes > 0),
       _clock = clock ?? DateTime.now;

  static const _magic = [0x44, 0x4e, 0x42, 0x31]; // DNB1
  static const _headerBytes = 12;
  static const _staleTemporaryAge = Duration(hours: 1);
  // An entry's mtime is its last-used time, and pruning only reaches an entry
  // once the limits have turned over: thousands of images, far more than a day
  // of reading. Recording use more finely buys no better eviction and costs a
  // disk write for every image on every warm launch.
  static const _lastUsedGranularity = Duration(hours: 24);

  final Directory directory;
  final int maxEntries;
  final int maxBytes;
  final int maxEntryBytes;
  final DateTime Function() _clock;
  int _writesSincePrune = 0;
  Future<void>? _pruning;

  static Future<FileByteCacheStore> applicationCache(Directory root) async {
    final store = FileByteCacheStore(
      Directory('${root.path}${Platform.pathSeparator}http-media-v1'),
    );
    // Directory creation is required before the store is published. The LRU
    // scan is maintenance, though, and may stat thousands of files: do not put
    // that work on the app's first-frame critical path.
    await store.directory.create(recursive: true);
    store._schedulePrune();
    return store;
  }

  Future<void> initialize() async {
    await directory.create(recursive: true);
    await _prune();
  }

  @override
  Future<Uint8List?> read(String url) async {
    final file = File(_pathFor(url));
    final maxEncodedBytes = _headerBytes + maxEntryBytes;
    FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      return null;
    }
    if (stat.type != FileSystemEntityType.file ||
        stat.size < _headerBytes ||
        stat.size > maxEncodedBytes) {
      await _delete(file);
      return null;
    }

    Uint8List encoded;
    try {
      final handle = await file.open();
      try {
        final length = await handle.length();
        // Allow one extra byte to detect growth after measuring the open file.
        final readLimit = length < maxEncodedBytes ? length : maxEncodedBytes;
        encoded = await handle.read(readLimit + 1);
        if (encoded.length > readLimit && readLimit < maxEncodedBytes) {
          return null;
        }
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return null;
    }

    if (encoded.length < _headerBytes || !_hasMagic(encoded)) {
      await _delete(file);
      return null;
    }
    final DateTime expiresAt;
    try {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        ByteData.sublistView(encoded, 4, 12).getInt64(0, Endian.big),
        isUtc: true,
      );
    } on RangeError {
      await _delete(file);
      return null;
    }
    final bodyLength = encoded.length - _headerBytes;
    final now = _clock();
    if (!expiresAt.isAfter(now.toUtc()) || bodyLength > maxEntryBytes) {
      await _delete(file);
      return null;
    }

    if (elapsedSince(stat.modified, now: now) >= _lastUsedGranularity) {
      unawaited(
        file
            .setLastModified(now)
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    return Uint8List.sublistView(encoded, _headerBytes);
  }

  @override
  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > maxEntryBytes ||
        !expiresAt.isAfter(_clock())) {
      return;
    }
    final target = File(_pathFor(url));
    final temporary = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final encoded = Uint8List(_headerBytes + bytes.length);
    encoded.setRange(0, 4, _magic);
    ByteData.sublistView(
      encoded,
      4,
      12,
    ).setInt64(0, expiresAt.toUtc().millisecondsSinceEpoch, Endian.big);
    encoded.setRange(_headerBytes, encoded.length, bytes);

    await directory.create(recursive: true);
    try {
      await temporary.writeAsBytes(encoded, flush: true);
      await temporary.rename(target.path);
    } finally {
      await _delete(temporary);
    }

    _writesSincePrune++;
    if (_writesSincePrune >= 64) {
      _writesSincePrune = 0;
      await _prune();
    }
  }

  @override
  Future<void> remove(String url) => _delete(File(_pathFor(url)));

  String _pathFor(String url) {
    final digest = SHA256Digest().process(Uint8List.fromList(utf8.encode(url)));
    final name = digest
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${directory.path}${Platform.pathSeparator}$name.bin';
  }

  static bool _hasMagic(Uint8List bytes) =>
      bytes[0] == _magic[0] &&
      bytes[1] == _magic[1] &&
      bytes[2] == _magic[2] &&
      bytes[3] == _magic[3];

  void _schedulePrune() {
    unawaited(
      Future<void>(
        _prune,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _prune() {
    final active = _pruning;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _performPrune().whenComplete(() {
      if (identical(_pruning, operation)) _pruning = null;
    });
    _pruning = operation;
    return operation;
  }

  Future<void> _performPrune() async {
    final path = directory.path;
    final entryLimit = maxEntries;
    final byteLimit = maxBytes;
    final staleTemporaryBefore = _clock().subtract(_staleTemporaryAge);
    await Isolate.run<void>(
      () => _pruneDirectory(path, entryLimit, byteLimit, staleTemporaryBefore),
    );
  }

  static void _pruneDirectory(
    String path,
    int maxEntries,
    int maxBytes,
    DateTime staleTemporaryBefore,
  ) {
    final directory = Directory(path);
    if (!directory.existsSync()) return;
    final files = <({File file, int bytes, DateTime usedAt})>[];
    for (final entry in scanByteCacheDirectory(directory)) {
      if (entry.file.path.endsWith('.tmp')) {
        try {
          // A live writer's temporary file is recent. Old ones can only be
          // leftovers from a killed process and otherwise evade both bounds.
          if (!entry.usedAt.isAfter(staleTemporaryBefore)) {
            entry.file.deleteSync();
          }
        } on FileSystemException {
          // A cache file may disappear while the OS is reclaiming cache space.
        }
        continue;
      }
      files.add(entry);
    }
    files.sort((left, right) => right.usedAt.compareTo(left.usedAt));
    var keptEntries = 0;
    var keptBytes = 0;
    for (final entry in files) {
      final fits =
          keptEntries < maxEntries && keptBytes + entry.bytes <= maxBytes;
      if (!fits) {
        try {
          entry.file.deleteSync();
        } on FileSystemException {
          // Missing/unavailable cache entries are equivalent to a cache miss.
        }
        continue;
      }
      keptEntries++;
      keptBytes += entry.bytes;
    }
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Missing/unavailable cache entries are equivalent to a cache miss.
    }
  }
}
