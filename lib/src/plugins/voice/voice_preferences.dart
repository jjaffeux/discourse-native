import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VoiceDevicePreference { audioInput, audioOutput, camera }

final class VoiceDevicePreferences {
  const VoiceDevicePreferences({
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

/// The platform implementation turns SharedPreferences' rejected-write result
/// into an error. [VoiceController] decides that optional preference failure
/// must be reported without preventing the live media operation.
abstract interface class VoicePreferences {
  Future<VoiceDevicePreferences> readDevices();

  Future<void> writeDevice(VoiceDevicePreference preference, String value);

  Future<void> writePushToTalk(bool enabled);

  /// Whether this device has accepted the peer-to-peer IP exposure warning
  /// ("don't show this again"). Per device, like the web client's.
  Future<bool> readMeshPrivacyAcknowledged();

  Future<void> writeMeshPrivacyAcknowledged(bool acknowledged);

  /// Whether joining a room may set the user's status to it. Null when
  /// never chosen: the site's default (on) applies.
  Future<bool?> readAutoStatusEnabled();

  Future<void> writeAutoStatusEnabled(bool enabled);

  Future<double?> readParticipantVolume(String siteUrl, int roomId, int userId);

  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  );
}

abstract interface class VoicePreferencesPersistence {
  Future<String?> readString(String key);

  Future<bool?> readBool(String key);

  Future<double?> readDouble(String key);

  Future<bool> writeString(String key, String value);

  Future<bool> writeBool(String key, bool value);

  Future<bool> writeDouble(String key, double value);
}

final class _SharedPreferencesVoicePersistence
    implements VoicePreferencesPersistence {
  const _SharedPreferencesVoicePersistence();

  @override
  Future<String?> readString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<bool?> readBool(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<double?> readDouble(String key) async =>
      (await SharedPreferences.getInstance()).getDouble(key);

  @override
  Future<bool> writeString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<bool> writeBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);

  @override
  Future<bool> writeDouble(String key, double value) async =>
      (await SharedPreferences.getInstance()).setDouble(key, value);
}

final class SharedPreferencesVoicePreferences implements VoicePreferences {
  const SharedPreferencesVoicePreferences({
    VoicePreferencesPersistence? persistence,
  }) : _persistence = persistence ?? const _SharedPreferencesVoicePersistence();

  static final SerialOperationQueue _operations = SerialOperationQueue();

  final VoicePreferencesPersistence _persistence;

  static const _audioInputKey = 'voice.device.audio-input';
  static const _audioOutputKey = 'voice.device.audio-output';
  static const _cameraKey = 'voice.device.camera';
  static const _pushToTalkKey = 'voice.device.push-to-talk';
  static const _meshPrivacyAcknowledgedKey = 'voice.mesh-privacy-acknowledged';
  static const _autoStatusKey = 'voice.auto-status-enabled';

  @override
  Future<VoiceDevicePreferences> readDevices() async {
    // Start these independent keys together. Each waits only for writes to its
    // own key, so a slow camera preference cannot block the microphone. A
    // single Future.wait also observes every failure: if the platform channel
    // is unavailable, the other concurrent reads must not escape as unhandled
    // futures after the caller has caught the first error.
    final values = await Future.wait<Object?>([
      _readString(_audioInputKey),
      _readString(_audioOutputKey),
      _readString(_cameraKey),
      _readBool(_pushToTalkKey),
    ]);
    return VoiceDevicePreferences(
      audioInputDeviceId: values[0] as String?,
      audioOutputDeviceId: values[1] as String?,
      cameraDeviceId: values[2] as String?,
      pushToTalkEnabled: values[3] as bool? ?? false,
    );
  }

  @override
  Future<void> writeDevice(VoiceDevicePreference preference, String value) {
    final key = switch (preference) {
      VoiceDevicePreference.audioInput => _audioInputKey,
      VoiceDevicePreference.audioOutput => _audioOutputKey,
      VoiceDevicePreference.camera => _cameraKey,
    };
    return _write(
      key,
      () => _persistence.writeString(key, value),
      'media device',
    );
  }

  @override
  Future<void> writePushToTalk(bool enabled) => _write(
    _pushToTalkKey,
    () => _persistence.writeBool(_pushToTalkKey, enabled),
    'push-to-talk preference',
  );

  @override
  Future<bool> readMeshPrivacyAcknowledged() async =>
      await _readBool(_meshPrivacyAcknowledgedKey) ?? false;

  @override
  Future<void> writeMeshPrivacyAcknowledged(bool acknowledged) => _write(
    _meshPrivacyAcknowledgedKey,
    () => _persistence.writeBool(_meshPrivacyAcknowledgedKey, acknowledged),
    'privacy acknowledgement',
  );

  @override
  Future<bool?> readAutoStatusEnabled() => _readBool(_autoStatusKey);

  @override
  Future<void> writeAutoStatusEnabled(bool enabled) => _write(
    _autoStatusKey,
    () => _persistence.writeBool(_autoStatusKey, enabled),
    'status preference',
  );

  Future<String?> _readString(String key) => _operations.run<String?>(
    owner: _persistence,
    key: key,
    operation: () => _persistence.readString(key),
  );

  Future<bool?> _readBool(String key) => _operations.run<bool?>(
    owner: _persistence,
    key: key,
    operation: () => _persistence.readBool(key),
  );

  Future<double?> _readDouble(String key) => _operations.run<double?>(
    owner: _persistence,
    key: key,
    operation: () => _persistence.readDouble(key),
  );

  Future<void> _write(
    String key,
    Future<bool> Function() persist,
    String description,
  ) => _operations.run<void>(
    owner: _persistence,
    key: key,
    operation: () async {
      _requireSaved(await persist(), description);
    },
  );

  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) {
    final key = _volumeKey(siteUrl, roomId, userId);
    return _readDouble(key);
  }

  @override
  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) {
    final key = _volumeKey(siteUrl, roomId, userId);
    return _write(
      key,
      () => _persistence.writeDouble(key, volume),
      'participant volume',
    );
  }

  static String _volumeKey(String siteUrl, int roomId, int userId) =>
      'voice.volume.${Uri.encodeComponent(siteUrl)}.$roomId.$userId';

  static void _requireSaved(bool saved, String description) {
    if (!saved) throw StateError('Could not persist Voice $description.');
  }
}
