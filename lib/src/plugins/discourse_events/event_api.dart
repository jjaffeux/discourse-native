import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../data/plugin_transport.dart';
import '../../plugin_api/core_plugin_host.dart' show PluginRequestCredentials;
import 'event_data.dart';

final class EventApi {
  const EventApi(this.transport, {this.clock = DateTime.now});
  final PluginApiTransport transport;
  final DateTime Function() clock;

  String _path(int id) {
    if (id <= 0) throw ArgumentError.value(id, 'eventId');
    return '/discourse-post-event/events/$id';
  }

  Future<PostEvent> get(
    String site,
    int id,
    PluginRequestCredentials credentials,
  ) async {
    final json = await transport.pluginGetJson(
      siteUrl: site,
      path: '${_path(id)}.json',
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    final event = PostEvent.decode(json['event']);
    if (event == null || event.id != id || event.topicId == null) {
      throw const FormatException('Invalid event response');
    }
    return event;
  }

  /// Upcoming bounds use ISO timestamps, as Discourse's web calendar does.
  /// Older event controllers cannot expand occurrences with `after=now`.
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
    final json = await transport.pluginGetJson(
      siteUrl: site,
      path: path,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (json['events'] is! List) {
      throw const FormatException('Invalid event list');
    }
    return List.unmodifiable([
      for (final raw in json['events'] as List) ?PostEvent.decode(raw),
    ]);
  }

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
    final json = await transport.pluginGetJson(
      siteUrl: site,
      path: path,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    if (json['invitees'] is! List) {
      throw const FormatException('Invalid participant list');
    }
    return List.unmodifiable([
      for (final raw in json['invitees'] as List) ?EventInvitee.decode(raw),
    ]);
  }

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
    await transport.pluginWriteJson(
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

  Future<void> withdraw(
    String site,
    int id,
    int inviteeId, {
    required String apiKey,
    required String clientId,
  }) async {
    if (inviteeId <= 0) throw ArgumentError.value(inviteeId, 'inviteeId');
    await transport.pluginWriteJson(
      siteUrl: site,
      path: '${_path(id)}/invitees/$inviteeId.json',
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<void> invite(
    String site,
    int id,
    List<String> usernames, {
    required String apiKey,
    required String clientId,
  }) async {
    await transport.pluginWriteJson(
      siteUrl: site,
      path: '${_path(id)}/invite',
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'invites': usernames},
    );
  }
}
