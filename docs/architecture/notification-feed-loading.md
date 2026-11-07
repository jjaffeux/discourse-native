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

## Retained bookmark and activity pages

`BookmarkListOwner` and `UserActivityOwner` retain each feed in a private
`_PagedFeedAccount<F>` alongside its captured lease and active request. The record
shares account and request ownership only; bookmark pages, activity offsets,
previous-page recovery and bounded window policies stay in their concrete owners.
It replaces the separate retained-feed and active-request maps, so completed
private rows cannot outlive the lease that admitted them.

Bare account retirement removes the exact record and clears its feed before
publishing the aspect and aggregate changes. Getters return an empty feed until
an explicit initial or refresh load admits a successor. Pagination and
`refreshLoaded` cannot create a replacement account by themselves. A retirement
observer may synchronously start a successor load; old publication, failure and
cleanup cannot remove its record or settle its request slot.

Retirement withdraws publication authority without completing dispatched I/O.
An old caller's future still waits for its physical request to finish, while a
successor has an independent slot and new credentials. Refresh within one account
continues to supersede the current request, and ordinary concurrent loads share
that account's active future as before.

Explicit `retire` stays silent and returns whether it removed a record.
`AccountActivityController.forget` uses it with `publishRetirement` to batch its
aspect changes. If lease retirement already removed and published the feed, a
later explicit retirement returns false and produces no duplicate publication.
The former test requiring an additional manual retirement after invalidation was
updated to this deliberate self-contained lifetime contract.

The history-owner tests first reproduced six old-source failures: retained rows,
default reload and pending-slot reuse for both feed types. They also pin new
credentials, physical completion timing, aspect/aggregate/earlier-observer
reentrancy, successor success followed by old failure, and silent explicit
retirement. Controller and bookmark-page suites retain pagination and presentation
contracts. Two independent account classes would duplicate this existing shared
request protocol; the private record keeps its limited common responsibility.
