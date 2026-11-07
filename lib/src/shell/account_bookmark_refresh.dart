part of 'account_activity_controller.dart';

/// Owns the reminder feed's active load and forced replay for one account.
final class _AccountBookmarkRefresh {
  _AccountBookmarkRefresh(this.controller, this.siteUrl, this.lease);

  final AccountActivityController controller;
  final String siteUrl;
  final SiteLease lease;
  _BookmarkRefreshJob? _active;
  _BookmarkRefreshJob? _pending;
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent =>
      !_retired &&
      lease.isCurrent &&
      identical(controller._bookmarkRefreshes[siteUrl], this);

  void observeRetirement() => _detach = lease.onRetire(retire);

  Future<void> load(DiscourseInstance instance, {required bool force}) {
    if (!isCurrent) return Future<void>.value();
    final active = _active;
    if (active != null) {
      if (!force) return active.result.future;
      final pending = _pending ??= _BookmarkRefreshJob(instance);
      pending.instance = instance;
      return pending.result.future;
    }
    final job = _BookmarkRefreshJob(instance);
    _start(job);
    return job.result.future;
  }

  bool _owns(_BookmarkRefreshJob job) => isCurrent && identical(_active, job);

  void _start(_BookmarkRefreshJob job) {
    _active = job;
    unawaited(_run(job));
  }

  Future<void> _run(_BookmarkRefreshJob job) async {
    try {
      await _load(job);
      if (!job.result.isCompleted) job.result.complete();
    } catch (error, stackTrace) {
      if (!job.result.isCompleted) job.result.completeError(error, stackTrace);
    } finally {
      if (_owns(job)) {
        _active = null;
        final pending = _pending;
        _pending = null;
        if (pending != null) _start(pending);
      }
    }
  }

  Future<void> _load(_BookmarkRefreshJob job) async {
    final instance = job.instance;
    final username = instance.user?.username;
    if (username == null || !_owns(job)) return;
    final owner = controller._reconciliationFor(siteUrl, lease: lease);
    final slot = controller._bookmarks;
    final held = owner.hasPublished(slot) ? owner.feed(slot) : null;
    if (held == null || held.error != null) {
      owner.publish(slot, const BookmarkFeed.loading());
    }
    if (!_owns(job)) return;

    void fail(String message) {
      final current = owner.feed(slot);
      owner.publish(
        slot,
        current.hasRows ? current : BookmarkFeed.failed(message),
      );
    }

    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(controller.credentials);
      if (!_owns(job)) return;
      final apiKey = auth.apiKey;
      if (apiKey == null) {
        fail(appL10n.reconnectToToSeeYourBookmarks(instance.host));
        return;
      }
      final bookmarks = await auth.run(
        () => controller.api.bookmarks(
          siteUrl: siteUrl,
          apiKey: apiKey,
          username: username,
        ),
      );
      if (_owns(job)) owner.publish(slot, BookmarkFeed.of(bookmarks));
    } on SiteLookupException catch (error) {
      if (!_owns(job)) return;
      fail(
        error.failure == SiteLookupFailure.notDiscourse
            ? appL10n.notAllowedTryReconnectingTo(instance.host)
            : appL10n.couldnTReach(instance.host),
      );
    } catch (_) {
      if (_owns(job)) fail(appL10n.couldnTLoadBookmarksFrom(instance.host));
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    if (identical(controller._bookmarkRefreshes[siteUrl], this)) {
      controller._bookmarkRefreshes.remove(siteUrl);
    }
    final active = _active;
    final pending = _pending;
    _active = null;
    _pending = null;
    if (active != null && !active.result.isCompleted) active.result.complete();
    if (pending != null && !pending.result.isCompleted) {
      pending.result.complete();
    }
  }
}

final class _BookmarkRefreshJob {
  _BookmarkRefreshJob(this.instance);

  DiscourseInstance instance;
  final result = Completer<void>();
}
