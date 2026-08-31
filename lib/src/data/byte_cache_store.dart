import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

abstract interface class ByteCacheStore {
  Future<Uint8List?> read(String url);

  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  });
}

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

  final Directory directory;
  final int maxEntries;
  final int maxBytes;
  final int maxEntryBytes;
  final DateTime Function() _clock;
  int _writesSincePrune = 0;
  Future<void>? _pruning;

  static Future<FileByteCacheStore> applicationCache() async {
    final root = await getApplicationCacheDirectory();
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
    FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      return null;
    }
    if (stat.type != FileSystemEntityType.file ||
        stat.size < _headerBytes ||
        stat.size > _headerBytes + maxEntryBytes) {
      await _delete(file);
      return null;
    }

    Uint8List encoded;
    try {
      encoded = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }

    if (encoded.length < _headerBytes || !_hasMagic(encoded)) {
      await _delete(file);
      return null;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      ByteData.sublistView(encoded, 4, 12).getInt64(0, Endian.big),
      isUtc: true,
    );
    final bodyLength = encoded.length - _headerBytes;
    if (!expiresAt.isAfter(_clock().toUtc()) || bodyLength > maxEntryBytes) {
      await _delete(file);
      return null;
    }

    unawaited(
      file
          .setLastModified(_clock())
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
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
    await directory.create(recursive: true);
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

    try {
      await temporary.writeAsBytes(encoded, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        await _delete(target);
        await temporary.rename(target.path);
      }
    } finally {
      await _delete(temporary);
    }

    _writesSincePrune++;
    if (_writesSincePrune >= 64) {
      _writesSincePrune = 0;
      await _prune();
    }
  }

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
    if (!await directory.exists()) return;
    final files = <({File file, int bytes, DateTime usedAt})>[];
    final staleTemporaryBefore = _clock().subtract(_staleTemporaryAge);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (entity.path.endsWith('.tmp')) {
          // A live writer's temporary file is recent. Old ones can only be
          // leftovers from a killed process and otherwise evade both bounds.
          if (!stat.modified.isAfter(staleTemporaryBefore)) {
            await _delete(entity);
          }
          continue;
        }
        if (!entity.path.endsWith('.bin')) continue;
        files.add((file: entity, bytes: stat.size, usedAt: stat.modified));
      } on FileSystemException {
        // A cache file may disappear while the OS is reclaiming cache space.
      }
    }
    files.sort((left, right) => right.usedAt.compareTo(left.usedAt));
    var keptEntries = 0;
    var keptBytes = 0;
    for (final entry in files) {
      final fits =
          keptEntries < maxEntries && keptBytes + entry.bytes <= maxBytes;
      if (!fits) {
        await _delete(entry.file);
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

/// Browser-equivalent rules matter here: Discourse marks
/// avatar and emoji assets public and immutable for about a year.
DateTime? persistentByteCacheExpiry(Map<String, String> headers, DateTime now) {
  if (!responseAllowsPersistentByteCache(headers)) return null;

  final directives = _cacheControlDirectives(headers);
  final sharedMaxAge = _freshnessDirective(directives, 's-maxage');
  final generalMaxAge = _freshnessDirective(directives, 'max-age');
  if (sharedMaxAge.specified || generalMaxAge.specified) {
    final maxAge = sharedMaxAge.specified
        ? sharedMaxAge.seconds
        : generalMaxAge.seconds;
    if (maxAge == null) return null;
    final parsedAge = int.tryParse(_headerValue(headers, 'age') ?? '') ?? 0;
    final age = parsedAge < 0 ? 0 : parsedAge;
    final seconds = (maxAge - age).clamp(
      0,
      const Duration(days: 366).inSeconds,
    );
    if (seconds == 0) return null;
    return now.add(Duration(seconds: seconds));
  }

  final expiresHeader = _headerValue(headers, 'expires');
  if (expiresHeader == null || expiresHeader.isEmpty) return null;
  late final DateTime expires;
  try {
    expires = HttpDate.parse(expiresHeader);
  } on HttpException {
    return null;
  }
  if (!expires.isAfter(now.toUtc())) return null;
  final maximum = now.toUtc().add(const Duration(days: 366));
  return expires.isAfter(maximum) ? maximum : expires;
}

/// The native byte store has no validator metadata and is shared by the app's
/// accounts, so directives which require a private cache or a conditional
/// request must remain memory-only.
bool responseAllowsPersistentByteCache(Map<String, String> headers) {
  final directives = _cacheControlDirectives(headers);
  for (final directive in directives) {
    if (directive.name == 'no-store' ||
        directive.name == 'no-cache' ||
        directive.name == 'private') {
      return false;
    }
  }

  final vary = _headerValue(headers, 'vary');
  return vary == null || !vary.split(',').any((field) => field.trim() == '*');
}

String? _headerValue(Map<String, String> headers, String name) {
  final direct = headers[name];
  if (direct != null) return direct;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

List<({String name, String? value})> _cacheControlDirectives(
  Map<String, String> headers,
) {
  final header = _headerValue(headers, 'cache-control') ?? '';
  final parts = <String>[];
  var start = 0;
  var quoted = false;
  var escaped = false;
  for (var index = 0; index < header.length; index++) {
    final character = header[index];
    if (escaped) {
      escaped = false;
    } else if (quoted && character == r'\') {
      escaped = true;
    } else if (character == '"') {
      quoted = !quoted;
    } else if (!quoted && character == ',') {
      parts.add(header.substring(start, index));
      start = index + 1;
    }
  }
  parts.add(header.substring(start));

  final directives = <({String name, String? value})>[];
  for (final untrimmed in parts) {
    final part = untrimmed.trim();
    if (part.isEmpty) continue;
    final equals = part.indexOf('=');
    final name = (equals < 0 ? part : part.substring(0, equals))
        .trim()
        .toLowerCase();
    if (name.isEmpty) continue;
    directives.add((
      name: name,
      value: equals < 0 ? null : part.substring(equals + 1).trim(),
    ));
  }
  return directives;
}

({bool specified, int? seconds}) _freshnessDirective(
  List<({String name, String? value})> directives,
  String name,
) {
  final matches = directives.where((directive) => directive.name == name);
  if (matches.isEmpty) return (specified: false, seconds: null);
  if (matches.length != 1) return (specified: true, seconds: null);

  var value = matches.single.value;
  if (value == null) return (specified: true, seconds: null);
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    return (specified: true, seconds: null);
  }
  return (specified: true, seconds: int.tryParse(value));
}
