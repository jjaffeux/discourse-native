# Account media cache lifetime

Account media caches participate in the same `SiteLifecycle` lease as the
requests that fill them. Retiring an account releases both pending consumers
and completed cached data. A retired cache cannot remain charged to the shared
budget and evict another connected forum's images or thumbnails.

`SiteImageRepository` keeps one `_SiteImageSession` per connected account.
The session owns its authenticated byte cache and a detachable retirement
observer. The repository installs the session before observing retirement.
Retirement removes only that exact session and closes its byte cache, which
also aborts remaining transfers. Forgetting, stale-session replacement, and
repository disposal use the same idempotent retirement path. Existing image
requests still own their individual interests and completion; releasing one
consumer does not close a current shared session.

Thumbnail jobs already own retirement observers while resolving or generating
artwork. A completed `_CachedThumbnail` now owns a separate observer for the
cached bytes or failure record. Removing or evicting that exact entry updates
the shared byte count and detaches its observer. Cache hits retain the same
observer when moving the entry to the end of the LRU order. This applies to
both PDF and video thumbnails through `SiteThumbnailRepository`; their native
generators and active-job scheduling remain unchanged.

Both owners check identity before removal, so an earlier retirement observer
can start a replacement at the same URL without old cleanup deleting it.
Credentials, cross-origin redirect policy, transfer limits, native generator
cancellation, cache limits, failure retry time, and caller-held values retain
their existing contracts.

Purging stale entries only when trimming would fix one eviction order but leave
completed account resources retained until unrelated activity. Ownership at
retirement releases those resources immediately and reuses the explicit
forget/dispose cleanup path. No common cache-lifetime framework is introduced.

`site_image_repository_test.dart` and `site_video_thumbnail_repository_test.dart`
include budget regressions that failed before this change: load a surviving
account, then the retiring account, retire it, and load a third account. The
survivor remains cached. They also cover earlier-observer replacement, pending
consumers, late results, account opening races, and ordinary LRU eviction.
