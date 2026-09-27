import 'dart:io';

import 'private_file_permissions.dart';

/// Runs [use] with [bytes] staged as an owner-only file named [filename] in a
/// fresh directory under [parent], then deletes that directory whether [use]
/// completes or fails.
///
/// This is how bytes reach a platform share sheet. share_plus writes an
/// `XFile.fromData` beneath `getTemporaryDirectory()` and never deletes it,
/// and on iOS that directory is `Library/Caches`, which outlives restarts,
/// sign-out and forum removal. On iOS the share future completes from the
/// sheet's completion handler, after the chosen activity has consumed the file,
/// so [use] must await it for the deletion to be safe.
///
/// The staged basename is the name recipients see: share_plus ignores
/// `fileNameOverrides` for a file that already has a path. [filename] is
/// reduced to a single path component so it cannot leave the directory.
Future<T> withStagedPrivateFile<T>(
  Directory parent,
  List<int> bytes, {
  required String prefix,
  required String filename,
  required Future<T> Function(File file) use,
}) => withPrivateStagingPath(
  parent,
  prefix: prefix,
  filename: filename,
  use: (file) async {
    await ensurePrivateFile(file);
    await file.writeAsBytes(bytes, flush: true);
    return use(file);
  },
);

/// Runs [use] with a not-yet-created file named [filename] in a fresh
/// owner-only directory under [parent], then deletes that directory whether
/// [use] completes or fails.
///
/// This is [withStagedPrivateFile] for content too large to hold in memory:
/// [use] writes the file itself, owner-only, before handing it to the share
/// sheet. The basename rules and deletion timing are the same.
Future<T> withPrivateStagingPath<T>(
  Directory parent, {
  required String prefix,
  required String filename,
  required Future<T> Function(File file) use,
}) async {
  final directory = await parent.createTemp(prefix);
  try {
    await ensurePrivateDirectory(directory);
    return await use(File('${directory.path}/${_pathComponent(filename)}'));
  } finally {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // A share target may still hold the file; the directory stays private.
    }
  }
}

String _pathComponent(String filename) {
  final name = filename.replaceAll(RegExp(r'[/\\\x00]'), '_');
  return name.isEmpty || name == '.' || name == '..' ? 'file' : name;
}
