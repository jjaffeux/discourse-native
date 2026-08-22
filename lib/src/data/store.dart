import 'package:flutter/foundation.dart';

/// A record that can live in the [Store].
///
/// Two things are needed of it: what identifies it, and what happens when the
/// site sends another copy. The default answer to the second is "the new one
/// wins", which is right for a record that always arrives whole. Records that
/// arrive in more than one shape — a post with its markdown and a post without
/// — override [merge] to say which fields survive.
abstract mixin class Storable<T extends Storable<T>> {
  /// Unique within a type, on one site. Discourse numbers most things, but
  /// users are identified by name, so this is an [Object] rather than an int.
  Object get storeId;

  /// Folds a newly arrived copy onto the one already held.
  T merge(covariant T incoming) => incoming;
}

/// One record's place in the [Store]: a value that changes over time, which
/// anything drawing that record can listen to.
///
/// Null until the record has been fetched, and null again if it turns out not
/// to exist. Handing out a ref for something not yet in hand is deliberate —
/// a topic row can be built from a list before its detail has been read, and
/// fills in when it arrives without the row being rebuilt from above.
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

/// The identity map: every record the app holds, once.
///
/// Keyed by the site it came from, its type, and its own id. The site is part
/// of the key rather than a separate store per site because topic 7 on two
/// different Discourses are two different topics, and this app shows both at
/// the same time.
///
/// What it buys is that there is one copy. A topic read from `/latest`, the
/// same topic read from `/unread`, and the header of the topic being read are
/// the same object, so marking it read in one place is not a message that has
/// to be delivered to the other two — they are watching the same [Ref].
///
/// Nothing is evicted. The store lives as long as the session, minus whatever
/// [forget] drops when a site is disconnected. A session's worth of topics and
/// posts is a few megabytes of small objects, and the alternative — an LRU
/// whose evictions have to be reconciled with what is on screen — costs more
/// than it saves at this size.
class Store {
  /// (site, type, id). A record, not a string: no separator to collide with,
  /// and no formatting on every lookup.
  final Map<(String, Type, Object), Ref<Object>> _refs = {};

  /// How many times any record of a type has changed on a site.
  ///
  /// A derivation over many records — the loaded window of a topic, say — has
  /// no single ref to watch, and re-deriving on every read costs a store
  /// lookup per record. This is its cache key: unchanged generation means no
  /// record of that type changed, so the previous answer still holds.
  final Map<(String, Type), int> _generations = {};

  /// The current change generation for records of type [T] on [siteUrl].
  int generationOf<T extends Storable<T>>(String siteUrl) =>
      _generations[(siteUrl, T)] ?? 0;

  void _bump(String siteUrl, Type type) {
    final key = (siteUrl, type);
    _generations[key] = (_generations[key] ?? 0) + 1;
  }

  /// The ref for a record, whether or not it has been fetched.
  ///
  /// Stable until [forget] is called for this site, so a widget can hold on to
  /// it for the lifetime of a connected site.
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

  /// What is held for a record right now, or null if it has never arrived.
  T? read<T extends Storable<T>>(String siteUrl, Object id) =>
      (_refs[(siteUrl, T, id)] as Ref<T>?)?.value;

  /// Puts a freshly fetched record in, and returns the copy that is now held.
  ///
  /// The return value is what [Storable.merge] decided, which is not always
  /// [record] — so callers that go on to use the record should use this rather
  /// than what they passed.
  T put<T extends Storable<T>>(String siteUrl, T record) {
    final cell = _cell<T>(siteUrl, record.storeId);
    final held = cell.value;
    final merged = held == null ? record : held.merge(record);
    if (!identical(held, merged)) _bump(siteUrl, T);
    cell._set(merged);
    return merged;
  }

  /// [put] for a payload's worth of records.
  List<T> putAll<T extends Storable<T>>(String siteUrl, Iterable<T> records) =>
      [for (final record in records) put(siteUrl, record)];

  /// Rewrites a record already held, and does nothing if it is not.
  ///
  /// This is how one view corrects another: opening a topic clears the unread
  /// badge on its row in every list at once, because there is only one row.
  /// Absent records are skipped rather than created — [change] has nothing to
  /// work from, and a record invented here would be a lie the site never told.
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

  /// Drops a record the site no longer serves.
  ///
  /// The ref stays, holding null: something may still be watching it, and what
  /// it should now be told is that the record is gone.
  void remove<T extends Storable<T>>(String siteUrl, Object id) {
    final cell = _refs[(siteUrl, T, id)] as Ref<T>?;
    if (cell?.value != null) _bump(siteUrl, T);
    cell?._set(null);
  }

  /// Forgets everything belonging to one site.
  ///
  /// For disconnecting: reconnecting can land on a different account, and what
  /// the last one could see is none of its business. Refs are emptied rather
  /// than disposed — a widget may still be listening while the frame that
  /// removes it is drawn, and a disposed notifier it re-listens to would throw.
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
