import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
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
/// into an error. `VoiceController` decides that optional preference failure
/// must be reported without preventing the live media operation.
abstract interface class VoicePreferences {
  Future<VoiceDevicePreferences> readDevices();

  Future<void> writeDevice(VoiceDevicePreference preference, String value);

  Future<void> writePushToTalk(bool enabled);

  /// Reads whether this account explicitly opted into camera auto-start.
  Future<bool> readCameraEnabled(String siteUrl, int userId);

  Future<void> writeCameraEnabled(String siteUrl, int userId, bool enabled);

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
  static final Expando<Map<String, Object>> _siteOwners = Expando();

  final VoicePreferencesPersistence _persistence;

  Map<String, Object> get _owners => _siteOwners[_persistence] ??= {};

  Object _owner(String siteUrl) => _owners.putIfAbsent(siteUrl, Object.new);

  bool _owns(String siteUrl, Object owner) =>
      identical(_owners[siteUrl], owner);

  static void _forgetSharedSites(ForgottenSites sites) =>
      const SharedPreferencesVoicePreferences().forgetSites(sites);

  /// Retires pending forum choices and reads when durable removal drops their
  /// keys. Device preferences and account changes retain their operations.
  void forgetSites(ForgottenSites sites) => _owners.removeWhere(
    (site, _) =>
        sites.includes(site, cameraEnabledKeys) ||
        sites.includes(site, volumeKeys),
  );

  static const _audioInputKey = 'voice.device.audio-input';
  static const _audioOutputKey = 'voice.device.audio-output';
  static const _cameraKey = 'voice.device.camera';
  static const _pushToTalkKey = 'voice.device.push-to-talk';
  static const _meshPrivacyAcknowledgedKey = 'voice.mesh-privacy-acknowledged';
  static const _autoStatusKey = 'voice.auto-status-enabled';

  /// Camera auto-start, per account on a forum.
  static const cameraEnabledKeys = SitePreferenceKey(
    'voice.camera-enabled',
    tail: SitePreferenceTail.id,
    onForget: _forgetSharedSites,
  );

  /// Participant volumes, per room and then per participant on a forum.
  static const volumeKeys = SitePreferenceKey(
    'voice.volume',
    tail: SitePreferenceTail.idPair,
    onForget: _forgetSharedSites,
  );

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
      appL10n.mediaDevice,
    );
  }

  @override
  Future<void> writePushToTalk(bool enabled) => _write(
    _pushToTalkKey,
    () => _persistence.writeBool(_pushToTalkKey, enabled),
    appL10n.pushToTalkPreference,
  );

  @override
  Future<bool> readCameraEnabled(String siteUrl, int userId) async {
    final key = _cameraEnabledKey(siteUrl, userId);
    return await _readSiteValue(
          siteUrl,
          key,
          () => _persistence.readBool(key),
        ) ??
        false;
  }

  @override
  Future<void> writeCameraEnabled(String siteUrl, int userId, bool enabled) {
    final key = _cameraEnabledKey(siteUrl, userId);
    return _write(
      key,
      () => _persistence.writeBool(key, enabled),
      appL10n.cameraPreference,
      siteUrl: siteUrl,
    );
  }

  static String _cameraEnabledKey(String siteUrl, int userId) =>
      '${cameraEnabledKeys.of(siteUrl)}.$userId';

  @override
  Future<bool> readMeshPrivacyAcknowledged() async =>
      await _readBool(_meshPrivacyAcknowledgedKey) ?? false;

  @override
  Future<void> writeMeshPrivacyAcknowledged(bool acknowledged) => _write(
    _meshPrivacyAcknowledgedKey,
    () => _persistence.writeBool(_meshPrivacyAcknowledgedKey, acknowledged),
    appL10n.privacyAcknowledgement,
  );

  @override
  Future<bool?> readAutoStatusEnabled() => _readBool(_autoStatusKey);

  @override
  Future<void> writeAutoStatusEnabled(bool enabled) => _write(
    _autoStatusKey,
    () => _persistence.writeBool(_autoStatusKey, enabled),
    appL10n.statusPreference,
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

  Future<T?> _readSiteValue<T>(
    String siteUrl,
    String key,
    Future<T?> Function() read,
  ) {
    final owner = _owner(siteUrl);
    return _operations.run<T?>(
      owner: _persistence,
      key: key,
      operation: () async {
        if (!_owns(siteUrl, owner)) return null;
        final value = await read();
        return _owns(siteUrl, owner) ? value : null;
      },
    );
  }

  Future<void> _write(
    String key,
    Future<bool> Function() persist,
    String description, {
    String? siteUrl,
  }) {
    final owner = siteUrl == null ? null : _owner(siteUrl);
    return _operations.run<void>(
      owner: _persistence,
      key: key,
      operation: () async {
        if (owner != null && !_owns(siteUrl!, owner)) return;
        _requireSaved(await persist(), description);
      },
    );
  }

  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) {
    final key = _volumeKey(siteUrl, roomId, userId);
    return _readSiteValue(siteUrl, key, () => _persistence.readDouble(key));
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
      appL10n.participantVolume,
      siteUrl: siteUrl,
    );
  }

  static String _volumeKey(String siteUrl, int roomId, int userId) =>
      '${volumeKeys.of(siteUrl)}.$roomId.$userId';

  static void _requireSaved(bool saved, String description) {
    if (!saved) throw StateError('Could not persist Voice $description.');
  }
}
