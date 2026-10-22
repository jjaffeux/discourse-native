import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/bookmark_host.dart';
import '../plugin_api/shell_extensions.dart';

part 'bookmark_target_hosts.dart';

abstract interface class BookmarkReadProjection {
  int get epoch;
  int revision(int topicId);
  bool Function() guard(int topicId);
  Post postFromRead(int topicId, int version, Post incoming);
  Post preservePost(Post incoming);
  TopicDetail detailFromRead(int version, TopicDetail incoming);
  Topic prepareRow(Topic incoming, int? versionAtDispatch);
  Topic projectTopicRow(Topic incoming);
}

final class BookmarkTopicSnapshot {
  const BookmarkTopicSnapshot({required this.bookmarks, required this.posts});
  final List<Bookmark> bookmarks;
  final Map<int, Bookmark?> posts;
}

abstract interface class BookmarkTopicData {
  bool postWriting(int postId);
  void Function() holdPostWrite(int postId, {bool notifyOnRelease = true});
  Future<BookmarkTopicSnapshot?> readBookmarkMetadata(int topicId, String slug);
}

typedef _WriteCredential = ({
  String? apiKey,
  AccountRequestCredentials? request,
  WriteException? failure,
});

final class BookmarkTransactions {
  BookmarkTransactions({
    required this.api,
    required this.store,
    required this.credentials,
    required this.lifecycle,
    required this.instanceAt,
    required this.siteContextFor,
    required this.pluginStrategies,
    required this.topicData,
    required this.checklistWriting,
    required this.topicSlug,
    required this.changes,
    required this.changed,
    required this.refreshMenu,
    required this.refreshList,
  });

  final BookmarksWriteApi api;
  final Store store;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final DiscourseInstance? Function(String) instanceAt;
  final BookmarkSiteContext Function(String) siteContextFor;
  final Iterable<PluginBookmarkTargetStrategy> Function() pluginStrategies;
  final BookmarkTopicData? Function(String, SiteLease) topicData;
  final bool Function(String, int) checklistWriting;
  final String Function(String, int) topicSlug;
  final Listenable changes;
  final void Function() changed;
  final Future<void> Function(DiscourseInstance) refreshMenu;
  final Future<void> Function(DiscourseInstance) refreshList;

  final Map<String, BookmarkAccountSession> _accounts = {};
  final Map<BookmarkTargetType, _CoreBookmarkTargetHost> _coreHosts = {};
  final Map<BookmarkTargetType, _PluginBookmarkTargetHost> _pluginHosts = {};
  bool _disposed = false;

  BookmarkAccountSession forSite(String siteUrl) {
    if (_disposed) throw StateError('Bookmark transactions are disposed.');
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    final account = BookmarkAccountSession._(
      this,
      siteUrl,
      lifecycle.capture(siteUrl),
    );
    _accounts[siteUrl] = account;
    account._detach = account.lease.onRetire(() {
      account._retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  BookmarkAccountSession? forLease(String siteUrl, SiteLease lease) {
    if (_disposed || !lease.isCurrent) return null;
    final account = forSite(siteUrl);
    return identical(account.lease.session, lease.session) ? account : null;
  }

  BookmarkTargetHost bookmarkTarget(BookmarkTargetType type) {
    if (type != BookmarkTargetType.post && type != BookmarkTargetType.topic) {
      throw ArgumentError.value(
        type,
        'targetType',
        'Plugin bookmark targets require a plugin-scoped host.',
      );
    }
    return _coreHosts.putIfAbsent(
      type,
      () => _CoreBookmarkTargetHost(this, type),
    );
  }

  PluginBookmarkHost pluginTarget(BookmarkTargetType type) => _pluginHosts
      .putIfAbsent(type, () => _PluginBookmarkTargetHost(this, type));

  PluginBookmarkTargetStrategy? _pluginBookmarkStrategy(
    BookmarkTargetType type,
  ) {
    PluginBookmarkTargetStrategy? owner;
    for (final candidate in pluginStrategies()) {
      if (candidate.pluginBookmarkTarget != type) continue;
      if (owner != null) {
        throw StateError('Duplicate bookmark target ${type.id}.');
      }
      owner = candidate;
    }
    return owner;
  }

  BookmarkTargetType? _bookmarkTargetFor(Bookmark bookmark) {
    final core = bookmark.coreTargetType;
    if (core != null) return core;
    PluginBookmarkTargetStrategy? owner;
    for (final candidate in pluginStrategies()) {
      if (candidate.pluginBookmarkTarget.wireName !=
          bookmark.bookmarkableType) {
        continue;
      }
      if (owner != null) {
        throw StateError(
          'Duplicate bookmark wire type ${bookmark.bookmarkableType}.',
        );
      }
      owner = candidate;
    }
    return owner?.pluginBookmarkTarget;
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?._retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account._retire();
    }
    _accounts.clear();
    for (final host in _coreHosts.values) {
      host.dispose();
    }
    for (final host in _pluginHosts.values) {
      host.dispose();
    }
    _coreHosts.clear();
    _pluginHosts.clear();
  }
}

sealed class _BookmarkWriteContext {
  const _BookmarkWriteContext();
}

final class _TopicBookmarkWriteContext extends _BookmarkWriteContext {
  const _TopicBookmarkWriteContext(this.topicId);

  final int topicId;
}

final class _PluginBookmarkWriteContext extends _BookmarkWriteContext {
  const _PluginBookmarkWriteContext();
}

const _pluginBookmarkWriteContext = _PluginBookmarkWriteContext();

final class BookmarkAccountSession implements BookmarkReadProjection {
  BookmarkAccountSession._(this._owner, this.siteUrl, this.lease);
  final BookmarkTransactions _owner;
  final String siteUrl;
  final SiteLease lease;
  final Set<int> _postBookmarkWritesInFlight = {};
  final Set<int> _topicBookmarkWritesInFlight = {};
  final Set<(BookmarkTargetType, int)> _pluginBookmarkWritesInFlight = {};
  final Map<int, int> _revisions = {};
  final Map<BookmarkTargetType, PluginBookmarkTargetStrategy?> _strategies = {};
  late final BookmarkTopicData? _topicData = _owner.topicData(siteUrl, lease);
  void Function()? _detach;
  bool _retired = false;
  int _epoch = 0;
  bool get isCurrent => !_retired && !_owner._disposed && lease.isCurrent;
  Store get _store => _owner.store;
  @override
  int get epoch => _epoch;
  @override
  int revision(int topicId) => _revisions[topicId] ?? 0;
  bool postBookmarkWriting(int postId) =>
      isCurrent && _postBookmarkWritesInFlight.contains(postId);

  void _retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    _postBookmarkWritesInFlight.clear();
    _topicBookmarkWritesInFlight.clear();
    _pluginBookmarkWritesInFlight.clear();
    _revisions.clear();
    _strategies.clear();
  }

  void _notify() {
    if (isCurrent) _owner.changed();
  }

  BookmarkWriteResult _retiredResult() => BookmarkWriteResult.reconciled(
    appL10n.theForumChangedBeforeTheBookmarkFinished,
  );

  Future<_WriteCredential> _credentialForWrite() async {
    try {
      final request = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(_owner.credentials);
      return request.apiKey == null
          ? (
              apiKey: null,
              request: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (apiKey: request.apiKey, request: request, failure: null);
    } catch (error) {
      return (
        apiKey: null,
        request: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  @override
  bool Function() guard(int topicId) {
    final version = revision(topicId);
    return () => isCurrent && version == revision(topicId);
  }

  @override
  Post preservePost(Post incoming) {
    final held = _store.read<Post>(siteUrl, incoming.id);
    return held == null ? incoming : incoming.withBookmarkOf(held);
  }

  @override
  Post postFromRead(int topicId, int version, Post incoming) =>
      version == revision(topicId) ? incoming : preservePost(incoming);
  @override
  TopicDetail detailFromRead(int version, TopicDetail incoming) {
    final held = _store.read<TopicDetail>(siteUrl, incoming.id);
    return version == revision(incoming.id) || held == null
        ? incoming
        : incoming.withBookmarksOf(held);
  }

  @override
  Topic prepareRow(Topic incoming, int? versionAtDispatch) {
    if (!isCurrent || versionAtDispatch == null || versionAtDispatch == epoch) {
      return incoming;
    }
    final held = _store.read<Topic>(siteUrl, incoming.id);
    final detail = _store.read<TopicDetail>(siteUrl, incoming.id);
    if (held == null && detail == null) return incoming;
    return incoming.copyWith(
      bookmarked: held?.bookmarked ?? detail?.hasBookmarks ?? false,
    );
  }

  @override
  Topic projectTopicRow(Topic incoming) {
    final detail = _store.read<TopicDetail>(siteUrl, incoming.id);
    return detail == null
        ? incoming
        : incoming.copyWith(bookmarked: detail.hasBookmarks);
  }

  bool Function() _advanceBookmarks(int topicId) {
    _revisions[topicId] = revision(topicId) + 1;
    _epoch++;
    return guard(topicId);
  }

  void _update<T extends Storable<T>>(
    Object id,
    T Function(T) change,
    bool Function() current,
  ) {
    if (current()) _store.update<T>(siteUrl, id, change);
  }

  @visibleForTesting
  void acceptBookmark(int topicId, Bookmark bookmark, {required bool isPost}) {
    if (!isCurrent) return;
    final current = _advanceBookmarks(topicId);
    _update<TopicDetail>(
      topicId,
      (held) => held.withBookmark(bookmark),
      current,
    );
    final id = bookmark.bookmarkableId;
    if (isPost && id != null) {
      _update<Post>(id, (held) => held.withBookmark(bookmark), current);
    }
    _update<Topic>(topicId, (held) => held.copyWith(bookmarked: true), current);
    _notify();
  }

  void _removeCoreBookmark(
    int topicId,
    Bookmark bookmark, {
    required bool isPost,
    required bool? topicBookmarked,
  }) {
    if (!isCurrent) return;
    final current = _advanceBookmarks(topicId);
    _update<TopicDetail>(
      topicId,
      (held) => held.withoutBookmark(bookmark.id),
      current,
    );
    final id = bookmark.bookmarkableId;
    if (isPost && id != null) {
      _update<Post>(id, (held) => held.withBookmark(null), current);
    }
    _update<Topic>(
      topicId,
      (held) => held.copyWith(bookmarked: topicBookmarked == true),
      current,
    );
    _notify();
  }

  void _clearBookmarks(int topicId) {
    if (!isCurrent) return;
    final current = _advanceBookmarks(topicId);
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    if (detail != null) {
      for (final id in detail.stream) {
        _update<Post>(id, (held) => held.withBookmark(null), current);
      }
      _update<TopicDetail>(topicId, (held) => held.withoutBookmarks(), current);
    }
    _update<Topic>(
      topicId,
      (held) => held.copyWith(bookmarked: false),
      current,
    );
    _notify();
  }

  @visibleForTesting
  Future<void> refreshBookmarks(int topicId, String slug) async {
    if (!isCurrent) return;
    final current = _advanceBookmarks(topicId);
    try {
      final snapshot = await _topicData?.readBookmarkMetadata(topicId, slug);
      if (snapshot == null || !current()) return;
      for (final entry in snapshot.posts.entries) {
        _update<Post>(
          entry.key,
          (held) => held.withBookmark(entry.value),
          current,
        );
      }
      _update<TopicDetail>(
        topicId,
        (held) => held.copyWith(bookmarks: snapshot.bookmarks),
        current,
      );
      _update<Topic>(
        topicId,
        (held) => held.copyWith(bookmarked: snapshot.bookmarks.isNotEmpty),
        current,
      );
      _notify();
    } catch (_) {}
  }

  bool bookmarkWriteInFlight({
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    context: _TopicBookmarkWriteContext(topicId),
    targetType: targetType,
    targetId: targetId,
  );

  bool _pluginBookmarkWriteInFlight({
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    context: _pluginBookmarkWriteContext,
    targetType: targetType,
    targetId: targetId,
  );

  bool _bookmarkWriteInFlight({
    required _BookmarkWriteContext context,
    required BookmarkTargetType targetType,
    required int targetId,
  }) {
    if (!isCurrent) return false;
    if (targetType == BookmarkTargetType.post) {
      return _postBookmarkWriteInFlight(targetId);
    }
    if (targetType == BookmarkTargetType.topic) {
      if (context case _TopicBookmarkWriteContext(:final topicId)) {
        return _topicBookmarkWritesInFlight.contains(topicId);
      }
      return false;
    }
    return _pluginBookmarkWritesInFlight.contains((targetType, targetId));
  }

  bool _postBookmarkWriteInFlight(int postId) {
    final key = postId;
    return _postBookmarkWritesInFlight.contains(key) ||
        ((_topicData?.postWriting(postId) ?? false) &&
            !_owner.checklistWriting(siteUrl, key));
  }

  PluginBookmarkTargetStrategy? _pluginBookmarkStrategy(
    BookmarkTargetType type,
  ) =>
      _strategies.putIfAbsent(type, () => _owner._pluginBookmarkStrategy(type));
  BookmarkTargetType? _bookmarkTargetFor(Bookmark bookmark) =>
      _owner._bookmarkTargetFor(bookmark);

  bool _bookmarkContextMatches(
    BookmarkTargetType targetType,
    _BookmarkWriteContext context,
  ) {
    final coreTarget =
        targetType == BookmarkTargetType.post ||
        targetType == BookmarkTargetType.topic;
    return switch (context) {
      _TopicBookmarkWriteContext(:final topicId) => coreTarget && topicId > 0,
      _PluginBookmarkWriteContext() => !coreTarget,
    };
  }

  Future<BookmarkWriteResult> createBookmark({
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _createBookmark(
    context: _TopicBookmarkWriteContext(topicId),
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _createBookmark({
    required _BookmarkWriteContext context,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) async {
    if (!isCurrent) return _retiredResult();
    final instance = _owner.instanceAt(siteUrl);
    final refreshTarget = targetType.refreshLabel;
    if (instance == null || !instance.isConnected) {
      return BookmarkWriteResult.refused(
        appL10n.reconnectToThisForumToBookmarkIt,
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetRequiresItsOwningContext,
      );
    }
    if (targetType != BookmarkTargetType.post &&
        targetType != BookmarkTargetType.topic &&
        _pluginBookmarkStrategy(targetType) == null) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetIsNotAvailableInThisBuild,
      );
    }
    final releaseBookmark = _beginBookmarkWrite(context, targetType, targetId);
    if (releaseBookmark == null) {
      return BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      );
    }
    try {
      final credential = await _credentialForWrite();
      if (!isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarkFinished,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      final preference =
          autoDeletePreference ??
          instance.user?.bookmarkAutoDeletePreference ??
          BookmarkAutoDeletePreference.clearReminder;
      final int id;
      try {
        id = await credential.request!.run(
          () => _owner.api.createBookmark(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            targetType: targetType,
            targetId: targetId,
            name: name,
            reminderAt: reminderAt,
            autoDeletePreference: preference,
          ),
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
            (refreshTarget).toString(),
          ),
        );
      }
      final postNumber = targetType == BookmarkTargetType.post
          ? _store.read<Post>(siteUrl, targetId)?.postNumber
          : null;
      final bookmark = Bookmark(
        id: id,
        bookmarkableId: targetId,
        bookmarkableType: targetType.wireName,
        postNumber: postNumber,
        name: name,
        reminderAt: reminderAt?.toUtc(),
        autoDeletePreference: preference,
      );
      final applied = lease.commit(() {
        _applyBookmark(context, bookmark, targetType);
      });
      if (!applied || !isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasSavedOnTheForum,
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(bookmark);
    } finally {
      releaseBookmark();
    }
  }

  Future<BookmarkWriteResult> updateBookmark({
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _updateBookmark(
    context: _TopicBookmarkWriteContext(topicId),
    bookmark: bookmark,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _updateBookmark({
    required _BookmarkWriteContext context,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) async {
    if (!isCurrent) return _retiredResult();
    final instance = _owner.instanceAt(siteUrl);
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkCannotBeEditedHere,
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetRequiresItsOwningContext,
      );
    }
    final refreshTarget = targetType.refreshLabel;
    final releaseBookmark = _beginBookmarkWrite(context, targetType, targetId);
    if (releaseBookmark == null) {
      return BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      );
    }
    try {
      final credential = await _credentialForWrite();
      if (!isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarkFinished,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      try {
        await credential.request!.run(
          () => _owner.api.updateBookmark(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            bookmarkId: bookmark.id,
            name: name,
            reminderAt: reminderAt,
            autoDeletePreference: autoDeletePreference,
          ),
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
            (refreshTarget).toString(),
          ),
        );
      }
      final updated = bookmark.copyWith(
        name: name,
        clearName: name == null,
        reminderAt: reminderAt?.toUtc(),
        clearReminder: reminderAt == null,
        autoDeletePreference: autoDeletePreference,
      );
      final applied = lease.commit(() {
        _applyBookmark(context, updated, targetType);
      });
      if (!applied || !isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasUpdatedOnTheForum,
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(updated);
    } finally {
      releaseBookmark();
    }
  }

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required int topicId,
    required Bookmark bookmark,
  }) => updateBookmark(
    topicId: topicId,
    bookmark: bookmark,
    name: bookmark.name,
    autoDeletePreference: bookmark.autoDeletePreference,
  );

  Future<BookmarkWriteResult> deleteBookmark({
    required int topicId,
    required Bookmark bookmark,
  }) => _deleteBookmark(
    context: _TopicBookmarkWriteContext(topicId),
    bookmark: bookmark,
  );

  Future<BookmarkWriteResult> _deleteBookmark({
    required _BookmarkWriteContext context,
    required Bookmark bookmark,
  }) async {
    if (!isCurrent) return _retiredResult();
    final instance = _owner.instanceAt(siteUrl);
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkCannotBeDeletedHere,
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetRequiresItsOwningContext,
      );
    }
    final refreshTarget = targetType.refreshLabel;
    final releaseBookmark = _beginBookmarkWrite(context, targetType, targetId);
    if (releaseBookmark == null) {
      return BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      );
    }
    try {
      final credential = await _credentialForWrite();
      if (!isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarkFinished,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      final bool? topicBookmarked;
      try {
        topicBookmarked = await credential.request!.run(
          () => _owner.api.deleteBookmark(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            bookmarkId: bookmark.id,
            targetType: targetType,
          ),
        );
        if (targetType.updatesTopicBookmarkState && topicBookmarked == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheDeletionTheIsBeingRefreshed(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheDeletionTheIsBeingRefreshed(
            (refreshTarget).toString(),
          ),
        );
      }
      final applied = lease.commit(() {
        _removeBookmark(
          context,
          bookmark,
          topicBookmarked: topicBookmarked,
          targetType: targetType,
        );
      });
      if (!applied || !isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasDeletedOnTheForum,
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        targetType: targetType,
        targetId: targetId,
      );
      return const BookmarkWriteResult.saved();
    } finally {
      releaseBookmark();
    }
  }

  Future<BookmarkWriteResult> deleteAllTopicBookmarks({
    required int topicId,
  }) async {
    final context = _TopicBookmarkWriteContext(topicId);
    if (!isCurrent) return _retiredResult();
    final instance = _owner.instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) {
      return BookmarkWriteResult.refused(
        appL10n.reconnectToThisForumToDeleteItsBookmarks,
      );
    }
    final key = topicId;
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    final postIds =
        detail?.postBookmarks
            .map((bookmark) => bookmark.bookmarkableId)
            .whereType<int>()
            .toSet() ??
        const <int>{};
    if (_topicBookmarkWritesInFlight.contains(key) ||
        postIds.any((id) => _postBookmarkWriteInFlight(id))) {
      return BookmarkWriteResult.refused(
        appL10n.anotherBookmarkActionIsStillFinishing,
      );
    }
    final data = _topicData;
    if (!isCurrent || data == null) return _retiredResult();
    _topicBookmarkWritesInFlight.add(key);
    _postBookmarkWritesInFlight.addAll(postIds);
    final releases = [
      for (final id in postIds) data.holdPostWrite(id, notifyOnRelease: false),
    ];
    _notify();
    try {
      final credential = await _credentialForWrite();
      if (!isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarksWereDeleted,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      try {
        await credential.request!.run(
          () => _owner.api.deleteTopicBookmarks(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
          ),
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(instance, context);
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheDeletionTheTopicIsBeingRefreshed,
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          _reconcileBookmarks(instance, context);
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheDeletionTheTopicIsBeingRefreshed,
        );
      }
      lease.commit(() => _clearBookmarks(topicId));
      _reconcileBookmarks(instance, context);
      return const BookmarkWriteResult.saved();
    } finally {
      _topicBookmarkWritesInFlight.remove(key);
      for (final postId in postIds) {
        _postBookmarkWritesInFlight.remove(postId);
      }
      for (final release in releases) {
        release();
      }
      _notify();
    }
  }

  void Function()? _beginBookmarkWrite(
    _BookmarkWriteContext context,
    BookmarkTargetType targetType,
    int targetId,
  ) {
    if (!isCurrent) return null;
    if (targetType == BookmarkTargetType.post) {
      final key = targetId;
      if (_postBookmarkWriteInFlight(targetId)) return null;
      _postBookmarkWritesInFlight.add(key);
      final data = _topicData;
      if (data == null) {
        _postBookmarkWritesInFlight.remove(key);
        return null;
      }
      final release = data.holdPostWrite(targetId);
      _notify();
      var released = false;
      return () {
        if (released) return;
        released = true;
        _postBookmarkWritesInFlight.remove(key);
        release();
      };
    }
    if (targetType == BookmarkTargetType.topic) {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      final key = topicId;
      if (!_topicBookmarkWritesInFlight.add(key)) return null;
      _notify();
      var released = false;
      return () {
        if (released) return;
        released = true;
        _topicBookmarkWritesInFlight.remove(key);
        _notify();
      };
    }
    if (_pluginBookmarkStrategy(targetType) == null) return null;
    final key = (targetType, targetId);
    if (!_pluginBookmarkWritesInFlight.add(key)) return null;
    _notify();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _pluginBookmarkWritesInFlight.remove(key);
      _notify();
    };
  }

  void _applyBookmark(
    _BookmarkWriteContext context,
    Bookmark bookmark,
    BookmarkTargetType targetType,
  ) {
    if (!isCurrent) return;
    final targetId = bookmark.bookmarkableId;
    final plugin = _pluginBookmarkStrategy(targetType);
    if (plugin != null) {
      if (targetId != null) {
        plugin.putPluginBookmark(siteUrl, targetId, bookmark);
      }
      _notify();
      return;
    }
    acceptBookmark(
      (context as _TopicBookmarkWriteContext).topicId,
      bookmark,
      isPost: targetType == BookmarkTargetType.post,
    );
  }

  void _removeBookmark(
    _BookmarkWriteContext context,
    Bookmark bookmark, {
    required bool? topicBookmarked,
    required BookmarkTargetType targetType,
  }) {
    if (!isCurrent) return;
    final targetId = bookmark.bookmarkableId;
    final plugin = _pluginBookmarkStrategy(targetType);
    if (plugin != null) {
      if (targetId != null) plugin.removePluginBookmark(siteUrl, targetId);
      _notify();
      return;
    }
    _removeCoreBookmark(
      (context as _TopicBookmarkWriteContext).topicId,
      bookmark,
      isPost: targetType == BookmarkTargetType.post,
      topicBookmarked: topicBookmarked,
    );
  }

  void _reconcileBookmarks(
    DiscourseInstance instance,
    _BookmarkWriteContext context, {
    BookmarkTargetType targetType = BookmarkTargetType.topic,
    int? targetId,
  }) {
    if (!isCurrent) return;
    final plugin = _pluginBookmarkStrategy(targetType);
    if (plugin != null && targetId != null) {
      unawaited(
        Future<void>.sync(
          () => plugin.reconcilePluginBookmark(siteUrl, targetId),
        ).catchError((Object error, StackTrace stackTrace) {}),
      );
    } else {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      unawaited(refreshBookmarks(topicId, _owner.topicSlug(siteUrl, topicId)));
    }
    if (!isCurrent) return;
    unawaited(_owner.refreshMenu(instance));
    if (!isCurrent) return;
    unawaited(_owner.refreshList(instance));
  }
}
