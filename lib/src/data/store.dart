import 'package:flutter/foundation.dart';

abstract mixin class Storable<T extends Storable<T>> {
  Object get storeId;

  T merge(covariant T incoming) => incoming;
}

class Ref<T extends Object> extends ChangeNotifier
    implements ValueListenable<T?> {
  Ref._(this._value);

  T? _value;

  @override
  T? get value => _value;

  void _set(T? next) {
    if (identical(_value, next)) return;
    _value = next;
    notifyListeners();
  }
}

class Store {
  final Map<(String, Type, Object), Ref<Object>> _refs = {};

  final Map<(String, Type), int> _generations = {};

  int generationOf<T extends Storable<T>>(String siteUrl) =>
      _generations[(siteUrl, T)] ?? 0;

  void _bump(String siteUrl, Type type) {
    final key = (siteUrl, type);
    _generations[key] = (_generations[key] ?? 0) + 1;
  }

  Ref<T> ref<T extends Storable<T>>(String siteUrl, Object id) =>
      _cell<T>(siteUrl, id);

  Ref<T> _cell<T extends Storable<T>>(String siteUrl, Object id) {
    final key = (siteUrl, T, id);
    final held = _refs[key];
    if (held != null) return held as Ref<T>;

    final created = Ref<T>._(null);
    _refs[key] = created;
    return created;
  }

  T? read<T extends Storable<T>>(String siteUrl, Object id) =>
      (_refs[(siteUrl, T, id)] as Ref<T>?)?.value;

  T put<T extends Storable<T>>(String siteUrl, T record) {
    final cell = _cell<T>(siteUrl, record.storeId);
    final held = cell.value;
    final merged = held == null ? record : held.merge(record);
    if (!identical(held, merged)) _bump(siteUrl, T);
    cell._set(merged);
    return merged;
  }

  List<T> putAll<T extends Storable<T>>(String siteUrl, Iterable<T> records) =>
      [for (final record in records) put(siteUrl, record)];

  void update<T extends Storable<T>>(
    String siteUrl,
    Object id,
    T Function(T held) change,
  ) {
    final cell = _refs[(siteUrl, T, id)] as Ref<T>?;
    final held = cell?.value;
    if (cell == null || held == null) return;
    final next = change(held);
    if (!identical(held, next)) _bump(siteUrl, T);
    cell._set(next);
  }

  void remove<T extends Storable<T>>(String siteUrl, Object id) {
    final cell = _refs[(siteUrl, T, id)] as Ref<T>?;
    if (cell?.value != null) _bump(siteUrl, T);
    cell?._set(null);
  }

  void forget(String siteUrl) {
    final _ = _generations.removeWhere((key, _) => key.$1 == siteUrl);
    final forgotten = <Ref<Object>>[];
    _refs.removeWhere((key, ref) {
      if (key.$1 != siteUrl) return false;
      forgotten.add(ref);
      return true;
    });
    // Detach every ref before notifying. A listener may synchronously look up
    // another record, and mutating a map from inside removeWhere would throw.
    for (final ref in forgotten) {
      ref._set(null);
    }
  }

  @visibleForTesting
  int get length => _refs.length;
}
