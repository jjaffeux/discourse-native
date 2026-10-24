part of 'voice_controller.dart';

final class _VoiceIncomingRoomAccess implements VoiceIncomingRooms {
  _VoiceIncomingRoomAccess(this.controller);

  final VoiceController controller;

  @override
  bool Function() captureAccount(String siteUrl) =>
      controller.captureSiteSession(siteUrl);

  @override
  Future<VoiceRoom?> resolve(
    String siteUrl,
    String slug, {
    required bool Function() ifCurrent,
  }) => controller._resolveRoom(siteUrl, slug, ifCurrent: ifCurrent);

  @override
  void rememberCaller(String siteUrl, VoiceIncomingCall call) {
    controller.rememberInviteRef(
      siteUrl: siteUrl,
      roomSlug: call.roomSlug,
      username: call.caller.username.toLowerCase(),
    );
  }
}

final class _VoiceIncomingJoinAccess implements VoiceIncomingJoins {
  _VoiceIncomingJoinAccess(this.controller);

  final VoiceController controller;

  @override
  Object? get admissionIdentity => controller._calls.admissionIdentity;

  @override
  bool get hasCallOrPendingJoin =>
      controller._call != null || controller._calls.hasPendingJoin;

  @override
  bool isInRoom(String siteUrl, int roomId) {
    final call = controller._call;
    return call != null && call.siteUrl == siteUrl && call.room.id == roomId;
  }

  @override
  Future<void> join(
    VoiceIncomingCallAcceptance acceptance, {
    required String siteName,
  }) => controller.join(
    siteUrl: acceptance.siteUrl,
    siteName: siteName,
    room: acceptance.room,
  );
}

final class _VoiceIncomingSystemNavigation implements VoiceIncomingNavigation {
  _VoiceIncomingSystemNavigation(this.controller);

  final VoiceController controller;

  @override
  FutureOr<String?> prepare(VoiceIncomingCallAcceptance acceptance) {
    final privacyWarningEnabled =
        controller._meshPrivacyWarningEnabledFor?.call(acceptance.siteUrl) ??
        false;
    if (!acceptance.isCurrent) return null;
    if (privacyWarningEnabled &&
        acceptance.room.expectedTransport == VoiceTransport.mesh) {
      return _prepareWithPrivacy(acceptance);
    }
    return _finish(acceptance, warnAboutPrivacy: false);
  }

  Future<String?> _prepareWithPrivacy(
    VoiceIncomingCallAcceptance acceptance,
  ) async {
    final acknowledged = await controller.meshPrivacyAcknowledged();
    return _finish(acceptance, warnAboutPrivacy: !acknowledged);
  }

  String? _finish(
    VoiceIncomingCallAcceptance acceptance, {
    required bool warnAboutPrivacy,
  }) {
    if (!acceptance.isCurrent) return null;
    final siteUrl = acceptance.siteUrl;
    final siteName = controller._siteNameFor?.call(siteUrl) ?? siteUrl;
    if (!acceptance.isCurrent) return null;
    controller._onIncomingCallAnswered?.call(siteUrl, acceptance.room);
    if (!acceptance.isCurrent) return null;
    if (warnAboutPrivacy) {
      controller._notify(
        appL10n
            .thisCallConnectsParticipantsDirectlySoOtherParticipantsMayBeAble,
      );
    }
    return siteName;
  }
}
