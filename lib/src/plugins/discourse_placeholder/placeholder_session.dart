import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'placeholder_store.dart';

const placeholderPluginId = PluginId('discourse-placeholder');
const placeholderSessionService = PluginServiceKey<PlaceholderSession>(
  owner: placeholderPluginId,
  name: 'values',
);

/// Owns account-bound value leases. Rendering and editing controllers stay in UI.
final class PlaceholderSession {
  PlaceholderSession({required this.persistence, required this.currentUser});
  final PlaceholderPersistence persistence;
  final PluginUserIdReader currentUser;
  final _posts = <PlaceholderPostId, _PlaceholderValues>{};
  final _pending = <Future<void>>{};
  final _persistenceOperations = SerialOperationQueue();
  bool _closed = false;

  PlaceholderLease acquire(String siteUrl, int topicId, int postId) {
    if (_closed) throw StateError('The placeholder session is closed.');
    final userId = currentUser(siteUrl);
    if (_closed) throw StateError('The placeholder session is closed.');
    final id = (
      siteUrl: siteUrl,
      userId: userId,
      topicId: topicId,
      postId: postId,
    );
    final values = _posts.putIfAbsent(id, () => _PlaceholderValues(this, id));
    final lease = PlaceholderLease._(values);
    values._leases.add(lease);
    if (values._leases.length == 1) unawaited(_track(values._restore));
    return lease;
  }

  void _release(PlaceholderLease lease, _PlaceholderValues values) {
    if (!values._leases.remove(lease) || values._leases.isNotEmpty) return;
    if (identical(_posts[values.id], values)) _posts.remove(values.id);
    values.dispose();
  }

  bool _current(_PlaceholderValues values) {
    if (_closed || !identical(_posts[values.id], values)) return false;
    final userId = currentUser(values.id.siteUrl);
    return !_closed &&
        identical(_posts[values.id], values) &&
        userId == values.id.userId;
  }

  Future<void> _track(Future<void> Function() operation) {
    late final Future<void> future;
    future = Future<void>.sync(operation)
        .catchError((Object error, StackTrace stack) {})
        .whenComplete(() => _pending.remove(future));
    _pending.add(future);
    return future;
  }

  Future<void> flush() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  Future<void> forget(String siteUrl) {
    final removal = _track(
      () => _persistenceOperations.run(
        owner: persistence,
        key: siteUrl,
        operation: () => persistence.forget(siteUrl),
      ),
    );
    final removed = _posts.values
        .where((v) => v.id.siteUrl == siteUrl)
        .toList();
    for (final values in removed) {
      _posts.remove(values.id);
      values._forget();
    }
    return removal;
  }

  Future<void> close() async {
    _closed = true;
    final retained = _posts.values.toList();
    _posts.clear();
    for (final values in retained) {
      values._forget();
    }
    await flush();
  }
}

/// One acquisition. Releasing it cannot revoke another reader of the same post.
final class PlaceholderLease extends FrameSafeNotifier {
  PlaceholderLease._(this._values) {
    _values.addListener(_changed);
  }

  final _PlaceholderValues _values;
  PlaceholderPostId get id => _values.id;
  bool get isCurrent => !isDisposed && _values.isCurrent;
  Map<String, String> get overrides => isCurrent ? _values.overrides : const {};

  void change(String key, String value, {String? defaultValue}) {
    if (isCurrent) _values.change(key, value, defaultValue: defaultValue);
  }

  void _changed() => notifySafely();

  void release() => dispose();

  @override
  void dispose() {
    if (isDisposed) return;
    _values.removeListener(_changed);
    super.dispose();
    _values._session._release(this, _values);
  }
}

final class _PlaceholderValues extends FrameSafeNotifier {
  _PlaceholderValues(this._session, this.id);
  final PlaceholderSession _session;
  final PlaceholderPostId id;
  final _overrides = <String, String>{};
  final _edited = <String>{};
  final _leases = <PlaceholderLease>{};

  bool get isCurrent => _session._current(this);
  Map<String, String> get overrides => Map.unmodifiable(_overrides);

  void _forget() {
    _overrides.clear();
    _edited.clear();
    notifySafely();
  }

  Future<void> _restore() async {
    final restored = await _session._persistenceOperations.run(
      owner: _session.persistence,
      key: id.siteUrl,
      operation: () => _session.persistence.read(id),
    );
    if (!isCurrent) return;
    for (final entry in restored.entries) {
      if (!_edited.contains(entry.key)) _overrides[entry.key] = entry.value;
    }
    notifySafely();
  }

  void change(String key, String value, {String? defaultValue}) {
    if (!isCurrent) return;
    _edited.add(key);
    final override = value.isEmpty || value == defaultValue ? null : value;
    if (override == null) {
      _overrides.remove(key);
    } else {
      _overrides[key] = override;
    }
    unawaited(
      _session._track(
        () => _session._persistenceOperations.run(
          owner: _session.persistence,
          key: id.siteUrl,
          operation: () => _session.persistence.write(id, key, override),
        ),
      ),
    );
    notifySafely();
  }
}
