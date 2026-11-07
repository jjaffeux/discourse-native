# Notification feed request ownership

`AccountActivityController` retains notification feed selection, HTTP dispatch,
and `NotificationReconciliation` publication. Each core or registered plugin
feed has one map of active `_NotificationFeedLoad` objects, keyed by site URL.
The load owns its captured `SiteLease`, shared completion, and detachable
retirement observer. There is no separate request-token map to clean up.

Ordinary callers join only a current load. The controller installs the load and
retirement cleanup before publishing loading state, so a synchronous listener
joins the same request. If a listener replaces the account, a successor can
start immediately at the same URL. The original request keeps its original
lease through credential acquisition, HTTP, error handling, and publication.

Retirement removes the exact load from its map and settles its callers, without
waiting for credential or HTTP completion. Late success, failure, or completion
cannot publish into or remove a successor. Forgetting and disposal use the same
cleanup. A completed load detaches its observer, so the account lifetime does
not retain completed requests. Cleanup is independent of a lease commit:
retired authority must prevent publication, but must still release resources.

Loaded snapshots, live-count authority, row-read overlays, and failure policy
remain with `NotificationReconciliation`. Existing rows stay visible during
refresh or a refresh failure. Other-notification catalog resolution and plugin
feed arrangement retain their existing callbacks. Live invalidations and
successful dismissals still wait for an active fetch before requesting a newer
one. Bookmark reminders and notification writes keep their separate operation
owners and queue policies.

## Design choice

Adding a lease map beside the former future and token maps would preserve the
same synchronization burden and permit partial cleanup. One private request
object groups the completion and account authority that must retire together.
A generic asynchronous loader framework would add policy callbacks without
reducing the domain behavior here. The private part shares only the existing
controller library and does not expose another application or plugin API.

## Verification

`account_activity_controller_test.dart` covers all four core feeds and a plugin
feed retiring without an explicit `forget`, immediate successor dispatch, late
old completion, loading listeners that replace the account synchronously, and
the formerly persistent token left after an old request completed. The eight
new cases failed before this ownership change. Existing cases cover
coalescing, loaded-feed refresh, failure messages, read reconciliation,
dismissal, and account forgetting.
