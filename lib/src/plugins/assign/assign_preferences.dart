import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Assign owns the key, including compatibility with the original app setting.
final class AssignPreferences extends ChangeNotifier {
  AssignPreferences({required this.diagnostics});
  static const storageKey = 'discourse_native.topic_list_show_assignments';
  final PluginDiagnosticsReporter diagnostics;
  static final _operations = ReadAfterWriteOperationQueue();
  bool _showAssignments = true;
  bool? _selected;
  bool _disposed = false;
  bool get showAssignments => _selected ?? _showAssignments;

  Future<void> load() async {
    try {
      final value = await _operations.read(
        owner: AssignPreferences,
        key: storageKey,
        operation: () async =>
            (await SharedPreferences.getInstance()).getBool(storageKey),
      );
      if (_disposed) return;
      _showAssignments = value ?? true;
      notifyListeners();
    } catch (error, stack) {
      diagnostics.reportError(
        error,
        stack,
        operation: 'assign.preferences.read',
      );
    }
  }

  Future<void> setShowAssignments(bool value) async {
    if (_disposed || value == _selected) return;
    final changed = value != showAssignments;
    _selected = value;
    if (changed) notifyListeners();
    try {
      await _operations.write(
        owner: AssignPreferences,
        key: storageKey,
        operation: () async {
          if (!await (await SharedPreferences.getInstance()).setBool(
            storageKey,
            value,
          )) {
            throw StateError('Could not save assignment display preference');
          }
        },
      );
    } catch (error, stack) {
      diagnostics.reportError(
        error,
        stack,
        operation: 'assign.preferences.write',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
