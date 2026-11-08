/// Plugin namespaces the current build does not claim cross an untrusted
/// persistence boundary and are carried opaquely until a later build reads
/// them. These helpers are the one place that decides what such a value may
/// contain and how two carried values compare, so the plugin-data and
/// notification-counter records cannot drift apart on either rule.
typedef FrozenJson = ({bool valid, Object? value});

/// Copies a decoded JSON value into an immutable tree. Non-finite numbers
/// and non-string keys cannot be re-encoded, so a value containing either is
/// refused as a whole rather than silently trimmed.
FrozenJson freezeJson(Object? value) {
  if (value == null || value is String || value is bool) {
    return (valid: true, value: value);
  }
  if (value is num) {
    return value.isFinite
        ? (valid: true, value: value)
        : (valid: false, value: null);
  }
  if (value is List) {
    final result = <Object?>[];
    for (final item in value) {
      final frozen = freezeJson(item);
      if (!frozen.valid) return (valid: false, value: null);
      result.add(frozen.value);
    }
    return (valid: true, value: List<Object?>.unmodifiable(result));
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) return (valid: false, value: null);
      final frozen = freezeJson(entry.value);
      if (!frozen.valid) return (valid: false, value: null);
      result[entry.key as String] = frozen.value;
    }
    return (valid: true, value: Map<String, Object?>.unmodifiable(result));
  }
  return (valid: false, value: null);
}

/// Keeps every namespace whose name is a non-empty string and whose value
/// freezes. A namespace that cannot be carried is dropped on its own; the
/// others are still preserved.
Map<String, Object?> preserveJsonNamespaces(Object? value) {
  final namespaces = <String, Object?>{};
  if (value is! Map) return namespaces;
  for (final entry in value.entries) {
    final name = entry.key;
    if (name is! String || name.isEmpty) continue;
    final frozen = freezeJson(entry.value);
    if (frozen.valid) namespaces[name] = frozen.value;
  }
  return namespaces;
}

bool deepJsonEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!deepJsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !deepJsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int deepJsonHash(Object? value) => switch (value) {
  final List<Object?> values => Object.hashAll(values.map(deepJsonHash)),
  final Map<Object?, Object?> values => Object.hashAllUnordered(
    values.entries.map(
      (entry) => Object.hash(entry.key, deepJsonHash(entry.value)),
    ),
  ),
  _ => value.hashCode,
};
