import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'event_api.dart';
import 'event_data.dart';

final class DiscourseEventApi implements EventApi {
  const DiscourseEventApi(this._transport, {this.clock = DateTime.now});
  final PluginApiTransport _transport;
  @override
  final DateTime Function() clock;

  String _path(int id) {
    if (id <= 0) throw ArgumentError.value(id, 'eventId');
    return '/discourse-post-event/events/$id';
  }

  @override
  Future<PostEvent> get(
    String site,
    int id,
    PluginRequestCredentials credentials,
  ) async {
    final json = await _transport.pluginGetJson(
      siteUrl: site,
      path: '${_path(id)}.json',
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    final event = PostEvent.decode(json['event']);
    if (event == null || event.id != id || event.topicId == null) {
      throw FormatException(appL10n.invalidEventResponse);
    }
    return event;
  }

  @override
  Future<PostEvent?> byTopic(
    String site,
    int topicId,
    PluginRequestCredentials credentials,
  ) async {
    if (topicId <= 0) throw ArgumentError.value(topicId, 'topicId');
    final path = Uri(
      path: '/discourse-post-event/events.json',
      queryParameters: {
        'topic_id': '$topicId',
        'include_details': 'true',
        'include_closed': 'true',
        'limit': '1',
      },
    ).toString();
    final json = await _transport.pluginGetJson(
      siteUrl: site,
      path: path,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (json['events'] is! List) {
      throw FormatException(appL10n.invalidEventList);
    }
    final rows = json['events'] as List;
    if (rows.isEmpty) return null;
    final event = PostEvent.decode(rows.first);
    if (event == null || event.topicId != topicId) {
      throw FormatException(appL10n.invalidEventResponse);
    }
    return event;
  }

  /// Upcoming bounds use ISO timestamps, as Discourse's web calendar does.
  /// Older event controllers cannot expand occurrences with `after=now`.
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
    final startsAfter = after ?? (upcoming ? clock() : null);
    final path = Uri(
      path: '/discourse-post-event/events.json',
      queryParameters: {
        if (includeDetails) 'include_details': 'true',
        'include_ongoing': 'true',
        'order': 'asc',
        'limit': '200',
        'attending_user': ?attendingUser,
        if (attendingUser != null && includeInterested)
          'include_interested': 'true',
        'search': ?search,
        'after': ?startsAfter?.toUtc().toIso8601String(),
        'before': ?before?.toUtc().toIso8601String(),
      },
    ).toString();
    final json = await _transport.pluginGetJson(
      siteUrl: site,
      path: path,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (json['events'] is! List) {
      throw FormatException(appL10n.invalidEventList);
    }
    return List.unmodifiable([
      for (final raw in json['events'] as List) ?PostEvent.decode(raw),
    ]);
  }

  @override
  Future<List<EventInvitee>> invitees(
    String site,
    int id,
    PluginRequestCredentials credentials, {
    String? filter,
    String? type,
  }) async {
    final path = Uri(
      path: '${_path(id)}/invitees.json',
      queryParameters: {'filter': ?filter, 'type': ?type},
    ).toString();
    final json = await _transport.pluginGetJson(
      siteUrl: site,
      path: path,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (json['invitees'] is! List) {
      throw FormatException(appL10n.invalidParticipantList);
    }
    return List.unmodifiable([
      for (final raw in json['invitees'] as List) ?EventInvitee.decode(raw),
    ]);
  }

  @override
  Future<void> respond(
    String site,
    int id, {
    required String apiKey,
    required String clientId,
    required String status,
    required bool recurring,
    int? inviteeId,
  }) async {
    if (!eventResponseStatuses.contains(status) ||
        (inviteeId != null && inviteeId <= 0)) {
      throw const WriteException(WriteFailure.validation);
    }
    await _transport.pluginWriteJson(
      siteUrl: site,
      path:
          '${_path(id)}/invitees${inviteeId == null ? '' : '/$inviteeId'}.json',
      method: inviteeId == null ? 'POST' : 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'invitee': {'status': status, 'recurring': recurring},
      },
    );
  }

  @override
  Future<void> withdraw(
    String site,
    int id,
    int inviteeId, {
    required String apiKey,
    required String clientId,
  }) async {
    if (inviteeId <= 0) throw ArgumentError.value(inviteeId, 'inviteeId');
    await _transport.pluginWriteJson(
      siteUrl: site,
      path: '${_path(id)}/invitees/$inviteeId.json',
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<void> invite(
    String site,
    int id,
    List<String> usernames, {
    required String apiKey,
    required String clientId,
  }) async {
    await _transport.pluginWriteJson(
      siteUrl: site,
      path: '${_path(id)}/invite',
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'invites': usernames},
    );
  }

  @override
  Future<String> calendar(
    String site,
    PluginRequestCredentials credentials, {
    int? eventId,
    String? attendingUser,
  }) async {
    final source = _transport;
    if (source is! PluginTextTransport) {
      throw UnsupportedError('Calendar downloads are unavailable.');
    }
    final calendar = await (source as PluginTextTransport).pluginGetText(
      siteUrl: site,
      path: Uri(
        path: '/discourse-post-event/events.ics',
        queryParameters: {
          'post_id': ?eventId?.toString(),
          'attending_user': ?attendingUser,
        },
      ).toString(),
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (!calendar.trimLeft().startsWith('BEGIN:VCALENDAR') ||
        !calendar.contains('END:VCALENDAR')) {
      throw FormatException(appL10n.invalidCalendarResponse);
    }
    if (!_eventComponent.hasMatch(calendar)) {
      throw const EmptyEventCalendarException();
    }
    return calendar;
  }
}

final _eventComponent = RegExp(r'^BEGIN:VEVENT\r?$', multiLine: true);
