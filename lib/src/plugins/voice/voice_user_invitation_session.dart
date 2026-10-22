part of 'voice_controller.dart';

sealed class VoiceUserInvitationResult {}

enum VoiceUserInvitationStatus implements VoiceUserInvitationResult {
  busy,
  empty,
  retired,
}

final class VoiceUserInvitationAccepted extends VoiceUserInvitationResult {
  VoiceUserInvitationAccepted(this.result);

  final VoiceInviteResult result;
}

final class VoiceUserInvitationRefused extends VoiceUserInvitationResult {
  VoiceUserInvitationRefused(this.error);

  final Object error;
}

final class VoiceUserInvitationSession extends ChangeNotifier {
  VoiceUserInvitationSession._(
    this._controller,
    this._siteUrl,
    this._roomId,
    this._ownsAccount,
  );

  final VoiceController _controller;
  final String _siteUrl;
  final int _roomId;
  final bool Function() _ownsAccount;
  List<VoiceInviteSuggestion>? _suggestions;
  final Set<String> _invited = {};
  bool _sending = false;
  bool _retired = false;
  bool _disposed = false;
  Object? _suggestionsRequest;

  List<VoiceInviteSuggestion>? get suggestions => _suggestions;
  Set<String> get invitedUsernames => Set.unmodifiable(_invited);
  bool get sending => _sending;
  bool get isCurrent => !_retired && _ownsAccount();
  bool get available => isCurrent && !_sending;

  Future<void> loadSuggestions() async {
    if (!isCurrent) return;
    final request = Object();
    _suggestionsRequest = request;
    bool current() => isCurrent && identical(_suggestionsRequest, request);
    final suggestions = await _controller._runHandledValue(() async {
      final credentials = await _controller._requestCredentials(
        _siteUrl,
        ifCurrent: current,
      );
      if (credentials == null) return const <VoiceInviteSuggestion>[];
      return credentials.run(
        () => current()
            ? _controller.api.inviteSuggestions(
                siteUrl: _siteUrl,
                roomId: _roomId,
                apiKey: credentials.apiKey!,
                clientId: credentials.clientId,
              )
            : Future.value(const <VoiceInviteSuggestion>[]),
      );
    }, fallback: const <VoiceInviteSuggestion>[]);
    if (!current()) return;
    _suggestions = List.unmodifiable(suggestions);
    notifyListeners();
  }

  Future<VoiceUserInvitationResult> submit(List<String> usernames) async {
    if (!isCurrent) return VoiceUserInvitationStatus.retired;
    if (_sending) return VoiceUserInvitationStatus.busy;
    final names = List<String>.unmodifiable([
      for (final name in usernames)
        if (name.trim().isNotEmpty) name.trim().replaceFirst('@', ''),
    ]);
    if (names.isEmpty) return VoiceUserInvitationStatus.empty;
    _sending = true;
    try {
      notifyListeners();
      if (!isCurrent) return VoiceUserInvitationStatus.retired;
      _controller._userActed();
      final credentials = await _controller._requestCredentials(
        _siteUrl,
        ifCurrent: () => isCurrent,
      );
      if (!isCurrent) return VoiceUserInvitationStatus.retired;
      if (credentials == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final result = await credentials.run<VoiceInviteResult?>(
        () => isCurrent
            ? _controller.api.invite(
                siteUrl: _siteUrl,
                roomId: _roomId,
                apiKey: credentials.apiKey!,
                usernames: names,
                clientId: credentials.clientId,
              )
            : Future.value(null),
      );
      if (!isCurrent || result == null) {
        return VoiceUserInvitationStatus.retired;
      }
      _invited.addAll(result.invitedUsernames);
      return VoiceUserInvitationAccepted(result);
    } catch (error) {
      if (!isCurrent) return VoiceUserInvitationStatus.retired;
      return VoiceUserInvitationRefused(error);
    } finally {
      _sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  void retire() => _retired = true;

  @override
  void dispose() {
    retire();
    _disposed = true;
    super.dispose();
  }
}
