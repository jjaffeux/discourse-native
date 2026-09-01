import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replacement device writes persist the latest request', () async {
    final persistence = _ControlledPersistence();
    addTearDown(() {
      if (!persistence.finishFirstStringWrite.isCompleted) {
        persistence.finishFirstStringWrite.complete();
      }
    });
    final oldPreferences = SharedPreferencesVoicePreferences(
      persistence: persistence,
    );
    final replacementPreferences = SharedPreferencesVoicePreferences(
      persistence: persistence,
    );

    final oldWrite = oldPreferences.writeDevice(
      VoiceDevicePreference.camera,
      'old-camera',
    );
    await persistence.firstStringWriteStarted.future;
    final replacementWrite = replacementPreferences.writeDevice(
      VoiceDevicePreference.camera,
      'new-camera',
    );

    await Future<void>.delayed(Duration.zero);
    expect(persistence.stringWriteValues, ['old-camera']);

    await replacementPreferences.writePushToTalk(true);
    expect(persistence.boolValue, isTrue);

    persistence.finishFirstStringWrite.complete();
    await Future.wait([oldWrite, replacementWrite]);

    expect(persistence.stringWriteValues, ['old-camera', 'new-camera']);
    expect(
      (await replacementPreferences.readDevices()).cameraDeviceId,
      'new-camera',
    );
  });

  test('a replacement read waits for an in-flight volume write', () async {
    final persistence = _ControlledPersistence();
    addTearDown(() {
      if (!persistence.finishFirstDoubleWrite.isCompleted) {
        persistence.finishFirstDoubleWrite.complete();
      }
    });
    final oldPreferences = SharedPreferencesVoicePreferences(
      persistence: persistence,
    );
    final replacementPreferences = SharedPreferencesVoicePreferences(
      persistence: persistence,
    );

    final writing = oldPreferences.writeParticipantVolume(
      'https://meta.discourse.org',
      7,
      11,
      0.4,
    );
    await persistence.firstDoubleWriteStarted.future;
    final reading = replacementPreferences.readParticipantVolume(
      'https://meta.discourse.org',
      7,
      11,
    );

    await Future<void>.delayed(Duration.zero);
    expect(persistence.doubleReads, 0);

    persistence.finishFirstDoubleWrite.complete();
    await writing;

    expect(await reading, 0.4);
    expect(persistence.doubleReads, 1);
  });

  test('a rejected write keeps the existing error contract', () async {
    final persistence = _ControlledPersistence(acceptBoolWrites: false);
    final preferences = SharedPreferencesVoicePreferences(
      persistence: persistence,
    );

    await expectLater(preferences.writePushToTalk(true), throwsStateError);
  });

  test('concurrent device-read failures are all observed', () async {
    final preferences = SharedPreferencesVoicePreferences(
      persistence: _FailingReadPersistence(),
    );

    await expectLater(preferences.readDevices(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
  });
}

final class _FailingReadPersistence implements VoicePreferencesPersistence {
  StateError get failure => StateError('preferences unavailable');

  @override
  Future<String?> readString(String key) => Future.error(failure);

  @override
  Future<bool?> readBool(String key) => Future.error(failure);

  @override
  Future<double?> readDouble(String key) => Future.error(failure);

  @override
  Future<bool> writeString(String key, String value) async => true;

  @override
  Future<bool> writeBool(String key, bool value) async => true;

  @override
  Future<bool> writeDouble(String key, double value) async => true;
}

final class _ControlledPersistence implements VoicePreferencesPersistence {
  _ControlledPersistence({this.acceptBoolWrites = true});

  final bool acceptBoolWrites;
  final Completer<void> firstStringWriteStarted = Completer<void>();
  final Completer<void> finishFirstStringWrite = Completer<void>();
  final Completer<void> firstDoubleWriteStarted = Completer<void>();
  final Completer<void> finishFirstDoubleWrite = Completer<void>();
  final List<String> stringWriteValues = [];
  final Map<String, String> strings = {};
  final Map<String, double> doubles = {};
  bool? boolValue;
  int doubleReads = 0;

  @override
  Future<String?> readString(String key) async => strings[key];

  @override
  Future<bool?> readBool(String key) async => boolValue;

  @override
  Future<double?> readDouble(String key) async {
    doubleReads++;
    return doubles[key];
  }

  @override
  Future<bool> writeString(String key, String value) async {
    stringWriteValues.add(value);
    if (stringWriteValues.length == 1) {
      firstStringWriteStarted.complete();
      await finishFirstStringWrite.future;
    }
    strings[key] = value;
    return true;
  }

  @override
  Future<bool> writeBool(String key, bool value) async {
    if (!acceptBoolWrites) return false;
    boolValue = value;
    return true;
  }

  @override
  Future<bool> writeDouble(String key, double value) async {
    firstDoubleWriteStarted.complete();
    await finishFirstDoubleWrite.future;
    doubles[key] = value;
    return true;
  }
}
