import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/draft_feed.dart';
import '../models/user_draft.dart';

/// Draft-list state is independent from shell navigation, just like account
/// notifications and bookmarks: paging or deleting a row must not rebuild the
/// rail, topic stream, and composer along with it.
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
  final Set<(String, String)> _deleting = {};

  DraftFeed feedFor(String? siteUrl) => siteUrl == null
      ? const DraftFeed()
      : _feeds[siteUrl] ?? const DraftFeed();

  bool deleting(String siteUrl, String draftKey) =>
      _deleting.contains((siteUrl, draftKey));

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

    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (apiKey == null) {
        _commit(lease, siteUrl, request, () {
          _feeds[siteUrl] = held.withError(
            'Reconnect to ${instance.host} to see your drafts.',
          );
        });
        return;
      }
      final page = await api.userDrafts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        offset: held.drafts.length,
        limit: pageSize,
      );
      _commit(lease, siteUrl, request, () {
        _feeds[siteUrl] = held.withPage(
          page,
          limit: pageSize,
          reportedCount: instance.user?.draftCount,
        );
      });
    } catch (error, stackTrace) {
      if (!lease.isCurrent || !identical(_requests[siteUrl], request)) return;
      _report(error, stackTrace, 'drafts.load');
      _commit(lease, siteUrl, request, () {
        _feeds[siteUrl] = held.withError(
          held.drafts.isEmpty
              ? "Couldn't load drafts from ${instance.host}."
              : "Couldn't load more drafts from ${instance.host}.",
        );
      });
    } finally {
      if (lease.isCurrent && identical(_requests[siteUrl], request)) {
        _requests.remove(siteUrl);
      }
    }
  }

  Future<bool> delete(DiscourseInstance instance, UserDraft draft) async {
    if (isDisposed || !instance.isConnected) return false;
    final identity = (instance.url, draft.key);
    if (_deleting.contains(identity)) return false;
    final lease = lifecycle.capture(instance.url);
    _deleting.add(identity);
    notifySafely();

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null) return false;
      await api.deleteUserDraft(
        siteUrl: instance.url,
        apiKey: apiKey,
        draftKey: draft.key,
        sequence: draft.sequence,
      );
      if (!lease.isCurrent || isDisposed) return false;
      _feeds[instance.url] = feedFor(instance.url).without(draft.key);
      return true;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _report(error, stackTrace, 'drafts.delete');
        _feeds[instance.url] = feedFor(
          instance.url,
        ).withError("Couldn't remove that draft. Try again.");
      }
      return false;
    } finally {
      if (lease.isCurrent && !isDisposed) {
        _deleting.remove(identity);
        notifySafely();
      }
    }
  }

  void forget(String siteUrl) {
    final changed = _feeds.remove(siteUrl) != null;
    _requests.remove(siteUrl);
    _deleting.removeWhere((identity) => identity.$1 == siteUrl);
    if (changed) notifySafely();
  }

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
    _deleting.clear();
    super.dispose();
  }
}
