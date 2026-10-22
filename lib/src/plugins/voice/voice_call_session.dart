part of 'voice_controller.dart';

final class _VoiceCallSession {
  _VoiceCallSession(
    this.manager,
    this.controller, {
    required this.siteUrl,
    required this.siteName,
    required this.requestedRoom,
    required this.siteSession,
    required this.correlationId,
  }) {
    _idleTracker = VoiceIdleTracker(
      thresholds: _activeIdleThresholds,
      onStateChanged: _onIdleStateChanged,
      onAutoMute: _onIdleAutoMute,
      onDisconnect: _onIdleDisconnect,
      clock: controller._idleClock,
      timerFactory: controller._timerFactory,
    );
  }

  final _VoiceCallManager manager;
  final VoiceController controller;
  final String siteUrl;
  final String siteName;
  final VoiceRoom requestedRoom;
  final Object siteSession;
  final String correlationId;
  VoiceCallSnapshot? _call;
  VoiceMediaSession? _media;
  String? _participantSessionId;
  bool _serverJoinActive = false;
  VoiceSignalBatcher? _signals;
  _VoiceMediaView? _mediaViewSeen;
  Future<void>? _mediaDisposal;
  Future<void>? _membershipLeave;
  Future<void>? _startOperation;
  Future<void>? _leaveOperation;
  bool _leaving = false;
  bool? _notifyServerOnClose;
  bool _retired = false;
  final Completer<void> _retirement = Completer<void>();
  Timer? _heartbeat;
  Future<void>? _heartbeatRequest;
  bool _heartbeatPending = false;
  Future<void>? _stateSync;
  Timer? _stateRetry;
  bool _stateSyncPending = false;
  late final VoiceIdleTracker _idleTracker;
  VoiceIdleState _idleState = VoiceIdleState.active;
  final SerialOperationQueue _cameraOperations = SerialOperationQueue();
  int _cameraRevision = 0;
  ({VoiceMediaSession media, int revision, bool remember})? _startingCamera;
  _VoiceCameraRestore? _cameraRestore;
  final Map<int, Object> _participantVolumeRevisions = {};

  bool get isActive =>
      !_retired &&
      identical(manager.current, this) &&
      controller._isCurrentSiteSession(siteUrl, siteSession);
  bool get cameraStarting =>
      _startingCamera?.media == _call?.media &&
      _startingCamera != null &&
      _startingCamera?.revision == _cameraRevision;

  void invalidateCamera() => _cameraRevision++;
  void acknowledgeUnmute() => _idleTracker.wasAutoMuted = false;
  void claimParticipantVolume(int userId) =>
      _participantVolumeRevisions[userId] = Object();
  void dismissError() => _call = _call?.copyWith(clearError: true);
  void updateRoom(VoiceRoom Function(VoiceRoom) update) {
    final call = _call;
    if (call != null) _call = call.copyWith(room: update(call.room));
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _retirement.complete();
    invalidateCamera();
    _signals?.close();
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatPending = false;
    _stateRetry?.cancel();
    _stateRetry = null;
    _stateSyncPending = false;
    _idleTracker.stop();
    _idleState = VoiceIdleState.active;
  }

  Future<void> drainRequests() async {
    final state = _stateSync;
    final heartbeat = _heartbeatRequest;
    if (state != null) await state;
    if (heartbeat != null) await heartbeat;
  }

  Future<void> _leaveMembership({required String apiKey, String? clientId}) {
    final active = _membershipLeave;
    if (active != null) return active;
    if (_notifyServerOnClose == false) return Future<void>.value();
    final completion = Completer<void>();
    _membershipLeave = completion.future;
    unawaited(
      Future<void>.sync(
        () => controller.api.leave(
          siteUrl: siteUrl,
          roomId: requestedRoom.id,
          apiKey: apiKey,
          clientId: clientId,
          participantSessionId: _participantSessionId,
        ),
      ).then(completion.complete, onError: completion.completeError),
    );
    return completion.future;
  }

  Future<void> disposeMedia(String operation) {
    final active = _mediaDisposal;
    if (active != null) return active;
    _signals?.close();
    final media = _media;
    if (media == null) return Future<void>.value();
    final completion = Completer<void>();
    _mediaDisposal = completion.future;
    try {
      media.removeListener(_mediaChanged);
    } catch (error, stackTrace) {
      controller._report(error, stackTrace, 'voice.media.removeListener');
    }
    unawaited(
      controller._runHandled(media.dispose, operation).then((_) {
        if (!completion.isCompleted) completion.complete();
      }),
    );
    return completion.future;
  }

  Future<void> start() => _startOperation ??= _start();

  Future<void> _start() async {
    final room = requestedRoom;
    bool isCurrent() => isActive;
    // Push to talk and the saved devices are restored asynchronously; a join
    // that raced the restore would open the microphone of a user who chose to
    // speak only while holding Space.
    await Future.any<void>([
      controller._devicePreferencesLoaded,
      _retirement.future,
    ]);
    if (!isCurrent()) return;
    final credentials = await controller._requestCredentials(
      siteUrl,
      ifCurrent: isCurrent,
    );
    final userId = controller._userIdFor(siteUrl);
    if (credentials == null || userId == null || !isCurrent()) {
      controller._record(
        'call.join.skipped',
        correlationId: correlationId,
        data: {
          'reason': !isCurrent()
              ? 'cancelled'
              : credentials == null
              ? 'missing_api_key'
              : 'missing_user_id',
        },
      );
      return;
    }
    controller._setSiteError(siteUrl, null);
    final apiKey = credentials.apiKey!;
    final clientId = credentials.clientId;
    final invitedBy = controller._consumeInviteRef(siteUrl, room);
    VoiceMediaSession? media;
    try {
      late VoiceJoinResponse response;
      try {
        controller._record(
          'call.join.server_request.started',
          correlationId: correlationId,
          data: {'roomId': room.id},
        );
        response = await credentials.run(
          () => controller.api.join(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            skipStatus: !controller._autoStatusEnabled,
            invitedBy: invitedBy,
            clientId: clientId,
          ),
        );
      } on WriteException catch (error) {
        if (error.failure != WriteFailure.rateLimited) rethrow;
        controller._record(
          'call.join.server_request.rate_limited',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          data: {
            'retryAfterMilliseconds':
                (error.retryAfter ?? const Duration(seconds: 1)).inMilliseconds,
          },
        );
        // A 429 is the one write failure that is safe to retry: Discourse
        // rejected it before the room mutation ran. Native user API keys share
        // a site-wide request budget, so a room switch can legitimately land
        // behind ordinary app refreshes or WebRTC signaling.
        await Future<void>.delayed(
          (error.retryAfter ?? const Duration(seconds: 1)) +
              const Duration(milliseconds: 150),
        );
        if (!isCurrent()) return;
        response = await credentials.run(
          () => controller.api.join(
            siteUrl: siteUrl,
            roomId: room.id,
            apiKey: apiKey,
            skipStatus: !controller._autoStatusEnabled,
            invitedBy: invitedBy,
            clientId: clientId,
          ),
        );
      }
      _participantSessionId = response.participantSessionId;
      _serverJoinActive = true;
      if (!isCurrent()) {
        await controller._runHandled(
          () => _leaveMembership(apiKey: apiKey, clientId: clientId),
          'voice.leaveSupersededJoin',
        );
        _serverJoinActive = false;
        return;
      }
      controller._record(
        'call.join.server_request.completed',
        correlationId: correlationId,
        data: {
          'transport': response.transport.name,
          'participantCount': response.room.participants.length,
        },
      );
      controller._recordRoster(
        'call.join.initial_roster',
        siteUrl,
        room.id,
        response.room.participants,
        correlationId: correlationId,
      );
      final signalBatcher = _signals = VoiceSignalBatcher(
        batchDelay: controller.signalBatchDelay,
        sendBatch: (payload) async {
          await controller._reporter.runOperation(
            'voice.signal',
            () => controller.api.signal(
              siteUrl: siteUrl,
              roomId: room.id,
              apiKey: apiKey,
              payload: payload,
              participantSessionId: _participantSessionId,
              clientId: clientId,
            ),
            correlationId: correlationId,
          );
        },
      );
      VoiceMediaSession? callbackMedia;
      bool mediaIsCurrent() =>
          isCurrent() &&
          callbackMedia != null &&
          identical(_call?.media, callbackMedia);
      media = controller.mediaFactory.create(
        join: response,
        localUserId: userId,
        sendSignal: (recipientId, event) async {
          if (!mediaIsCurrent()) return;
          controller._record(
            'signaling.send.started',
            component: 'signaling',
            correlationId: correlationId,
            data: {
              'roomId': room.id,
              'recipientPresent': true,
              'type': _voiceSignalingDiagnosticType(event['type']),
            },
          );
          controller._recordRaw(
            'signaling.send.raw',
            component: 'signaling',
            correlationId: correlationId,
            data: {
              'siteUrl': siteUrl,
              'roomId': room.id,
              'recipientId': recipientId,
              'signal': event,
            },
          );
          try {
            await signalBatcher.send(recipientId, event);
            controller._record(
              'signaling.send.completed',
              component: 'signaling',
              correlationId: correlationId,
            );
          } catch (error, stackTrace) {
            controller._record(
              'signaling.send.failed',
              component: 'signaling',
              correlationId: correlationId,
              severity: DiagnosticSeverity.warning,
              data: {'errorType': error.runtimeType.toString()},
            );
            controller._recordRaw(
              'signaling.send.failure_detail',
              component: 'signaling',
              correlationId: correlationId,
              severity: DiagnosticSeverity.warning,
              message: error.toString(),
              data: {
                'recipientId': recipientId,
                'stackTrace': stackTrace.toString(),
              },
            );
            rethrow;
          }
        },
        refreshLiveKitCredentials: () async {
          final fallback = response.livekit;
          if (fallback == null) {
            throw StateError('LiveKit credentials are unavailable.');
          }
          if (!mediaIsCurrent()) return fallback;
          controller._record(
            'livekit.credentials.refresh.requested',
            component: 'livekit',
            correlationId: correlationId,
            data: {'roomId': room.id},
          );
          final refreshCredentials = await controller._requests.credentialsFor(
            siteUrl,
          );
          if (!mediaIsCurrent()) return fallback;
          final refreshed = await controller._reporter.runOperation(
            'voice.livekitToken',
            () => controller.api.livekitToken(
              siteUrl: siteUrl,
              roomId: room.id,
              apiKey: apiKey,
              clientId: refreshCredentials.clientId,
            ),
            correlationId: correlationId,
          );
          if (refreshed.participantSessionId case final renewed?) {
            _participantSessionId = renewed;
          }
          controller._record(
            'livekit.credentials.refresh.received',
            component: 'livekit',
            correlationId: correlationId,
          );
          return mediaIsCurrent() ? refreshed : fallback;
        },
        diagnostics: controller.diagnostics,
        correlationId: correlationId,
      );
      _media = media;
      callbackMedia = media;
      controller._record(
        'media.session.created',
        component: 'media',
        correlationId: correlationId,
        data: {'transport': media.transport.name},
      );
      final joinedRoom = VoiceController._mergeRoom(
        controller.room(siteUrl, room.id) ?? room,
        response.room,
      );
      // Push to talk speaks only while Space is held, so it joins muted even
      // where the room would let the user speak.
      final initiallyMuted =
          controller._pushToTalkEnabled ||
          !VoiceController._canPublishAudio(
            joinedRoom,
            joinedRoom.participants,
            userId,
          );
      await media.setMuted(initiallyMuted);
      if (!isCurrent()) {
        controller._record(
          'call.join.cancelled',
          correlationId: correlationId,
          data: {'reason': 'cancelled_after_media_creation'},
        );
        await controller._runHandled(
          () => _leaveMembership(apiKey: apiKey, clientId: clientId),
          'voice.leaveCancelledJoin',
        );
        _serverJoinActive = false;
        await disposeMedia('voice.media.disposeAfterCancelledJoin');
        return;
      }
      _mediaViewSeen = VoiceController._mediaView(media);
      media.addListener(_mediaChanged);
      controller._incomingRoomJoined(siteUrl, room.id);
      final roomResponse = controller
          ._roomDirectory(siteUrl)
          .acceptWrite(response.room);
      _call = VoiceCallSnapshot(
        siteUrl: siteUrl,
        siteName: siteName,
        room: VoiceController._mergeRoom(
          controller.room(siteUrl, room.id) ?? room,
          roomResponse,
        ),
        status: VoiceCallStatus.joining,
        media: media,
        muted: initiallyMuted,
      );
      _restoreParticipantVolumes(_call!);
      if (controller.systemCall
          case final NativeVoiceSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(correlationId);
      }
      controller._record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': null,
          'to': VoiceCallStatus.joining.name,
          'transport': media.transport.name,
        },
      );
      controller._onCallSiteChanged();
      controller.attachTracker(siteUrl);
      controller._notifyCallChanged();
      if (!isCurrent()) return;
      controller._record(
        'callkit.command.requested',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'start'},
      );
      await controller.systemCall.start(
        roomName: room.name,
        siteName: siteName,
      );
      controller._record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'start'},
      );
      if (!isCurrent()) return;
      controller._record(
        'media.connect.started',
        component: 'media',
        correlationId: correlationId,
      );
      await media.connect();
      controller._record(
        'media.connect.completed',
        component: 'media',
        correlationId: correlationId,
      );
      if (!isCurrent()) return;
      if (controller._audioInputDeviceId case final deviceId?) {
        await controller._selectSavedAudioDevice(
          kind: 'audio_input',
          deviceId: deviceId,
          correlationId: correlationId,
          selectDevice: media.selectAudioInput,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return;
      }
      if (controller._audioOutputDeviceId case final deviceId?) {
        await controller._selectSavedAudioDevice(
          kind: 'audio_output',
          deviceId: deviceId,
          correlationId: correlationId,
          selectDevice: media.selectAudioOutput,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return;
      }
      _call = _call?.copyWith(
        status: VoiceCallStatus.connected,
        clearError: true,
      );
      controller._record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': VoiceCallStatus.joining.name,
          'to': VoiceCallStatus.connected.name,
        },
      );
      await _requestStateSync();
      if (!isCurrent()) return;
      if (initiallyMuted) {
        await controller.systemCall.setMuted(true);
        if (!isCurrent()) return;
      }
      await controller.systemCall.connected();
      controller._record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'connected'},
      );
      if (!isCurrent()) return;
      _startHeartbeat();
      _idleTracker.start();
      controller._record(
        'call.join.completed',
        correlationId: correlationId,
        data: {
          ...controller._roomDiagnosticData(response.room),
          'transport': response.transport.name,
        },
      );
      controller._notifyCallChanged();
      _restorePreferredCamera();
    } catch (error, stackTrace) {
      if (media != null) {
        await disposeMedia('voice.media.disposeAfterJoin');
      }
      if (_serverJoinActive) {
        await controller._runHandled(
          () => _leaveMembership(apiKey: apiKey, clientId: clientId),
          'voice.leaveFailedJoin',
        );
      }
      if (!isCurrent()) return;
      controller._record(
        'call.join.failed',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        data: {'errorType': error.runtimeType.toString()},
      );
      controller._recordRaw(
        'call.join.failure_detail',
        correlationId: correlationId,
        severity: DiagnosticSeverity.error,
        message: error.toString(),
        data: {'stackTrace': stackTrace.toString()},
      );
      await controller._runHandled(
        controller.systemCall.failed,
        'voice.systemCall.failed',
      );
      if (controller.systemCall
          case final NativeVoiceSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(null);
      }
      if (isCurrent()) {
        _call = null;
        if (_serverJoinActive) {
          controller._removeLocalParticipant(siteUrl, room.id);
        }
        controller._setSiteError(siteUrl, _joinFailureMessage(error, room));
        controller._onCallSiteChanged();
        controller._notifyCallChanged();
      }
      if (isCurrent()) controller._report(error, stackTrace, 'voice.join');
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeatPending = false;
    controller._recordRaw(
      'heartbeat.started',
      component: 'heartbeat',
      correlationId: correlationId,
      data: {
        'intervalMilliseconds': controller.heartbeatInterval.inMilliseconds,
      },
    );
    _scheduleHeartbeat();
  }

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    if (controller._disposed ||
        _retired ||
        _call?.status != VoiceCallStatus.connected) {
      return;
    }
    _heartbeat = Timer(controller.heartbeatInterval, () {
      _heartbeat = null;
      unawaited(_requestHeartbeat());
    });
  }

  Future<void> _requestHeartbeat() {
    final active = _heartbeatRequest;
    if (active != null) {
      _heartbeatPending = true;
      return active;
    }

    _heartbeat?.cancel();
    _heartbeat = null;
    late final Future<void> request;
    request = _beat().whenComplete(() {
      if (!identical(_heartbeatRequest, request)) return;
      _heartbeatRequest = null;
      if (controller._disposed ||
          _retired ||
          _call?.status != VoiceCallStatus.connected) {
        return;
      }
      if (_heartbeatPending) {
        _heartbeatPending = false;
        unawaited(_requestHeartbeat());
      } else {
        _scheduleHeartbeat();
      }
    });
    _heartbeatRequest = request;
    return request;
  }

  Future<void> _beat() async {
    final call = _call;
    if (call == null || call.status != VoiceCallStatus.connected) return;
    final siteSession = controller._siteSession(call.siteUrl);
    bool isCurrent() =>
        controller._isCurrentCall(call, siteSession) &&
        _call?.status == VoiceCallStatus.connected;
    try {
      controller._recordRaw(
        'heartbeat.requested',
        component: 'heartbeat',
        correlationId: correlationId,
        data: {
          'siteUrl': call.siteUrl,
          'roomId': call.room.id,
          'idleState': _idleState.name,
        },
      );
      final credentials = await controller._keyRequestCredentials(
        call.siteUrl,
        ifCurrent: isCurrent,
      );
      if (credentials == null) {
        if (!isCurrent()) return;
        controller._record(
          'heartbeat.credentials_missing',
          component: 'heartbeat',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
        );
        await close(
          notifyServer: false,
          reason: _VoiceLeaveReason.credentialsMissing,
        );
        return;
      }
      await controller._reporter.runOperation(
        'voice.heartbeat',
        () => credentials.run(
          () => controller.api.heartbeat(
            siteUrl: call.siteUrl,
            roomId: call.room.id,
            apiKey: credentials.apiKey!,
            idle: _idleState,
            participantSessionId: _participantSessionId,
          ),
        ),
        correlationId: correlationId,
      );
      controller._recordRaw(
        'heartbeat.completed',
        component: 'heartbeat',
        correlationId: correlationId,
      );
    } on WriteException catch (error, stackTrace) {
      if (!isCurrent()) return;
      if (VoiceController._isExpulsion(error)) {
        // The server no longer recognizes this session — it lapsed while the
        // app was cut off, the room was deleted, or access was revoked.
        // Every later beat would be refused the same way, and if nobody else
        // is in the room no roster broadcast will ever prune the local
        // user, so the call is unwound here the way the web client does.
        controller._record(
          'heartbeat.expelled',
          component: 'heartbeat',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          data: {'statusCode': error.statusCode},
        );
        controller._setSiteError(
          call.siteUrl,
          error.errors.isNotEmpty
              ? error.errors.join('\n')
              : appL10n.yourCallSessionHasExpiredRejoinTheRoomToStartA,
        );
        await close(
          notifyServer: error.statusCode != HttpStatus.notFound,
          reason: _VoiceLeaveReason.sessionExpired,
        );
        return;
      }
      controller._recordRaw(
        'heartbeat.failed',
        component: 'heartbeat',
        correlationId: correlationId,
        severity: DiagnosticSeverity.warning,
        message: error.toString(),
        data: {
          'errorType': error.runtimeType.toString(),
          'statusCode': error.statusCode,
          'stackTrace': stackTrace.toString(),
        },
      );
      controller._report(error, stackTrace, 'voice.heartbeat');
    } catch (error, stackTrace) {
      if (isCurrent()) {
        controller._recordRaw(
          'heartbeat.failed',
          component: 'heartbeat',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          message: error.toString(),
          data: {
            'errorType': error.runtimeType.toString(),
            'stackTrace': stackTrace.toString(),
          },
        );
        controller._report(error, stackTrace, 'voice.heartbeat');
      }
    }
  }

  VoiceIdleThresholds _activeIdleThresholds() {
    final call = _call;
    if (call == null) return VoiceController._defaultIdleThresholds('');
    try {
      return controller._idleThresholdsFor(call.siteUrl);
    } catch (error, stackTrace) {
      controller._report(error, stackTrace, 'voice.idle.thresholds');
      return VoiceController._defaultIdleThresholds(call.siteUrl);
    }
  }

  void _onIdleStateChanged(VoiceIdleState state, {required bool wasAutoMuted}) {
    if (controller._disposed) return;
    final call = _call;
    if (call == null || call.status == VoiceCallStatus.leaving) return;
    _idleState = state;
    controller._record(
      'idle.state_changed',
      component: 'idle',
      correlationId: correlationId,
      data: {'state': state.name, 'wasAutoMuted': wasAutoMuted},
    );
    final userId = controller._userIdFor(call.siteUrl);
    if (userId != null) {
      controller._updateRoom(
        call.siteUrl,
        call.room.id,
        (room) => room.withParticipants([
          for (final participant in room.participants)
            participant.id == userId
                ? VoiceController._participantWithIdleState(participant, state)
                : participant,
        ]),
      );
    }
    if (state == VoiceIdleState.active && wasAutoMuted && call.muted) {
      controller._notify(
        appL10n.youWereAutoMutedAfterBeingIdleUnmuteToKeepTalking,
      );
    }
    unawaited(_requestHeartbeat());
    controller._notifyCallChanged();
  }

  void _onIdleAutoMute() {
    final call = _call;
    if (controller._disposed ||
        call == null ||
        call.status == VoiceCallStatus.leaving) {
      return;
    }
    controller._record(
      'idle.auto_muted',
      component: 'idle',
      correlationId: correlationId,
      data: {'alreadyMuted': call.muted},
    );
    if (!call.muted) {
      controller._observe(
        () => _setMuted(true, syncSystem: true),
        'voice.idle.autoMute',
      );
    }
  }

  void _onIdleDisconnect() {
    final call = _call;
    if (controller._disposed ||
        call == null ||
        call.status == VoiceCallStatus.leaving) {
      return;
    }
    controller._record(
      'idle.disconnected',
      component: 'idle',
      correlationId: correlationId,
      severity: DiagnosticSeverity.warning,
    );
    controller._setSiteError(
      call.siteUrl,
      appL10n.youWereDisconnectedFromDueToInactivity(
        (call.room.name).toString(),
      ),
    );
    controller._observe(
      () => close(notifyServer: true, reason: _VoiceLeaveReason.idleDisconnect),
      'voice.idle.disconnect',
    );
  }

  void _userActed() {
    if (controller._disposed) return;
    _idleTracker.recordActivity();
  }

  Future<void> _setCameraEnabled(
    bool enabled, {
    String? deviceId,
    bool remember = false,
  }) async {
    final call = _call;
    if (controller._disposed ||
        call == null ||
        call.status == VoiceCallStatus.leaving) {
      return;
    }
    final revision = ++_cameraRevision;
    final userId = controller._userIdFor(call.siteUrl);
    final siteSession = controller._siteSession(call.siteUrl);
    bool isCurrent() =>
        controller._isCurrentCall(call, siteSession) &&
        (!enabled ||
            (revision == _cameraRevision &&
                userId != null &&
                _canPublishCamera(_call!, userId))) &&
        controller._userIdFor(call.siteUrl) == userId;
    // Turning off is deliberate even if capture or persistence is still pending.
    final saving = !enabled && remember && userId != null
        ? controller._rememberCamera(call.siteUrl, userId, false)
        : Future<void>.value();
    _startingCamera = enabled
        ? (media: call.media, revision: revision, remember: remember)
        : null;
    controller._notifyCallChanged();
    var applied = false;
    await _cameraOperations
        .run(
          owner: this,
          key: call.media,
          operation: () async {
            if (!isCurrent()) return;
            try {
              await call.media.setCameraEnabled(
                enabled,
                deviceId: deviceId ?? controller._cameraDeviceId,
                facing: deviceId == null ? controller._cameraFacing : null,
                shouldContinue: isCurrent,
              );
              if (!isCurrent()) {
                if (enabled) await call.media.setCameraEnabled(false);
                return;
              }
              applied = true;
              _call = _call!.copyWith(cameraEnabled: enabled);
              controller._notifyCallChanged();
            } catch (error, stackTrace) {
              if (isCurrent()) {
                _call = _call!.copyWith(
                  error: appL10n.theMediaSettingWasNotApplied,
                );
                controller._notifyCallChanged();
              }
              controller._report(error, stackTrace, 'voice.mediaState');
            }
          },
        )
        .whenComplete(() => _finishStartingCamera(call.media, revision));
    // Stopping capture must never wait behind a slow preference or state write.
    if (applied && isCurrent()) {
      if (enabled && remember && userId != null) {
        await controller._rememberCamera(call.siteUrl, userId, true);
      }
      if (isCurrent()) await _requestStateSync();
    }
    await saving;
  }

  void _finishStartingCamera(VoiceMediaSession media, int revision) {
    if (_startingCamera?.media != media ||
        _startingCamera?.revision != revision) {
      return;
    }
    _startingCamera = null;
    if (!controller._disposed && identical(_call?.media, media)) {
      controller._notifyCallChanged();
    }
  }

  bool _canRestoreCamera(VoiceCallSnapshot call, int userId) {
    final current = _call;
    if (controller._disposed ||
        !controller._foreground ||
        current == null ||
        !identical(current.media, call.media) ||
        controller._userIdFor(call.siteUrl) != userId ||
        current.status != VoiceCallStatus.connected ||
        !controller._isWatching(current) ||
        current.cameraEnabled ||
        current.screenSharing) {
      return false;
    }
    return _canPublishCamera(current, userId);
  }

  bool _canPublishCamera(VoiceCallSnapshot call, int userId) {
    if (!call.room.videoAllowed ||
        !call.room.videoEnabled ||
        !VoiceController._canPublishAudio(
          call.room,
          call.room.participants,
          userId,
        )) {
      return false;
    }
    final publishers = call.room.participants.where(
      (participant) =>
          participant.id != userId &&
          (participant.videoOn || participant.screenSharing),
    );
    return publishers.length < controller._videoMaxPublishersFor(call.siteUrl);
  }

  void _restorePreferredCamera() {
    if (controller._disposed) return;
    final call = _call;
    if (call == null) return;
    final pending = _cameraRestore;
    if (pending != null) {
      pending.again = true;
      return;
    }
    final userId = controller._userIdFor(call.siteUrl);
    if (userId == null || !_canRestoreCamera(call, userId)) return;
    final revision = _cameraRevision;
    final siteSession = controller._siteSession(call.siteUrl);
    bool isCurrent() =>
        revision == _cameraRevision &&
        controller._isCurrentCall(call, siteSession) &&
        _canRestoreCamera(call, userId);
    final preference = controller._cameraPreferences.putIfAbsent((
      call.siteUrl,
      userId,
    ), () => controller._readCameraPreference(call.siteUrl, userId));
    final restore = _VoiceCameraRestore();
    _cameraRestore = restore;
    unawaited(
      (() async {
            if (!await preference) return;
            await controller._devicePreferencesLoaded;
            if (!isCurrent()) return;
            await _cameraOperations
                .run(
                  owner: this,
                  key: call.media,
                  operation: () async {
                    if (!isCurrent()) return;
                    _startingCamera = (
                      media: call.media,
                      revision: revision,
                      remember: false,
                    );
                    controller._notifyCallChanged();
                    if (!isCurrent()) return;
                    await call.media.setCameraEnabled(
                      true,
                      deviceId: controller._cameraDeviceId,
                      facing: controller._cameraFacing,
                      shouldContinue: isCurrent,
                    );
                    if (!isCurrent()) {
                      await call.media.setCameraEnabled(false);
                      return;
                    }
                    _call = _call!.copyWith(cameraEnabled: true);
                    controller._notifyCallChanged();
                  },
                )
                .whenComplete(
                  () => _finishStartingCamera(call.media, revision),
                );
            if (controller._isCurrentCall(call, siteSession) &&
                revision == _cameraRevision) {
              await _requestStateSync();
            }
          })()
          .catchError((Object error, StackTrace stackTrace) {
            // An automatic attempt must leave the audio call usable without a modal.
            controller._report(error, stackTrace, 'voice.camera.restore');
          })
          .whenComplete(() {
            _cameraRestore = null;
            if (restore.again && identical(_call?.media, call.media)) {
              _restorePreferredCamera();
            }
          }),
    );
  }

  Future<void> _selectCamera(
    String? deviceId, {
    VoiceCameraFacing? facing,
  }) async {
    if (controller._disposed) return;
    final selection = controller._cameraSelection;
    final call = _call;
    final switchCamera = call != null && (call.cameraEnabled || cameraStarting);
    final remember = cameraStarting && _startingCamera!.remember;
    final revision = ++_cameraRevision;
    final userId = call == null ? null : controller._userIdFor(call.siteUrl);
    final siteSession = call == null
        ? null
        : controller._siteSession(call.siteUrl);
    bool isCurrent() =>
        call != null &&
        siteSession != null &&
        revision == _cameraRevision &&
        controller._isCurrentCall(call, siteSession) &&
        controller._userIdFor(call.siteUrl) == userId &&
        userId != null &&
        _canPublishCamera(_call!, userId);
    if (facing == null) controller._cameraDeviceId = deviceId;
    controller._cameraFacing = facing;
    _startingCamera = switchCamera
        ? (media: call.media, revision: revision, remember: remember)
        : null;
    controller._notifyCallChanged();
    final correlationId =
        controller._activeDiagnosticCorrelationId ??
        controller._reporter.newCorrelationId('voice-device');
    try {
      await controller._traceDeviceSelection(
        kind: 'camera',
        origin: 'user',
        deviceId: deviceId ?? facing!.name,
        applied: switchCamera,
        correlationId: correlationId,
        action: () async {
          if (deviceId != null) {
            await controller._persistPreference(
              () => controller._preferences.writeDevice(
                VoiceDevicePreference.camera,
                deviceId,
              ),
              'voice.preferences.camera',
            );
          }
          if (controller._disposed ||
              revision != _cameraRevision ||
              !identical(selection, controller._cameraSelection)) {
            return;
          }
          if (!switchCamera) {
            _restorePreferredCamera();
            return;
          }
          final media = call.media;
          var applied = false;
          await _cameraOperations.run(
            owner: this,
            key: media,
            operation: () async {
              if (!isCurrent()) return;
              await media.setCameraEnabled(false);
              if (!controller._isCurrentCall(call, siteSession!)) return;
              _call = _call!.copyWith(cameraEnabled: false);
              controller._notifyCallChanged();
              if (!isCurrent()) return;
              await media.setCameraEnabled(
                true,
                deviceId: deviceId,
                facing: facing,
                shouldContinue: isCurrent,
              );
              if (!isCurrent()) {
                await media.setCameraEnabled(false);
                return;
              }
              applied = true;
              _call = _call!.copyWith(cameraEnabled: true);
              controller._notifyCallChanged();
            },
          );
          if (applied && remember && isCurrent()) {
            await controller._rememberCamera(call.siteUrl, userId!, true);
          }
        },
      );
    } catch (_) {
      if (isCurrent()) {
        _call = _call!.copyWith(error: appL10n.theMediaSettingWasNotApplied);
        controller._notifyCallChanged();
      }
      rethrow;
    } finally {
      if (call != null) {
        _finishStartingCamera(call.media, revision);
        if (controller._isCurrentCall(call, siteSession!)) {
          unawaited(_requestStateSync());
        }
      }
    }
    if (!controller._disposed) controller._notifyCallChanged();
  }

  void _restoreParticipantVolumes(VoiceCallSnapshot call) {
    final siteSession = controller._siteSession(call.siteUrl);
    final localUserId = controller._userIdFor(call.siteUrl);
    final revisions = _participantVolumeRevisions;
    for (final participant in call.room.participants) {
      final userId = participant.id;
      if (userId == localUserId || revisions.containsKey(userId)) continue;
      final revision = revisions[userId] = Object();
      controller._observe(() async {
        final volume = await controller.participantVolume(
          call.siteUrl,
          call.room.id,
          userId,
        );
        // The call may have been left or replaced during the read, and a
        // slider change made meanwhile is newer than what was saved.
        if (volume == 1 ||
            !controller._isCurrentCall(call, siteSession) ||
            !identical(_participantVolumeRevisions[userId], revision)) {
          return;
        }
        await call.media.setParticipantVolume(userId, volume);
      }, 'voice.media.restoreParticipantVolume');
    }
  }

  Future<void> _updateMediaState({
    required Future<void> Function(VoiceCallSnapshot call) media,
    required VoiceCallSnapshot Function(VoiceCallSnapshot call) update,
    required VoiceCallSnapshot Function(
      VoiceCallSnapshot current,
      VoiceCallSnapshot previous,
    )
    rollback,
    Future<void> Function(VoiceCallSnapshot current)? system,
  }) async {
    if (controller._disposed) return;
    final call = _call;
    // A leaving call's media is already being released; a control that lands
    // meanwhile must not restart capture on it.
    if (call == null || call.status == VoiceCallStatus.leaving) return;
    _call = update(call);
    controller._notifyCallChanged();
    try {
      await media(call);
    } catch (error, stackTrace) {
      final current = _call;
      if (!controller._disposed &&
          current != null &&
          identical(current.media, call.media)) {
        // Roster, status, and recording updates can land while the media call
        // is in flight; restoring the pre-toggle snapshot would erase them.
        // Revert only the toggled field on the current snapshot.
        _call = rollback(
          current,
          call,
        ).copyWith(error: appL10n.theMediaSettingWasNotApplied);
        controller._notifyCallChanged();
      }
      controller._report(error, stackTrace, 'voice.mediaState');
      return;
    }

    if (controller._disposed) return;
    await _requestStateSync();
    // Toggles made while one state sync runs all resume, back to back, when
    // it drains. Each hands the platform the call's current state rather
    // than the value it set, so an earlier toggle cannot land last and
    // overturn a newer one. A call that no longer owns this media has none
    // of this toggle's state left to sync.
    final current = _call;
    if (controller._disposed ||
        system == null ||
        current == null ||
        !identical(current.media, call.media)) {
      return;
    }
    try {
      await system(current);
    } catch (error, stackTrace) {
      // The local media operation already succeeded. A platform call-control
      // sync failure must not roll it back or claim that the device rejected
      // the setting.
      controller._report(error, stackTrace, 'voice.systemCallState');
    }
  }

  Future<void> _requestStateSync() {
    _stateSyncPending = true;
    controller._recordRaw(
      'state_sync.queued',
      component: 'state',
      correlationId: correlationId,
      data: {'coalesced': _stateSync != null || _stateRetry != null},
    );
    final active = _stateSync;
    if (active != null || _stateRetry != null) {
      return active ?? Future<void>.value();
    }

    late final Future<void> operation;
    operation = _drainStateSync().whenComplete(() {
      if (identical(_stateSync, operation)) _stateSync = null;
      if (_stateSyncPending && _stateRetry == null && !controller._disposed) {
        unawaited(_requestStateSync());
      }
    });
    _stateSync = operation;
    return operation;
  }

  Future<void> _drainStateSync() async {
    while (_stateSyncPending && _stateRetry == null && !controller._disposed) {
      _stateSyncPending = false;
      final call = _call;
      if (call == null || call.status == VoiceCallStatus.leaving) return;
      final siteSession = controller._siteSession(call.siteUrl);
      bool isCurrent() => controller._isCurrentCall(call, siteSession);
      try {
        controller._recordRaw(
          'state_sync.requested',
          component: 'state',
          correlationId: correlationId,
          data: {
            'siteUrl': call.siteUrl,
            'roomId': call.room.id,
            'muted': call.muted,
            'deafened': call.deafened,
            'video': call.cameraEnabled,
            'screen': call.screenSharing,
            'watching': controller._isWatching(call),
          },
        );
        final credentials = await controller._keyRequestCredentials(
          call.siteUrl,
          ifCurrent: isCurrent,
        );
        if (credentials == null) return;
        await controller._reporter.runOperation(
          'voice.state',
          () => credentials.run(
            () => controller.api.state(
              siteUrl: call.siteUrl,
              roomId: call.room.id,
              apiKey: credentials.apiKey!,
              muted: call.muted,
              deafened: call.deafened,
              video: call.cameraEnabled,
              screen: call.screenSharing,
              watching: controller._isWatching(call),
              participantSessionId: _participantSessionId,
            ),
          ),
          correlationId: correlationId,
        );
        controller._recordRaw(
          'state_sync.completed',
          component: 'state',
          correlationId: correlationId,
        );
      } on WriteException catch (error, stackTrace) {
        if (!isCurrent()) return;
        if (error.failure != WriteFailure.rateLimited) {
          controller._report(error, stackTrace, 'voice.state');
          return;
        }
        controller._recordRaw(
          'state_sync.rate_limited',
          component: 'state',
          correlationId: correlationId,
          severity: DiagnosticSeverity.warning,
          data: {
            'retryAfterMilliseconds':
                (error.retryAfter ?? const Duration(seconds: 1)).inMilliseconds,
          },
        );
        _stateSyncPending = true;
        _stateRetry = Timer(
          (error.retryAfter ?? const Duration(seconds: 1)) +
              const Duration(milliseconds: 150),
          () {
            _stateRetry = null;
            if (!controller._disposed) unawaited(_requestStateSync());
          },
        );
      } catch (error, stackTrace) {
        if (isCurrent()) controller._report(error, stackTrace, 'voice.state');
        return;
      }
    }
  }

  void _mediaChanged() {
    if (controller._disposed) return;
    final call = _call;
    if (call != null) {
      final seen = _mediaViewSeen;
      final view = VoiceController._mediaView(call.media);
      _mediaViewSeen = view;
      if (!call.muted &&
          call.media.speakingParticipantIds.contains(
            controller._userIdFor(call.siteUrl),
          )) {
        _idleTracker.recordVoiceActivity();
      }
      var updated = call;
      final status = switch (view.connectionState) {
        VoiceMediaConnectionState.connected => VoiceCallStatus.connected,
        VoiceMediaConnectionState.reconnecting => VoiceCallStatus.reconnecting,
        VoiceMediaConnectionState.failed => VoiceCallStatus.failed,
      };
      // Only a call that has already settled takes its status from the media
      // layer. A join reaches `connected` at the end of its own sequence —
      // after the state sync, the saved devices and the platform call — and
      // the transports notify from inside `connect()`, so letting media
      // promote a `joining` call would announce the call before any of that
      // ran and would lift the guard that keeps a roster published before
      // join.json committed from tearing the call down.
      if ((status != call.status ||
              (status == VoiceCallStatus.failed &&
                  !identical(
                    seen?.connectionFailure,
                    view.connectionFailure,
                  ))) &&
          call.status != VoiceCallStatus.leaving &&
          call.status != VoiceCallStatus.joining) {
        controller._record(
          'call.status_changed',
          correlationId: correlationId,
          severity: status == VoiceCallStatus.failed
              ? DiagnosticSeverity.error
              : DiagnosticSeverity.info,
          data: {
            'from': call.status.name,
            'to': status.name,
            'mediaConnectionState': view.connectionState.name,
          },
        );
        updated = updated.copyWith(
          status: status,
          error: status == VoiceCallStatus.failed
              ? switch (view.connectionFailure) {
                  WriteException error => error.message,
                  _ => appL10n.theMediaConnectionCouldNotBeRestored,
                }
              : null,
          clearError:
              status == VoiceCallStatus.connected ||
              status == VoiceCallStatus.reconnecting,
        );
      }
      final screenShareEnded =
          updated.status != VoiceCallStatus.leaving &&
          updated.screenSharing &&
          !view.screenSharing;
      if (screenShareEnded) {
        controller._record(
          'media.screen_share.ended',
          component: 'media',
          correlationId: correlationId,
          data: {'cause': 'track_ended'},
        );
        updated = updated.copyWith(screenSharing: false);
      }
      _call = updated;
      if (view.connectionFailure case final WriteException error
          when updated.status == VoiceCallStatus.failed &&
              error.statusCode == HttpStatus.gone) {
        // The instance ended, so teardown must not leave a failed call owning
        // capture or send a leave against a replacement instance. The room's
        // existing error surface explains why the user needs to rejoin.
        controller._setSiteError(call.siteUrl, error.message);
        controller._observe(
          () => close(
            notifyServer: false,
            reason: _VoiceLeaveReason.sessionExpired,
          ),
          'voice.reconnect.instanceEnded',
        );
        return;
      }
      // A heartbeat that fires while the call is away from connected declines
      // to reschedule itself, so a recovered connection must restart the chain
      // or server presence expires and the roster prunes the local user.
      if (updated.status == VoiceCallStatus.connected &&
          call.status != VoiceCallStatus.connected) {
        _startHeartbeat();
        _restorePreferredCamera();
      }
      if (screenShareEnded) {
        unawaited(_requestStateSync());
        _restorePreferredCamera();
      }
      // Speaking, connection-quality and remote-track events arrive several
      // times a second for as long as a call lasts. This controller drives
      // the sidebar, the chat inbox and the call port, none of which reads
      // them; participant tiles listen to the media session for those. Only
      // a changed call, or media state read through it, is worth a redraw.
      if (!identical(updated, call) ||
          seen == null ||
          !VoiceController._sameMediaView(seen, view)) {
        controller._notifyCallChanged();
      }
    }
  }

  void _refreshCallRoom(String siteUrl, VoiceRoom incoming) {
    final call = _call;
    if (call == null ||
        call.siteUrl != siteUrl ||
        call.room.id != incoming.id) {
      return;
    }
    final room =
        VoiceController._mergeRoom(
          call.room,
          incoming,
          preserveRecording: true,
        ).copyWith(
          participants: call.room.participants,
          ringing: call.room.ringing,
        );
    final userId = controller._userIdFor(siteUrl);
    final couldPublishAudio =
        userId == null ||
        VoiceController._canPublishAudio(
          call.room,
          call.room.participants,
          userId,
        );
    final canPublishAudio =
        userId == null ||
        VoiceController._canPublishAudio(room, room.participants, userId);
    final canPublishVideo = canPublishAudio && room.videoAllowed;
    final stopsVideo =
        !canPublishVideo && (call.cameraEnabled || call.screenSharing);
    _call = call.copyWith(room: room, muted: canPublishAudio ? null : true);
    if (canPublishAudio != couldPublishAudio) {
      controller._observe(() async {
        // The call already shows a demoted speaker muted, so silence the
        // microphone first; the publishing change can wait behind queued
        // media work.
        if (!canPublishAudio) {
          await controller._runHandled(
            () => call.media.setMuted(true),
            'voice.media.rosterMute',
          );
        }
        await controller._runHandled(
          () => call.media.setAudioPublishingAllowed(canPublishAudio),
          'voice.media.audioPublishing',
        );
      }, 'voice.media.roomUpdate');
    }
    if (stopsVideo) {
      controller._record(
        'media.video.room_disallowed',
        component: 'media',
        correlationId: correlationId,
        data: {'roomId': room.id},
      );
      controller._observe(() async {
        if (call.cameraEnabled) await _setCameraEnabled(false);
        if (call.screenSharing) await _setScreenSharing(false);
      }, 'voice.media.roomVideoDisabled');
      controller._notify(appL10n.videoWasTurnedOffInThisRoom);
    }
  }

  Future<void> _setMuted(bool muted, {required bool syncSystem}) =>
      _updateMediaState(
        media: (call) => call.media.setMuted(muted),
        update: (call) => call.copyWith(muted: muted),
        rollback: (current, previous) =>
            current.copyWith(muted: previous.muted),
        system: syncSystem
            ? (current) => controller.systemCall.setMuted(current.muted)
            : null,
      );

  Future<void> _setDeafened(bool deafened) => _updateMediaState(
    media: (call) => call.media.setDeafened(deafened),
    update: (call) => call.copyWith(deafened: deafened),
    rollback: (current, previous) =>
        current.copyWith(deafened: previous.deafened),
  );

  Future<void> _setScreenSharing(bool enabled) async {
    _cameraRevision++;
    await _updateMediaState(
      media: (call) => call.media.setScreenShareEnabled(enabled),
      update: (call) => call.copyWith(screenSharing: enabled),
      rollback: (current, previous) =>
          current.copyWith(screenSharing: previous.screenSharing),
    );
    if (!enabled) _restorePreferredCamera();
  }

  void receiveParticipants(
    String siteUrl,
    int roomId,
    List<VoiceParticipant> participants,
  ) {
    final call = _call;
    if (call != null && call.siteUrl == siteUrl && call.room.id == roomId) {
      final userId = controller._userIdFor(siteUrl);
      // Room subscriptions are cursored from the directory load, not from the
      // join response, so a roster published before join.json committed can
      // still be delivered while the join settles. The local user's absence
      // from such a roster is not evidence of removal until the call has
      // connected.
      if (call.status != VoiceCallStatus.leaving &&
          call.status != VoiceCallStatus.joining &&
          userId != null &&
          !participants.any((participant) => participant.id == userId)) {
        controller._observe(
          () => close(
            notifyServer: false,
            clearImmediately: true,
            reason: _VoiceLeaveReason.rosterRemoval,
          ),
          'voice.rosterRemoval',
        );
        return;
      }
      var canPublishAudio = true;
      if (userId != null) {
        canPublishAudio = VoiceController._canPublishAudio(
          call.room,
          participants,
          userId,
        );
      }
      _call = call.copyWith(
        room: call.room.withParticipants(participants),
        muted: canPublishAudio ? null : true,
      );
      _restoreParticipantVolumes(_call!);
      controller._observe(() async {
        if (userId != null) {
          // The call already shows a demoted speaker muted, so silence the
          // microphone first; the publishing change can wait behind queued
          // media work.
          if (!canPublishAudio) {
            await controller._runHandled(
              () => call.media.setMuted(true),
              'voice.media.rosterMute',
            );
          }
          await controller._runHandled(
            () => call.media.setAudioPublishingAllowed(canPublishAudio),
            'voice.media.audioPublishing',
          );
        }
        await controller._runHandled(
          () => call.media.syncParticipants(participants),
          'voice.media.participants',
        );
      }, 'voice.media.participantUpdate');
    }
    controller._notifyCallChanged();
  }

  Future<void> close({
    required bool notifyServer,
    required _VoiceLeaveReason reason,
    bool clearImmediately = false,
  }) {
    controller._retireIncomingAnswer();
    final active = _leaveOperation;
    final call = _call;
    if (active != null) {
      controller._record(
        'call.leave.coalesced',
        correlationId: correlationId,
        data: {'reason': reason.name, 'clearImmediately': clearImmediately},
      );
      if (clearImmediately &&
          call != null &&
          identical(_call?.media, call.media)) {
        _call = null;
        controller._onCallSiteChanged();
        if (!controller._disposed) controller._notifyCallChanged();
      }
      return active;
    }

    final completion = Completer<void>();
    final operation = completion.future;
    _leaving = true;
    _leaveOperation = operation;
    _notifyServerOnClose = notifyServer;
    retire();
    if (call == null) {
      unawaited(_finishUnpublishedClose(completion));
      return operation;
    }
    controller._record(
      'call.leave.started',
      correlationId: correlationId,
      data: {
        ...controller._roomDiagnosticData(call.room),
        'reason': reason.name,
        'notifyServer': notifyServer,
        'clearImmediately': clearImmediately,
        'status': call.status.name,
      },
    );
    controller._recordRaw(
      'call.leave.context',
      correlationId: correlationId,
      data: {
        ...controller._rawRoomDiagnosticData(
          call.siteUrl,
          call.room,
          siteName: call.siteName,
        ),
        'reason': reason.name,
      },
    );
    _call = clearImmediately
        ? null
        : call.copyWith(status: VoiceCallStatus.leaving);
    // A delayed roster broadcast must not leave our avatar beside Join room.
    controller._removeLocalParticipant(call.siteUrl, call.room.id);
    if (!clearImmediately && call.status != VoiceCallStatus.leaving) {
      controller._record(
        'call.status_changed',
        correlationId: correlationId,
        data: {
          'from': call.status.name,
          'to': VoiceCallStatus.leaving.name,
          'reason': reason.name,
        },
      );
    }
    if (clearImmediately) controller._onCallSiteChanged();
    if (!controller._disposed) controller._notifyCallChanged();
    unawaited(
      _finishLeave(
        call,
        notifyServer: notifyServer,
        reason: reason,
        operation: operation,
        completion: completion,
      ),
    );
    return operation;
  }

  Future<void> _finishUnpublishedClose(Completer<void> completion) async {
    final mediaDisposal = disposeMedia('voice.media.disposeUnpublished');
    try {
      final start = _startOperation;
      if (start != null) {
        await controller._runHandled(() => start, 'voice.join.close');
      }
      await mediaDisposal;
      await disposeMedia('voice.media.disposeUnpublished');
    } finally {
      _leaving = false;
      if (!completion.isCompleted) completion.complete();
      manager.release(this);
    }
  }

  Future<void> _finishLeave(
    VoiceCallSnapshot call, {
    required bool notifyServer,
    required _VoiceLeaveReason reason,
    required Future<void> operation,
    required Completer<void> completion,
  }) async {
    try {
      controller._record(
        'media.dispose.started',
        component: 'media',
        correlationId: correlationId,
      );
      final mediaDisposal = disposeMedia('voice.media.dispose');
      if (notifyServer) {
        try {
          controller._record(
            'call.leave.server_request.started',
            correlationId: correlationId,
            data: {'roomId': call.room.id},
          );
          final credentials = await controller._requestCredentials(
            call.siteUrl,
          );
          if (credentials != null) {
            await controller._reporter.runOperation(
              'voice.leave',
              () => _leaveMembership(apiKey: credentials.apiKey!),
              correlationId: correlationId,
            );
            controller._record(
              'call.leave.server_request.completed',
              correlationId: correlationId,
            );
          } else {
            controller._record(
              'call.leave.server_request.skipped',
              correlationId: correlationId,
              severity: DiagnosticSeverity.warning,
              data: {'reason': 'missing_api_key'},
            );
          }
        } catch (error, stackTrace) {
          controller._record(
            'call.leave.server_request.failed',
            correlationId: correlationId,
            severity: DiagnosticSeverity.warning,
            data: {'errorType': error.runtimeType.toString()},
          );
          controller._recordRaw(
            'call.leave.server_request.failure_detail',
            correlationId: correlationId,
            severity: DiagnosticSeverity.warning,
            message: error.toString(),
            data: {'stackTrace': stackTrace.toString()},
          );
          controller._report(error, stackTrace, 'voice.leave');
        }
      } else {
        controller._record(
          'call.leave.server_request.skipped',
          correlationId: correlationId,
          data: {'reason': 'local_only'},
        );
      }

      await mediaDisposal;
      controller._record(
        'media.dispose.completed',
        component: 'media',
        correlationId: correlationId,
      );
      controller._record(
        'callkit.command.requested',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'end'},
      );
      await controller._runHandled(
        controller.systemCall.end,
        'voice.systemCall.end',
      );
      controller._record(
        'callkit.command.completed',
        component: 'callkit',
        correlationId: correlationId,
        data: {'command': 'end'},
      );
    } catch (error, stackTrace) {
      controller._report(error, stackTrace, 'voice.leave.dispose');
    } finally {
      if (identical(_leaveOperation, operation)) {
        _leaving = false;
      }
      if (identical(_call?.media, call.media)) {
        _call = null;
        try {
          controller._onCallSiteChanged();
        } catch (error, stackTrace) {
          controller._report(
            error,
            stackTrace,
            'voice.callSiteChanged.dispose',
          );
        }
      }
      controller._record(
        'call.leave.completed',
        correlationId: correlationId,
        data: {'reason': reason.name},
      );
      if (controller.systemCall
          case final NativeVoiceSystemCall nativeSystemCall) {
        nativeSystemCall.associateDiagnostics(null);
      }
      if (!controller._disposed) {
        try {
          controller._notifyCallChanged();
        } catch (error, stackTrace) {
          controller._report(error, stackTrace, 'voice.listeners.dispose');
        }
      }
      if (!completion.isCompleted) completion.complete();
      manager.release(this);
    }
  }
}
