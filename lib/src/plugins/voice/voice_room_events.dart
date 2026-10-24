part of 'voice_controller.dart';

final class _VoiceRoomEvents {
  _VoiceRoomEvents({
    required this._calls,
    required this._directoryFor,
    required this._userIdFor,
    required this._publish,
    required this._notify,
    required this._observe,
  });

  final _VoiceCallManager _calls;
  final _VoiceRoomDirectory? Function(String) _directoryFor;
  final VoiceUserIdLookup _userIdFor;
  final VoidCallback _publish;
  final void Function(String) _notify;
  final void Function(Future<void> Function()) _observe;

  VoiceCallSnapshot? get _call => _calls.current?._call;

  VoiceRoom? room(String siteUrl, int roomId) =>
      _directoryFor(siteUrl)?.room(roomId) ??
      (_call?.siteUrl == siteUrl && _call?.room.id == roomId
          ? _call?.room
          : null);

  void deliver(String siteUrl, int roomId, Object? data) {
    if (data is! Map<String, dynamic>) return;
    if (data['type'] == 'signal') {
      _observe(() => _handleSignalEnvelope(siteUrl, roomId, data));
      return;
    }
    final event = VoiceRoomEvent.fromJson(data);
    if (event == null) return;
    if (event is! VoiceKickedEvent) {
      _directoryFor(siteUrl)?.liveRoomChanged(roomId);
    }
    switch (event) {
      case VoiceKickedEvent():
        final call = _call;
        if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
          _observe(() => _calls.leave(notifyServer: false));
        }
      case VoiceRoleChangedEvent():
        final held = room(siteUrl, roomId);
        if (held != null &&
            held.participants.any(
              (participant) => participant.id == event.userId,
            )) {
          _replaceParticipants(siteUrl, roomId, [
            for (final participant in held.participants)
              participant.id == event.userId
                  ? _participantWithRole(participant, event.role)
                  : participant,
          ]);
        }
        if (event.userId == _userIdFor(siteUrl) &&
            _call?.siteUrl == siteUrl &&
            _call?.room.id == roomId) {
          _notify(
            event.role == VoiceRole.participant
                ? appL10n.youVeBeenMovedToListeners
                : appL10n.youVeBeenMadeASpeaker,
          );
        }
      case VoiceHandRaiseEvent():
        _applyHandRaise(siteUrl, roomId, event);
      case VoiceRingingEvent():
        updateRoom(siteUrl, roomId, (room) => room.withRinging(event.entry));
        _publish();
      case VoiceParticipantsEvent():
        _replaceParticipants(siteUrl, roomId, event.participants);
      case VoiceRecordingEvent():
        final wasRecording = room(siteUrl, roomId)?.recording?.active ?? false;
        updateRoom(
          siteUrl,
          roomId,
          (room) => room.withRecording(event.recording),
        );
        _publish();
        final call = _call;
        if (call?.siteUrl == siteUrl && call?.room.id == roomId) {
          final recording = event.recording;
          if (recording != null && recording.active) {
            if (recording.startedById != _userIdFor(siteUrl)) {
              _notify(appL10n.thisCallIsNowBeingRecorded);
            }
          } else if (wasRecording) {
            _notify(appL10n.theRecordingHasStopped);
          }
        }
    }
  }

  void _applyHandRaise(String siteUrl, int roomId, VoiceHandRaiseEvent event) {
    final userId = _userIdFor(siteUrl);
    updateRoom(siteUrl, roomId, (room) {
      if (!room.participants.any((p) => p.id == event.userId)) return room;
      return room.withParticipants([
        for (final participant in room.participants)
          participant.id == event.userId
              ? _participantWithHandRaised(
                  participant,
                  event.raised ? (event.raisedAt ?? DateTime.now()) : null,
                )
              : participant,
      ]);
    });
    final call = _call;
    final inCall =
        call != null && call.siteUrl == siteUrl && call.room.id == roomId;
    final held = inCall ? call.room : room(siteUrl, roomId);
    if (inCall && event.userId == userId) {
      if (!event.raised && event.reason == 'dismissed') {
        _notify(appL10n.yourRequestToSpeakWasDismissed);
      }
    } else if (inCall && event.raised && (held?.canManage ?? false)) {
      final raiser = held?.participants
          .where((participant) => participant.id == event.userId)
          .firstOrNull;
      if (raiser != null) {
        _notify(
          appL10n.raisedTheirHandToSpeak(
            (raiser.name ?? raiser.username).toString(),
          ),
        );
      }
    }
    _publish();
  }

  Future<void> _handleSignalEnvelope(
    String siteUrl,
    int roomId,
    Map<String, dynamic> envelope,
  ) async {
    final senderId = liveRefreshId(envelope['sender_id']);
    if (senderId == null) return;

    final events = <Map<String, dynamic>>[];
    final rawEvents = envelope['events'];
    if (rawEvents is Iterable) {
      for (final value in rawEvents.take(25)) {
        if (value is Map) events.add(Map<String, dynamic>.from(value));
      }
    } else {
      final legacyEvent = envelope['data'];
      if (legacyEvent is Map) {
        events.add(Map<String, dynamic>.from(legacyEvent));
      }
    }
    final call = _call;

    if (call == null ||
        call.siteUrl != siteUrl ||
        call.room.id != roomId ||
        events.isEmpty) {
      return;
    }
    final activeCall = call;

    // Voice attests the sender and includes their basic serialization so an
    // offer can beat the asynchronous roster broadcast without creating an
    // invisible peer. Stage rooms still wait for the authoritative roster,
    // because the basic serialization does not carry the sender's stage role.
    if (activeCall.room.type == VoiceRoomType.open &&
        events.any((event) => event['type'] == 'offer') &&
        !activeCall.room.participants.any(
          (participant) => participant.id == senderId,
        )) {
      final rawSender = envelope['sender'];
      if (rawSender is Map) {
        final participant = VoiceParticipant.fromJson(
          Map<String, dynamic>.from(rawSender),
        );
        if (participant.id == senderId) {
          final participants = canonicalVoiceParticipants([
            ...activeCall.room.participants,
            participant,
          ]);
          _directoryFor(siteUrl)?.updateListedRoom(
            roomId,
            (room) => room.withParticipants(participants),
          );
          if (identical(_call?.media, activeCall.media)) {
            _calls.current?.updateRoom(
              (room) => room.withParticipants(participants),
            );
            _publish();
            await activeCall.media.syncParticipants(participants);
          }
        }
      }
    }

    if (!identical(_call?.media, activeCall.media)) return;
    for (final event in events) {
      await activeCall.media.handleSignal(senderId, event);
    }
  }

  static VoiceParticipant _participantWithRole(
    VoiceParticipant participant,
    VoiceRole role,
  ) => VoiceParticipant(
    id: participant.id,
    username: participant.username,
    externalAgent: participant.externalAgent,
    livekitIdentity: participant.livekitIdentity,
    role: role,
    name: participant.name,
    avatarTemplate: participant.avatarTemplate,
    muted: participant.muted,
    deafened: participant.deafened,
    videoOn: participant.videoOn,
    screenSharing: participant.screenSharing,
    watchingVideo: participant.watchingVideo,
    idleState: participant.idleState,
    handRaisedAt: participant.handRaisedAt,
  );

  static VoiceParticipant _participantWithHandRaised(
    VoiceParticipant participant,
    DateTime? handRaisedAt,
  ) => VoiceParticipant(
    id: participant.id,
    username: participant.username,
    externalAgent: participant.externalAgent,
    livekitIdentity: participant.livekitIdentity,
    role: participant.role,
    name: participant.name,
    avatarTemplate: participant.avatarTemplate,
    muted: participant.muted,
    deafened: participant.deafened,
    videoOn: participant.videoOn,
    screenSharing: participant.screenSharing,
    watchingVideo: participant.watchingVideo,
    idleState: participant.idleState,
    handRaisedAt: handRaisedAt,
  );

  void updateRoom(
    String siteUrl,
    int roomId,
    VoiceRoom Function(VoiceRoom room) update, {
    bool updateCall = true,
  }) {
    _directoryFor(siteUrl)?.updateRoom(roomId, update);
    final call = _call;
    if (updateCall &&
        call != null &&
        call.siteUrl == siteUrl &&
        call.room.id == roomId) {
      _calls.current?.updateRoom(update);
    }
  }

  void _replaceParticipants(
    String siteUrl,
    int roomId,
    List<VoiceParticipant> participants,
  ) {
    updateRoom(
      siteUrl,
      roomId,
      (room) => room.withParticipants(participants),
      updateCall: false,
    );
    if (_calls.current case final session?) {
      session.receiveParticipants(siteUrl, roomId, participants);
    } else {
      _publish();
    }
  }
}
