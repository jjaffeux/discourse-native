import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import 'event_controller.dart';

/// One export's view and account lifetime, including native save continuations.
/// Cancelling retires continuations; it cannot dismiss an OS-owned share sheet.
final class EventExportOperation {
  EventExportOperation(this.controller, this.site)
    : _lease = controller.requests.capture(site),
      _accountRevision = controller.accountRevision(site);

  final EventController controller;
  final String site;
  final PluginSiteLease _lease;
  final int _accountRevision;
  bool _cancelled = false;

  bool get isCurrent =>
      !_cancelled &&
      _lease.isCurrent &&
      controller.isAccountCurrent(site, _accountRevision);

  void cancel() => _cancelled = true;
}

Future<String> eventCalendar(
  EventController controller,
  String site, {
  int? eventId,
  bool mine = false,
  bool Function()? isCurrent,
}) async {
  final operation = EventExportOperation(controller, site);
  bool current() => operation.isCurrent && (isCurrent?.call() ?? true);
  if (!current()) throw StateError('Export cancelled.');
  final transport = controller.api.transport;
  if (transport is! PluginTextTransport) {
    throw UnsupportedError('Calendar downloads are unavailable.');
  }
  final username = mine
      ? controller.siteState.currentUserFor(site)?.username
      : null;
  if (mine && username == null) throw StateError('Connect your account first.');
  final credentials = await controller.requests.credentialsFor(site);
  if (!current()) throw StateError('Export cancelled.');
  final calendar = await (transport as PluginTextTransport).pluginGetText(
    siteUrl: site,
    path: Uri(
      path: '/discourse-post-event/events.ics',
      queryParameters: {
        'post_id': ?eventId?.toString(),
        'attending_user': ?username,
      },
    ).toString(),
    apiKey: credentials.apiKey,
    clientId: credentials.clientId,
  );
  if (!current()) throw StateError('Export cancelled.');
  if (!calendar.trimLeft().startsWith('BEGIN:VCALENDAR') ||
      !calendar.contains('END:VCALENDAR')) {
    throw FormatException(appL10n.invalidCalendarResponse);
  }
  if (!_eventComponent.hasMatch(calendar)) {
    throw const EmptyEventCalendarException();
  }
  return calendar;
}

final _eventComponent = RegExp(r'^BEGIN:VEVENT\r?$', multiLine: true);

/// A well-formed calendar holding no event, which would import nothing. The
/// feed leaves out closed events and anything before its default window.
final class EmptyEventCalendarException implements Exception {
  const EmptyEventCalendarException();
}

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
