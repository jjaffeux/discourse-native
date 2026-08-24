import 'package:flutter/foundation.dart';

/// Stable identity for one plugin-owned value attached to a core record.
///
/// The owner/name pair is explicit instead of relying on a Dart [Type], so the
/// composition boundary can reject duplicate claims before decoding payloads.
@immutable
final class PluginDataKey<T extends Object> {
  const PluginDataKey({required this.owner, required this.name});

  final String owner;
  final String name;

  String get id => '$owner/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginDataKey<Object> &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => 'PluginDataKey<$T>($id)';
}

/// What installed plugins had to say about one core record.
///
/// Values are parsed once with the record and remain opaque to core. A stable
/// typed key makes ownership explicit while preserving type-safe reads.
@immutable
final class PluginData {
  const PluginData._(this._values);

  static const PluginData none = PluginData._(
    <PluginDataKey<Object>, Object>{},
  );

  final Map<PluginDataKey<Object>, Object> _values;

  T? get<T extends Object>(PluginDataKey<T> key) => _values[key] as T?;

  PluginData withValue<T extends Object>(PluginDataKey<T> key, T? value) {
    final next = Map<PluginDataKey<Object>, Object>.of(_values);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return next.isEmpty ? none : PluginData._(Map.unmodifiable(next));
  }

  PluginData withValueFor(PluginDataKey<Object> key, Object? value) {
    final next = Map<PluginDataKey<Object>, Object>.of(_values);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return next.isEmpty ? none : PluginData._(Map.unmodifiable(next));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginData && mapEquals(other._values, _values);

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// Decodes plugin-owned fields without making core records import a manifest.
abstract interface class PluginDataDecoder {
  PluginData readPost(Map<String, dynamic> json, String siteUrl);

  PluginData readTopic(Map<String, dynamic> json, String siteUrl);

  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  });
}

/// The decoder used by a core-only manifest.
final class EmptyPluginDataDecoder implements PluginDataDecoder {
  const EmptyPluginDataDecoder();

  @override
  PluginData readPost(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readTopic(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) => incoming;
}
