import '../../data/plugin_transport.dart';
import 'resenha_models.dart';

/// Typed client for the Resenha plugin's existing JSON contract.
final class ResenhaApi {
  const ResenhaApi(this._transport);

  final PluginApiTransport _transport;

  Future<ResenhaDirectory> rooms({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => ResenhaDirectory.fromJson(
    await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/resenha/rooms.json',
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  Future<ResenhaRoom> room({
    required String siteUrl,
    required String slug,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/resenha/rooms/${Uri.encodeComponent(slug)}.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    return ResenhaRoom.fromJson(
      body['room'] is Map<String, dynamic>
          ? body['room'] as Map<String, dynamic>
          : body,
    );
  }

  Future<ResenhaJoinResponse> join({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    bool skipStatus = false,
    String? participantSessionId,
    String? clientId,
  }) async => ResenhaJoinResponse.fromJson(
    await _write(siteUrl, '/resenha/rooms/$roomId/join.json', 'POST', apiKey, {
      'skip_status': skipStatus ? true : null,
      'participant_session_id': participantSessionId,
    }, clientId),
  );

  Future<void> heartbeat({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    ResenhaIdleState idle = ResenhaIdleState.active,
    String? participantSessionId,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/heartbeat.json',
    'POST',
    apiKey,
    {
      'idle_state': idle.wireName,
      'participant_session_id': participantSessionId,
    },
    clientId,
  );

  Future<void> leave({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    String? participantSessionId,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/leave.json',
    'DELETE',
    apiKey,
    {'participant_session_id': participantSessionId},
    clientId,
  );

  Future<List<ResenhaParticipant>> participants({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/resenha/rooms/$roomId/participants.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    final raw = body['participants'];
    return List.unmodifiable([
      if (raw is List)
        for (final value in raw)
          if (value is Map<String, dynamic>) ResenhaParticipant.fromJson(value),
    ]);
  }

  Future<void> signal({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    required Map<String, Object?> payload,
    String? participantSessionId,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/signal.json',
    'POST',
    apiKey,
    {'payload': payload, 'participant_session_id': participantSessionId},
    clientId,
  );

  Future<void> state({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    bool? muted,
    bool? deafened,
    bool? video,
    bool? screen,
    bool? watching,
    String? participantSessionId,
    String? clientId,
  }) =>
      _voidWrite(siteUrl, '/resenha/rooms/$roomId/state.json', 'POST', apiKey, {
        'muted': muted,
        'deafened': deafened,
        'video': video,
        'screen': screen,
        'watching': watching,
        'participant_session_id': participantSessionId,
      }, clientId);

  Future<ResenhaLiveKitCredentials> livekitToken({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    String? clientId,
  }) async => ResenhaLiveKitCredentials.fromJson(
    await _write(
      siteUrl,
      '/resenha/rooms/$roomId/livekit_token.json',
      'POST',
      apiKey,
      const {},
      clientId,
    ),
  );

  Future<ResenhaChatSession> chatSession({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    bool ensure = false,
    String? clientId,
  }) async => ResenhaChatSession.fromJson(
    ensure
        ? await _write(
            siteUrl,
            '/resenha/rooms/$roomId/chat_session.json',
            'POST',
            apiKey,
            const {},
            clientId,
          )
        : await _transport.pluginGetJson(
            siteUrl: siteUrl,
            path: '/resenha/rooms/$roomId/chat_session.json',
            apiKey: apiKey,
            clientId: clientId,
          ),
  );

  Future<ResenhaChatSession> firstChatMessage({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    required String message,
    String? clientId,
  }) async => ResenhaChatSession.fromJson(
    await _write(
      siteUrl,
      '/resenha/rooms/$roomId/chat_message.json',
      'POST',
      apiKey,
      {'message': message},
      clientId,
    ),
  );

  Future<ResenhaRoom> createRoom({
    required String siteUrl,
    required String apiKey,
    required ResenhaRoomDraft draft,
    String? clientId,
  }) async => _roomFromWrite(
    await _write(siteUrl, '/resenha/rooms.json', 'POST', apiKey, {
      'room': draft.toJson(),
    }, clientId),
  );

  Future<ResenhaRoom> updateRoom({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    required ResenhaRoomDraft draft,
    String? clientId,
  }) async => _roomFromWrite(
    await _write(siteUrl, '/resenha/rooms/$roomId.json', 'PUT', apiKey, {
      'room': draft.toJson(),
    }, clientId),
  );

  Future<void> deleteRoom({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId.json',
    'DELETE',
    apiKey,
    const {},
    clientId,
  );

  Future<List<ResenhaMembership>> memberships({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/resenha/rooms/$roomId/memberships.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    final raw = body['memberships'];
    return List.unmodifiable([
      if (raw is List)
        for (final value in raw)
          if (value is Map<String, dynamic>) ResenhaMembership.fromJson(value),
    ]);
  }

  Future<void> addMembership({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    int? userId,
    String? username,
    required ResenhaRole role,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/memberships.json',
    'POST',
    apiKey,
    {'user_id': userId, 'username': username, 'role': role.wireName},
    clientId,
  );

  Future<void> updateMembership({
    required String siteUrl,
    required int roomId,
    required int membershipId,
    required String apiKey,
    required ResenhaRole role,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/memberships/$membershipId.json',
    'PUT',
    apiKey,
    {'role': role.wireName},
    clientId,
  );

  Future<void> removeMembership({
    required String siteUrl,
    required int roomId,
    required int membershipId,
    required String apiKey,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/memberships/$membershipId.json',
    'DELETE',
    apiKey,
    const {},
    clientId,
  );

  Future<void> requestToSpeak({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    bool raised = true,
    int? userId,
    String? participantSessionId,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/request_to_speak.json',
    raised ? 'POST' : 'DELETE',
    apiKey,
    {'user_id': userId, 'participant_session_id': participantSessionId},
    clientId,
  );

  Future<void> kick({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    required int userId,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/kick.json',
    'DELETE',
    apiKey,
    {'user_id': userId},
    clientId,
  );

  Future<void> flag({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    required int userId,
    required int flagTypeId,
    required String message,
    String? clientId,
  }) => _voidWrite(
    siteUrl,
    '/resenha/rooms/$roomId/flag.json',
    'POST',
    apiKey,
    {'user_id': userId, 'flag_type_id': flagTypeId, 'message': message},
    clientId,
  );

  Future<int?> notifyModeratorsFlagType({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: '/site.json',
      apiKey: apiKey,
      clientId: clientId,
    );
    final types = body['post_action_types'];
    if (types is! List) return null;
    for (final value in types) {
      if (value is Map<String, dynamic> &&
          value['name_key'] == 'notify_moderators') {
        final id = value['id'];
        if (id is num) return id.toInt();
        if (id is String) return int.tryParse(id);
      }
    }
    return null;
  }

  Future<ResenhaRecording?> setRecording({
    required String siteUrl,
    required int roomId,
    required String apiKey,
    required bool active,
    String? clientId,
  }) async {
    final body = await _write(
      siteUrl,
      '/resenha/rooms/$roomId/recording.json',
      active ? 'POST' : 'DELETE',
      apiKey,
      const {},
      clientId,
    );
    final recording = body['recording'];
    return recording is Map<String, dynamic>
        ? ResenhaRecording.fromJson(recording)
        : null;
  }

  Future<Map<String, dynamic>> _write(
    String siteUrl,
    String path,
    String method,
    String apiKey,
    Map<String, Object?> body,
    String? clientId,
  ) => _transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  Future<void> _voidWrite(
    String siteUrl,
    String path,
    String method,
    String apiKey,
    Map<String, Object?> body,
    String? clientId,
  ) async {
    await _write(siteUrl, path, method, apiKey, body, clientId);
  }

  static ResenhaRoom _roomFromWrite(Map<String, dynamic> body) =>
      ResenhaRoom.fromJson(
        body['room'] is Map<String, dynamic>
            ? body['room'] as Map<String, dynamic>
            : body,
      );
}
