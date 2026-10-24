import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/bookmark_feed.dart';
import '../models/discourse_instance.dart';
import '../models/user_activity_feed.dart';

final class BookmarkListOwner extends FrameSafeNotifier {
  BookmarkListOwner({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.changed,
  });

  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final VoidCallback changed;
  final Map<String, BookmarkListFeed> _feeds = {};
  late final _requests = _PagedRequestSlot(lifecycle);

  BookmarkListFeed feedFor(String? siteUrl) => siteUrl == null
      ? const BookmarkListFeed()
      : _feeds[siteUrl] ?? const BookmarkListFeed();

  Future<void> load(
    DiscourseInstance instance, {
    bool refresh = false,
    bool loadMore = false,
    bool loadPrevious = false,
  }) {
    assert(
      [refresh, loadMore, loadPrevious].where((value) => value).length <= 1,
    );
    if (isDisposed || !instance.isConnected) return Future<void>.value();

    final siteUrl = instance.url;
    final held = feedFor(siteUrl);
    if (!refresh && !loadMore && !loadPrevious && held.loaded) {
      return Future<void>.value();
    }
    if (loadMore && (!held.loaded || !held.hasMore)) {
      return Future<void>.value();
    }

    if (loadPrevious && (!held.loaded || !held.hasPrevious)) {
      return Future<void>.value();
    }

    final replace = refresh || !held.loaded;
    final page = replace
        ? 0
        : loadPrevious
        ? held.previousPage
        : held.nextPage;
    return _requests.run(
      siteUrl,
      refresh: refresh,
      publishLoading: () {
        _feeds[siteUrl] = held.loadingPage(prepend: loadPrevious);
        _publish();
      },
      load: (request) => _loadPage(
        instance,
        request: request,
        page: page,
        replace: replace,
        prepend: loadPrevious,
      ),
    );
  }

  /// A bookmark write invalidates a list already on hand, which Back would
  /// otherwise show again unchanged. A list never opened is left for the page
  /// to load when it is.
  Future<void> refreshLoaded(DiscourseInstance instance) {
    if (!_feeds.containsKey(instance.url)) return Future<void>.value();
    return load(instance, refresh: true);
  }

  Future<void> _loadPage(
    DiscourseInstance instance, {
    required _PagedRequest request,
    required int page,
    required bool replace,
    required bool prepend,
  }) async {
    final siteUrl = instance.url;
    final username = instance.user?.username;
    if (username == null) return;

    void fail(String message) {
      final held = feedFor(siteUrl);
      _feeds[siteUrl] = held.withError(message, retryFromStart: replace);
    }

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        request.lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!request.isCurrent) {
        return;
      }
      if (apiKey == null) {
        request.commit(() {
          fail(
            appL10n.reconnectToToSeeYourBookmarks((instance.host).toString()),
          );
          _publish();
        });
        return;
      }
      final loaded = await auth.run(
        () => api.bookmarkListPage(
          siteUrl: siteUrl,
          apiKey: apiKey,
          username: username,
          page: page,
        ),
      );
      if (prepend && !loaded.hasMore && request.isCurrent) {
        await load(instance, refresh: true);
        return;
      }
      request.commit(() {
        _feeds[siteUrl] = feedFor(siteUrl).withPage(
          loaded,
          replace: replace,
          prepend: prepend,
          requestPage: page,
        );
        _publish();
      });
    } on SiteLookupException catch (error) {
      if (!request.isCurrent) {
        return;
      }

      request.commit(() {
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
        );
        _publish();
      });
    } catch (error) {
      if (!request.isCurrent) {
        return;
      }

      request.commit(() {
        fail(appL10n.couldnTLoadBookmarksFrom((instance.host).toString()));
        _publish();
      });
    }
  }

  bool retire(String siteUrl) {
    final hadFeed = _feeds.remove(siteUrl) != null;
    _requests.forget(siteUrl);
    return hadFeed;
  }

  void publishRetirement() => notifySafely();

  void _publish() {
    notifySafely();
    changed();
  }

  @override
  void dispose() {
    _requests.clear();
    _feeds.clear();
    super.dispose();
  }
}

final class UserActivityOwner extends FrameSafeNotifier {
  UserActivityOwner({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.changed,
  });

  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final VoidCallback changed;
  final Map<String, UserActivityFeed> _feeds = {};
  late final _requests = _PagedRequestSlot(lifecycle);

  static const int pageSize = 30;

  UserActivityFeed feedFor(String? siteUrl) => siteUrl == null
      ? const UserActivityFeed()
      : _feeds[siteUrl] ?? const UserActivityFeed();

  Future<void> load(
    DiscourseInstance instance, {
    bool refresh = false,
    bool loadMore = false,
    bool loadPrevious = false,
  }) {
    assert(
      [refresh, loadMore, loadPrevious].where((value) => value).length <= 1,
    );
    if (isDisposed || !instance.isConnected) return Future<void>.value();

    final siteUrl = instance.url;
    final held = feedFor(siteUrl);
    if (!refresh && !loadMore && !loadPrevious && held.loaded) {
      return Future<void>.value();
    }
    if (loadMore && (!held.loaded || !held.hasMore)) {
      return Future<void>.value();
    }

    if (loadPrevious && (!held.loaded || !held.hasPrevious)) {
      return Future<void>.value();
    }

    final replace = refresh || !held.loaded;
    final offset = replace
        ? 0
        : loadPrevious
        ? held.previousOffset(pageSize)
        : held.nextOffset;
    final limit = loadPrevious ? held.firstOffset - offset : pageSize;
    return _requests.run(
      siteUrl,
      refresh: refresh,
      publishLoading: () {
        _feeds[siteUrl] = held.loadingPage(
          replace: replace,
          prepend: loadPrevious,
        );
        _publish();
      },
      load: (request) => _loadPage(
        instance,
        request: request,
        offset: offset,
        replace: replace,
        prepend: loadPrevious,
        limit: limit,
      ),
    );
  }

  Future<void> _loadPage(
    DiscourseInstance instance, {
    required _PagedRequest request,
    required int offset,
    required bool replace,
    required bool prepend,
    required int limit,
  }) async {
    final siteUrl = instance.url;
    final username = instance.user?.username;
    if (username == null) return;

    void fail(String message) {
      final held = feedFor(siteUrl);
      _feeds[siteUrl] = held.withError(message, retryFromStart: replace);
    }

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        request.lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!request.isCurrent) {
        return;
      }
      if (apiKey == null) {
        request.commit(() {
          fail(
            appL10n.reconnectToToSeeYourActivity((instance.host).toString()),
          );
          _publish();
        });
        return;
      }
      final page = await auth.run(
        () => api.userActivity(
          siteUrl: siteUrl,
          apiKey: apiKey,
          username: username,
          offset: offset,
          limit: limit,
        ),
      );
      if (prepend && page.rawItemCount < limit && request.isCurrent) {
        await load(instance, refresh: true);
        return;
      }
      request.commit(() {
        _feeds[siteUrl] = feedFor(siteUrl).withPage(
          page,
          limit: limit,
          replace: replace,
          prepend: prepend,
          requestOffset: offset,
        );
        _publish();
      });
    } on SiteLookupException catch (error) {
      if (!request.isCurrent) {
        return;
      }

      request.commit(() {
        fail(
          error.failure == SiteLookupFailure.notDiscourse
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
        );
        _publish();
      });
    } catch (error) {
      if (!request.isCurrent) {
        return;
      }

      request.commit(() {
        fail(appL10n.couldnTLoadActivityFrom((instance.host).toString()));
        _publish();
      });
    }
  }

  bool retire(String siteUrl) {
    final hadFeed = _feeds.remove(siteUrl) != null;
    _requests.forget(siteUrl);
    return hadFeed;
  }

  void publishRetirement() => notifySafely();

  void _publish() {
    notifySafely();
    changed();
  }

  @override
  void dispose() {
    _requests.clear();
    _feeds.clear();
    super.dispose();
  }
}

final class _PagedRequestSlot {
  _PagedRequestSlot(this.lifecycle);

  final SiteLifecycle lifecycle;
  final Map<String, _PagedRequest> _requests = {};

  Future<void> run(
    String siteUrl, {
    required bool refresh,
    required void Function() publishLoading,
    required Future<void> Function(_PagedRequest request) load,
  }) {
    final active = _requests[siteUrl];
    if (active != null && !refresh) return active.future;

    final request = _PagedRequest(this, siteUrl, lifecycle.capture(siteUrl));
    _requests[siteUrl] = request;

    void finish([Object? error, StackTrace? stackTrace]) {
      if (identical(_requests[siteUrl], request)) {
        _requests.remove(siteUrl);
      }
      if (error == null) {
        request._result.complete();
      } else {
        request._result.completeError(error, stackTrace!);
      }
    }

    publishLoading();
    if (!request.isCurrent) {
      finish();
      return request.future;
    }
    try {
      unawaited(
        load(request).then<void>(
          (_) => finish(),
          onError: (Object error, StackTrace stackTrace) =>
              finish(error, stackTrace),
        ),
      );
    } catch (error, stackTrace) {
      finish(error, stackTrace);
    }
    return request.future;
  }

  void forget(String siteUrl) => _requests.remove(siteUrl)?.future.ignore();

  void clear() => _requests.clear();
}

final class _PagedRequest {
  _PagedRequest(this._slot, this.siteUrl, this.lease);

  final _PagedRequestSlot _slot;
  final String siteUrl;
  final SiteLease lease;
  final _result = Completer<void>();

  Future<void> get future => _result.future;

  bool get isCurrent =>
      lease.isCurrent && identical(_slot._requests[siteUrl], this);

  bool commit(SiteMutation mutation) => isCurrent && lease.commit(mutation);
}
