import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_activity_api.dart';
import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/site_lookup_failure.dart';
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
  final _accounts = <String, _PagedFeedAccount<BookmarkListFeed>>{};

  _PagedFeedAccount<BookmarkListFeed>? _currentAccount(String siteUrl) {
    final account = _accounts[siteUrl];
    return !isDisposed && account?.isCurrent == true ? account : null;
  }

  _PagedFeedAccount<BookmarkListFeed>? _accountFor(String siteUrl) {
    if (isDisposed) return null;
    final previous = _accounts[siteUrl];
    if (previous != null && !previous.isCurrent) {
      _retireAccount(previous, publish: true);
    }
    if (isDisposed) return null;
    if (_currentAccount(siteUrl) case final held?) return held;
    final account = _PagedFeedAccount(
      siteUrl,
      lifecycle.capture(siteUrl),
      const BookmarkListFeed(),
    );
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(
      () => _retireAccount(account, publish: true),
    );
    return account.isCurrent ? account : null;
  }

  bool _retireAccount(
    _PagedFeedAccount<BookmarkListFeed> account, {
    bool publish = false,
  }) {
    final owns = identical(_accounts[account.siteUrl], account);
    if (owns) _accounts.remove(account.siteUrl);
    account.retire();
    if (owns && publish) _publish();
    return owns;
  }

  BookmarkListFeed feedFor(String? siteUrl) => siteUrl == null
      ? const BookmarkListFeed()
      : _currentAccount(siteUrl)?.feed ?? const BookmarkListFeed();

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
    if ((loadMore || loadPrevious) && _currentAccount(siteUrl) == null) {
      return Future<void>.value();
    }
    final account = _accountFor(siteUrl);
    if (account == null) return Future<void>.value();
    final held = account.feed;
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
    return account.run(
      refresh: refresh,
      publishLoading: () {
        account.feed = held.loadingPage(prepend: loadPrevious);
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
    if (_currentAccount(instance.url) == null) return Future<void>.value();
    return load(instance, refresh: true);
  }

  Future<void> _loadPage(
    DiscourseInstance instance, {
    required _PagedRequest<BookmarkListFeed> request,
    required int page,
    required bool replace,
    required bool prepend,
  }) async {
    final siteUrl = instance.url;
    final username = instance.user?.username;
    if (username == null) return;

    void fail(String message) {
      final held = request.account.feed;
      request.account.feed = held.withError(message, retryFromStart: replace);
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
        request.account.feed = request.account.feed.withPage(
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
    final account = _accounts[siteUrl];
    return account != null && _retireAccount(account);
  }

  void publishRetirement() => notifySafely();

  void _publish() {
    notifySafely();
    changed();
  }

  @override
  void dispose() {
    for (final account in _accounts.values.toList()) {
      _retireAccount(account);
    }
    super.dispose();
  }
}

final class UserActivityOwner extends FrameSafeNotifier {
  UserActivityOwner({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.changed,
    this.username,
  });

  final String? username;
  final AccountActivityApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final VoidCallback changed;
  final _accounts = <String, _PagedFeedAccount<UserActivityFeed>>{};

  _PagedFeedAccount<UserActivityFeed>? _currentAccount(String siteUrl) {
    final account = _accounts[siteUrl];
    return !isDisposed && account?.isCurrent == true ? account : null;
  }

  _PagedFeedAccount<UserActivityFeed>? _accountFor(String siteUrl) {
    if (isDisposed) return null;
    final previous = _accounts[siteUrl];
    if (previous != null && !previous.isCurrent) {
      _retireAccount(previous, publish: true);
    }
    if (isDisposed) return null;
    if (_currentAccount(siteUrl) case final held?) return held;
    final account = _PagedFeedAccount(
      siteUrl,
      lifecycle.capture(siteUrl),
      const UserActivityFeed(),
    );
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(
      () => _retireAccount(account, publish: true),
    );
    return account.isCurrent ? account : null;
  }

  bool _retireAccount(
    _PagedFeedAccount<UserActivityFeed> account, {
    bool publish = false,
  }) {
    final owns = identical(_accounts[account.siteUrl], account);
    if (owns) _accounts.remove(account.siteUrl);
    account.retire();
    if (owns && publish) _publish();
    return owns;
  }

  static const int pageSize = 30;

  UserActivityFeed feedFor(String? siteUrl) => siteUrl == null
      ? const UserActivityFeed()
      : _currentAccount(siteUrl)?.feed ?? const UserActivityFeed();

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
    if ((loadMore || loadPrevious) && _currentAccount(siteUrl) == null) {
      return Future<void>.value();
    }
    final account = _accountFor(siteUrl);
    if (account == null) return Future<void>.value();
    final held = account.feed;
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
    return account.run(
      refresh: refresh,
      publishLoading: () {
        account.feed = held.loadingPage(
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
    required _PagedRequest<UserActivityFeed> request,
    required int offset,
    required bool replace,
    required bool prepend,
    required int limit,
  }) async {
    final siteUrl = instance.url;
    final username = this.username ?? instance.user?.username;
    if (username == null) return;

    void fail(String message) {
      final held = request.account.feed;
      request.account.feed = held.withError(message, retryFromStart: replace);
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
        request.account.feed = request.account.feed.withPage(
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
    final account = _accounts[siteUrl];
    return account != null && _retireAccount(account);
  }

  void publishRetirement() => notifySafely();

  void _publish() {
    notifySafely();
    changed();
  }

  @override
  void dispose() {
    for (final account in _accounts.values.toList()) {
      _retireAccount(account);
    }
    super.dispose();
  }
}

/// Retains one feed and its physical request lane for one captured account.
final class _PagedFeedAccount<F extends Object> {
  _PagedFeedAccount(this.siteUrl, this.lease, F empty)
    : _empty = empty,
      feed = empty;

  final String siteUrl;
  final SiteLease lease;
  final F _empty;
  F feed;
  void Function()? detach;
  _PagedRequest<F>? _active;
  bool _retired = false;
  bool get isCurrent => !_retired && lease.isCurrent;

  Future<void> run({
    required bool refresh,
    required void Function() publishLoading,
    required Future<void> Function(_PagedRequest<F> request) load,
  }) {
    if (!isCurrent) return Future<void>.value();
    final active = _active;
    if (active != null && !refresh) return active.future;
    final request = _PagedRequest(this);
    _active = request;

    void finish([Object? error, StackTrace? stackTrace]) {
      if (identical(_active, request)) _active = null;
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

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    feed = _empty;
    _active?.future.ignore();
    _active = null;
  }
}

final class _PagedRequest<F extends Object> {
  _PagedRequest(this.account);

  final _PagedFeedAccount<F> account;
  final _result = Completer<void>();

  SiteLease get lease => account.lease;
  Future<void> get future => _result.future;
  bool get isCurrent => account.isCurrent && identical(account._active, this);

  bool commit(SiteMutation mutation) => isCurrent && lease.commit(mutation);
}
