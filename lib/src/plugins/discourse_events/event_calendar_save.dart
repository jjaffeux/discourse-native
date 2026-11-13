import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sharing;

/// Share a server-generated snapshot, never a feed URL containing credentials.
Future<void> saveEventCalendar(
  String calendar, {
  required String filename,
  required bool Function() isCurrent,
  Rect? sharePositionOrigin,
  @visibleForTesting Future<Directory> Function()? temporaryDirectory,
}) async {
  if (!isCurrent()) return;
  final bytes = Uint8List.fromList(utf8.encode(calendar));
  if (!kIsWeb &&
      {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform)) {
    final location = await selector.getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        selector.XTypeGroup(label: appL10n.calendar, extensions: const ['ics']),
      ],
    );
    if (location != null && isCurrent()) {
      await selector.XFile.fromData(
        bytes,
        name: filename,
        mimeType: 'text/calendar',
      ).saveTo(location.path);
    }
  } else {
    // The calendar carries private event names, places and descriptions, so
    // no copy may outlive the share.
    await withStagedPrivateFile(
      await (temporaryDirectory ?? getTemporaryDirectory)(),
      bytes,
      prefix: 'calendar-share-',
      filename: filename,
      use: (file) async {
        // Staging yields, and an obsolete export must not reach the sheet.
        if (!isCurrent()) return;
        await sharing.SharePlus.instance.share(
          sharing.ShareParams(
            files: [sharing.XFile(file.path, mimeType: 'text/calendar')],
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
      },
    );
  }
}
