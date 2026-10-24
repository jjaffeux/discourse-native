# Shared category and tag knowledge

The private taxonomy collaborator in `taxonomy_directory_controller.dart` owns category and tag knowledge for `ShellController`. One site record groups the directory feeds, category completeness, request ownership, known category snapshot, site tag sources, scoped tags, and derived sidebar and filter caches. Account teardown removes the record as one unit.

Existing consumers use the shell facade.

```dart
await shell.loadCategories(siteUrl);
final roots = shell.categoryFeedFor(siteUrl).categoryIds;
final choices = shell.topicComposerCategories(siteUrl);
await shell.loadTags(siteUrl);
final tags = shell.topicListFilterTagsFor(siteUrl);
```

## Canonical entities and directory membership

Store owns canonical `TopicCategory` entities and their partial-payload merge rules. The taxonomy owner builds its immutable known-category snapshot from Store's merge results. A topic badge can refine labels without erasing an omitted template, permission, tag minimum, or notification preference. An authoritative response can still clear a field it explicitly reports.

Known categories and directory roots are different. Categories learned from topics, composer placeholders, and searches do not become directory roots. `CategoryFeed.categoryIds` retains server-listed root order. Missing and inaccessible category IDs remain unresolved. Targeted lookup follows available ancestors, joins overlapping ID requests, limits batches to 100 IDs, and terminates on cycles. Cached resolution does not read credentials.

The existing pure directory, category path, and sidebar algorithms retain their traversal, visibility, ordering, and muted-activity behavior. Pages keep local search, selection, viewport paging triggers, and Native components.

## Request and account lifetime

The owner uses the existing account request capability and its key, client-ID, anonymous, cancellation, and priority policies. Initial category loads share their request intent. Targeted category IDs register their pending result before credential IO. Directory and scoped-tag requests retain their exact request tokens.

A site record retains readable projections after its lease is revoked. New asynchronous work and late publication require current authority. Explicit account teardown discards the record, so a replacement account cannot inherit its requests or cache. Revoking a lease alone must not erase a category projection staged immediately before a synchronous Store listener.

Full category loading waits for site presentation settings before publishing navigation metadata. Partial responses remain retryable. Refresh retains the paged roots and cursor. Every nonempty page advances paging, including a short page, and an empty root page ends it. Tag refresh and errors retain the previous loaded snapshot.

## Tag projections

Known tag precedence is personal sidebar tags, site top tags, anonymous defaults, then directory tags. Filter tags exclude PM-only entries before case-insensitive deduplication. The cache tracks account identity and source-list identities. Equal results within the same account retain the previous immutable list, including after counter-only user updates.

Sidebar projection keeps its separate connected-user preferences, anonymous defaults, scoped lookup, and selected-tag rules. Category-scoped lookup does not add global tag fallback values. Anonymous directory loading excludes PM-only tags. Composer policy continues to own authoring permission, selected tags, templates, minimum tags, and editor lifetime.

## Category preference writes

`NotificationPreferenceTransactions` owns category notification queues, membership merging, and refresh admission. It reuses the current-user preference version barrier and tracking reconciler. Shell adapters publish and persist the merged current user. The taxonomy owner receives only the category projection. It stages the immutable snapshot before publishing the category through Store, then leaves reentrant listeners free to choose a newer level or retire the account. It does not assign an older snapshot after Store publication.

## Design and validation

Two independent designs compared a standalone service with injected callbacks and a private shell collaborator. The collaborator is the base because it completes operations without another callback or effects protocol. It adopts the standalone design's per-account records and explicit retained-read contract. The shell facade preserves current application and plugin callers. Superseded shell maps and private loading and merge helpers are removed in the same migration.

The architecture follows Model the Domain by grouping one account's taxonomy knowledge. It follows Laziness Protocol by reusing Store, feed types, pure algorithms, and the established shell-part pattern. No new public SDK or endpoint repository is introduced.

`taxonomy_directory_test.dart` exercises overlapping category lookup, cyclic and inaccessible ancestors, root membership, and stale category and tag refreshes after account replacement. Existing category, tag, sidebar, filter, composer, request-consumer, and notification ownership tests preserve the surrounding contracts. Rendered directory and filter tests cover the existing desktop and mobile Native components. No performance gain is claimed.
