import 'package:shared_preferences/shared_preferences.dart';

enum ResenhaDevicePreference { audioInput, audioOutput, camera }

final class ResenhaDevicePreferences {
  const ResenhaDevicePreferences({
    this.audioInputDeviceId,
    this.audioOutputDeviceId,
    this.cameraDeviceId,
    this.pushToTalkEnabled = false,
  });

  final String? audioInputDeviceId;
  final String? audioOutputDeviceId;
  final String? cameraDeviceId;
  final bool pushToTalkEnabled;
}

/// Non-secret, best-effort preferences for one Resenha media client.
///
/// The platform implementation turns SharedPreferences' rejected-write result
/// into an error. [ResenhaController] decides that optional preference failure
/// must be reported without preventing the live media operation.
abstract interface class ResenhaPreferences {
  Future<ResenhaDevicePreferences> readDevices();

  Future<void> writeDevice(ResenhaDevicePreference preference, String value);

  Future<void> writePushToTalk(bool enabled);

  Future<double?> readParticipantVolume(String siteUrl, int roomId, int userId);

  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  );
}

final class SharedPreferencesResenhaPreferences implements ResenhaPreferences {
  const SharedPreferencesResenhaPreferences();

  static const _audioInputKey = 'resenha.device.audio-input';
  static const _audioOutputKey = 'resenha.device.audio-output';
  static const _cameraKey = 'resenha.device.camera';
  static const _pushToTalkKey = 'resenha.device.push-to-talk';

  @override
  Future<ResenhaDevicePreferences> readDevices() async {
    final preferences = await SharedPreferences.getInstance();
    return ResenhaDevicePreferences(
      audioInputDeviceId: preferences.getString(_audioInputKey),
      audioOutputDeviceId: preferences.getString(_audioOutputKey),
      cameraDeviceId: preferences.getString(_cameraKey),
      pushToTalkEnabled: preferences.getBool(_pushToTalkKey) ?? false,
    );
  }

  @override
  Future<void> writeDevice(
    ResenhaDevicePreference preference,
    String value,
  ) async {
    final key = switch (preference) {
      ResenhaDevicePreference.audioInput => _audioInputKey,
      ResenhaDevicePreference.audioOutput => _audioOutputKey,
      ResenhaDevicePreference.camera => _cameraKey,
    };
    _requireSaved(
      await (await SharedPreferences.getInstance()).setString(key, value),
      'media device',
    );
  }

  @override
  Future<void> writePushToTalk(bool enabled) async {
    _requireSaved(
      await (await SharedPreferences.getInstance()).setBool(
        _pushToTalkKey,
        enabled,
      ),
      'push-to-talk preference',
    );
  }

  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async => (await SharedPreferences.getInstance()).getDouble(
    _volumeKey(siteUrl, roomId, userId),
  );

  @override
  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) async {
    _requireSaved(
      await (await SharedPreferences.getInstance()).setDouble(
        _volumeKey(siteUrl, roomId, userId),
        volume,
      ),
      'participant volume',
    );
  }

  static String _volumeKey(String siteUrl, int roomId, int userId) =>
      'resenha.volume.${Uri.encodeComponent(siteUrl)}.$roomId.$userId';

  static void _requireSaved(bool saved, String description) {
    if (!saved) throw StateError('Could not persist Resenha $description.');
  }
}
