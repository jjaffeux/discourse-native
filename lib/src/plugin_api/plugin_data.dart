import 'package:flutter/foundation.dart';

import 'preserved_json.dart';

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

/// The persisted namespace is [key.id]. A codec also understands the flat
/// fields written by releases which predate namespaced plugin data, keeping
/// that migration knowledge beside the feature which owns it.
abstract base class PluginDataPersistenceCodec<T extends Object> {
  const PluginDataPersistenceCodec();

  PluginDataKey<T> get key;

  T? decode(Object? value);

  Object? encode(T value);

  T? decodeLegacy(Map<String, dynamic> json) => null;

  /// The default keeps a namespaced value authoritative and consults legacy
  /// flat fields only when the namespace is absent. A codec may override this
  /// when a later schema revision needs to combine an existing namespace with
  /// a field written outside it by an older release.
  T? decodeStored({
    required Object? namespacedValue,
    required bool hasNamespacedValue,
    required Map<String, dynamic> record,
  }) => hasNamespacedValue ? decode(namespacedValue) : decodeLegacy(record);
}

/// Values are parsed once with the record and remain opaque to core. A stable
/// typed key makes ownership explicit while preserving type-safe reads.
@immutable
final class PluginData {
  const PluginData._(this._values, this._preservedNamespaces);

  static const PluginData none = PluginData._(
    <PluginDataKey<Object>, Object>{},
    <String, Object?>{},
  );

  final Map<PluginDataKey<Object>, Object> _values;
  final Map<String, Object?> _preservedNamespaces;

  /// Values cross an untrusted persistence boundary, so malformed namespace
  /// names are ignored and nested collections are copied into immutable JSON
  /// values before the model keeps them.
  factory PluginData.preserveNamespaces(Object? value) {
    final namespaces = preserveJsonNamespaces(value);
    return namespaces.isEmpty
        ? none
        : PluginData._(
            const <PluginDataKey<Object>, Object>{},
            Map.unmodifiable(namespaces),
          );
  }

  T? get<T extends Object>(PluginDataKey<T> key) => _values[key] as T?;

  bool contains<T extends Object>(PluginDataKey<T> key) =>
      _values.containsKey(key);

  bool get isEmpty => _values.isEmpty && _preservedNamespaces.isEmpty;

  Map<String, Object?> get preservedNamespaces => _preservedNamespaces;

  PluginData withValue<T extends Object>(PluginDataKey<T> key, T? value) {
    final next = Map<PluginDataKey<Object>, Object>.of(_values);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return _from(next, _preservedNamespaces);
  }

  PluginData withValueFor(PluginDataKey<Object> key, Object? value) {
    final next = Map<PluginDataKey<Object>, Object>.of(_values);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return _from(next, _preservedNamespaces);
  }

  /// Marks one installed namespace as consumed before retaining its typed
  /// value. A malformed value is consumed too: an installed codec owns its
  /// recovery policy and an invalid old payload must not be emitted forever.
  PluginData withoutPreservedNamespace(String name) {
    if (!_preservedNamespaces.containsKey(name)) return this;
    final next = Map<String, Object?>.of(_preservedNamespaces)..remove(name);
    return _from(_values, next);
  }

  /// Installed typed values remain authoritative during a live refresh.
  PluginData preservingUnknownFrom(PluginData held) {
    if (held._preservedNamespaces.isEmpty) return this;
    final next = <String, Object?>{
      ...held._preservedNamespaces,
      ..._preservedNamespaces,
    };
    return _from(_values, next);
  }

  static PluginData _from(
    Map<PluginDataKey<Object>, Object> values,
    Map<String, Object?> preservedNamespaces,
  ) {
    if (values.isEmpty && preservedNamespaces.isEmpty) return none;
    return PluginData._(
      Map.unmodifiable(values),
      Map.unmodifiable(preservedNamespaces),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginData &&
          mapEquals(other._values, _values) &&
          deepJsonEquals(other._preservedNamespaces, _preservedNamespaces);

  @override
  int get hashCode => Object.hashAllUnordered([
    ..._values.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ..._preservedNamespaces.entries.map(
      (entry) => Object.hash(entry.key, deepJsonHash(entry.value)),
    ),
  ]);
}

abstract interface class PluginDataDecoder {
  PluginData readGroup(Map<String, dynamic> json, String siteUrl);

  PluginData readPost(Map<String, dynamic> json, String siteUrl);

  PluginData readTopic(Map<String, dynamic> json, String siteUrl);

  PluginData readUserCard(Map<String, dynamic> json, String siteUrl);

  PluginData readCurrentUser(Map<String, dynamic> json, String siteUrl);

  PluginData readSiteSettings(Map<String, dynamic> json, String siteUrl);

  PluginData readStoredCurrentUser(Map<String, dynamic> json);

  PluginData readStoredSiteSettings(Map<String, dynamic> json);

  Map<String, Object?> writeStoredCurrentUser(PluginData data);

  Map<String, Object?> writeStoredSiteSettings(PluginData data);

  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  });
}

final class EmptyPluginDataDecoder implements PluginDataDecoder {
  const EmptyPluginDataDecoder();

  @override
  PluginData readGroup(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readPost(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readTopic(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readUserCard(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readCurrentUser(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      PluginData.none;

  @override
  PluginData readStoredCurrentUser(Map<String, dynamic> json) =>
      PluginData.preserveNamespaces(json['plugins']);

  @override
  PluginData readStoredSiteSettings(Map<String, dynamic> json) =>
      PluginData.preserveNamespaces(json['plugins']);

  @override
  Map<String, Object?> writeStoredCurrentUser(PluginData data) =>
      data.preservedNamespaces;

  @override
  Map<String, Object?> writeStoredSiteSettings(PluginData data) =>
      data.preservedNamespaces;

  @override
  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) => incoming;
}
