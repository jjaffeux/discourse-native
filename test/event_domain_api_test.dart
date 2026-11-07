import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_api.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

const _calendar =
    'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:42\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  test('event browsing and export consume a domain API without HTTP', () async {
    final ports = EventTestPorts();
    addTearDown(ports.close);
    final api = _MemoryEvents();
    final controller = EventController(
      api: api,
      requests: ports.requests,
      posts: ports.posts,
      siteState: ports.controller.siteState,
      accounts: ports.controller.accounts,
      topics: ports.controller.topics,
      trackers: (_) => ports.channels,
      zones: ports.zones,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.list(eventSite, mine: true, search: 'planning'),
      isEmpty,
    );
    expect(api.listCalls, [(eventSite, 'lee', 'planning', 'key')]);
    expect(
      await eventCalendar(controller, eventSite, eventId: 42, mine: true),
      _calendar,
    );
    expect(api.calendarCalls, [(eventSite, 42, 'lee', 'key')]);
    expect(ports.transport.requests, isEmpty);
  });
}

final class _MemoryEvents implements EventApi {
  final listCalls = <(String, String?, String?, String?)>[];
  final calendarCalls = <(String, int?, String?, String?)>[];

  @override
  DateTime Function() get clock => eventTestNow;

  @override
  Future<List<PostEvent>> list(
    String site,
    PluginRequestCredentials credentials, {
    String? attendingUser,
    String? search,
    bool upcoming = false,
    bool includeDetails = true,
    bool includeInterested = true,
    DateTime? after,
    DateTime? before,
  }) async {
    listCalls.add((site, attendingUser, search, credentials.apiKey));
    return const [];
  }

  @override
  Future<String> calendar(
    String site,
    PluginRequestCredentials credentials, {
    int? eventId,
    String? attendingUser,
  }) async {
    calendarCalls.add((site, eventId, attendingUser, credentials.apiKey));
    return _calendar;
  }

  @override
  Future<PostEvent> get(
    String site,
    int id,
    PluginRequestCredentials credentials,
  ) => throw UnimplementedError();
  @override
  Future<PostEvent?> byTopic(
    String site,
    int topicId,
    PluginRequestCredentials credentials,
  ) => throw UnimplementedError();
  @override
  Future<List<EventInvitee>> invitees(
    String site,
    int id,
    PluginRequestCredentials credentials, {
    String? filter,
    String? type,
  }) => throw UnimplementedError();
  @override
  Future<void> respond(
    String site,
    int id, {
    required String apiKey,
    required String clientId,
    required String status,
    required bool recurring,
    int? inviteeId,
  }) => throw UnimplementedError();
  @override
  Future<void> withdraw(
    String site,
    int id,
    int inviteeId, {
    required String apiKey,
    required String clientId,
  }) => throw UnimplementedError();
  @override
  Future<void> invite(
    String site,
    int id,
    List<String> usernames, {
    required String apiKey,
    required String clientId,
  }) => throw UnimplementedError();
}
