import 'dart:async';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_export.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/event_export_platform.dart';
import 'support/event_fixtures.dart';

const calendar =
    'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:series-42\r\nDTSTART;VALUE=DATE:20260908\r\nDTEND;VALUE=DATE:20260909\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'calendar export preserves the server representation and filters by post ID',
    () async {
      final transport = _TextTransport();
      final ports = EventTestPorts(transport: transport);
      addTearDown(ports.close);
      expect(
        await eventCalendar(ports.controller, eventSite, eventId: 42),
        calendar,
      );
      expect(transport.path, '/discourse-post-event/events.ics?post_id=42');
      expect(transport.apiKey, 'key');
      expect(transport.clientId, 'test-client');
      await eventCalendar(ports.controller, eventSite, mine: true);
      expect(
        transport.path,
        '/discourse-post-event/events.ics?attending_user=lee',
      );
      expect(transport.path, isNot(contains('key')));
    },
  );

  test(
    'HTML/error responses and a changed account never reach file sharing',
    () async {
      final transport = _TextTransport()
        ..result = Future.value('<html>Sign in</html>');
      final ports = EventTestPorts(transport: transport);
      addTearDown(ports.close);
      await expectLater(
        eventCalendar(ports.controller, eventSite),
        throwsFormatException,
      );
      final gate = Completer<String>();
      transport.result = gate.future;
      transport.entered = Completer<void>();
      final pending = eventCalendar(ports.controller, eventSite);
      await transport.entered!.future;
      ports.requests.forget(eventSite);
      gate.complete(calendar);
      await expectLater(pending, throwsStateError);
    },
  );

  test(
    'a calendar without an event is refused instead of saved empty',
    () async {
      // The feed leaves out closed events and anything before its window.
      final transport = _TextTransport()
        ..result = Future.value(
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
          'X-WR-CALNAME:BEGIN:VEVENT\r\nEND:VCALENDAR\r\n',
        );
      final ports = EventTestPorts(transport: transport);
      addTearDown(ports.close);
      await expectLater(
        eventCalendar(ports.controller, eventSite, eventId: 42),
        throwsA(isA<EmptyEventCalendarException>()),
      );
    },
  );

  test('a retired view does not fetch after credential lookup', () async {
    final transport = _TextTransport();
    final ports = EventTestPorts(transport: transport);
    addTearDown(ports.close);
    var current = true;
    final pending = eventCalendar(
      ports.controller,
      eventSite,
      isCurrent: () => current,
    );
    current = false;
    await expectLater(pending, throwsStateError);
    expect(transport.path, isNull);
  });

  group('saving a calendar', () {
    late EventExportFileSelector selector;
    late FileSelectorPlatform previousSelector;
    late TargetPlatform? previousPlatform;
    final sharing = _Sharing();
    late SharePlatform previousSharing;
    late Directory temporary;

    setUpAll(() {
      previousSharing = SharePlatform.instance;
      SharePlatform.instance = sharing;
    });
    tearDownAll(() => SharePlatform.instance = previousSharing);
    setUp(() {
      previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      previousSelector = FileSelectorPlatform.instance;
      selector = EventExportFileSelector();
      FileSelectorPlatform.instance = selector;
      sharing.calls.clear();
      sharing.result = Completer<ShareResult>();
      sharing.entered = Completer<void>();
    });
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('event-share-test-');
    });
    tearDown(() async {
      FileSelectorPlatform.instance = previousSelector;
      debugDefaultTargetPlatformOverride = previousPlatform;
      await temporary.delete(recursive: true);
    });

    Future<void> share({
      String filename = 'my-events.ics',
      bool Function()? isCurrent,
      Rect? origin,
      VoidCallback? onTemporaryDirectory,
    }) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      return saveEventCalendar(
        calendar,
        filename: filename,
        isCurrent: isCurrent ?? () => true,
        sharePositionOrigin: origin,
        temporaryDirectory: () async {
          onTemporaryDirectory?.call();
          return temporary;
        },
      );
    }

    Future<File> sharedFile() async {
      await sharing.entered.future;
      return File(sharing.calls.single.files!.single.path);
    }

    Future<File> destination() async {
      final directory = await Directory.systemTemp.createTemp('event-export-');
      addTearDown(() => directory.delete(recursive: true));
      return File('${directory.path}/chosen-calendar.ics');
    }

    test('preserves calendar bytes at the user-selected path', () async {
      final file = await destination();
      selector.choosePath = () async => file.path;
      const content = '$calendar\r\nRésumé';
      await saveEventCalendar(
        content,
        filename: 'event-42.ics',
        isCurrent: () => true,
      );
      expect(selector.filenames, ['event-42.ics']);
      expect(await file.readAsString(), content);
    });

    test('does not open a picker for an obsolete operation', () async {
      await saveEventCalendar(
        calendar,
        filename: 'event-42.ics',
        isCurrent: () => false,
      );
      expect(selector.filenames, isEmpty);
    });

    test('accepts a dismissed save dialog without writing', () async {
      await saveEventCalendar(
        calendar,
        filename: 'event-42.ics',
        isCurrent: () => true,
      );
      expect(selector.filenames, ['event-42.ics']);
    });

    for (final change in [
      'view replacement',
      'account refresh',
      'account reset',
      'controller disposal',
    ]) {
      test('does not overwrite the chosen file after $change', () async {
        final ports = EventTestPorts();
        if (change != 'controller disposal') addTearDown(ports.close);
        final operation = EventExportOperation(ports.controller, eventSite);
        final file = await destination();
        await file.writeAsString('existing calendar');
        final entered = Completer<void>();
        final location = Completer<String?>();
        selector.choosePath = () {
          entered.complete();
          return location.future;
        };
        final pending = saveEventCalendar(
          calendar,
          filename: 'event-42.ics',
          isCurrent: () => operation.isCurrent,
        );
        await entered.future;
        switch (change) {
          case 'view replacement':
            operation.cancel();
          case 'account refresh':
            ports.controller.pluginCurrentUserRefreshed(eventSite);
          case 'account reset':
            ports.requests.forget(eventSite);
          case 'controller disposal':
            ports.close();
        }
        location.complete(file.path);
        await pending;
        expect(await file.readAsString(), 'existing calendar');
      });
    }

    test(
      'shares a private snapshot named for the export, then deletes it',
      () async {
        const origin = Rect.fromLTWH(10, 20, 300, 100);
        var current = true;
        final pending = share(isCurrent: () => current, origin: origin);
        final file = await sharedFile();
        final params = sharing.calls.single;
        expect(params.sharePositionOrigin, origin);
        expect(params.files!.single.mimeType, 'text/calendar');
        expect(file.parent.parent.path, temporary.path);
        expect(
          file.parent.path,
          startsWith('${temporary.path}/calendar-share-'),
        );
        expect(file.uri.pathSegments.last, 'my-events.ics');
        if (!Platform.isWindows) {
          expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
        }
        expect(await file.readAsString(), calendar);
        // Ownership cannot recall a share already handed to the platform.
        current = false;
        sharing.result.complete(
          const ShareResult('target', ShareResultStatus.success),
        );
        await pending;
        expect(selector.filenames, isEmpty);
        expect(temporary.listSync(), isEmpty);
      },
    );

    test('a dismissed share leaves no calendar copy behind', () async {
      final pending = share();
      await sharedFile();
      expect(temporary.listSync(), hasLength(1));
      sharing.result.complete(
        const ShareResult('', ShareResultStatus.dismissed),
      );
      await pending;
      expect(temporary.listSync(), isEmpty);
    });

    test('a failed share leaves no calendar copy behind', () async {
      final pending = share();
      await sharedFile();
      expect(temporary.listSync(), hasLength(1));
      sharing.result.completeError(PlatformException(code: 'error'));
      await expectLater(pending, throwsA(isA<PlatformException>()));
      expect(temporary.listSync(), isEmpty);
    });

    test('keeps a hostile filename inside its staging directory', () async {
      final pending = share(filename: '../../escape.ics');
      final file = await sharedFile();
      expect(file.parent.parent.path, temporary.path);
      expect(file.uri.pathSegments.last, '.._.._escape.ics');
      sharing.result.complete(
        const ShareResult('target', ShareResultStatus.success),
      );
      await pending;
      expect(temporary.listSync(), isEmpty);
    });

    test('an export retired while staging never reaches the sheet', () async {
      var current = true;
      await share(
        isCurrent: () => current,
        onTemporaryDirectory: () => current = false,
      );
      expect(sharing.calls, isEmpty);
      expect(temporary.listSync(), isEmpty);
    });

    test('does not hand an obsolete snapshot to the share sheet', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await saveEventCalendar(
        calendar,
        filename: 'my-events.ics',
        isCurrent: () => false,
      );
      expect(sharing.calls, isEmpty);
    });
  });
}

final class _Sharing extends SharePlatform {
  final calls = <ShareParams>[];
  late Completer<ShareResult> result;
  late Completer<void> entered;

  @override
  Future<ShareResult> share(ShareParams params) {
    calls.add(params);
    entered.complete();
    return result.future;
  }
}

final class _TextTransport extends RecordingPluginTransport
    implements PluginTextTransport {
  String? path;
  String? apiKey;
  String? clientId;
  Future<String> result = Future.value(calendar);
  Completer<void>? entered;
  @override
  Future<String> pluginGetText({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    this.path = path;
    this.apiKey = apiKey;
    this.clientId = clientId;
    entered?.complete();
    return result;
  }
}
