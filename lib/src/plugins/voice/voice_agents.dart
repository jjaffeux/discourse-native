// Public callback names describe the boundary rather than expose its storage.
// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'voice_models.dart';

/// Authenticated serializer data, never a client site setting or persisted grant.
final class VoiceAgentPermission {
  const VoiceAgentPermission(this.botId);

  static VoiceAgentPermission read(Map<String, dynamic> site) {
    final value = site['voice_livekit_agent_bot_id'];
    return VoiceAgentPermission(value is int && value < 0 ? value : null);
  }

  final int? botId;

  bool allows(VoiceRoom room) =>
      botId != null &&
      room.isPublic &&
      room.expectedTransport == VoiceTransport.livekit &&
      room.participants.any((participant) => participant.id > 0) &&
      !room.participants.any((participant) => participant.id == botId);
}

String? validateVoiceAgentName(String value) {
  final name = value.trim();
  if (name.isEmpty) return appL10n.enterAnAgentName;
  if (name.runes.length > 256) return appL10n.use256CharactersOrFewer;
  return null;
}

List<String> readVoiceAgentNames(Map<String, dynamic> body) =>
    List.unmodifiable({
      for (final agent in jsonObjects(body['agents']))
        if (agent['name'] case final String name)
          if (validateVoiceAgentName(name) == null) name.trim(),
    });

/// One chooser's account and room lifetime. Callbacks must also check ownership
/// after credentials resolve, before sending a request.
final class VoiceAgentInvitation extends FrameSafeNotifier {
  VoiceAgentInvitation({
    required bool Function() isCurrent,
    required Future<List<String>> Function(bool refresh) load,
    required Future<bool> Function(String name) invite,
  }) : _isCurrent = isCurrent,
       _load = load,
       _invite = invite;

  final bool Function() _isCurrent;
  final Future<List<String>> Function(bool refresh) _load;
  final Future<bool> Function(String name) _invite;
  bool _disposed = false;
  int _revision = 0;
  bool get isCurrent => !_disposed && _isCurrent();
  List<String> names = const [];
  bool loading = false;
  bool sending = false;
  bool sent = false;
  String? catalogueError;
  String? error;

  Future<void> refresh({bool force = true}) async {
    if (!isCurrent || sending || sent) return;
    final revision = ++_revision;
    loading = true;
    catalogueError = null;
    notifySafely();
    try {
      final result = await _load(force);
      if (!isCurrent || revision != _revision) return;
      names = result;
    } catch (_) {
      if (!isCurrent || revision != _revision) return;
      names = const [];
      catalogueError = appL10n.couldnTLoadDeployedAgentsYouCanTypeAName;
    } finally {
      if (isCurrent && revision == _revision) {
        loading = false;
        notifySafely();
      }
    }
  }

  Future<void> submit(String value) async {
    if (!isCurrent || sending || sent || loading) return;
    error = validateVoiceAgentName(value);
    if (error != null) {
      notifySafely();
      return;
    }
    sending = true;
    notifySafely();
    try {
      final accepted = await _invite(value.trim());
      if (!isCurrent) return;
      sent = accepted;
      if (!accepted) error = appL10n.thisInvitationIsNoLongerAvailable;
    } catch (failure) {
      if (!isCurrent) return;
      error = failure is WriteException
          ? failure.message
          : appL10n.couldnTInviteTheAgentTryAgain;
    } finally {
      if (isCurrent) {
        sending = false;
        notifySafely();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
