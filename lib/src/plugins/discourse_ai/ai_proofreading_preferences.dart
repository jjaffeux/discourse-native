import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The choice is an account's, not a forum's: a proofread sends the post to
/// the site's AI helper and posts its rewrite, which only the account that
/// opted in has agreed to.
abstract interface class AiProofreadingPreferencePersistence {
  Future<bool?> readEnabled({required String siteUrl, required int userId});

  Future<bool> writeEnabled({
    required String siteUrl,
    required int userId,
    required bool enabled,
  });

  /// Removes the choice stored for a whole forum before choices were bound to
  /// an account.
  Future<bool> removeSiteWideEnabled({required String siteUrl});
}

final class SharedPreferencesAiProofreadingPreferencePersistence
    implements AiProofreadingPreferencePersistence {
  const SharedPreferencesAiProofreadingPreferencePersistence();

  static const String _keyPrefix =
      'discourse_native.ai_proofreading_enabled_by_account';
  static const String _siteWideKeyPrefix =
      'discourse_native.ai_proofreading_enabled';

  @override
  Future<bool?> readEnabled({
    required String siteUrl,
    required int userId,
  }) async =>
      (await SharedPreferences.getInstance()).getBool(_key(siteUrl, userId));

  @override
  Future<bool> writeEnabled({
    required String siteUrl,
    required int userId,
    required bool enabled,
  }) async => (await SharedPreferences.getInstance()).setBool(
    _key(siteUrl, userId),
    enabled,
  );

  @override
  Future<bool> removeSiteWideEnabled({required String siteUrl}) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '$_siteWideKeyPrefix.${Uri.encodeComponent(siteUrl)}';
    return !preferences.containsKey(key) || await preferences.remove(key);
  }

  static String _key(String siteUrl, int userId) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}.$userId';
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

  /// A forum-wide choice left from before cannot say which account made it,
  /// so reading any account's choice removes it rather than adopting it.
  Future<bool> read({required String siteUrl, required int userId}) =>
      _operations.read(
        owner: _persistence,
        key: (siteUrl: siteUrl, userId: userId),
        operation: () => _read(siteUrl, userId),
      );

  Future<bool> _read(String siteUrl, int userId) async {
    await _removeSiteWide(siteUrl);
    try {
      return await _persistence.readEnabled(siteUrl: siteUrl, userId: userId) ??
          false;
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aiProofreading.readEnabled');
      return false;
    }
  }

  Future<void> _removeSiteWide(String siteUrl) async {
    try {
      if (!await _persistence.removeSiteWideEnabled(siteUrl: siteUrl)) {
        throw StateError(
          'Could not remove the forum-wide AI proofreading preference.',
        );
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'aiProofreading.removeSiteWideEnabled',
      );
    }
  }

  Future<void> write({
    required String siteUrl,
    required int userId,
    required bool enabled,
  }) => _operations.write<void>(
    owner: _persistence,
    key: (siteUrl: siteUrl, userId: userId),
    operation: () =>
        _persist(siteUrl: siteUrl, userId: userId, enabled: enabled),
  );

  Future<void> _persist({
    required String siteUrl,
    required int userId,
    required bool enabled,
  }) async {
    try {
      final saved = await _persistence.writeEnabled(
        siteUrl: siteUrl,
        userId: userId,
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
