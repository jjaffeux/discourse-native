import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import 'updater.dart';

/// Remembers which channel the user asked for, and when we last looked.
///
/// Preferences rather than the keychain: neither of these is a secret, and the
/// keychain is reserved for credentials (see [SecureStore]).
///
/// Every method swallows its own failures. Not being able to remember the
/// channel is a reason to fall back to the built-in default, not a reason for
/// the app to fail to start.
class UpdateStore {
  static const String _channelKey = 'discourse_native.update_channel';
  static const String _lastCheckedKey = 'discourse_native.update_last_checked';

  static void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'storage',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  Future<UpdateChannel?> readChannel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // byName rather than values.byName: a channel this build no longer has
      // must read as "no preference" instead of throwing on launch.
      return UpdateChannel.byName(prefs.getString(_channelKey));
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'updates.readChannel');
      return null;
    }
  }

  Future<void> writeChannel(UpdateChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_channelKey, channel.name);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'updates.writeChannel');
      return;
    }
  }

  Future<DateTime?> readLastChecked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_lastCheckedKey);
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'updates.readLastChecked');
      return null;
    }
  }

  Future<void> writeLastChecked(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckedKey, at.millisecondsSinceEpoch);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'updates.writeLastChecked');
      return;
    }
  }
}
