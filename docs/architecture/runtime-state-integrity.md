# Runtime state integrity

This change gives storage transactions, pending requests, and published state
one owner for their actual lifetime. Each improvement has a controlled
before/after test. The baseline is `ecafcb48a`.

## Ownership choices

The app already has keyed operation queues, a private-file transaction owner,
account leases, and immutable state conventions. Reusing those owners keeps
the fixes local. A new application-wide coordinator would duplicate their
policy and require callers to know a second lifetime protocol.

| # | Owner and data shape | Change | Observable advantage |
| --- | --- | --- | --- |
| 1 | Draft persistence and site transaction lane | Share the existing serial queue across replacement stores and use one default persistence owner. | A replacement write or clear cannot overlap its predecessor and leave stale drafts. |
| 2 | Private document submission admission | Serialize per-document target admission before entering the existing path transaction queue. | A slow file resolver cannot invert updates submitted to one document. |
| 3 | HTTP Basic authentication document state | Share credentials, load completion, write queue, generation, and rollback versions per storage owner. | Replacement wrappers retain other origins and cannot roll back a newer credential. |
| 4 | Emoji preference document state | Share cached preferences, hydration, retirement authority, and unreadable-document state per persistence owner. | Two already-hydrated default stores compose tone and history edits instead of overwriting one another. |
| 5 | Sidebar section preferences | Use the existing coalescing snapshot writer with the existing site retirement and snapshot owners. | A held write and 100 queued choices require two physical writes, retaining the final choice and replacement-read barrier. |
| 6 | Credential migration transactions | Share the serial queue by primary storage identity, retaining the advisory file lock. | Replacing the migration wrapper cannot let an older migration resurrect a deleted credential. |
| 7 | Chat thread metadata runs | Retire detail and notification completions with their metadata owner. | Forgotten callers settle without waiting for physical I/O, and late completions cannot affect successors. |
| 8 | Event topic lookups | Keep active lookups separate from bounded completed answers. | Cache pressure cannot evict pending authority and start duplicate requests. |
| 9 | Placeholder private document codec | Distinguish corrupt documents from unsupported formats at decoding. | Recovery preserves damaged bytes, and an older app cannot overwrite a future format. |
| 10 | Dashboard report snapshot | Own an immutable copy of the report map when publishing state. | Neither API code nor consumers can mutate retained reports without a state publication. |

The alternative for authentication is to reload before every mutation. That
adds storage reads and still leaves wrapper-local generations and rollback
authority inconsistent. Sharing the document state addresses both concerns.
For event lookups, increasing the cache limit merely moves the duplicate-request
threshold. Pending authority belongs to active work, independent of answer
retention limits.

## Verification

Emoji preferences retain their existing optimistic policy when persistence
fails. A rejected write does not erase accepted session choices. Their shared
document state is retired through the existing site-preference removal
contract. Authentication and emoji state sharing use persistence identity;
separate backend objects remain independent.

Sidebar choices publish immediately and keep best-effort persistence. Calls
superseded before their write starts settle with the newest coalesced write.
The shared writer retains one small lane record per visited site and section
for the lifetime of the persistence owner. This change reduces physical writes
under a held-write burst; it does not claim a memory reduction or fewer writes
when choices arrive after earlier writes have completed.

Credential migration sharing applies to wrappers holding the same primary
storage object. Distinct handles for the same platform namespace still need
the existing advisory lock. Private-file invocation order applies within one
document; distinct documents share path coordination after resolving targets.

These checks establish ordering, isolation, data preservation, and request
counts. They do not measure startup time, frame rate, or real-world latency.

## Before and after

Each row names an executable regression check. Each failed against the
original production code before passing against the changed owner.

| # | Test file and primary check | Baseline observation | Accepted observation |
| --- | --- | --- | --- |
| 1 | `draft_store_test.dart`, replacement writes, replacement clear, and default document-location admission | Two writes or default path resolutions overlap; old text survives replacement clear. | One operation is admitted while its predecessor is held; clearing leaves no draft. |
| 2 | `private_file_document_test.dart`, target resolution preserves one document's submission order | Actual mutation order is `second, first`. | Order is `first, second`, and the file retains the second value. A failed resolver does not poison later admission. |
| 3 | `http_basic_auth_test.dart`, replacement stores retain each other's accepted origins and rollback authority follows a replacement save | Concurrent physical writes, lost origin, and stale rollback removes replacement credentials. | Physical writes serialize, independent persisted reads retain both origins, and stale rollback preserves the replacement. |
| 4 | `emoji_picker_store_test.dart`, hydrated default stores compose edits to one preference document | Raw SharedPreferences JSON has tone `neutral` after one store saved `t5` and another recorded `wave`. | Raw JSON retains `t5` and `wave`. Both stores' passive getters agree. Restart checks read independent persistence identities. |
| 5 | `sidebar_section_store_test.dart`, a section burst writes only its active and newest choice | The actual SharedPreferences backend receives 101 writes. | The same burst receives two writes, `true` then `false`. A replacement read sees the final value. Queued choices cannot survive retirement. |
| 6 | `private_storage_test.dart`, replacement migrators share the primary transaction owner | Deletion runs while an old migration write is held. | Deletion waits, then leaves a durable deletion tombstone and no readable credential. |
| 7 | `chat_thread_metadata_owner_test.dart`, forget, dispose, and revoke settle abandoned metadata before transport completes | The caller-settled flag remains false during held I/O. | Detail and all active or queued notification callers settle before transport is released. Late completion publishes nothing. |
| 8 | `event_onebox_test.dart`, topic lookups keep active admission separate from cached answers | 65 held topic loads plus another consumer cause 66 HTTP reads. | There are 65 reads. Completed answers remain capped at 64, and old completion cannot replace a successor. |
| 9 | `plugins/discourse_placeholder/placeholder_store_test.dart`, corrupt recovery and unknown document versions | Corrupt recovery retains no damaged backup; version 99 is overwritten. | The backup retains the original bytes. Version 99 remains byte-identical across read, write, and forget. |
| 10 | `dashboard_test.dart`, state and API publication isolate report ownership | Clearing the source map empties published reports. | Published reports remain intact, and consumer mutation throws `UnsupportedError`. |

## Reproduce the checks

Run from the repository root. These are explicit owner, caller, and boundary
files, not the full suite.

Final validation passed **631 tests across these 35 files**. Static analysis
of all **22 changed Dart files** reported no issues. Formatting and
`git diff --check` passed. Independent review accepted all ten owner changes.

The global test fixture retires shared emoji snapshots whenever it resets
the mock preference backend. This keeps each test's simulated installation
independent, including composer tests and the no-binding notifier test.

```sh
flutter test --no-pub \
  test/draft_store_test.dart \
  test/private_file_document_test.dart \
  test/http_basic_auth_test.dart \
  test/emoji_picker_store_test.dart \
  test/sidebar_section_store_test.dart \
  test/private_storage_test.dart \
  test/chat_thread_metadata_owner_test.dart \
  test/chat_thread_controller_test.dart \
  test/event_controller_test.dart \
  test/event_controller_admission_test.dart \
  test/event_onebox_test.dart \
  test/plugins/discourse_placeholder/placeholder_store_test.dart \
  test/plugins/discourse_placeholder/placeholder_session_test.dart \
  test/dashboard_test.dart \
  test/dashboard_page_test.dart \
  test/dashboard_navigation_test.dart \
  test/linux_preferences_store_test.dart \
  test/apple_file_draft_persistence_test.dart \
  test/account_draft_namespace_test.dart \
  test/http_transport_test.dart \
  test/add_instance_basic_auth_test.dart \
  test/sidebar_section_removal_writes_test.dart \
  test/custom_sidebar_sections_test.dart \
  test/authenticator_test.dart \
  test/coalescing_snapshot_writer_test.dart \
  test/site_preference_inventory_test.dart \
  test/plugin_dependency_boundary_test.dart \
  test/standalone_owner_dependency_boundary_test.dart \
  test/owner_dependency_graph_test.dart \
  test/emoji_picker_test.dart \
  test/emoji_picker_site_retirement_test.dart \
  test/plugin_emoji_host_test.dart \
  test/emoji_composer_panel_test.dart \
  test/emoji_picker_controller_test.dart \
  test/frame_safe_notifier_headless_test.dart
```
