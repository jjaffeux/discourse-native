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

sealed class _AdmittedBookmarkTarget {
  _AdmittedBookmarkTarget(this.account, this.type, this.id, this._release);

  final BookmarkAccountSession account;
  final BookmarkTargetType type;
  final int id;
  final void Function() _release;
  bool _released = false;

  int? get postNumber => null;

  void apply(Bookmark bookmark);
  void remove(Bookmark bookmark, bool? topicBookmarked);
  void reconcileTarget();

  void reconcile(DiscourseInstance instance) {
    if (!account.isCurrent) return;
    reconcileTarget();
    if (!account.isCurrent) return;
    unawaited(account._owner.refreshMenu(instance));
    if (!account.isCurrent) return;
    unawaited(account._owner.refreshList(instance));
  }

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

final class _AdmittedCoreBookmarkTarget extends _AdmittedBookmarkTarget {
  _AdmittedCoreBookmarkTarget(
    BookmarkAccountSession account,
    BookmarkTargetType type,
    int id,
    this.topicId,
    void Function() release,
  ) : super(account, type, id, release);

  final int topicId;
  bool get isPost => type == BookmarkTargetType.post;

  @override
  int? get postNumber => isPost
      ? account._store.read<Post>(account.siteUrl, id)?.postNumber
      : null;

  @override
  void apply(Bookmark bookmark) =>
      account.acceptBookmark(topicId, bookmark, isPost: isPost);

  @override
  void remove(Bookmark bookmark, bool? topicBookmarked) =>
      account._removeCoreBookmark(
        topicId,
        bookmark,
        isPost: isPost,
        topicBookmarked: topicBookmarked,
      );

  @override
  void reconcileTarget() {
    unawaited(
      account.refreshBookmarks(
        topicId,
        account._owner.topicSlug(account.siteUrl, topicId),
      ),
    );
  }
}

final class _AdmittedPluginBookmarkTarget extends _AdmittedBookmarkTarget {
  _AdmittedPluginBookmarkTarget(
    super.account,
    super.type,
    super.id,
    super.release,
    this.strategy,
  );

  final PluginBookmarkTargetStrategy strategy;

  @override
  void apply(Bookmark bookmark) {
    if (!account.isCurrent) return;
    strategy.putPluginBookmark(account.siteUrl, id, bookmark);
    account._notify();
  }

  @override
  void remove(Bookmark bookmark, bool? topicBookmarked) {
    if (!account.isCurrent) return;
    strategy.removePluginBookmark(account.siteUrl, id);
    account._notify();
  }

  @override
  void reconcileTarget() {
    unawaited(
      Future<void>.sync(
        () => strategy.reconcilePluginBookmark(account.siteUrl, id),
      ).catchError((Object error, StackTrace stackTrace) {}),
    );
  }
}

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
    topicId: topicId,
    targetType: targetType,
    targetId: targetId,
  );

  bool _pluginBookmarkWriteInFlight({
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    topicId: null,
    targetType: targetType,
    targetId: targetId,
  );

  bool _bookmarkWriteInFlight({
    required int? topicId,
    required BookmarkTargetType targetType,
    required int targetId,
  }) {
    if (!isCurrent) return false;
    if (targetType == BookmarkTargetType.post) {
      return _postBookmarkWriteInFlight(targetId);
    }
    if (targetType == BookmarkTargetType.topic) {
      return topicId != null && _topicBookmarkWritesInFlight.contains(topicId);
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

  Future<BookmarkWriteResult> createBookmark({
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _createBookmark(
    topicId: topicId,
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _createBookmark({
    required int? topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) async {
    if (!isCurrent) return _retiredResult();
    final instance = _owner.instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) {
      return BookmarkWriteResult.refused(
        appL10n.reconnectToThisForumToBookmarkIt,
      );
    }
    final admission = _admitBookmarkTarget(
      topicId: topicId,
      targetType: targetType,
      targetId: targetId,
      creating: true,
    );
    if (admission.refusal case final refusal?) return refusal;
    final target = admission.target!;
    final refreshTarget = target.type.refreshLabel;
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
            targetType: target.type,
            targetId: target.id,
            name: name,
            reminderAt: reminderAt,
            autoDeletePreference: preference,
          ),
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          target.reconcile(instance);
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          target.reconcile(instance);
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
            (refreshTarget).toString(),
          ),
        );
      }
      final bookmark = Bookmark(
        id: id,
        bookmarkableId: target.id,
        bookmarkableType: target.type.wireName,
        postNumber: target.postNumber,
        name: name,
        reminderAt: reminderAt?.toUtc(),
        autoDeletePreference: preference,
      );
      final applied = lease.commit(() {
        target.apply(bookmark);
      });
      if (!applied || !isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasSavedOnTheForum,
        );
      }
      target.reconcile(instance);
      return BookmarkWriteResult.saved(bookmark);
    } finally {
      target.release();
    }
  }

  Future<BookmarkWriteResult> updateBookmark({
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _updateBookmark(
    topicId: topicId,
    bookmark: bookmark,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _updateBookmark({
    required int? topicId,
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
    final admission = _admitBookmarkTarget(
      topicId: topicId,
      targetType: targetType,
      targetId: targetId,
    );
    if (admission.refusal case final refusal?) return refusal;
    final target = admission.target!;
    final refreshTarget = target.type.refreshLabel;
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
            originalReminderAt: bookmark.reminderAt,
            autoDeletePreference: autoDeletePreference,
          ),
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          target.reconcile(instance);
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          target.reconcile(instance);
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
        target.apply(updated);
      });
      if (!applied || !isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasUpdatedOnTheForum,
        );
      }
      target.reconcile(instance);
      return BookmarkWriteResult.saved(updated);
    } finally {
      target.release();
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
  }) => _deleteBookmark(topicId: topicId, bookmark: bookmark);

  Future<BookmarkWriteResult> _deleteBookmark({
    required int? topicId,
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
    final admission = _admitBookmarkTarget(
      topicId: topicId,
      targetType: targetType,
      targetId: targetId,
    );
    if (admission.refusal case final refusal?) return refusal;
    final target = admission.target!;
    final refreshTarget = target.type.refreshLabel;
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
            targetType: target.type,
          ),
        );
        if (target.type.updatesTopicBookmarkState && topicBookmarked == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          target.reconcile(instance);
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheDeletionTheIsBeingRefreshed(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          target.reconcile(instance);
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheDeletionTheIsBeingRefreshed(
            (refreshTarget).toString(),
          ),
        );
      }
      final applied = lease.commit(() {
        target.remove(bookmark, topicBookmarked);
      });
      if (!applied || !isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasDeletedOnTheForum,
        );
      }
      target.reconcile(instance);
      return const BookmarkWriteResult.saved();
    } finally {
      target.release();
    }
  }

  Future<BookmarkWriteResult> deleteAllTopicBookmarks({
    required int topicId,
  }) async {
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
    final target = _AdmittedCoreBookmarkTarget(
      this,
      BookmarkTargetType.topic,
      topicId,
      topicId,
      () {
        _topicBookmarkWritesInFlight.remove(key);
        for (final postId in postIds) {
          _postBookmarkWritesInFlight.remove(postId);
        }
        for (final release in releases) {
          release();
        }
        _notify();
      },
    );
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
          target.reconcile(instance);
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheDeletionTheTopicIsBeingRefreshed,
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error) {
        if (isCurrent) {
          target.reconcile(instance);
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheDeletionTheTopicIsBeingRefreshed,
        );
      }
      lease.commit(() => _clearBookmarks(topicId));
      target.reconcile(instance);
      return const BookmarkWriteResult.saved();
    } finally {
      target.release();
    }
  }

  ({_AdmittedBookmarkTarget? target, BookmarkWriteResult? refusal})
  _admitBookmarkTarget({
    required int? topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    bool creating = false,
  }) {
    final core =
        targetType == BookmarkTargetType.post ||
        targetType == BookmarkTargetType.topic;
    if (core ? topicId == null || topicId <= 0 : topicId != null) {
      return (
        target: null,
        refusal: BookmarkWriteResult.refused(
          appL10n.thisBookmarkTargetRequiresItsOwningContext,
        ),
      );
    }
    final strategy = !core && creating
        ? _pluginBookmarkStrategy(targetType)
        : null;
    if (creating && !core && strategy == null) {
      return (
        target: null,
        refusal: BookmarkWriteResult.refused(
          appL10n.thisBookmarkTargetIsNotAvailableInThisBuild,
        ),
      );
    }
    final busy = (
      target: null,
      refusal: BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      ),
    );
    if (!isCurrent) return busy;
    final _AdmittedBookmarkTarget target;
    if (targetType == BookmarkTargetType.post) {
      if (_postBookmarkWriteInFlight(targetId)) return busy;
      _postBookmarkWritesInFlight.add(targetId);
      final data = _topicData;
      if (data == null) {
        _postBookmarkWritesInFlight.remove(targetId);
        return busy;
      }
      final release = data.holdPostWrite(targetId);
      target = _AdmittedCoreBookmarkTarget(
        this,
        targetType,
        targetId,
        topicId!,
        () {
          _postBookmarkWritesInFlight.remove(targetId);
          release();
        },
      );
    } else if (targetType == BookmarkTargetType.topic) {
      if (!_topicBookmarkWritesInFlight.add(topicId!)) return busy;
      target = _AdmittedCoreBookmarkTarget(
        this,
        targetType,
        targetId,
        topicId,
        () {
          _topicBookmarkWritesInFlight.remove(topicId);
          _notify();
        },
      );
    } else {
      final admittedStrategy = creating
          ? strategy
          : _pluginBookmarkStrategy(targetType);
      final key = (targetType, targetId);
      if (admittedStrategy == null || !_pluginBookmarkWritesInFlight.add(key)) {
        return busy;
      }
      target = _AdmittedPluginBookmarkTarget(this, targetType, targetId, () {
        _pluginBookmarkWritesInFlight.remove(key);
        _notify();
      }, admittedStrategy);
    }
    _notify();
    return (target: target, refusal: null);
  }
}
