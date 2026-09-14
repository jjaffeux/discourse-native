import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'camera preference defaults off and belongs to a site and account',
    () async {
      final persistence = _MemoryPersistence();
      final preferences = SharedPreferencesVoicePreferences(
        persistence: persistence,
      );
      const site = 'https://meta.discourse.org';
      expect(await preferences.readCameraEnabled(site, 1), isFalse);

      await preferences.writeCameraEnabled(site, 1, true);
      final replacement = SharedPreferencesVoicePreferences(
        persistence: persistence,
      );

      expect(await replacement.readCameraEnabled(site, 1), isTrue);
      expect(await replacement.readCameraEnabled(site, 2), isFalse);
      expect(
        await replacement.readCameraEnabled('https://other.example.com', 1),
        isFalse,
      );

      await replacement.writeCameraEnabled(site, 1, false);
      expect(await preferences.readCameraEnabled(site, 1), isFalse);
    },
  );

  test('a rejected camera preference write reports failure', () async {
    final preferences = SharedPreferencesVoicePreferences(
      persistence: _ControlledPersistence(acceptBoolWrites: false),
    );

    await expectLater(
      preferences.writeCameraEnabled('https://meta.discourse.org', 1, true),
      throwsStateError,
    );
  });

  test(
    'camera off persists last across a delayed on write and replacement reads',
    () async {
      final persistence = _ControlledPersistence(holdBoolWrite: true);
      final preferences = SharedPreferencesVoicePreferences(
        persistence: persistence,
      );
      final replacement = SharedPreferencesVoicePreferences(
        persistence: persistence,
      );
      const site = 'https://meta.discourse.org';
      addTearDown(() {
        if (!persistence.finishFirstBoolWrite.isCompleted) {
          persistence.finishFirstBoolWrite.complete();
        }
      });
      final enabling = preferences.writeCameraEnabled(site, 1, true);
      await persistence.firstBoolWriteStarted.future;
      final disabling = replacement.writeCameraEnabled(site, 1, false);
      final reading = preferences.readCameraEnabled(site, 1);
      persistence.finishFirstBoolWrite.complete();
      await Future.wait([enabling, disabling]);
      expect(await reading, isFalse);
      expect(persistence.boolWriteValues, [true, false]);
    },
  );

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

  test(
    'privacy acknowledgement and status choice round-trip per device',
    () async {
      final persistence = _MemoryPersistence();
      final preferences = SharedPreferencesVoicePreferences(
        persistence: persistence,
      );

      expect(await preferences.readMeshPrivacyAcknowledged(), isFalse);
      expect(await preferences.readAutoStatusEnabled(), isNull);

      await preferences.writeMeshPrivacyAcknowledged(true);
      await preferences.writeAutoStatusEnabled(false);

      expect(await preferences.readMeshPrivacyAcknowledged(), isTrue);
      expect(await preferences.readAutoStatusEnabled(), isFalse);
      expect(persistence.values, {
        'voice.mesh-privacy-acknowledged': true,
        'voice.auto-status-enabled': false,
      });
    },
  );

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
  _ControlledPersistence({
    this.acceptBoolWrites = true,
    this.holdBoolWrite = false,
  });

  final bool holdBoolWrite;
  final firstBoolWriteStarted = Completer<void>();
  final finishFirstBoolWrite = Completer<void>();
  final boolWriteValues = <bool>[];

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
    boolWriteValues.add(value);
    if (holdBoolWrite && boolWriteValues.length == 1) {
      firstBoolWriteStarted.complete();
      await finishFirstBoolWrite.future;
    }

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

final class _MemoryPersistence implements VoicePreferencesPersistence {
  final Map<String, Object> values = {};

  @override
  Future<bool?> readBool(String key) async => values[key] as bool?;

  @override
  Future<double?> readDouble(String key) async => values[key] as double?;

  @override
  Future<String?> readString(String key) async => values[key] as String?;

  @override
  Future<bool> writeBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> writeDouble(String key, double value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> writeString(String key, String value) async {
    values[key] = value;
    return true;
  }
}
