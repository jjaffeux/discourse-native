import 'dart:convert';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../../data/plugin_transport.dart';
import 'event_controller.dart';

Future<String> eventCalendar(
  EventController controller,
  String site, {
  int? eventId,
  bool mine = false,
}) async {
  final transport = controller.api.transport;
  if (transport is! PluginTextTransport) {
    throw UnsupportedError('Calendar downloads are unavailable.');
  }
  final lease = controller.requests.capture(site);
  final username = mine
      ? controller.siteState.currentUserFor(site)?.username
      : null;
  if (mine && username == null) throw StateError('Connect your account first.');
  final credentials = await controller.requests.credentialsFor(site);
  if (!lease.isCurrent) throw StateError('Account changed.');
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
  if (!lease.isCurrent) throw StateError('Account changed.');
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
  Rect? sharePositionOrigin,
}) async {
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
    if (location != null) {
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
