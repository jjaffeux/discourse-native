# Presentation sessions

`SitePresentationController` keeps one captured `_PresentationSession` per site.
It owns the typed appearance, configuration, custom emoji, catalog and alias
entries. Each entry holds its value, retry budget, failed-read marker and shared
request. `_PresentationResource` retains the common request policy and selects
its typed entry from the captured session rather than holding another URL map.

Requests capture their session before cache hits and operation joining. The
session must still own the site after credential IO, before publication and
before admitting persistence. Forgetting a session without rotating its lease
also invalidates that authority. Late completion and loading cleanup touch only
the captured entry. Same-session callers retain `RequestIntentOperation` joins,
retry forgiveness, failed-read suppression and explicit-refresh behavior. Equal
appearance still skips persistence; equal configuration still persists.

Retirement removes only its exact session, clears all five entries and derived
emoji indexes, invalidates presentation tokens, then notifies listeners. A
successor created by an earlier retirement observer cannot be removed by the old
observer. Explicit forgetting and disposal detach the same observer. Disposing
the controller clears every session without publishing retirement changes.

## Display continuity and account authority

Appearance is not intrinsically public: the loader can use a user's stored theme
preferences. This change does not introduce a cross-account public theme cache.
`appearanceFor` retains its existing persisted-instance fallback. `configFor`
also retains its persisted fallback for display/cooking continuity, whereas
`accountConfigFor` suppresses that fallback after retirement and cooking settings
remain stale until the current session fetches configuration.

Retirement invalidates persisted freshness, so a new account cannot treat the
previous session's persisted appearance as a fresh HTTP result. Display fallback
remains available while the replacement loads. Shell account establishment still
owns deliberate clearing/restoration of instance appearance and configuration.
Cancelled authorization occurs before lifecycle rotation and leaves the current
presentation session untouched. Accepted replacement and recovery retain their
existing rotation, signed-out snapshot and restored-instance policies.

## Design decision and verification

Five independently leased resource maps would require five observers and
coordinated invalidation of aliases, tokens and persisted freshness. One session
expresses their common authority while preserving typed entries and the existing
resource policy helper. No extra callback or repository layer is introduced.

This deliberately replaces the former controller contract requiring explicit
`forget` after lifecycle invalidation before resource readmission. It is ownership
hardening: shell account rotation already pairs invalidation with forgetting, so
no reachable production account leak is claimed.

`test/site_presentation_controller_test.dart` covers resource intent sharing,
retirement without forgetting, replacement before old settlement, persisted
fallback versus account authority, same-lease forgetting during credential IO,
reentrant successor creation, equality/persistence and retry behavior. Account
coordinator and shell tests retain cancelled-sign-in and rollback coverage.
