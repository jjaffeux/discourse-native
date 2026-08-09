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

final _ChmodDart _nativeChmod = DynamicLibrary.process()
    .lookupFunction<_ChmodNative, _ChmodDart>('chmod');

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
