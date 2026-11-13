import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/foundation/native_media_download_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Share a server-generated snapshot, never a feed URL containing credentials.
Future<void> saveEventCalendar(
  String calendar, {
  required String filename,
  required bool Function() isCurrent,
  Rect? sharePositionOrigin,
  @visibleForTesting Future<Directory> Function()? temporaryDirectory,
}) async {
  if (!isCurrent()) return;
  const environment = NativeMediaDownloadEnvironment();
  final bytes = Uint8List.fromList(utf8.encode(calendar));
  if (!kIsWeb && usesMediaSaveDialog(defaultTargetPlatform)) {
    final path = await environment.chooseSavePath(
      suggestedName: filename,
      fileType: (label: appL10n.calendar, extension: 'ics'),
    );
    if (path != null && isCurrent()) {
      await environment.saveBytes(
        bytes,
        path: path,
        filename: filename,
        mimeType: 'text/calendar',
      );
    }
  } else {
    // The calendar carries private event names, places and descriptions, so
    // no copy may outlive the share.
    await withStagedPrivateFile(
      await (temporaryDirectory ?? environment.temporaryDirectory)(),
      bytes,
      prefix: 'calendar-share-',
      filename: filename,
      use: (file) async {
        // Staging yields, and an obsolete export must not reach the sheet.
        if (!isCurrent()) return;
        await environment.shareFile(
          file,
          mimeType: 'text/calendar',
          sharePositionOrigin: sharePositionOrigin,
        );
      },
    );
  }
}
