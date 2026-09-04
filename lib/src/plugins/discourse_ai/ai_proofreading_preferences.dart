import 'package:shared_preferences/shared_preferences.dart';

import '../../data/serial_operation_queue.dart';
import '../../data/store_diagnostics.dart';

abstract interface class AiProofreadingPreferencePersistence {
  Future<bool?> readEnabled({required String siteUrl});

  Future<bool> writeEnabled({required String siteUrl, required bool enabled});
}

final class SharedPreferencesAiProofreadingPreferencePersistence
    implements AiProofreadingPreferencePersistence {
  const SharedPreferencesAiProofreadingPreferencePersistence();

  static const String _keyPrefix = 'discourse_native.ai_proofreading_enabled';

  @override
  Future<bool?> readEnabled({required String siteUrl}) async =>
      (await SharedPreferences.getInstance()).getBool(_key(siteUrl));

  @override
  Future<bool> writeEnabled({
    required String siteUrl,
    required bool enabled,
  }) async =>
      (await SharedPreferences.getInstance()).setBool(_key(siteUrl), enabled);

  static String _key(String siteUrl) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}';
}

final class AiProofreadingPreferenceStore {
  const AiProofreadingPreferenceStore({
    AiProofreadingPreferencePersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesAiProofreadingPreferencePersistence();

  final AiProofreadingPreferencePersistence _persistence;
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  Future<bool> read({required String siteUrl}) => _operations.read(
    owner: _persistence,
    key: siteUrl,
    operation: () => _read(siteUrl),
  );

  Future<bool> _read(String siteUrl) async {
    try {
      return await _persistence.readEnabled(siteUrl: siteUrl) ?? false;
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aiProofreading.readEnabled');
      return false;
    }
  }

  Future<void> write({required String siteUrl, required bool enabled}) =>
      _operations.write<void>(
        owner: _persistence,
        key: siteUrl,
        operation: () => _persist(siteUrl: siteUrl, enabled: enabled),
      );

  Future<void> _persist({
    required String siteUrl,
    required bool enabled,
  }) async {
    try {
      final saved = await _persistence.writeEnabled(
        siteUrl: siteUrl,
        enabled: enabled,
      );
      if (!saved) {
        throw StateError('Could not persist the AI proofreading preference.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aiProofreading.writeEnabled');
    }
  }
}
