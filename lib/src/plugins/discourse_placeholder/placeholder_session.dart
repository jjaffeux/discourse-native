import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/store_diagnostics.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
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
  final _posts = <PlaceholderPostId, PlaceholderValues>{};
  final _pending = <Future<void>>{};
  bool _closed = false;

  PlaceholderValues acquire(String siteUrl, int topicId, int postId) {
    final id = (
      siteUrl: siteUrl,
      userId: currentUser(siteUrl),
      topicId: topicId,
      postId: postId,
    );
    final values = _posts.putIfAbsent(id, () => PlaceholderValues._(this, id));
    values._readers++;
    if (values._readers == 1) _track(values._restore);
    return values;
  }

  void release(PlaceholderValues values) {
    if (--values._readers != 0) return;
    if (identical(_posts[values.id], values)) _posts.remove(values.id);
    values.dispose();
  }

  bool _current(PlaceholderValues values) =>
      !_closed &&
      identical(_posts[values.id], values) &&
      currentUser(values.id.siteUrl) == values.id.userId;

  void _track(Future<void> Function() operation) {
    late final Future<void> future;
    future = Future<void>.sync(operation)
        .catchError((Object error, StackTrace stack) {
          reportStorageFailure(error, stack, 'placeholder.session');
        })
        .whenComplete(() => _pending.remove(future));
    _pending.add(future);
  }

  Future<void> flush() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  Future<void> forget(String siteUrl) async {
    final removed = _posts.values
        .where((v) => v.id.siteUrl == siteUrl)
        .toList();
    for (final values in removed) {
      _posts.remove(values.id);
      values._forget();
    }
    // Accepted writes finish before removal, and detached leases reject new ones.
    await flush();
    try {
      await persistence.forget(siteUrl);
    } catch (error, stack) {
      reportStorageFailure(error, stack, 'placeholder.session.forget');
    }
  }

  Future<void> close() async {
    _closed = true;
    _posts.clear();
    await flush();
  }
}

final class PlaceholderValues extends ChangeNotifier {
  PlaceholderValues._(this._session, this.id);
  final PlaceholderSession _session;
  final PlaceholderPostId id;
  final _overrides = <String, String>{};
  final _edited = <String>{};
  int _readers = 0;

  bool get isCurrent => _session._current(this);
  Map<String, String> get overrides => Map.unmodifiable(_overrides);

  void _forget() {
    _overrides.clear();
    notifyListeners();
  }

  Future<void> _restore() async {
    final restored = await _session.persistence.read(id);
    if (!isCurrent) return;
    for (final entry in restored.entries) {
      if (!_edited.contains(entry.key)) _overrides[entry.key] = entry.value;
    }
    notifyListeners();
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
    _session._track(() => _session.persistence.write(id, key, override));
    notifyListeners();
  }
}
