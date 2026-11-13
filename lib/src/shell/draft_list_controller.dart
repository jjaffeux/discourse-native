import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/draft_feed.dart';
import '../models/user_draft.dart';

typedef ListedDraftDeleter =
    Future<void> Function(
      String siteUrl,
      UserDraft draft,
      bool Function() isCurrent,
    );

final class DraftListController extends FrameSafeNotifier {
  DraftListController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.deleteDraft,
    this.limit = pageSize,
  }) : assert(limit > 0);

  static const int pageSize = 30;

  final int limit;

  final DraftsApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final ListedDraftDeleter? deleteDraft;

  final Map<String, _DraftAccount> _accounts = {};

  _DraftAccount? _existingAccount(String siteUrl) {
    final account = _accounts[siteUrl];
    if (account == null || account.isCurrent) return account;
    account.retire();
    return null;
  }

  _DraftAccount _accountFor(String siteUrl) {
    final held = _existingAccount(siteUrl);
    if (held != null) return held;
    final account = _DraftAccount(this, siteUrl, lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.observeRetirement();
    return account;
  }

  void _retireAccount(_DraftAccount account) {
    if (!identical(_accounts[account.siteUrl], account)) return;
    account.retire();
    notifySafely();
  }

  DraftFeed feedFor(String? siteUrl) => siteUrl == null
      ? const DraftFeed()
      : _existingAccount(siteUrl)?.feed ?? const DraftFeed();

  bool deleting(String siteUrl, String draftKey) =>
      _existingAccount(siteUrl)?.deletions.containsKey(draftKey) ?? false;

  /// Mirrors core's `draft:destroyed` cache propagation for drafts removed
  /// from outside this controller (for example, from the composer).
  void recordDeleted(
    String siteUrl,
    String draftKey, {
    bool knownToExist = false,
  }) {
    if (isDisposed) return;
    final account = _accountFor(siteUrl);
    if (account.request != null) account.deletedWhileLoading.add(draftKey);
    account.feed = account.feed.without(draftKey, knownToExist: knownToExist);
    notifySafely();
  }

  Future<void> reconcileCount(
    DiscourseInstance instance, {
    required int previousCount,
  }) {
    if (isDisposed || !instance.isConnected) return Future<void>.value();
    final account = _existingAccount(instance.url);
    if (account == null) return Future<void>.value();
    final feed = account.feed;
    if (!feed.loaded && !feed.loading) return Future<void>.value();
    final count = instance.user!.draftCount;
    final total = feed.totalCount;
    final pendingDeletes = feed.drafts
        .where((draft) => account.deletions.containsKey(draft.key))
        .length;
    // A server count can arrive before its local deletion response. Those
    // deletions already explain the change and must not reset the page.
    if (total != null &&
        count <= total &&
        count >= total - pendingDeletes &&
        (count < total || count < previousCount)) {
      return Future<void>.value();
    }
    account.feed = feed.withoutTotalCount();
    notifySafely();
    if (!account.isCurrent) return Future<void>.value();
    return load(instance, refresh: true);
  }

  void invalidateTotalCount(String siteUrl) {
    if (isDisposed) return;
    final account = _existingAccount(siteUrl);
    if (account == null) return;
    account.feed = account.feed.withoutTotalCount();
    notifySafely();
  }

  Future<void> load(
    DiscourseInstance instance, {
    bool refresh = false,
    bool loadPrevious = false,
  }) async {
    assert(!(refresh && loadPrevious));
    if (isDisposed || !instance.isConnected) return;
    final siteUrl = instance.url;
    final account = _accountFor(siteUrl);
    final lease = account.lease;
    if (account.request != null) {
      if (refresh) {
        account.pendingRefresh = instance;
      }
      return;
    }
    // A refresh keeps the held rows visible until its first page replaces
    // them: the feed is shared by every panel and menu that lists drafts, and
    // a failed refresh must not cost the rows already on screen.
    final held = account.feed;
    refresh = refresh || held.requiresRefresh;
    loadPrevious = loadPrevious && !refresh;
    if (!refresh && loadPrevious && !held.hasPrevious) return;
    if (!refresh && !loadPrevious && held.loaded && !held.hasMore) return;

    final request = Object();
    account.request = request;
    account.feed = held.loadingMore(prepend: loadPrevious);
    notifySafely();
    // Publishing can synchronously dispose this owner through a listener.
    // Do not let that replacement boundary cross into credential storage.
    if (!_isCurrentLoad(account, request)) return;

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!_isCurrentLoad(account, request)) return;
      if (apiKey == null) {
        _commit(account, request, () {
          account.feed = account.feed.withError(
            appL10n.reconnectToToSeeYourDrafts((instance.host).toString()),
          );
        });
        return;
      }
      final current = account.feed;
      final offset = refresh
          ? 0
          : loadPrevious
          ? current.previousOffset(limit)
          : current.nextOffset;
      final requestLimit = loadPrevious ? current.firstOffset - offset : limit;
      final page = await auth.run(
        () => api.userDrafts(
          siteUrl: siteUrl,
          apiKey: apiKey,
          offset: offset,
          limit: requestLimit,
        ),
      );
      // A next page must build on the feed as it stands now, not the [held]
      // snapshot: a delete that landed during the request already removed its
      // row, and replaying the snapshot would put the row back. A refresh
      // restarts at the first page, so it replaces every held row instead.
      _commit(account, request, () {
        final removed = account.deletedWhileLoading;
        // Deletions of already loaded rows adjusted the cursor in `without`.
        // Only newly encountered deleted keys still need that adjustment, and
        // a refresh starts a new cursor that no deletion has adjusted yet.
        final heldKeys = refresh
            ? const <String>{}
            : {for (final draft in held.drafts) draft.key};
        final deletedFromPage = {
          for (final draft in page.drafts)
            if (removed.contains(draft.key) && !heldKeys.contains(draft.key))
              draft.key,
        };
        final base = refresh ? const DraftFeed() : account.feed;
        if (loadPrevious &&
            page.rawItemCount - deletedFromPage.length < requestLimit) {
          account.feed = base.requiringRefresh();
          account.pendingRefresh = instance;
          return;
        }
        account.feed = base.withPage(
          UserDraftPage(
            drafts: [
              for (final draft in page.drafts)
                if (!removed.contains(draft.key)) draft,
            ],
            rawItemCount: page.rawItemCount,
          ),
          limit: requestLimit,
          prepend: loadPrevious,
          requestOffset: loadPrevious ? offset : null,
          reportedCount: instance.user?.draftCount,
          deletedCount: deletedFromPage.length,
        );
      });
    } catch (error) {
      if (!_isCurrentLoad(account, request)) return;

      _commit(account, request, () {
        final current = account.feed;
        account.feed = current.withError(
          refresh || current.drafts.isEmpty
              ? appL10n.couldnTLoadDraftsFrom((instance.host).toString())
              : appL10n.couldnTLoadMoreDraftsFrom((instance.host).toString()),
        );
      });
    } finally {
      if (_isCurrentLoad(account, request)) {
        account.request = null;
        account.deletedWhileLoading.clear();
        final pending = account.pendingRefresh;
        account.pendingRefresh = null;
        if (pending != null) unawaited(load(pending, refresh: true));
      }
    }
  }

  Future<bool> delete(DiscourseInstance instance, UserDraft draft) async {
    if (isDisposed || !instance.isConnected) return false;
    final account = _accountFor(instance.url);
    final identity = draft.key;
    if (account.deletions.containsKey(identity)) return false;
    final request = Object();
    final lease = account.lease;
    account.deletions[identity] = request;
    notifySafely();
    if (!_isCurrentDeletion(account, identity, request)) return false;

    try {
      if (deleteDraft case final delete?) {
        await delete(
          instance.url,
          draft,
          () => _isCurrentDeletion(account, identity, request),
        );
      } else {
        final auth = await AccountRequestSession(
          instance.url,
          lease,
        ).keyCredentials(credentials);
        final apiKey = auth.apiKey;
        if (!_isCurrentDeletion(account, identity, request)) return false;
        if (apiKey == null) return false;
        await auth.run(
          () => api.deleteUserDraft(
            siteUrl: instance.url,
            apiKey: apiKey,
            draftKey: draft.key,
            sequence: draft.sequence,
          ),
        );
      }
      if (!_isCurrentDeletion(account, identity, request)) return false;
      recordDeleted(instance.url, draft.key, knownToExist: true);
      return true;
    } catch (error) {
      if (_isCurrentDeletion(account, identity, request)) {
        account.feed = account.feed.withError(
          appL10n.couldnTRemoveThatDraftTryAgain,
          deleting: true,
        );
      }
      return false;
    } finally {
      if (account.isCurrent &&
          identical(account.deletions[identity], request)) {
        account.deletions.remove(identity);
        notifySafely();
      }
    }
  }

  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    account?.retire();
    if (account != null) notifySafely();
  }

  bool _isCurrentLoad(_DraftAccount account, Object request) =>
      account.isCurrent && identical(account.request, request);

  bool _isCurrentDeletion(
    _DraftAccount account,
    String draftKey,
    Object request,
  ) => account.isCurrent && identical(account.deletions[draftKey], request);

  void _commit(_DraftAccount account, Object request, VoidCallback mutation) {
    if (!_isCurrentLoad(account, request)) return;
    mutation();
    notifySafely();
  }

  @override
  void dispose() {
    final accounts = _accounts.values.toList();
    _accounts.clear();
    for (final account in accounts) {
      account.retire();
    }
    super.dispose();
  }
}

final class _DraftAccount {
  _DraftAccount(this.controller, this.siteUrl, this.lease);

  final DraftListController controller;
  final String siteUrl;
  final SiteLease lease;
  DraftFeed feed = const DraftFeed();
  Object? request;
  DiscourseInstance? pendingRefresh;
  final deletions = <String, Object>{};
  // Deletions outrank pages produced against an older server snapshot.
  final deletedWhileLoading = <String>{};
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent =>
      !_retired &&
      lease.isCurrent &&
      identical(controller._accounts[siteUrl], this);

  void observeRetirement() =>
      _detach = lease.onRetire(() => controller._retireAccount(this));

  void retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    if (identical(controller._accounts[siteUrl], this)) {
      controller._accounts.remove(siteUrl);
    }
    feed = const DraftFeed();
    request = null;
    pendingRefresh = null;
    deletions.clear();
    deletedWhileLoading.clear();
  }
}
