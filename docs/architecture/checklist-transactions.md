# Checklist transactions

`ChecklistTransactions` owns checklist admission and account lifetime. The shell
composes its dependencies and keeps the public `togglePostChecklist` facade.

The directory keeps one account record per original `SiteLease`. Each record
owns its post queues, credential acquisition, request scope, and completion
cleanup. Retirement detaches its observer and discards only that account's
metadata. Late completion removes only its original operation and releases its
captured TopicDataSession hold. It never looks up a successor account.

The mutation sequence belongs to the directory so replacement accounts continue
the sequence. Each save retains the queue's exact raw and updatedAt baseline.
Credentials are bound to the original lease before transport dispatch.

`PostChecklistWrite` remains the per-post optimistic and reconciliation engine.
It coalesces rapid toggles and handles changed content, refusals, and uncertain
outcomes. `TopicDataSession` remains the canonical publication and post-hold
authority. `BookmarkTransactions` keeps bookmark fields and overlap policy.
Checklist and bookmark saves can overlap; conflicting post actions cannot.

The bookmark activity queries are lazy composition callbacks. Constructors do
not invoke them or create account records. This avoids recursive construction
between the bookmark, checklist, and topic-data owners. The checklist activity
query only reads existing metadata.

A directory with private account records keeps account policy out of the
per-post engine. Expanding PostChecklistWrite would combine account lookup and
transport lifetime with optimistic reconciliation. No new canonical cache or
shared lock is needed.

`posted_todos_test.dart` pins optimistic rendering, queue coalescing, exact
concurrency inputs, uncertain outcomes, bookmark overlap, and successor
cleanup. `checklist_transactions_test.dart` exercises original request identity,
credential failure and absence, retirement during credential/load/save,
repeated retirement, and construction without a Flutter binding.
