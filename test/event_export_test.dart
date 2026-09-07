import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

const calendar =
    'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:series-42\r\nDTSTART;VALUE=DATE:20260908\r\nDTEND;VALUE=DATE:20260909\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
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
        '/discourse-post-event/events.ics?attending_user=lee&include_interested=true',
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
