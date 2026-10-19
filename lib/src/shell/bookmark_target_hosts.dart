part of 'bookmark_transactions.dart';

final class _BookmarkOpeningSession implements BookmarkSession {
  _BookmarkOpeningSession(this._owner, String siteUrl)
    : _lease = _owner.lifecycle.capture(siteUrl),
      siteContext = _owner.siteContextFor(siteUrl);

  final BookmarkTransactions _owner;
  final SiteLease _lease;

  @override
  final BookmarkSiteContext siteContext;

  @override
  bool get isCurrent => !_owner._disposed && _lease.isCurrent;
}

final class _CoreBookmarkTargetHost implements BookmarkTargetHost {
  _CoreBookmarkTargetHost(this._owner, this._targetType);

  final BookmarkTransactions _owner;
  final BookmarkTargetType _targetType;
  final Map<
    ({String siteUrl, int topicId, int targetId}),
    _BookmarkWriteListenable
  >
  _writeListenables = {};

  bool _owns(Bookmark bookmark) =>
      _owner._bookmarkTargetFor(bookmark) == _targetType;

  BookmarkWriteResult _foreignBookmark() => BookmarkWriteResult.refused(
    appL10n.thisBookmarkDoesNotBelongTo((_targetType.refreshLabel).toString()),
  );

  @override
  BookmarkSession captureSession(String siteUrl) =>
      _BookmarkOpeningSession(_owner, siteUrl);

  @override
  BookmarkSiteContext siteContextFor(String siteUrl) =>
      _owner.siteContextFor(siteUrl);

  @override
  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required int targetId,
  }) => _owner
      .forSite(siteUrl)
      .bookmarkWriteInFlight(
        topicId: topicId,
        targetType: _targetType,
        targetId: targetId,
      );

  @override
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int topicId,
    required int targetId,
  }) {
    final key = (siteUrl: siteUrl, topicId: topicId, targetId: targetId);
    return _writeListenables.putIfAbsent(
      key,
      () => _BookmarkWriteListenable(
        _owner.changes,
        () => bookmarkWriteInFlight(
          siteUrl: siteUrl,
          topicId: topicId,
          targetId: targetId,
        ),
        onUnused: (listenable) {
          if (identical(_writeListenables[key], listenable)) {
            _writeListenables.remove(key);
          }
        },
      ),
    );
  }

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _owner
      .forSite(siteUrl)
      .createBookmark(
        topicId: topicId,
        targetType: _targetType,
        targetId: targetId,
        name: name,
        reminderAt: reminderAt,
        autoDeletePreference: autoDeletePreference,
      );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _owner
        .forSite(siteUrl)
        .updateBookmark(
          topicId: topicId,
          bookmark: bookmark,
          name: name,
          reminderAt: reminderAt,
          autoDeletePreference: autoDeletePreference,
        );
  }

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _owner
        .forSite(siteUrl)
        .clearBookmarkReminder(topicId: topicId, bookmark: bookmark);
  }

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _owner
        .forSite(siteUrl)
        .deleteBookmark(topicId: topicId, bookmark: bookmark);
  }

  void dispose() {
    for (final listenable in _writeListenables.values) {
      listenable.dispose();
    }
    _writeListenables.clear();
  }
}

final class _PluginBookmarkTargetHost implements PluginBookmarkHost {
  _PluginBookmarkTargetHost(this._owner, this._targetType);

  final BookmarkTransactions _owner;
  final BookmarkTargetType _targetType;
  final Map<({String siteUrl, int targetId}), _BookmarkWriteListenable>
  _writeListenables = {};

  bool _owns(Bookmark bookmark) =>
      _owner._bookmarkTargetFor(bookmark) == _targetType;

  BookmarkWriteResult _foreignBookmark() => BookmarkWriteResult.refused(
    appL10n.thisBookmarkDoesNotBelongTo((_targetType.refreshLabel).toString()),
  );

  @override
  BookmarkSession captureSession(String siteUrl) =>
      _BookmarkOpeningSession(_owner, siteUrl);

  @override
  BookmarkSiteContext siteContextFor(String siteUrl) =>
      _owner.siteContextFor(siteUrl);

  @override
  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int targetId,
  }) => _owner
      .forSite(siteUrl)
      ._pluginBookmarkWriteInFlight(
        targetType: _targetType,
        targetId: targetId,
      );

  @override
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int targetId,
  }) {
    final key = (siteUrl: siteUrl, targetId: targetId);
    return _writeListenables.putIfAbsent(
      key,
      () => _BookmarkWriteListenable(
        _owner.changes,
        () => bookmarkWriteInFlight(siteUrl: siteUrl, targetId: targetId),
        onUnused: (listenable) {
          if (identical(_writeListenables[key], listenable)) {
            _writeListenables.remove(key);
          }
        },
      ),
    );
  }

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _owner
      .forSite(siteUrl)
      ._createBookmark(
        context: _pluginBookmarkWriteContext,
        targetType: _targetType,
        targetId: targetId,
        name: name,
        reminderAt: reminderAt,
        autoDeletePreference: autoDeletePreference,
      );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _owner
        .forSite(siteUrl)
        ._updateBookmark(
          context: _pluginBookmarkWriteContext,
          bookmark: bookmark,
          name: name,
          reminderAt: reminderAt,
          autoDeletePreference: autoDeletePreference,
        );
  }

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _owner
        .forSite(siteUrl)
        ._updateBookmark(
          context: _pluginBookmarkWriteContext,
          bookmark: bookmark,
          name: bookmark.name,
          autoDeletePreference: bookmark.autoDeletePreference,
        );
  }

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _owner
        .forSite(siteUrl)
        ._deleteBookmark(
          context: _pluginBookmarkWriteContext,
          bookmark: bookmark,
        );
  }

  void dispose() {
    for (final listenable in _writeListenables.values) {
      listenable.dispose();
    }
    _writeListenables.clear();
  }
}

final class _BookmarkWriteListenable extends ChangeNotifier
    implements ValueListenable<bool> {
  _BookmarkWriteListenable(
    Listenable source,
    bool Function() read, {
    required void Function(_BookmarkWriteListenable listenable) onUnused,
  }) : _source = source,
       _read = read,
       _release = onUnused,
       _value = read() {
    _source.addListener(_refresh);
  }

  final Listenable _source;
  final bool Function() _read;
  final void Function(_BookmarkWriteListenable listenable) _release;
  bool _value;
  bool _released = false;

  @override
  bool get value => _value;

  void _refresh() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (hasListeners || _released) return;
    _released = true;
    _release(this);
    // Flutter forbids disposal while a notification is in progress.
    scheduleMicrotask(dispose);
  }

  @override
  void dispose() {
    _released = true;
    _source.removeListener(_refresh);
    super.dispose();
  }
}
