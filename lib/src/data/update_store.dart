import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';
import 'updater.dart';

/// Raw, non-secret update preferences.
///
/// Write methods preserve the boolean durability result returned by the
/// platform preferences implementation. [UpdateStore] owns the policy for a
/// rejected write, which keeps that failure path testable without a platform
/// channel.
abstract interface class UpdatePersistence {
  Future<String?> readChannelName();

  Future<bool> writeChannelName(String value);

  Future<int?> readLastCheckedMillis();

  Future<bool> writeLastCheckedMillis(int value);
}

final class SharedPreferencesUpdatePersistence implements UpdatePersistence {
  const SharedPreferencesUpdatePersistence();

  static const String _channelKey = 'discourse_native.update_channel';
  static const String _lastCheckedKey = 'discourse_native.update_last_checked';

  @override
  Future<String?> readChannelName() async =>
      (await SharedPreferences.getInstance()).getString(_channelKey);

  @override
  Future<bool> writeChannelName(String value) async =>
      (await SharedPreferences.getInstance()).setString(_channelKey, value);

  @override
  Future<int?> readLastCheckedMillis() async =>
      (await SharedPreferences.getInstance()).getInt(_lastCheckedKey);

  @override
  Future<bool> writeLastCheckedMillis(int value) async =>
      (await SharedPreferences.getInstance()).setInt(_lastCheckedKey, value);
}

/// Remembers which channel the user asked for, and when we last looked.
///
/// Preferences rather than private storage: neither value is a secret, and
/// private storage is reserved for credentials and unsent drafts.
///
/// Every method swallows its own failures. Not being able to remember the
/// channel is a reason to fall back to the built-in default, not a reason for
/// the app to fail to start.
class UpdateStore {
  UpdateStore({UpdatePersistence? persistence})
    : _persistence = persistence ?? _defaultPersistence;

  static const UpdatePersistence _defaultPersistence =
      SharedPreferencesUpdatePersistence();
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final UpdatePersistence _persistence;

  Future<UpdateChannel?> readChannel() async {
    try {
      // byName rather than values.byName: a channel this build no longer has
      // must read as "no preference" instead of throwing on launch.
      final name = await _operations.run<String?>(
        owner: _persistence,
        key: SharedPreferencesUpdatePersistence._channelKey,
        operation: _persistence.readChannelName,
      );
      return UpdateChannel.byName(name);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'updates.readChannel');
      return null;
    }
  }

  Future<void> writeChannel(UpdateChannel channel) async {
    try {
      final saved = await _operations.run<bool>(
        owner: _persistence,
        key: SharedPreferencesUpdatePersistence._channelKey,
        operation: () => _persistence.writeChannelName(channel.name),
      );
      if (!saved) {
        throw StateError('Could not persist the update channel.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'updates.writeChannel');
      return;
    }
  }

  Future<DateTime?> readLastChecked() async {
    try {
      final millis = await _operations.run<int?>(
        owner: _persistence,
        key: SharedPreferencesUpdatePersistence._lastCheckedKey,
        operation: _persistence.readLastCheckedMillis,
      );
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'updates.readLastChecked');
      return null;
    }
  }

  Future<void> writeLastChecked(DateTime at) async {
    try {
      final saved = await _operations.run<bool>(
        owner: _persistence,
        key: SharedPreferencesUpdatePersistence._lastCheckedKey,
        operation: () =>
            _persistence.writeLastCheckedMillis(at.millisecondsSinceEpoch),
      );
      if (!saved) {
        throw StateError('Could not persist the last update check.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'updates.writeLastChecked');
      return;
    }
  }
}
