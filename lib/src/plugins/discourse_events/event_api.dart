import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'event_data.dart';

abstract interface class EventApi {
  /// Shared by upcoming query bounds and calendar date presentation.
  DateTime Function() get clock;

  Future<PostEvent> get(
    String site,
    int id,
    PluginRequestCredentials credentials,
  );

  Future<PostEvent?> byTopic(
    String site,
    int topicId,
    PluginRequestCredentials credentials,
  );

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
  });

  Future<List<EventInvitee>> invitees(
    String site,
    int id,
    PluginRequestCredentials credentials, {
    String? filter,
    String? type,
  });

  Future<void> respond(
    String site,
    int id, {
    required String apiKey,
    required String clientId,
    required String status,
    required bool recurring,
    int? inviteeId,
  });

  Future<void> withdraw(
    String site,
    int id,
    int inviteeId, {
    required String apiKey,
    required String clientId,
  });

  Future<void> invite(
    String site,
    int id,
    List<String> usernames, {
    required String apiKey,
    required String clientId,
  });

  Future<String> calendar(
    String site,
    PluginRequestCredentials credentials, {
    int? eventId,
    String? attendingUser,
  });
}

/// An empty server calendar would import nothing.
final class EmptyEventCalendarException implements Exception {
  const EmptyEventCalendarException();
}
