import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

/// Encoded composer geometry persistence.
///
/// Returning `false` preserves the durability result exposed by the platform
/// preferences implementation. [ComposerGeometryStore] owns the best-effort
/// presentation-state policy for a rejected write.
abstract interface class ComposerGeometryPersistence {
  Future<String?> readGeometry();

  Future<bool> writeGeometry(String encoded);
}

final class SharedPreferencesComposerGeometryPersistence
    implements ComposerGeometryPersistence {
  const SharedPreferencesComposerGeometryPersistence();

  @override
  Future<String?> readGeometry() async =>
      (await SharedPreferences.getInstance()).getString(
        ComposerGeometryStore.storageKey,
      );

  @override
  Future<bool> writeGeometry(String encoded) async =>
      (await SharedPreferences.getInstance()).setString(
        ComposerGeometryStore.storageKey,
        encoded,
      );
}

/// The user's preferred composer window geometry.
///
/// Size is stored in logical pixels. Position is a fraction of the space in
/// which the panel can move so it keeps the same relative placement when the
/// app window or content pane changes size.
final class ComposerGeometryPreference {
  const ComposerGeometryPreference({
    required this.width,
    required this.height,
    required this.horizontalPosition,
    required this.verticalPosition,
  });

  final double width;
  final double height;
  final double horizontalPosition;
  final double verticalPosition;

  bool get isValid =>
      width.isFinite &&
      width > 0 &&
      height.isFinite &&
      height > 0 &&
      horizontalPosition.isFinite &&
      horizontalPosition >= 0 &&
      horizontalPosition <= 1 &&
      verticalPosition.isFinite &&
      verticalPosition >= 0 &&
      verticalPosition <= 1;

  Map<String, double> toJson() => {
    'width': width,
    'height': height,
    'horizontalPosition': horizontalPosition,
    'verticalPosition': verticalPosition,
  };

  static ComposerGeometryPreference? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final width = value['width'];
    final height = value['height'];
    final horizontalPosition = value['horizontalPosition'];
    final verticalPosition = value['verticalPosition'];
    if (width is! num ||
        height is! num ||
        horizontalPosition is! num ||
        verticalPosition is! num) {
      return null;
    }
    final preference = ComposerGeometryPreference(
      width: width.toDouble(),
      height: height.toDouble(),
      horizontalPosition: horizontalPosition.toDouble(),
      verticalPosition: verticalPosition.toDouble(),
    );
    return preference.isValid ? preference : null;
  }
}

/// Persists composer window geometry between composer sessions and launches.
///
/// This is optional presentation state. Storage failures fall back to the
/// default bottom-centred composer and must never prevent composing.
final class ComposerGeometryStore {
  const ComposerGeometryStore({ComposerGeometryPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesComposerGeometryPersistence();

  static const String storageKey = 'discourse_native.composer_geometry';
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final ComposerGeometryPersistence _persistence;

  Future<ComposerGeometryPreference?> read() =>
      _operations.run(owner: _persistence, key: storageKey, operation: _read);

  Future<ComposerGeometryPreference?> _read() async {
    try {
      final encoded = await _persistence.readGeometry();
      if (encoded == null) return null;
      return ComposerGeometryPreference.fromJson(jsonDecode(encoded));
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'composer.readGeometry');
      return null;
    }
  }

  Future<void> write(ComposerGeometryPreference preference) async {
    if (!preference.isValid) return;
    await _operations.run<void>(
      owner: _persistence,
      key: storageKey,
      operation: () => _persist(preference),
    );
  }

  Future<void> _persist(ComposerGeometryPreference preference) async {
    try {
      final saved = await _persistence.writeGeometry(
        jsonEncode(preference.toJson()),
      );
      if (!saved) throw StateError('Could not persist composer geometry.');
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'composer.writeGeometry');
    }
  }
}
