import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

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
