import 'package:desktop_drop/desktop_drop.dart';

import '../models/composer_upload.dart';

List<ComposerUploadFile> composerUploadFilesFromDrop(
  Iterable<DropItem> items,
) => List.unmodifiable([
  for (final item in items.whereType<DropItemFile>())
    ComposerUploadFile(
      name: item.name,
      length: () => _droppedFileLength(item),
      openRead: () => _openDroppedFile(item),
    ),
]);

bool dropContainsDirectory(Iterable<DropItem> items) =>
    items.any((item) => item is DropItemDirectory);

Stream<List<int>> _openDroppedFile(DropItemFile item) async* {
  final bookmark = item.extraAppleBookmark;
  var scoped = false;
  if (bookmark != null && bookmark.isNotEmpty) {
    scoped = await DesktopDrop.instance.startAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
  }
  try {
    yield* item.openRead();
  } finally {
    if (scoped) {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark!,
      );
    }
  }
}

Future<int> _droppedFileLength(DropItemFile item) async {
  final bookmark = item.extraAppleBookmark;
  var scoped = false;
  if (bookmark != null && bookmark.isNotEmpty) {
    scoped = await DesktopDrop.instance.startAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
  }
  try {
    return await item.length();
  } finally {
    if (scoped) {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark!,
      );
    }
  }
}
