import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/post.dart';

typedef TopicReaderWindow = ({
  List<int> stream,
  (int, int)? range,
  List<int> ids,
});

/// Derived reader data, bounded to one window and saved target per live tab.
final class TopicReaderProjections {
  TopicReaderProjections(this._store);

  final Store _store;
  final _tabs = <(String, String), TopicReaderProjection>{};
  bool _disposed = false;

  TopicReaderProjection? forTab(String siteUrl, String tabId, SiteLease lease) {
    if (_disposed || !lease.isCurrent) return null;
    final key = (siteUrl, tabId);
    final held = _tabs[key];
    if (held != null && identical(held._lease.session, lease.session)) {
      return held;
    }
    held?._retire();
    final reader = TopicReaderProjection._(_store, siteUrl, lease);
    _tabs[key] = reader;
    reader._detach = lease.onRetire(() {
      reader._retire();
      if (identical(_tabs[key], reader)) _tabs.remove(key);
    });
    return reader;
  }

  void retainTabs(String siteUrl, SiteLease lease, Set<String> liveTabIds) {
    if (_disposed || !lease.isCurrent) return;
    _tabs.removeWhere((key, reader) {
      if (key.$1 != siteUrl ||
          !identical(reader._lease.session, lease.session) ||
          liveTabIds.contains(key.$2)) {
        return false;
      }
      reader._retire();
      return true;
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final reader in _tabs.values) {
      reader._retire();
    }
    _tabs.clear();
  }
}

final class TopicReaderProjection {
  TopicReaderProjection._(this._store, this._siteUrl, this._lease);

  final Store _store;
  final String _siteUrl;
  final SiteLease _lease;
  void Function()? _detach;
  bool _retired = false;
  ({List<int> stream, int? target, Object? structure})? _key;
  TopicReaderWindow _window = emptyWindow;
  List<int>? _stream;
  Map<int, int> _positions = {};
  StoreStructureDependency? _structure;
  ({List<int> ids, int target, bool hasEarlier, Object? structure, int? index})?
  _initial;

  static const TopicReaderWindow emptyWindow = (
    stream: [],
    range: null,
    ids: [],
  );

  bool get isCurrent => !_retired && _lease.isCurrent;

  void _retire() {
    _retired = true;
    _detach?.call();
    _detach = null;
    _key = null;
    _structure?.dispose();
    _structure = null;
    _stream = null;
    _positions = {};
    _window = emptyWindow;
    _initial = null;
  }

  TopicReaderWindow project(List<int> stream, int? target) {
    if (!isCurrent) return emptyWindow;
    if (!identical(_stream, stream)) {
      _structure?.dispose();
      _stream = stream;
      final positions = <int, int>{};
      for (var index = 0; index < stream.length; index++) {
        positions.putIfAbsent(stream[index], () => index);
      }
      _positions = positions;
      _structure = _store.trackStructureWhere<Post>(
        _siteUrl,
        positions.containsKey,
      );
    }
    final structure = _structure!.token;
    final key = _key;
    if (key != null &&
        identical(key.stream, stream) &&
        key.target == target &&
        identical(key.structure, structure)) {
      return _window;
    }
    final range = _loadedRange(stream, target);
    _key = (stream: stream, target: target, structure: structure);
    _initial = null;
    return _window = (
      stream: stream,
      range: range,
      ids: range == null ? const [] : stream.sublist(range.$1, range.$2 + 1),
    );
  }

  (int, int)? _loadedRange(List<int> stream, int? target) {
    if (stream.isEmpty) return null;
    var anchor = -1;
    final retained = _store.retainedRecords<Post>(_siteUrl);
    if (retained.length < stream.length) {
      for (var index = 0; index < stream.length; index++) {
        final post = _store.read<Post>(_siteUrl, stream[index]);
        if (post == null) break;
        if (target == null || post.postNumber >= target) {
          anchor = index;
          break;
        }
      }
      if (anchor < 0) {
        var fallback = -1;
        for (final post in retained) {
          if (post == null) continue;
          final index = _positions[post.id];
          if (index == null) continue;
          if (fallback < 0 || index < fallback) fallback = index;
          if ((target == null || post.postNumber >= target) &&
              (anchor < 0 || index < anchor)) {
            anchor = index;
          }
        }
        if (anchor < 0) anchor = fallback;
        if (anchor >= 0) _store.read<Post>(_siteUrl, stream[anchor]);
      }
    } else {
      if (target != null) {
        for (var i = 0; i < stream.length; i++) {
          final post = _store.read<Post>(_siteUrl, stream[i]);
          if (post != null && post.postNumber >= target) {
            anchor = i;
            break;
          }
        }
      }
      if (anchor < 0) {
        anchor = stream.indexWhere(
          (id) => _store.read<Post>(_siteUrl, id) != null,
        );
      }
    }
    if (anchor < 0) return null;
    var first = anchor;
    while (first > 0 &&
        _store.read<Post>(_siteUrl, stream[first - 1]) != null) {
      first--;
    }
    var last = anchor;
    while (last + 1 < stream.length &&
        _store.read<Post>(_siteUrl, stream[last + 1]) != null) {
      last++;
    }
    return (first, last);
  }

  int? initialIndex(List<int> ids, int target, {required bool hasEarlier}) {
    if (!isCurrent) return null;
    final structure = _structure?.token;
    final cached = _initial;
    if (cached != null &&
        identical(cached.ids, ids) &&
        cached.target == target &&
        cached.hasEarlier == hasEarlier &&
        identical(cached.structure, structure)) {
      return cached.index;
    }
    int? index;
    for (var i = 0; i < ids.length; i++) {
      final post = _store.read<Post>(_siteUrl, ids[i]);
      if (post != null && post.postNumber >= target) {
        index = i + (hasEarlier ? 1 : 0);
        break;
      }
    }
    _initial = (
      ids: ids,
      target: target,
      hasEarlier: hasEarlier,
      structure: structure,
      index: index,
    );
    return index;
  }

  List<int> pendingAfter(TopicReaderWindow window, int limit) {
    if (!isCurrent) return const [];
    final start = window.range == null ? 0 : window.range!.$2 + 1;
    final pending = <int>[];
    for (var index = start; index < window.stream.length; index++) {
      final id = window.stream[index];
      if (_store.containsRecord<Post>(_siteUrl, id)) continue;
      pending.add(id);
      if (pending.length == limit) break;
    }
    return pending;
  }

  List<int> pendingBefore(TopicReaderWindow window, int limit) {
    if (!isCurrent) return const [];
    final range = window.range;
    if (range == null || range.$1 == 0) return const [];
    final start = range.$1 > limit ? range.$1 - limit : 0;
    return [
      for (var i = start; i < range.$1; i++)
        if (_store.read<Post>(_siteUrl, window.stream[i]) == null)
          window.stream[i],
    ];
  }

  Post? megaEdge(
    TopicReaderWindow window,
    TopicDetail detail, {
    required bool newer,
  }) {
    if (!isCurrent || !detail.isMegaTopic) return null;
    final stream = window.stream;
    final range = window.range;
    if (range == null || !identical(stream, detail.stream)) return null;
    if (newer) {
      if (range.$2 + 1 < stream.length ||
          stream[range.$2] == detail.lastPostId) {
        return null;
      }
      return _store.read<Post>(_siteUrl, stream[range.$2]);
    }
    if (range.$1 > 0) return null;
    final first = _store.read<Post>(_siteUrl, stream.first);
    return first != null && first.postNumber > 1 ? first : null;
  }
}
