part of 'voice_controller.dart';

extension VoiceCallReactions on VoiceController {
  VoiceReactionSession? reactionsForCall(String siteUrl, int roomId) =>
      _call?.siteUrl == siteUrl && _call?.room.id == roomId
      ? callReactions
      : null;

  VoiceReactionSession? get callReactions {
    _retireObsoleteReactions();
    final call = _call;
    final userId = call == null ? null : _userIdFor(call.siteUrl);
    if (call == null ||
        userId == null ||
        call.status != VoiceCallStatus.connected) {
      return null;
    }
    if (_reactionSession case final session?) return session;
    final siteSession = _siteSession(call.siteUrl);
    bool current() =>
        _isCurrentCall(call, siteSession) &&
        _call?.status == VoiceCallStatus.connected;
    final username = call.room.participants
        .where((participant) => participant.id == userId)
        .firstOrNull
        ?.username;
    final session = VoiceReactionSession(
      siteUrl: call.siteUrl,
      roomId: call.room.id,
      userId: userId,
      username: username ?? '',
      isCurrent: current,
      load: () async {
        final credentials = await _requestCredentials(
          call.siteUrl,
          ifCurrent: current,
        );
        if (credentials == null) return null;
        final settings = await credentials.run(
          () => api.reactionSettings(
            siteUrl: call.siteUrl,
            apiKey: credentials.apiKey!,
            clientId: credentials.clientId,
          ),
        );
        return current() ? settings : null;
      },
      send: (emoji) async {
        final credentials = await _keyRequestCredentials(
          call.siteUrl,
          ifCurrent: current,
        );
        final participantSessionId = _calls.current?._participantSessionId;
        if (credentials == null || !current() || participantSessionId == null) {
          return;
        }
        await credentials.run(
          () => api.reaction(
            siteUrl: call.siteUrl,
            roomId: call.room.id,
            apiKey: credentials.apiKey!,
            clientId: credentials.clientId,
            emoji: emoji,
            participantSessionId: participantSessionId,
          ),
        );
      },
      onError: (error) => _notify(
        error is WriteException ? error.message : appL10n.failedToSend,
      ),
      timerFactory: _timerFactory,
    );
    _reactionMedia = call.media;
    _reactionSession = session;
    unawaited(session.load());
    return session;
  }

  void _receiveReaction(String siteUrl, int roomId, Map<String, dynamic> data) {
    final call = _call;
    if (!_foreground ||
        call == null ||
        call.siteUrl != siteUrl ||
        call.room.id != roomId) {
      return;
    }
    callReactions?.receive(data);
  }

  void _retireObsoleteReactions() {
    if (_reactionSession == null) return;
    if (!identical(_reactionMedia, _call?.media) ||
        _call?.status == VoiceCallStatus.leaving ||
        _call?.status == VoiceCallStatus.failed) {
      _clearReactions();
    }
  }

  void _clearReactions() {
    _reactionSession?.dispose();
    _reactionSession = null;
    _reactionMedia = null;
  }
}
