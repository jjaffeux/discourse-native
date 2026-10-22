part of 'voice_controller.dart';

final class _VoiceDevicePreferences {
  final audioInput = _VoicePreferenceChoice<String?>(null);
  final audioOutput = _VoicePreferenceChoice<String?>(null);
  final camera =
      _VoicePreferenceChoice<({String? deviceId, VoiceCameraFacing? facing})>((
        deviceId: null,
        facing: null,
      ));
  final pushToTalk = _VoicePreferenceChoice(false);
  final autoStatus = _VoicePreferenceChoice(true);
  final audioOperations = SerialOperationQueue();

  void restoreDevices(VoiceDevicePreferences stored) {
    audioInput.restore(stored.audioInputDeviceId);
    audioOutput.restore(stored.audioOutputDeviceId);
    camera.restore((deviceId: stored.cameraDeviceId, facing: null));
    pushToTalk.restore(stored.pushToTalkEnabled);
  }

  Object selectCamera(String? deviceId, VoiceCameraFacing? facing) {
    return camera.select((
      deviceId: facing == null ? deviceId : camera.value.deviceId,
      facing: facing,
    ));
  }
}

final class _VoicePreferenceChoice<T> {
  _VoicePreferenceChoice(this._stored);

  T _stored;
  _VoicePreferenceIntent<T>? _intent;

  T get value => _intent == null ? _stored : _intent!.value;
  Object? get intent => _intent;

  Object select(T value) => _intent = _VoicePreferenceIntent(value);

  void restore(T value) => _stored = value;

  bool isCurrent(Object? intent) => identical(_intent, intent);
}

final class _VoicePreferenceIntent<T> {
  _VoicePreferenceIntent(this.value);

  final T value;
}
