import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef ByteCacheFileMetadata = ({File file, int bytes, DateTime usedAt});
typedef DarwinCacheDirectoryBatch = ({Uint8List bytes, int count});

List<ByteCacheFileMetadata> scanByteCacheDirectory(Directory directory) =>
    tryReadDarwinByteCacheDirectory(directory.path) ??
    scanPortableByteCacheDirectory(directory);

List<ByteCacheFileMetadata> scanPortableByteCacheDirectory(
  Directory directory,
) {
  final files = <ByteCacheFileMetadata>[];
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File || !_isCacheFile(entity.path)) continue;
    try {
      final stat = entity.statSync();
      if (stat.type == FileSystemEntityType.notFound || stat.size < 0) continue;
      files.add((file: entity, bytes: stat.size, usedAt: stat.modified));
    } on FileSystemException {
      // The OS or another cache writer may remove a listed file.
    }
  }
  return files;
}

List<ByteCacheFileMetadata>? tryReadDarwinByteCacheDirectory(String path) {
  if (!(Platform.isMacOS || Platform.isIOS) ||
      sizeOf<IntPtr>() != 8 ||
      path.contains('\u0000')) {
    return null;
  }
  final native = _darwinDirectoryApi;
  if (native == null) return null;

  return using((arena) {
    final handle = native.open(path.toNativeUtf8(allocator: arena));
    if (handle == nullptr) return null;
    try {
      final descriptor = native.descriptor(handle);
      if (descriptor < 0) return null;
      final attributes = arena<_DarwinAttributeList>();
      attributes.ref
        ..bitmapCount = 5
        ..reserved = 0
        ..common = _commonAttributes
        ..volume = 0
        ..directory = 0
        ..file = _dataLength
        ..fork = 0;
      final buffer = arena<Uint8>(_bufferBytes);
      return decodeDarwinCacheDirectoryBatches(
        path,
        _readDarwinBatches(native, descriptor, attributes, buffer),
      );
    } finally {
      native.close(handle);
    }
  });
}

// FSOPT_PACK_INVAL_ATTRS reserves requested common fields. Non-file nodes omit
// the file-attribute group, and returned masks still decide field validity.
List<ByteCacheFileMetadata>? decodeDarwinCacheDirectoryBatches(
  String directoryPath,
  Iterable<DarwinCacheDirectoryBatch> batches,
) {
  final files = <ByteCacheFileMetadata>[];
  for (final batch in batches) {
    final bytes = batch.bytes;
    if (batch.count <= 0 || batch.count > bytes.length ~/ _commonPrefixBytes) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    for (var index = 0; index < batch.count; index++) {
      if (bytes.length - offset < _commonPrefixBytes) return null;
      final length = data.getUint32(offset, Endian.host);
      if (length < _commonPrefixBytes ||
          length % 8 != 0 ||
          length > bytes.length - offset) {
        return null;
      }
      final end = offset + length;
      final common = data.getUint32(offset + 4, Endian.host);
      final volume = data.getUint32(offset + 8, Endian.host);
      final directory = data.getUint32(offset + 12, Endian.host);
      final file = data.getUint32(offset + 16, Endian.host);
      final fork = data.getUint32(offset + 20, Endian.host);
      if (common & ~_commonAttributes != 0 ||
          volume != 0 ||
          directory != 0 ||
          file & ~_dataLength != 0 ||
          fork != 0 ||
          common & _identityAttributes != _identityAttributes ||
          data.getUint32(offset + 24, Endian.host) != 0) {
        return null;
      }

      // attrreference offsets are relative to their own field, not the record.
      final nameStart = offset + 28 + data.getInt32(offset + 28, Endian.host);
      final nameLength = data.getUint32(offset + 32, Endian.host);
      if (nameStart < offset + _commonPrefixBytes ||
          nameStart > end ||
          nameLength <= 1 ||
          nameLength > end - nameStart ||
          bytes[nameStart + nameLength - 1] != 0) {
        return null;
      }
      final nameBytes = Uint8List.sublistView(
        bytes,
        nameStart,
        nameStart + nameLength - 1,
      );
      if (nameBytes.contains(0) || nameBytes.contains(0x2f)) return null;
      final String name;
      try {
        name = utf8.decode(nameBytes);
      } on FormatException {
        return null;
      }
      if (name == '.' || name == '..') return null;

      if (_isCacheFile(name)) {
        final type = data.getUint32(offset + 36, Endian.host);
        if (type == _regularFile) {
          if (common & _modifiedTime == 0 ||
              file & _dataLength == 0 ||
              nameStart < offset + _filePrefixBytes) {
            return null;
          }
          final seconds = data.getInt64(offset + 40, Endian.host);
          final nanoseconds = data.getInt64(offset + 48, Endian.host);
          final size = data.getInt64(offset + 56, Endian.host);
          if (size < 0 ||
              nanoseconds < 0 ||
              nanoseconds >= 1000000000 ||
              seconds < -_maximumDateTimeSeconds ||
              seconds > _maximumDateTimeSeconds) {
            return null;
          }
          final DateTime modified;
          try {
            modified = DateTime.fromMicrosecondsSinceEpoch(
              seconds * Duration.microsecondsPerSecond + nanoseconds ~/ 1000,
            );
          } on ArgumentError {
            return null;
          }
          final separator = directoryPath.endsWith(Platform.pathSeparator)
              ? ''
              : Platform.pathSeparator;
          files.add((
            file: File('$directoryPath$separator$name'),
            bytes: size,
            usedAt: modified,
          ));
        } else if (type != _directory && type != _symbolicLink) {
          // Dart may list pipes and other special nodes as File objects.
          return null;
        }
      }
      offset = end;
    }
  }
  return files;
}

Iterable<DarwinCacheDirectoryBatch> _readDarwinBatches(
  _DarwinDirectoryApi native,
  int descriptor,
  Pointer<_DarwinAttributeList> attributes,
  Pointer<Uint8> buffer,
) sync* {
  while (true) {
    final count = native.read(
      descriptor,
      attributes.cast(),
      buffer.cast(),
      _bufferBytes,
      _packInvalidAttributes,
    );
    if (count == 0) return;
    yield (bytes: buffer.asTypedList(_bufferBytes), count: count);
    if (count < 0) return;
  }
}

bool _isCacheFile(String path) =>
    path.endsWith('.bin') || path.endsWith('.tmp');

const _bufferBytes = 64 * 1024;
const _commonPrefixBytes = 56;
const _filePrefixBytes = 64;
const _returnedAttributes = 0x80000000;
const _entryError = 0x20000000;
const _name = 0x00000001;
const _objectType = 0x00000008;
const _modifiedTime = 0x00000400;
const _identityAttributes = _returnedAttributes | _name | _objectType;
const _commonAttributes = _identityAttributes | _entryError | _modifiedTime;
const _dataLength = 0x00000200;
const _packInvalidAttributes = 0x00000008;
const _regularFile = 1;
const _directory = 2;
const _symbolicLink = 5;
const _maximumDateTimeSeconds = 8640000000000;

final class _DarwinAttributeList extends Struct {
  @Uint16()
  external int bitmapCount;
  @Uint16()
  external int reserved;
  @Uint32()
  external int common;
  @Uint32()
  external int volume;
  @Uint32()
  external int directory;
  @Uint32()
  external int file;
  @Uint32()
  external int fork;
}

typedef _OpenDirectoryNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _OpenDirectoryDart = Pointer<Void> Function(Pointer<Utf8>);
typedef _DirectoryDescriptorNative = Int32 Function(Pointer<Void>);
typedef _DirectoryDescriptorDart = int Function(Pointer<Void>);
typedef _CloseDirectoryNative = Int32 Function(Pointer<Void>);
typedef _CloseDirectoryDart = int Function(Pointer<Void>);
typedef _ReadDirectoryNative =
    Int32 Function(Int32, Pointer<Void>, Pointer<Void>, Size, Uint64);
typedef _ReadDirectoryDart =
    int Function(int, Pointer<Void>, Pointer<Void>, int, int);

final _DarwinDirectoryApi? _darwinDirectoryApi = _loadDarwinDirectoryApi();

_DarwinDirectoryApi? _loadDarwinDirectoryApi() {
  try {
    final library = DynamicLibrary.process();
    return _DarwinDirectoryApi(
      open: library.lookupFunction<_OpenDirectoryNative, _OpenDirectoryDart>(
        'opendir',
      ),
      descriptor: library
          .lookupFunction<_DirectoryDescriptorNative, _DirectoryDescriptorDart>(
            'dirfd',
          ),
      close: library.lookupFunction<_CloseDirectoryNative, _CloseDirectoryDart>(
        'closedir',
      ),
      read: library.lookupFunction<_ReadDirectoryNative, _ReadDirectoryDart>(
        'getattrlistbulk',
      ),
    );
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}

final class _DarwinDirectoryApi {
  const _DarwinDirectoryApi({
    required this.open,
    required this.descriptor,
    required this.close,
    required this.read,
  });

  final _OpenDirectoryDart open;
  final _DirectoryDescriptorDart descriptor;
  final _CloseDirectoryDart close;
  final _ReadDirectoryDart read;
}
