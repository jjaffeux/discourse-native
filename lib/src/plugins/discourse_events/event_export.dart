import 'dart:convert';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../../data/plugin_transport.dart';
import '../../plugin_api/core_plugin_host.dart' show PluginSiteLease;
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
        if (mine) 'include_interested': 'true',
      },
    ).toString(),
    apiKey: credentials.apiKey,
    clientId: credentials.clientId,
  );
  if (!current()) throw StateError('Export cancelled.');
  if (!calendar.trimLeft().startsWith('BEGIN:VCALENDAR') ||
      !calendar.contains('END:VCALENDAR')) {
    throw const FormatException('Invalid calendar response');
  }
  return calendar;
}

/// Share a server-generated snapshot, never a feed URL containing credentials.
Future<void> saveEventCalendar(
  String calendar, {
  required String filename,
  required bool Function() isCurrent,
  Rect? sharePositionOrigin,
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
      acceptedTypeGroups: const [
        selector.XTypeGroup(label: 'Calendar', extensions: ['ics']),
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
    await sharing.SharePlus.instance.share(
      sharing.ShareParams(
        files: [
          sharing.XFile.fromData(
            bytes,
            name: filename,
            mimeType: 'text/calendar',
          ),
        ],
        fileNameOverrides: [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
