import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/draft_feed.dart';
import '../models/user_draft.dart';

typedef _DraftDeletionKey = ({String siteUrl, String draftKey});

final class DraftListController extends FrameSafeNotifier {
  DraftListController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  static const int pageSize = 30;

  final DraftsApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;

  final Map<String, DraftFeed> _feeds = {};
  final Map<String, Object> _requests = {};
  final Map<_DraftDeletionKey, Object> _deletions = {};
  // Draft keys deleted while a page request was in flight. That response was
  // produced against an older server state, so these keys outrank it.
  final Map<String, Set<String>> _deletedWhileLoading = {};

  DraftFeed feedFor(String? siteUrl) => siteUrl == null
      ? const DraftFeed()
      : _feeds[siteUrl] ?? const DraftFeed();

  bool deleting(String siteUrl, String draftKey) =>
      _deletions.containsKey((siteUrl: siteUrl, draftKey: draftKey));

  /// Mirrors core's `draft:destroyed` cache propagation for drafts removed
  /// from outside this controller (for example, from the composer).
  void recordDeleted(
    String siteUrl,
    String draftKey, {
    bool knownToExist = false,
  }) {
    if (isDisposed) return;
    if (_requests.containsKey(siteUrl)) {
      (_deletedWhileLoading[siteUrl] ??= {}).add(draftKey);
    }
    _feeds[siteUrl] = feedFor(
      siteUrl,
    ).without(draftKey, knownToExist: knownToExist);
    notifySafely();
  }

  void invalidateTotalCount(String siteUrl) {
    if (isDisposed || !_feeds.containsKey(siteUrl)) return;
    _feeds[siteUrl] = feedFor(siteUrl).withoutTotalCount();
    notifySafely();
  }

  Future<void> load(DiscourseInstance instance, {bool refresh = false}) async {
    if (isDisposed || !instance.isConnected) return;
    final siteUrl = instance.url;
    if (_requests.containsKey(siteUrl)) return;
    final held = refresh ? const DraftFeed() : feedFor(siteUrl);
    if (!refresh && held.loaded && !held.hasMore) return;

    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    _requests[siteUrl] = request;
    _feeds[siteUrl] = held.loadingMore();
    notifySafely();
    // Publishing can synchronously dispose this owner through a listener.
    // Do not let that replacement boundary cross into credential storage.
    if (!_isCurrentLoad(lease, siteUrl, request)) return;

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!_isCurrentLoad(lease, siteUrl, request)) return;
      if (apiKey == null) {
        _commit(lease, siteUrl, request, () {
          _feeds[siteUrl] = feedFor(
            siteUrl,
          ).withError('Reconnect to ${instance.host} to see your drafts.');
        });
        return;
      }
      final page = await api.userDrafts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        offset: held.drafts.length,
        limit: pageSize,
      );
      // The commit must build on the feed as it stands now, not the [held]
      // snapshot: a delete that landed during the request already removed its
      // row, and replaying the snapshot would put the row back.
      _commit(lease, siteUrl, request, () {
        final removed = _deletedWhileLoading[siteUrl] ?? const <String>{};
        _feeds[siteUrl] = feedFor(siteUrl).withPage(
          [
            for (final draft in page)
              if (!removed.contains(draft.key)) draft,
          ],
          limit: pageSize,
          reportedCount: instance.user?.draftCount,
        );
      });
    } catch (error, stackTrace) {
      if (!lease.isCurrent || !identical(_requests[siteUrl], request)) return;
      _report(error, stackTrace, 'drafts.load');
      _commit(lease, siteUrl, request, () {
        final current = feedFor(siteUrl);
        _feeds[siteUrl] = current.withError(
          current.drafts.isEmpty
              ? "Couldn't load drafts from ${instance.host}."
              : "Couldn't load more drafts from ${instance.host}.",
        );
      });
    } finally {
      if (!isDisposed && identical(_requests[siteUrl], request)) {
        _requests.remove(siteUrl);
        _deletedWhileLoading.remove(siteUrl);
      }
    }
  }

  Future<bool> delete(DiscourseInstance instance, UserDraft draft) async {
    if (isDisposed || !instance.isConnected) return false;
    final identity = (siteUrl: instance.url, draftKey: draft.key);
    if (_deletions.containsKey(identity)) return false;
    final request = Object();
    final lease = lifecycle.capture(instance.url);
    _deletions[identity] = request;
    notifySafely();
    if (!_isCurrentDeletion(lease, identity, request)) return false;

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!_isCurrentDeletion(lease, identity, request)) return false;
      if (apiKey == null) return false;
      await api.deleteUserDraft(
        siteUrl: instance.url,
        apiKey: apiKey,
        draftKey: draft.key,
        sequence: draft.sequence,
      );
      if (!_isCurrentDeletion(lease, identity, request)) return false;
      recordDeleted(instance.url, draft.key, knownToExist: true);
      return true;
    } catch (error, stackTrace) {
      if (_isCurrentDeletion(lease, identity, request)) {
        _report(error, stackTrace, 'drafts.delete');
        _feeds[instance.url] = feedFor(
          instance.url,
        ).withError("Couldn't remove that draft. Try again.");
      }
      return false;
    } finally {
      if (!isDisposed && identical(_deletions[identity], request)) {
        _deletions.remove(identity);
        notifySafely();
      }
    }
  }

  void forget(String siteUrl) {
    var changed = _feeds.remove(siteUrl) != null;
    changed = _requests.remove(siteUrl) != null || changed;
    _deletedWhileLoading.remove(siteUrl);
    final deletionsBefore = _deletions.length;
    _deletions.removeWhere((identity, _) => identity.siteUrl == siteUrl);
    changed = _deletions.length != deletionsBefore || changed;
    if (changed) notifySafely();
  }

  bool _isCurrentLoad(SiteLease lease, String siteUrl, Object request) =>
      !isDisposed && lease.isCurrent && identical(_requests[siteUrl], request);

  bool _isCurrentDeletion(
    SiteLease lease,
    _DraftDeletionKey identity,
    Object request,
  ) =>
      !isDisposed &&
      lease.isCurrent &&
      identical(_deletions[identity], request);

  void _commit(
    SiteLease lease,
    String siteUrl,
    Object request,
    VoidCallback mutation,
  ) {
    if (isDisposed || !lease.isCurrent) return;
    lease.commit(() {
      if (!identical(_requests[siteUrl], request)) return;
      mutation();
      notifySafely();
    });
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'drafts',
      handled: true,
      degraded: true,
    );
  }

  @override
  void dispose() {
    _requests.clear();
    _deletions.clear();
    _deletedWhileLoading.clear();
    super.dispose();
  }
}
