# Ten verified ownership improvements

These changes tighten existing storage and media boundaries. They reuse the
app's operation queues, snapshot writer, account leases, and request pools.
The evidence is deterministic behavior and operation counts, not an estimate
of application startup time or frame performance.

## Changes and proof

The baseline is `c92d27f1e`. Running the final eight owner test files against
that implementation produced 97 passes and 11 assertion failures. All 108
passed after the changes. Two assertions cover the media pool's admission
contract; each other improvement has one primary regression test.

| # | Architectural change | Before | Proven advantage | Primary proof |
| --- | --- | --- | --- | --- |
| 1 | Scalar preferences use `ReadAfterWriteOperationQueue` instead of serializing every read. | A pending hydration read prevents a later save from reaching persistence. | A save reaches persistence before the older read is released. Reads submitted after writes still observe those writes; owner/key isolation remains covered. | `scalar_preference_repository_test.dart`: `an abandoned hydration read does not hold later saves` |
| 2 | Composer layout uses the existing `CoalescingSnapshotWriter`. | Every accepted intermediate layout requires a physical write. | A held write followed by 100 updates produces two writes, with final width 500. A replacement store's read waits for that accepted final snapshot. | `composer_layout_store_test.dart`: `a layout burst writes only its active and newest pending snapshot` |
| 3 | Recent-history account identity is a `(site, account)` record in both retained and hydrating state. | Concatenating strings with a NUL delimiter permits distinct input pairs to share an entry. | Delimiter-bearing pairs retain separate histories across save and reload. The stored document format is unchanged. This removes a representation ambiguity; it does not claim current production account names contain NULs. | `recent_destinations_store_test.dart`: `account identities cannot collide through delimiter characters` |
| 4 | Recent history captures immutable route-list snapshots and serializes inside the writer. | Coalescing drops redundant disk writes after all snapshots have already been serialized. | A held save followed by 100 saves serializes the counted route twice instead of 101 times. A visit made after the final save does not leak into that saved snapshot. | `recent_destinations_store_test.dart`: `superseded history is never serialized and accepted snapshots stay fixed` |
| 5 | Bookmark hydration joins the same transaction lane as mutations and flush. | Reload temporarily makes the store unreadable; a mutation accepted during reload fails instead of waiting. | Reload followed by a mutation completes in submission order, and reopening storage retains the bookmark. Existing failed-write and unreadable-document protections remain covered. | `destination_bookmarks_store_test.dart`: `reload and mutations share one transaction order` |
| 6 | GET request keys hash session and authentication with `identityHashCode`, matching their `identical` equality. | Domain objects' changing hash codes can make an equal request key miss an in-flight map entry. | A newly constructed equal key still finds the admitted request after those domain hash codes change. This makes the key independent of its identity tokens' value semantics. | `request_coordinator_test.dart`: `GET identity keys do not inherit mutable domain hash codes` |
| 7 | The byte-download pool registers a completer before invoking its download capability, using `Future.sync`. | Synchronous callback reentry starts a second transfer; synchronous exceptions escape a future-returning API. | Reentry joins one transfer and receives the same response. A synchronous failure arrives through the returned future and the next attempt can retry. | `byte_cache_request_pool_test.dart`: both tests |
| 8 | Thumbnail publication copies generator-owned bytes once and exposes an unmodifiable view. | A generator or consumer can mutate shared cached bytes after publication. | Mutating the generator's source leaves cached bytes unchanged; writing through the published view is rejected. Concurrent consumers and cache hits still share the published buffer. | `site_video_thumbnail_repository_test.dart`: `cached thumbnails own immutable bytes independently of their generator` |
| 9 | Thumbnail resource cleanup detaches handles before release and isolates each optional bridge failure. | A throwing release callback exits before returning the scheduler slot, leaving the next job queued. | With concurrency one and a release callback that throws, the second job starts and completes; no uncaught cleanup error escapes. Cancellation and retirement use the same release path. | `site_video_thumbnail_repository_test.dart`: `failed extraction cleanup cannot strand the next queued thumbnail` |
| 10 | Retry-After decoding compares decimal seconds to the cap before integer conversion. | Oversized numeric values become a missing delay; clamping through whole seconds truncates a fractional cap. | Arbitrarily large numeric values and leading-zero values saturate at the exact 1.5-second cap; an ordinary one-second delay remains one second. Both HTTP and media coordinators consume this shared parser. | `retry_after_test.dart`: `numeric delays saturate before integer overflow and retain cap precision` |

## Reproduce the owner checks

Run from the repository root:

```sh
flutter test --no-pub \
  test/scalar_preference_repository_test.dart \
  test/composer_layout_store_test.dart \
  test/recent_destinations_store_test.dart \
  test/destination_bookmarks_store_test.dart \
  test/request_coordinator_test.dart \
  test/byte_cache_request_pool_test.dart \
  test/site_video_thumbnail_repository_test.dart \
  test/retry_after_test.dart
```

The layout and history counts describe that controlled burst while the first
physical write is held. They are not a universal write-reduction percentage:
updates separated by completed writes still require their own writes.

Thumbnail ownership adds one bounded copy per successful extraction (accepted
images are at most 2 MiB). That copy buys isolation from the native generator
and consumers; it does not claim a memory reduction. Cleanup failures retain
the existing optional-thumbnail fallback policy and cannot stop unrelated jobs.

Composer layout keeps best-effort persistence and read-after-save behavior.
Superseded pending saves complete with the newest coalesced write. Scalar
hydration can finish with an older value after a later save; presentation owners
continue to decide whether that hydration still has publication authority.
Bookmark mutations retain durability-before-publication semantics.

## Caller and boundary validation

The directly affected preference controllers, composer docking, account
retirement, byte caches, bookmarks shell/UI, snapshot writer, media pipeline,
and preference inventory are checked in their explicit test files. The full
application suite is left to CI, as required by `AGENTS.md`.

The media concurrency fixture holds the second origin until it has two active
requests, instead of releasing every later response immediately with the first
wave. Its counter decrements the current active count. This strengthened fixture
passes with both the original and revised download pool; it checks actual
capacity and sharing independently of future-callback timing.

Final validation: **336 tests passed across 25 explicit files** (the eight owner
files above plus the 17 caller/boundary files below). Static analysis of all 17
changed Dart files reported **No issues found**; formatting and `git diff
--check` were clean.

```sh
flutter test --no-pub \
  test/ui_preference_store_test.dart \
  test/composer_presentation_controller_test.dart \
  test/composer_docking_test.dart \
  test/appearance_preferences_test.dart \
  test/forum_theme_mode_retirement_test.dart \
  test/forum_theme_removal_writes_test.dart \
  test/header_preferences_test.dart \
  test/topic_presentation_controller_test.dart \
  test/startup_settings_restore_test.dart \
  test/user_directory_column_width_store_test.dart \
  test/byte_cache_request_test.dart \
  test/byte_cache_test.dart \
  test/destination_bookmarks_shell_test.dart \
  test/destination_bookmarks_ui_test.dart \
  test/coalescing_snapshot_writer_test.dart \
  test/media_pipeline_boundary_test.dart \
  test/site_preference_inventory_test.dart
```
