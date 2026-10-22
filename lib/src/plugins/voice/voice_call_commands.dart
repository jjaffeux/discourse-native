part of 'voice_controller.dart';

final class _VoiceCallCommands {
  _VoiceCallCommands._(
    this.controller,
    this.call,
    this.siteSession,
    this.participantSessionId,
  );

  static _VoiceCallCommands? admit(VoiceController controller) {
    final call = controller._call;
    if (call == null) return null;
    return _VoiceCallCommands._(
      controller,
      call,
      controller._siteSession(call.siteUrl),
      controller._calls.current?._participantSessionId,
    );
  }

  final VoiceController controller;
  final VoiceCallSnapshot call;
  final Object siteSession;
  final String? participantSessionId;

  bool get _isCurrent => controller._isCurrentCall(call, siteSession);

  Future<T?> _dispatch<T>(
    Future<T> Function(PluginRequestCredentials) request, {
    required bool keyOnly,
  }) async {
    final credentials = keyOnly
        ? await controller._keyRequestCredentials(
            call.siteUrl,
            ifCurrent: () => _isCurrent,
          )
        : await controller._requestCredentials(
            call.siteUrl,
            ifCurrent: () => _isCurrent,
          );
    if (credentials == null) return null;
    return credentials.run<T?>(() async {
      if (!_isCurrent) return null;
      return request(credentials);
    });
  }

  Future<void> requestToSpeak({int? userId, required bool raised}) =>
      _dispatch<void>(
        (credentials) => controller.api.requestToSpeak(
          siteUrl: call.siteUrl,
          roomId: call.room.id,
          apiKey: credentials.apiKey!,
          userId: userId,
          raised: raised,
          participantSessionId: participantSessionId,
        ),
        keyOnly: true,
      );

  Future<void> setParticipantRole(int userId, VoiceRole role) async {
    if (userId < 0 ||
        call.room.participants.any((p) => p.id == userId && p.isAgent)) {
      return;
    }
    await _dispatch<void>(
      (credentials) => controller.api.addMembership(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: credentials.apiKey!,
        userId: userId,
        role: role,
        clientId: credentials.clientId,
      ),
      keyOnly: false,
    );
  }

  Future<void> kick(int userId) => _dispatch<void>(
    (credentials) => controller.api.kick(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      apiKey: credentials.apiKey!,
      userId: userId,
    ),
    keyOnly: true,
  );

  Future<bool> flagParticipant(int userId, String message) async {
    final text = message.trim();
    if (text.isEmpty) return false;
    final flagTypeId = await _dispatch<int?>(
      (credentials) => controller.api.notifyModeratorsFlagType(
        siteUrl: call.siteUrl,
        apiKey: credentials.apiKey!,
        clientId: credentials.clientId,
      ),
      keyOnly: false,
    );
    if (flagTypeId == null || !_isCurrent) return false;
    return await _dispatch<bool>((credentials) async {
          await controller.api.flag(
            siteUrl: call.siteUrl,
            roomId: call.room.id,
            apiKey: credentials.apiKey!,
            userId: userId,
            flagTypeId: flagTypeId,
            message: text,
          );
          return true;
        }, keyOnly: true) ??
        false;
  }

  Future<void> setRecording(bool active) async {
    await _dispatch<VoiceRecording?>(
      (credentials) => controller.api.setRecording(
        siteUrl: call.siteUrl,
        roomId: call.room.id,
        apiKey: credentials.apiKey!,
        active: active,
      ),
      keyOnly: true,
    );
  }
}
