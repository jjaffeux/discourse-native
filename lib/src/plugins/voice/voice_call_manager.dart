part of 'voice_controller.dart';

final class _VoicePendingJoin {
  const _VoicePendingJoin(
    this.key,
    this.siteSession,
    this.correlationId,
    this.completion,
  );
  final (String, int) key;
  final Object siteSession;
  final String correlationId;
  final Future<void> completion;
}

final class _VoiceCallManager {
  _VoiceCallManager(this.controller);
  final VoiceController controller;
  _VoiceCallSession? current;
  final Set<_VoiceCallSession> _sessions = {};
  Future<void>? _joinTail;
  _VoicePendingJoin? _pending;
  Future<void>? _closeOperation;

  Object? get admissionIdentity => _joinTail;
  bool get hasPendingJoin => _pending != null;
  String? get leavingCorrelationId =>
      current?._leaving == true ? current?.correlationId : null;
  _VoiceCallSession? forMedia(VoiceMediaSession media) {
    for (final session in _sessions) {
      if (identical(session._media, media)) return session;
    }
    return null;
  }

  bool isJoining(String siteUrl, int roomId) =>
      (_pending?.key == (siteUrl, roomId) &&
          identical(
            _pending?.siteSession,
            controller._siteSessions[siteUrl],
          )) ||
      (current?._call?.siteUrl == siteUrl &&
          current?._call?.room.id == roomId &&
          current?._call?.status == VoiceCallStatus.joining);

  Set<(String, int)> get joiningRooms => {
    if (_pending case final pending?
        when identical(
          pending.siteSession,
          controller._siteSessions[pending.key.$1],
        ))
      pending.key,
    if (current?._call case final call?
        when call.status == VoiceCallStatus.joining)
      (call.siteUrl, call.room.id),
  };

  Future<void> join({
    required String siteUrl,
    required String siteName,
    required VoiceRoom room,
  }) {
    final siteSession = controller._siteSession(siteUrl);
    final key = (siteUrl, room.id);
    final pending = _pending;
    if (pending?.key == key &&
        identical(pending?.siteSession, siteSession) &&
        pending != null) {
      controller._record(
        'call.join.coalesced',
        correlationId: pending.correlationId,
        data: controller._roomDiagnosticData(room),
      );
      return pending.completion;
    }

    final correlationId = controller._nextCallCorrelationId();
    controller._record(
      'call.join.requested',
      correlationId: correlationId,
      data: controller._roomDiagnosticData(room),
    );
    controller._recordRaw(
      'call.join.context',
      correlationId: correlationId,
      data: controller._rawRoomDiagnosticData(
        siteUrl,
        room,
        siteName: siteName,
      ),
    );
    final previousJoin = _joinTail;
    Future<void> runJoin() => controller._runPublicOperation(
      () => _runJoin(
        siteUrl: siteUrl,
        siteName: siteName,
        room: room,
        siteSession: siteSession,
        correlationId: correlationId,
      ),
      'voice.join',
      correlationId: correlationId,
    );
    final operation = controller._reporter.runOperation(
      'voice.join',
      () => previousJoin == null
          ? runJoin()
          : previousJoin.then((_) => runJoin()),
      correlationId: correlationId,
    );
    // Room taps can arrive while the preceding transport is still connecting.
    // Keep each leave/join transition atomic so a later tap cannot dispose the
    // media session that the earlier transition is still establishing.
    _joinTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_pending?.completion, tracked)) {
        _pending = null;
        if (!controller._disposed) controller._notifyCallChanged();
      }
    });
    _pending = _VoicePendingJoin(key, siteSession, correlationId, tracked);
    if (!controller._disposed) controller._notifyCallChanged();
    return tracked;
  }

  Future<void> _runJoin({
    required String siteUrl,
    required String siteName,
    required VoiceRoom room,
    required Object siteSession,
    required String correlationId,
  }) async {
    bool siteIsCurrent() =>
        controller._isCurrentSiteSession(siteUrl, siteSession);
    if (!controller.supportedPlatform || !siteIsCurrent()) {
      controller._record(
        'call.join.skipped',
        correlationId: correlationId,
        data: {
          ...controller._roomDiagnosticData(room),
          'reason': !controller.supportedPlatform
              ? 'unsupported_platform'
              : 'stale_site',
          'platform': Platform.operatingSystem,
        },
      );
      return;
    }
    controller._record(
      'call.join.started',
      correlationId: correlationId,
      data: controller._roomDiagnosticData(room),
    );
    final pendingLeave = current?._leaveOperation;
    if (pendingLeave != null) await pendingLeave;
    if (!siteIsCurrent()) return;
    final held = current?._call;
    if (held?.siteUrl == siteUrl && held?.room.id == room.id) {
      controller._record(
        'call.join.cancelled',
        correlationId: correlationId,
        data: {'reason': 'active_room_toggle'},
      );
      await leave(notifyServer: true, reason: _VoiceLeaveReason.roomToggle);
      return;
    }
    if (held != null) {
      await leave(notifyServer: true, reason: _VoiceLeaveReason.roomSwitch);
    }
    if (!siteIsCurrent()) return;
    final session = _VoiceCallSession(
      this,
      controller,
      siteUrl: siteUrl,
      siteName: siteName,
      requestedRoom: room,
      siteSession: siteSession,
      correlationId: correlationId,
    );
    current = session;
    _sessions.add(session);
    try {
      await session.start();
    } finally {
      if (session._call == null) {
        session.retire();
        release(session);
      }
    }
  }

  Future<void> leave({
    required bool notifyServer,
    required _VoiceLeaveReason reason,
    bool clearImmediately = false,
  }) {
    controller._incomingAnswer = null;
    final session = current;
    return session?.close(
          notifyServer: notifyServer,
          reason: reason,
          clearImmediately: clearImmediately,
        ) ??
        Future<void>.value();
  }

  void retire() => current?.retire();

  void release(_VoiceCallSession session) {
    unawaited(_release(session));
  }

  Future<void> _release(_VoiceCallSession session) async {
    final closing = session._leaveOperation;
    if (closing != null) await closing;
    await session.drainRequests();
    _sessions.remove(session);
    if (identical(current, session) && session._call == null) {
      current = null;
    }
  }

  Future<void> close() => _closeOperation ??= _finishClose();

  Future<void> _finishClose() async {
    retire();
    final session = current;
    if (session != null) {
      await session.close(
        notifyServer: true,
        reason: _VoiceLeaveReason.sessionClose,
      );
    }
    final tail = _joinTail;
    if (tail != null) await tail;
    final lateSession = current;
    if (lateSession != null) {
      await lateSession.close(
        notifyServer: true,
        reason: _VoiceLeaveReason.sessionClose,
      );
    }
    await Future.wait([
      for (final session in _sessions.toList()) session.drainRequests(),
    ]);
  }
}
