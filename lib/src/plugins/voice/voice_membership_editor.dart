part of 'voice_controller.dart';

sealed class VoiceMembershipOpenResult {}

final class VoiceMembershipOpened extends VoiceMembershipOpenResult {
  VoiceMembershipOpened(this.editor);

  final VoiceMembershipEditor editor;
}

final class VoiceMembershipOpenFailure extends VoiceMembershipOpenResult {
  VoiceMembershipOpenFailure(this._ownsAccount);

  final bool Function() _ownsAccount;

  bool get isCurrent => _ownsAccount();
}

sealed class VoiceMembershipEditResult {}

enum VoiceMembershipEditStatus implements VoiceMembershipEditResult {
  accepted,
  refreshFailed,
  busy,
  retired,
}

final class VoiceMembershipEditRefused extends VoiceMembershipEditResult {
  VoiceMembershipEditRefused(this.message);

  final String message;
}

final class VoiceMembershipEditor extends ChangeNotifier {
  VoiceMembershipEditor._(
    this._controller,
    this._siteUrl,
    this._roomId,
    this._ownsAccount,
  );

  final VoiceController _controller;
  final String _siteUrl;
  final int _roomId;
  final bool Function() _ownsAccount;
  List<VoiceMembership> _memberships = const [];
  bool _writing = false;
  bool _retired = false;

  List<VoiceMembership> get memberships => _memberships;
  bool get isCurrent => !_retired && _ownsAccount();
  bool get available => isCurrent && !_writing;

  /// Calls [onAccepted] after the write succeeds and before roster refresh.
  Future<VoiceMembershipEditResult> add(
    String username,
    VoiceRole role, {
    VoidCallback? onAccepted,
  }) => _edit(
    (credentials) => _controller.api.addMembership(
      siteUrl: _siteUrl,
      roomId: _roomId,
      apiKey: credentials.apiKey!,
      username: username,
      role: role,
    ),
    'voice.membership.add',
    failure: appL10n.couldnTAddTheMember,
    onAccepted: onAccepted,
  );

  Future<VoiceMembershipEditResult> changeRole(
    int membershipId,
    VoiceRole role,
  ) => _edit(
    (credentials) => _controller.api.updateMembership(
      siteUrl: _siteUrl,
      roomId: _roomId,
      membershipId: membershipId,
      apiKey: credentials.apiKey!,
      role: role,
    ),
    'voice.membership.update',
    failure: appL10n.couldnTChangeTheMemberSRole,
  );

  Future<VoiceMembershipEditResult> remove(int membershipId) => _edit(
    (credentials) => _controller.api.removeMembership(
      siteUrl: _siteUrl,
      roomId: _roomId,
      membershipId: membershipId,
      apiKey: credentials.apiKey!,
    ),
    'voice.membership.remove',
    failure: appL10n.couldnTRemoveTheMember,
  );

  Future<bool> _refresh() async {
    if (!isCurrent) return false;
    final rows = await _controller._runPublicValueOperation(
      () async {
        final credentials = await _controller._keyRequestCredentials(
          _siteUrl,
          ifCurrent: () => isCurrent,
        );
        if (credentials == null) return null;
        return credentials.run(
          () => _controller.api.memberships(
            siteUrl: _siteUrl,
            roomId: _roomId,
            apiKey: credentials.apiKey!,
          ),
        );
      },
      'voice.memberships',
      fallback: null,
    );
    if (!isCurrent || rows == null) return false;
    _memberships = List.unmodifiable(rows);
    return true;
  }

  Future<VoiceMembershipEditResult> _edit(
    Future<void> Function(PluginRequestCredentials) write,
    String operation, {
    required String failure,
    VoidCallback? onAccepted,
  }) async {
    if (!isCurrent) return VoiceMembershipEditStatus.retired;
    if (_writing) return VoiceMembershipEditStatus.busy;
    _writing = true;
    try {
      notifyListeners();
      if (!isCurrent) return VoiceMembershipEditStatus.retired;
      try {
        final credentials = await _controller._keyRequestCredentials(
          _siteUrl,
          ifCurrent: () => isCurrent,
        );
        if (!isCurrent) return VoiceMembershipEditStatus.retired;
        if (credentials == null) {
          throw const WriteException(WriteFailure.forbidden);
        }
        await credentials.run(() => write(credentials));
      } catch (error, stackTrace) {
        _controller._report(error, stackTrace, operation);
        if (!isCurrent) return VoiceMembershipEditStatus.retired;
        return VoiceMembershipEditRefused(
          error is WriteException ? error.message : failure,
        );
      }
      if (!isCurrent) return VoiceMembershipEditStatus.retired;
      onAccepted?.call();
      if (!isCurrent) return VoiceMembershipEditStatus.retired;
      final refreshed = await _refresh();
      if (!isCurrent) return VoiceMembershipEditStatus.retired;
      return refreshed
          ? VoiceMembershipEditStatus.accepted
          : VoiceMembershipEditStatus.refreshFailed;
    } finally {
      _writing = false;
      if (!_retired) notifyListeners();
    }
  }

  void retire() => _retired = true;

  @override
  void dispose() {
    retire();
    super.dispose();
  }
}
