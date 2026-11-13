import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/composer_placement.dart';
import 'coalescing_snapshot_writer.dart';
import 'preference_storage_scope.dart';

class ComposerLayoutPreference {
  const ComposerLayoutPreference({
    this.placement = ComposerPlacement.right,
    this.sideWidth = 420,
    this.replyHeight = 280,
    this.topicHeight = 380,
  });

  final ComposerPlacement placement;
  final double sideWidth, replyHeight, topicHeight;

  ComposerLayoutPreference copyWith({
    ComposerPlacement? placement,
    double? sideWidth,
    double? replyHeight,
    double? topicHeight,
  }) => ComposerLayoutPreference(
    placement: placement ?? this.placement,
    sideWidth: sideWidth ?? this.sideWidth,
    replyHeight: replyHeight ?? this.replyHeight,
    topicHeight: topicHeight ?? this.topicHeight,
  );

  Map<String, Object> toJson() => {
    'placement': placement.name,
    'sideWidth': sideWidth,
    'replyHeight': replyHeight,
    'topicHeight': topicHeight,
  };

  static ComposerLayoutPreference? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final placement = ComposerPlacement.values
        .where((item) => item.name == value['placement'])
        .firstOrNull;
    if (placement == null) return null;
    double? dimension(String key) {
      final item = value[key];
      return item is num && item.isFinite && item > 0 ? item.toDouble() : null;
    }

    final width = dimension('sideWidth');
    final reply = dimension('replyHeight');
    final topic = dimension('topicHeight');
    if (width == null || reply == null || topic == null) return null;
    return ComposerLayoutPreference(
      placement: placement,
      sideWidth: width,
      replyHeight: reply,
      topicHeight: topic,
    );
  }
}

abstract interface class ComposerLayoutPersistence {
  Future<String?> readLayout();
  Future<bool> writeLayout(String encoded);
}

@PreferenceStorage.device(
  'Composer layout is shared by every forum on this device.',
)
final class SharedPreferencesComposerLayoutPersistence
    implements ComposerLayoutPersistence {
  const SharedPreferencesComposerLayoutPersistence();
  @override
  Future<String?> readLayout() async => (await SharedPreferences.getInstance())
      .getString(ComposerLayoutStore.storageKey);
  @override
  Future<bool> writeLayout(String encoded) async =>
      (await SharedPreferences.getInstance()).setString(
        ComposerLayoutStore.storageKey,
        encoded,
      );
}

/// Placement preferences never read or migrate the obsolete floating geometry.
final class ComposerLayoutStore {
  const ComposerLayoutStore({ComposerLayoutPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesComposerLayoutPersistence();
  static const storageKey = 'discourse_native.composer_layout';
  final ComposerLayoutPersistence _persistence;

  CoalescingSnapshotWriter<ComposerLayoutPreference> get _snapshots =>
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _write,
      );

  Future<ComposerLayoutPreference> read() => _snapshots.readShared(_read);

  Future<ComposerLayoutPreference> _read() async {
    try {
      final encoded = await _persistence.readLayout();
      return encoded == null
          ? const ComposerLayoutPreference()
          : ComposerLayoutPreference.fromJson(jsonDecode(encoded)) ??
                const ComposerLayoutPreference();
    } catch (error) {
      return const ComposerLayoutPreference();
    }
  }

  Future<void> write(ComposerLayoutPreference value) => _snapshots.save(value);

  Future<void> _write(ComposerLayoutPreference value) async {
    try {
      if (!await _persistence.writeLayout(jsonEncode(value.toJson()))) {
        throw StateError('Could not save composer layout.');
      }
    } catch (_) {}
  }
}
