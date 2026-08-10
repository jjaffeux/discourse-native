import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const int _privateDirectoryMode = 0x1c0; // 0700
const int _privateFileMode = 0x180; // 0600

/// Creates [directory] when needed and makes it accessible only to its owner on
/// POSIX platforms. Other platforms retain their native filesystem behavior.
Future<void> ensurePrivateDirectory(Directory directory) async {
  await directory.create(recursive: true);
  _restrictPermissions(directory.path, _privateDirectoryMode);
}

/// Creates an empty [file] when needed, then makes its contents owner-only.
///
/// Call this before writing sensitive content so a newly created file never
/// contains readable data while it still has process-default permissions.
Future<void> ensurePrivateFile(File file) async {
  await ensurePrivateDirectory(file.parent);
  if (!await file.exists()) await file.create();
  restrictPrivateFile(file);
}

/// Repairs the permissions of an existing private file before it is read.
void restrictPrivateFile(File file) {
  _restrictPermissions(file.path, _privateFileMode);
}

bool get _supportsPosixPermissions =>
    Platform.isAndroid ||
    Platform.isFuchsia ||
    Platform.isIOS ||
    Platform.isLinux ||
    Platform.isMacOS;

typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);
typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32, Uint32);
typedef _OpenDart = int Function(Pointer<Utf8>, int, int);
typedef _FlockNative = Int32 Function(Int32, Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

final _ChmodDart _nativeChmod = DynamicLibrary.process()
    .lookupFunction<_ChmodNative, _ChmodDart>('chmod');
final _OpenDart _nativeOpen = DynamicLibrary.process()
    .lookupFunction<_OpenNative, _OpenDart>('open');
final _FlockDart _nativeFlock = DynamicLibrary.process()
    .lookupFunction<_FlockNative, _FlockDart>('flock');
final _CloseDart _nativeClose = DynamicLibrary.process()
    .lookupFunction<_CloseNative, _CloseDart>('close');

/// Runs [operation] while holding a process-aware exclusive `flock` on [file].
///
/// Dart's `RandomAccessFile.lock` uses process-scoped record locks on these
/// platforms, which do not coordinate independent isolates in one process.
/// `flock` is tied to the opened file description, so it covers both isolates
/// and separate app processes.
Future<T> withPrivateAdvisoryFileLock<T>(
  File file,
  Future<T> Function() operation,
) async {
  await ensurePrivateFile(file);
  final nativePath = file.path.toNativeUtf8();
  final int descriptor;
  try {
    // O_RDWR. The file already exists, so the variadic mode argument is unused.
    descriptor = _nativeOpen(nativePath, 0x0002, 0);
  } finally {
    malloc.free(nativePath);
  }
  if (descriptor < 0) {
    throw FileSystemException('Could not open private lock file', file.path);
  }

  try {
    if (_nativeFlock(descriptor, 0x0002) != 0) {
      throw FileSystemException('Could not lock private file', file.path);
    }
    return await operation();
  } finally {
    // LOCK_UN. Closing also releases the lock; both calls are best effort so a
    // cleanup error cannot replace the operation's more useful exception.
    _nativeFlock(descriptor, 0x0008);
    _nativeClose(descriptor);
  }
}

void _restrictPermissions(String path, int mode) {
  if (!_supportsPosixPermissions) return;

  final nativePath = path.toNativeUtf8();
  try {
    if (_nativeChmod(nativePath, mode) != 0) {
      throw FileSystemException('Could not set private permissions', path);
    }
  } finally {
    malloc.free(nativePath);
  }
}
