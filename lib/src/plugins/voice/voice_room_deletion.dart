part of 'voice_controller.dart';

extension VoiceRoomDeletion on VoiceController {
  Future<bool> deleteRoom({
    required String siteUrl,
    required int roomId,
  }) async {
    final ownsAccount = captureSiteSession(siteUrl);
    final deleted = await _runHandledValue<bool>(
      () => _roomDirectory(siteUrl).deleteRoom(roomId),
      fallback: false,
    );
    if (!deleted || !ownsAccount()) return false;
    if (_call?.siteUrl == siteUrl && _call?.room.id == roomId) {
      await _leave(notifyServer: false);
    }
    return ownsAccount();
  }
}
