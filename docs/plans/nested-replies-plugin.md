# Nested replies plugin implementation plan

Implement nested replies as an optional Native plugin. The plugin owns the tree reader, feature detection, server requests, wire decoding, sorting, context navigation, pins, and activity log. Core supplies generic plugin contracts for topic readers and shared topic operations. Removing the module must remove every nested replies behavior without changing core source.

The plugin and the generic contracts are implemented in this branch. The design below records the source investigation and intended behavior; the implementation map lists the final API names. The HTTP and web behavior reference is the local Discourse checkout at `/Users/joffreyjaffeux/Code/discourse`, inspected on 2026-10-31 at HEAD `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. That checkout contains unrelated working changes. Native was inspected at `a2e6b6751be587aa026e5c5aeb99278af1b0b6d5`. Verify the owning server files again during implementation rather than assume a particular deployed Discourse version supports these endpoints.

Keep this document with the repository's implementation plans. Server changes and deployment are outside this change's scope.

## Implementation map

`lib/src/plugins/nested_replies/nested_replies_module.dart` registers the optional module in the bundled manifest. Removing that registration leaves the ordinary reader and notification fallback. An explicit false site setting removes plugin topic records and retires reader memory. Missing site-setting evidence permits a reader only when authoritative topic data confirms the mode; private messages always decline.

| Implemented area | Owning files |
| --- | --- |
| Wire decoding, settings, topic/post records | `nested_replies_data.dart`, `nested_replies_api.dart`, `nested_replies_plugin.dart` |
| Graph, independent root/child paging, generations, live reconciliation | `nested_replies_controller.dart` |
| Native reader, shared header/posts, context navigation, placeholders, visible timings | `nested_replies_reader.dart` and its part files |
| Bounded reference-only history and loaded-page restoration | `nested_replies_reader_memory.dart` |
| Mode/category controls, conversion, and activity | `nested_replies_admin.dart` |
| Bulk selection and subset results | `nested_replies_bulk.dart` |
| Session availability, legacy links, pin serialization/recheck, lifecycle | `nested_replies_services.dart` |
| Bucket notification presentation and destination | `nested_replies_notifications.dart` |

Paths in this table are relative to `lib/src/plugins/nested_replies/`. Feature tests live in the matching directory under `test/plugins/`.

The generic SDK contracts use these final names:

- `TopicRecordDecodeContext` carries list, detail, recommendation, or partial provenance. Plugin records reconcile partial fields through `TopicRecordValue`.
- `TopicReadingPolicyRecord` supplies a `TopicReadingPolicy`. The ordinary chronological policy remains the default. The activity policy separates catch-up from exact visible timings.
- `TopicReaderPlugin` selects a reader for an authoritative `TopicReaderProbe`. Conflicting claims fail explicitly. `TopicReaderOutlet` waits for discovery before either viewport starts.
- `PluginTopicReader` binds the original account, tab, route, and query. It provides canonical ingestion, visible observations, events, reply/edit/navigation, metadata refresh, and visit reconciliation. Hidden desktop panels retain their handle but are not foreground.
- `TopicContentResult` supplies metadata without flat-stream membership and explicit complete/redacted posts. `AcceptedTopicContent` acknowledges canonical IDs before graph publication. Fresh ordinary content can replace redaction only with request-start reference authority; stale responses and active-reader ordinary refreshes cannot restore it.
- `PluginTopicHeader` and `PluginTopicPost` reuse existing presentation and post extension points. The plugin owns a lazy projection of its graph and reports its full renderable selection order separately from actual visible timing observations.
- `TopicDestination.query` preserves opaque query text through normal routes and history. The plugin interprets its own keys. No core query parser understands tree behavior.
- `PluginNotificationPresentationStrategy` is session scoped. Declines, invalid routes, and failures retain the core notification fallback.
- `PluginTopicRecordsHost` invalidates only the consuming module's topic records under its original lease. Reader and record ports revoke retained authority at session close.
- `PluginCategorySettingsApi` loads generic category snapshots and saves only requested setting/custom-field patches. The plugin owns its category form inside the topic settings panel. A separate core category-admin screen and feature fields on `TopicCategory` are unnecessary.
- `TopicListHeaderPlugin` adds actions to the existing list heading; `TopicListTitlePlugin` composes the selection control with the original title. Bulk protocol and selection state remain in the plugin.

Reader history stores graph references, pagination, expansion, requested/effective sorts, and semantic scroll anchors. It does not store canonical post bodies. Entries expire after ten minutes and are bounded to fifteen entries and twenty thousand nodes per session. Returning to a reader keeps the restored graph visible while a foreground visit and background page replay build its replacement. The graph swaps atomically, preserves disclosure and scroll position, and queues unseen roots behind the new-replies control. Request-scoped loader guards reject superseded content before canonical ingestion.

Verification includes protocol/controller/widget tests and an assembled `DiscourseApp` test using the actual module, shell, canonical ingestion, header, post renderer, and composer. The assembled test checks phone and desktop rendering, branch order, shared post extensions, selection order, exact-parent replies, authoritative mode removal, a fresh disabled site setting, absent/disabled requests, bucket notifications, and legacy links. The test can export screenshots with `NESTED_REPLIES_INTEGRATION_EXPORT=1` to `/private/tmp/nested-replies-integration-previews/`. Tests use controlled server responses; a deployed-server/device session remains separate validation.

### Reddit-style presentation

The nested reader uses compact shared posts with a 32-point indentation step on desktop and a 20-point step on phones. Native circular minus/plus toggles collapse each comment to its canonical author/status/time row and restore its previous reply expansion. The opening post retains ordinary presentation. Small inline reply-count and pagination controls preserve independent branch loading. Phone context views rebase visual indentation while keeping the original controller depth for sort, flattening, and child requests; narrow readers use context navigation before their text column becomes too small.

`DThreadRail` and `DThreadConnector` in the Native kit own the two-pixel strokes, rounded elbows, hover/focus treatment, keyboard activation, and exact desktop stroke hit testing. Gaps between branches pass pointer events through. Desktop connector strokes and vertical ancestor rails collapse the displayed parent; actual reply targets remain independent. Phone curves are decorative, while circular toggles and straight interactive rails use the kit's existing touch targets.

Core exposes the generic `TopicPostLayout` standard, compact, and header-only layouts plus leading, body-leading, and footer-leading slots. The compact author appears before canonical news headers so bookmarks/notices do not move connector geometry. The shared post footer aligns its leading slot with actual engagement controls beneath flag descriptions. Core has no branch or depth policy. The plugin's flat projection supplies ancestor identities and continuation flags, so virtualized rows draw their own segments without measuring other rows.

The presentation pass passed 98 focused tests, static analysis, Native ownership, and localization audits. Independent review reproduced and verified fixes for phone context-depth rebasing and connector gaps intercepting pointer events. The new layout was also inspected in the running desktop app and exported phone/desktop renders.

### Validation record

The final named acceptance run passed 227 tests across the plugin, canonical ingestion, read credits, worker projection, plugin ownership, category settings, notification strategies, and shared header behavior. Independent review confirmed the generic boundary and the final restored-reader reconciliation. Static analysis covered `lib/` and every changed test; the Native ownership and localization audits also passed.

A separate directly related host run passed 364 tests and exposed one existing failure in `test/desktop_topic_page_test.dart`, `narrow topic header separates controls from the list` on iOS. The same missing `topic-list-title` assertion failed on untouched Native HEAD `a2e6b6751be587aa026e5c5aeb99278af1b0b6d5`. That unrelated assertion is unchanged.

To repeat focused feature coverage, run `flutter test test/plugins/nested_replies`. Generic reader regressions live in `test/topic_reader_content_test.dart`, `test/topic_read_controller_test.dart`, and `test/topic_reader_panel_navigation_test.dart`. The physical ownership guard is `test/plugin_dependency_boundary_test.dart`. The initial acceptance run did not include a full local test suite, deployment, or live device/backend validation. A subsequent desktop check exposed a zero reading-speed argument in the shared post adapter on a topic with a positive word count. The adapter now reads the current site setting; a regression verifies 1,200 words at 200 and 400 words per minute. All 13 assembled reader tests pass, and hot reload restored the original live topic map. Other live endpoint and device flows remain separate validation.

## Ownership and required migration

Use `lib/src/plugins/nested_replies/` for all feature code and `test/plugins/nested_replies/` for its tests. Import the public `package:discourse_native/discourse_plugin_sdk.dart` and `package:discourse_native/discourse_ui.dart`. Do not import core implementation files or obtain `ShellController`, raw credentials, `SiteLifecycle`, or a writable `Store`.

The exception for core is reusable infrastructure exposed through public plugin APIs. Neither those APIs nor their host implementations may mention nested replies, its setting names, `/n/`, hot sorting, tree depth, pin limits, or wire flags. The bundled manifest may import the plugin module as composition, following the existing plugins. Localization and source ownership test registration also follow existing plugin conventions.

There is already feature logic in Native core. Migrate it into plugin data and generic policies in the same change that introduces the replacement APIs.

| Existing core location | Behavior to move into the plugin |
| --- | --- |
| `lib/src/models/topic.dart` | Decode `is_nested_view` and `has_new_replies`; suppress numeric unread and new-topic badges; show a reply dot; choose root entry instead of chronological unread entry. |
| `lib/src/models/post.dart`, `TopicDetail` | Decode `is_nested_view` and suppress chronological resume. |
| `lib/src/shell/unread_topic_feed.dart` | Decide whether a nested topic is caught up using list state rather than post-number comparisons. |
| `lib/src/shell/topic_read_controller.dart` | Avoid deriving nested topic catch-up from the highest timed post. |
| `lib/src/shell/shell_controller.dart`, `topicOpensAtTop` | Choose initial sheet/header position using nested topic semantics. |
| `lib/src/shell/topic_view.dart` | Suppress the chronological first-unread separator for this reader. |

Remove `Topic.isNestedView`, `Topic.hasNewReplies`, `TopicDetail.isNestedView`, their parsing, copying, equality, persistence, and callers after migration. Keep genuinely generic provenance such as `listReadStateKnown` if it still serves ordinary topics. Move feature assertions out of core-only model tests. The core-only codec must ignore nested wire fields and retain ordinary topic behavior.

A core model may hold opaque `PluginData`. The plugin interprets its own namespace. A generic host can apply a returned activity, entry, or reader policy without inspecting the data that produced it.

## What Discourse implements

Nested replies is another presentation of ordinary topics and posts. A reply keeps its original `reply_to_post_number`. Creating, editing, moderating, quoting, liking, bookmarking, and reporting use the existing post operations. Native must reuse those workflows.

The OP is separate from the reply forest. Roots are posts numbered at least 2 whose parent is absent or post 1. Post numbers identify graph relationships and context targets. Database post IDs identify canonical records, pins, and mutations. Do not interchange them.

The server owns visibility filtering, recursive counts, rank order, hot-score snapshots, stat backfill, and category conversion. Native consumes their results. It must not rebuild ranking, count hidden descendants, or convert topics because a category has a default.

The key server sources are `app/controllers/nested_topics_controller.rb`, `app/services/nested_topic/`, `lib/nested_replies/`, `app/models/nested_topic.rb`, and `Topic#nested_view?` in `app/models/topic.rb`. The web state reference is `frontend/discourse/app/lib/nested-topic-model.js` and `frontend/discourse/app/controllers/nested.js`.

## Availability and activation

### Distinguish installation, site availability, and topic mode

1. The module must be present in the manifest. With `corePluginManifest`, nothing registers, decodes, intercepts navigation, or calls nested endpoints.
2. The server must support and enable the feature for the current site/account session.
3. A particular topic must have authoritative `is_nested_view: true` before the plugin replaces its reader. Private messages always use the ordinary reader.
4. Each action also requires its own current permissions. Feature availability does not grant write authority.

`Topic#nested_view?` returns false when the global feature is disabled or the topic is a PM. Otherwise it checks for a `NestedTopic` record or the site-wide default. Topic detail, list, and suggested serializers emit `is_nested_view: true` only when that predicate succeeds. They omit the field for ordinary topics. Do not wait for an explicit false.

Category defaults apply at topic creation. They create a per-topic record. Turning a category default on does not retroactively enable historical topics. Turning it off does not remove records already created. Use the server topic field, not category membership, to choose a reader.

A successful `/n/` read does not prove that a topic is nested. The controller checks the global setting and topic visibility, but it can return a tree for an ordinary regular topic. Do not probe `/n/` as a way to opt topics in.

### Define the plugin's capability state

Keep unknown, available, disabled, and request failure distinct. Settings and topic records belong to their original account lease and carry freshness/provenance.

| Current evidence | Reader and controls |
| --- | --- |
| Module absent | Ordinary behavior. No plugin UI or requests. |
| Fresh site setting explicitly false | Ordinary behavior. Hide nested controls and retire active plugin work. |
| Site setting true, topic has no authoritative nested flag | Ordinary reader. Eligible staff may see the mode toggle. |
| Fresh topic flag true, no newer explicit site denial | Nested reader. The server predicate itself proves that this topic supports the feature. Late or refused settings may limit configurable controls, but must not authorize extra writes. |
| Only cached or incomplete evidence, never validated in this lease | Shared loading, retry, or ordinary availability handling until discovery resolves. Do not expose plugin controls or start tree requests on that evidence alone. |
| Current nested read fails | Show a scoped error and retry. Recheck topic metadata when appropriate. A 404 alone does not distinguish feature removal, deleted topic, or access loss. |

A full fresh topic response that omits the flag must clear stale activation. Omission from a child page, edit result, or other partial payload must not erase established topic mode. Extend the generic plugin record decode/merge contract to carry response provenance and field authority. Today's `TopicRecordPlugin.readTopic` receives only a map and site URL. Installed typed values do not gain partial-field preservation from `PluginData.preservingUnknownFrom`, which handles unknown stored namespaces.

Keep mode authority separate from list-activity authority. A complete topic detail can settle reader selection while remaining sparse about `has_new_replies`. Define typed decode/merge input identifying authoritative fields or record domains, use it for all topic publication paths, and migrate existing plugin decoder callers. Do not infer authority from unrelated field presence.

Scope a transient failure to the site, account lease, and topic operation that produced it. Never disable the module globally because one forum returns 404. A timeout or 500 is not evidence of unsupported software.

The plugin's session-scoped capability service enforces this state for every contribution and request. Generic reader lifecycle dispatch retires selected handles when the capability changes. `PluginSiteFeature.siteFeatureEnabled` alone does neither job and cannot represent unknown or failed discovery.

Cached trees can restore a reader whose activation remains valid in the same lease. They cannot establish availability after account replacement or override newer disabled metadata. Existing persistence codecs cover settings and current-user plugin data. Do not assume that topic records already have a durable plugin codec. If a retained payload needs migration, keep its legacy-field interpretation in the plugin at that storage boundary. Do not introduce topic persistence solely to migrate an in-memory field.

### Settings to decode inside the plugin

| Setting | Server default | Native use |
| --- | --- | --- |
| `nested_replies_enabled` | `false` | Site controls and explicit denial. |
| `nested_replies_default` | `false` | Hide ineffective per-topic disable controls when globally forced. |
| `nested_replies_hot_sort_enabled` | `false` | Offer Hot only when enabled. |
| `nested_replies_default_sort` | `top` | Initial requested sort when a route supplies none. |
| `nested_replies_max_depth` | `3`, allowed 1 through 10 | Depth and continuation presentation. |
| `nested_replies_cap_nesting_depth` | `true` | Distinguish flattening from continuation. |

Backend hot-score tuning, maintenance switches, and batch sizes stay on the server. Missing optional settings use conservative presentation defaults. They never manufacture a topic capability or permission.

## Server request contracts

Use `corePluginTransportPort`, `corePluginRequestPort`, and the current public model codec. Build same-site paths relative to the forum base so subfolder installations work. Capture the original lease before asynchronous credential or network work. Check it after every await and before publication or navigation.

Use JSON routes. Browser `/n/` pages redirect to canonical `/t/` URLs and are not Native navigation destinations.

| Operation | Request | Response |
| --- | --- | --- |
| Root page | `GET /n/:slug/:topic_id.json` with `sort`, zero-based `page`, and foreground-only `track_visit` | `roots`, `has_more_roots`, `page`. Page 0 also has `topic`, `op_post`, `sort`, `effective_sort`, `message_bus_last_id`, and optional `pinned_post_ids`. |
| Child page | `GET /n/:slug/:topic_id/children/:post_number.json` with `sort`, `page`, and `depth` | `children`, `has_more`, `page`. The path number is the parent post number. |
| Context | `GET /n/:slug/:topic_id/context/:post_number.json` with `sort`, optional `context`, and foreground-only `track_visit` | `topic`, `op_post`, `ancestor_chain`, `ancestors_truncated`, `siblings`, `target_post`, `effective_sort`, `message_bus_last_id`. `/n/:slug/:topic_id/:post_number.json` is an alias. |
| Activity | `GET /n/:slug/:topic_id/activity.json` with `page` | `small_actions`, `has_more`. Page 0 includes a synthetic topic-created entry. |
| Toggle root pin | `PUT /n/:slug/:topic_id/pin.json` with `post_id` | Complete replacement `pinned_post_ids`. |
| Toggle topic mode | `PUT /n/:slug/:topic_id/toggle.json` with boolean `enabled` | `{is_nested_view: enabled}`. Refresh effective topic metadata afterward. |
| Bulk topic mode | `PUT /topics/bulk.json` with `topic_ids` and `operation: {type: "enable_nested_view"}` or `"disable_nested_view"` | Changed `topic_ids` and optional `errors`. Refresh affected metadata and account for partial success. |
| Convert historical category topics | `POST /categories/:id/convert_nested_replies` | `success`, `converted_topic_count`, `nested_replies_conversion_completed`. |

Root pages contain 20 ordinary roots. Child pages contain 50 entries. The controller clamps pages to 0 through 1000 and child depth to 1 through 100. Missing depth becomes 1. Send explicit typed values rather than depend on coercion.

Root and child `has_more` mean that the response contains a full page, not that another record was found. An exact multiple may require a final empty request. Stop according to the returned flag. Keep already loaded content on page errors and retry the same page.

Pinned IDs are excluded from every ordinary root page. Page 0 prepends eligible pinned roots in stored order and can exceed 20 entries. Later pages do not repeat pins. Deduplicate defensively without replacing server ordering.

The terminal root page carries top-level `suggested_topics`, `suggested_group_name`, `related_topics`, and `related_messages` when present. Context responses can carry them too. Absence on earlier pages means unresolved, not an authoritative empty result. Hydrate categories carried inside `topic.categories`, including categories needed by recommendations.

Nested topic metadata deliberately lacks `post_stream`, `timeline_lookup`, and `user_badges`. It is not a complete flat topic payload. Do not pass it to a decoder that invents an empty authoritative chronological stream.

### Node decoding

A recursive node is a normal post payload plus `children`, `direct_reply_count`, `total_descendant_count`, and optional `avatar_color`. Context ancestors and sibling samples use post payloads without recursive children.

Decode ordinary post fields with the shared `DiscourseModelCodec`. Decode feature fields in the plugin. Keep a distinct placeholder variant for redacted posts that cannot satisfy the full ordinary post presentation contract.

Deleted posts can remain structural parents. Nonstaff deleted placeholders may contain only ID, post number, parent number, empty content, empty actions, and counts. Author, timestamps, permissions, and ordinary metadata may be absent. Never fill those from stale canonical content or expose an older cached body. Staff can receive fuller fields with the marker. Deleted root leaves are filtered for ordinary users, but a direct context request can still return a deleted leaf placeholder.

Ignored non-OP posts have `ignored_post_placeholder: true` and empty content. Deleted status takes precedence. Revealing ignored content uses the existing cooked-content operation, `/posts/:id/cooked.json`, with current authorization. Do not infer permission to reveal from a cached body. This path does not turn the OP into an ignored placeholder.

Validate `avatar_color` as optional presentation data. It may be absent for uploaded avatars without a dominant color. Server counts remain authoritative; loaded children cannot establish descendant totals or reveal invisible posts.

### Sort and depth semantics

| Sort | Server ordering |
| --- | --- |
| `top` | Like count descending, then post number ascending. |
| `new` | Creation time descending. |
| `old` | Post number ascending. |
| `hot` | Thread hot score, then individual hot score descending, then post number ascending. |

Store requested and effective sort separately. A Hot request can resolve to Top while hot is disabled, a topic is ineligible, or its score snapshot is unavailable. All root and child pagination for that loaded view must use the effective sort. Preserve the requested selection for display and the next deliberate reload. Do not locally rerank loaded fragments or implement hot-score calculation.

Preloaded children are a sample. Normal preload reaches at most three levels with at most three children per parent. Hot preload has its own bounded selection, including an overall 60-post budget and 15 posts per starting root. Empty `children` does not imply no replies.

The first explicit child-page request must fetch page 0 even when preload supplied children. Merge by identity, retain existing expanded subtrees, and then advance through subsequent pages. Track whether a real child page has been fetched separately from whether children are visible.

At a capped depth, the server returns all deeper descendants as a flattened ordered child list. A returned entry's actual parent can differ from its display parent. Store both relationships. Do not reconstruct presentation by following only `reply_to_post_number`. At that boundary use total descendants, rather than direct replies alone, to describe remaining content.

When depth capping is disabled, descendants retain their direct-parent shape and the reader offers Continue this thread at the visual limit. This opens the same canonical post with `context=0`. Neither presentation mode changes the parent when replying.

## Reader behavior

### Root and context views

An ordinary list, last-read, unread, or last-post entry opens the topic root. An explicit numbered post link above post 1 opens context. Resolve `/last` as deliberate navigation intent rather than accidentally treating the sentinel as a real post number. Keep normal topic identity for tabs, history, search, bookmarks, and sharing.

Context without a `context` parameter requests a window of ancestors capped by configured depth. `context=0` rebases the target as a new depth-zero root. Positive values request an ancestor window, up to the server contract's limit of 100. Ancestors are oldest first and exclude the OP. `siblings` is keyed by ancestor post number and supplies a nearby sample, up to five entries per group. Decode it independently from paginated child lists. The current web model does not use it as a complete child page.

Keep explicit states for a complete chain, a truncated chain, a deliberately ancestor-free view, and missing visible ancestors. View full topic returns to the root. View parent context uses the top returned ancestor when truncated. A new context request replaces the old focused path even when both targets share an ancestor root.

Whole-post collapse and child-list expansion are separate states. A collapsed leaf is valid. Preserve user choices ahead of defaults. Preloaded children and placeholders normally start expanded unless route collapse intent says otherwise. Expand labels prefer total descendants, then direct replies, then loaded children.

`collapse_replies=true` is route intent. At the root it hides roots' descendants. In a context without ancestors it preserves the target and its direct replies while hiding grandchildren. With ancestors it must not hide the target. Carry this intent through navigation within the topic. Do not turn it into a site preference.

### Mobile and desktop

Desktop presents expandable branches. Phones support a focused branch with ancestor navigation, an All replies action, and restoration of the prior root anchor. Fetch necessary children before entering focus and discard an obsolete completion. Direct post links enter focused context. Back and forward restore the path and scroll state. Keep ancestor-avatar clicks within their navigation control rather than opening a competing user card.

Use semantic post anchors plus pixel offsets for restoration. If a target is unavailable, choose an adjacent visible ancestor or root and explain the missing target. User scroll intent cancels delayed restoration. Do not keep moving the viewport after the user starts scrolling.

Use a lazy visible-row projection of the graph rather than recursively mounting every loaded post. Row identity includes placement where needed. Canonical post identity remains shared. Collapse, child loads, pin changes, sort changes, live insertion, and composer layout changes preserve a stable visible anchor.

The current web cache holds 15 entries for 10 minutes and keys by topic, sort, target, and context. Native can use its own bounded tab cache, but must preserve expansion, child-page progress, requested/effective sort, focus path, root page, pins, bus cursor, and anchor. Store references and graph data, not duplicate canonical entities. Include site, account lease, tab, reader identity, and generation in the cache scope. Account retirement clears it. Do not snapshot the whole graph on each scroll frame.

### Shared post and topic workflows

Reuse the public host-backed presentation and command implementations for cooked content, uploads, oneboxes, polls, reactions, notices, user cards, flags, likes, bookmarks, sharing, quotes, edit history, edits, deletion, recovery, wiki, ownership, locking, rebake, post type, and permanent deletion. Other plugins must continue to contribute through the same registry.

Reuse topic title, category, tags, notifications, topic menus, and recommendations. Do not copy `_PostTile`, `_StoredPost`, or private topic controller logic into the plugin. Extract reusable presentation from their current owner and migrate the ordinary reader to the same API.

The OP renders separately with ordinary topic/post operations. Replies by the topic author can show an OP badge. Pinned roots show a pin indicator. Suppress the ordinary flat Show replies control through a generic post-presentation policy because this reader owns reply navigation.

Bulk selection operates on the reader's visible order. Select below means subsequent rendered rows, not increasing post numbers. Select replies uses the plugin's graph scope and must handle unloaded descendants deliberately through existing moderation workflows. Never silently claim that a partial loaded tree is the whole subtree. Topic deletion remains the OP's deletion workflow.

Open the ordinary topic reply or edit composer. Retain topic draft keys, sequences, uploads, validation, submission settlement, and queued or uncertain outcomes. Replying to a post supplies its actual parent number. Root replies use the ordinary topic-reply contract. Suppress the ordinary post-save chronological jump for the originating reader, while retaining the accepted write's canonical publication. Accepted replies notify that reader to place or refetch the relevant branch. Cancelled, queued, failed, and ambiguous submissions must not create a phantom node.

Reuse existing drafts on entry. Reader changes must not discard a draft or bind an in-flight submission to a successor tab/account. Floating topic actions follow Native chrome and composer state. The web hides its floating controls while composing and in mobile focus mode; preserve that interaction without adding a second dock.

## Plugin API design

### Existing APIs to reuse

| Existing API | Use |
| --- | --- |
| `PluginModule`, `PluginDescriptor`, `PluginSessionContribution` | Registration, scoped services, and teardown. |
| `SitePlugin`, `SiteSettingsPlugin`, `PluginSiteFeature` | Plugin-owned settings parsing and site feature evidence. `PluginSiteFeature` is a boolean query, not automatic activation or teardown. |
| `TopicRecordPlugin`, `PostRecordPlugin`, `PluginDataKey` | Typed topic/post feature records. Existing persistence codecs separately cover settings and current-user data. |
| `IsolateTopicDecoderPlugin` | Pure reconstruction for worker decoding when eligible. |
| `TopicListTitlePlugin`, `TopicListMetadataPlugin`, `PostMenuPlugin`, `TopicMapActionPlugin` | Existing additive presentation and action contributions where their contracts fit. |
| `PluginRouteNavigationHost`, `PluginLinkHandler` | Canonical route navigation and supported link interception. |
| `PluginPostHost`, `PluginTopicRefreshHost`, `PluginPostEditorHost`, `PluginPostQuoteHost` | Existing controlled writes and repair where their visibility constraints fit. |
| `PluginRequestHost`, `PluginApiTransport`, `PluginSiteLease`, `DiscourseModelCodec` | Account-bound transport and canonical decoding. |
| Existing notification records and resolution | Stable envelope, opaque data, and safe default presentation. `NotificationTypePlugin` can register new types, but cannot replace the core-owned replied type. |

These are building blocks, not a complete reader contract. `ContentPlugin` currently handles only `ExtensionDestination`. `MainContent` directly builds `TopicView` for `TopicDestination`, including list-backed readers. The existing composer host restricts `buildComposer` to targets owned by the consuming plugin. Existing edit/quote operations also assume a visible topic. Those checks must recognize the selected generic reader without granting broad shell access.

`PluginPostHost` cannot ingest arbitrary returned posts. It can update a plugin's own record and request controlled post refresh. The nested plugin therefore also needs a sanctioned canonical ingestion path.

### Chosen architecture

Choose a plugin-owned reader on the canonical topic route. Core resolves a reader and owns its lifetime, canonical entities, navigation, and shared operations. The plugin owns its graph, root/context controller, visible-row projection, and reader widget.

The alternative is a plugin-owned graph projected into an expanded core chronological viewport. That shares more viewport code, but would expose branch expansion, context paths, synthetic rows, depth flattening, and per-parent paging through many core callbacks. It also risks retaining feature-specific resume, geometry, and unread assumptions. Reuse generic geometry and post presentation from the existing reader instead of making core interpret the graph.

Use the alternate design's useful constraint: the plugin's reader must still virtualize a flat projection of currently visible rows and report standard visible-post observations. Owning the reader does not justify copying post workflows or mounting an unbounded widget tree.

### Proposed contract families

The names below are design names. Final signatures must fit the existing SDK's scoped host-port and owned-builder conventions. Implement the smallest complete contracts, update existing APIs where appropriate, and migrate callers rather than retaining two competing ways to do an operation.

| Proposed generic contract | Responsibility and constraints |
| --- | --- |
| `TopicReaderPlugin` with owned `TopicReaderSession` | Inspect authoritative topic plugin data and route intent, return a reader contribution or decline. Core selects at most one. Conflicting claims are an explicit registry error, not first-match behavior. Own activation, suspend/resume, and close. |
| `TopicReaderContext` | Carry site/topic identity, explicit target, tab/navigation identity, metadata provenance, and opaque plugin route data. No shell controller, credential store, or feature flags. |
| Topic entry and activity policy | Resolve root versus chronological resume, initial header/sheet position, unread indicators, queue membership, separator policy, and catch-up projection through typed generic results. Permit no contribution so ordinary defaults apply. Pure synchronous projections consume current canonical records and freshness. |
| Lease-scoped topic content host | Run an ingestion callback under owner-reserved read authority and accept typed decoded metadata/post batches through `TopicDataSession`. Separate metadata updates from stream-membership authority. Enforce holds, revisions, bookmark authority, redaction, lease validity, and stale-response rejection. Return accepted IDs and a revision before the plugin commits graph edges. |
| Public topic/post presentation | Build standard topic header/footer and post content/actions for supplied canonical IDs and generic presentation policies. Allow a reader to own reply navigation and visible selection order. Redacted feature placeholders can use a separate plugin composition. |
| Ordinary topic composer operation and write observations | Open normal reply/edit with an originating reader token and post-save navigation policy. Publish typed accepted outcomes and semantic mutation events. Preserve the existing composer and mutation owners. |
| Topic event and read-observation host | Observe authorized core topic events and canonical changes; submit visible post timing observations; request tracking reconciliation after a foreground visit. No access to raw reserved channels or direct notification counters. |
| Opaque topic route and reader history data | Preserve namespaced plugin query/anchor state through parsing, serialization, tabs, sheets, deep links, and back/forward. Core stores the envelope and dispatches its codec; the plugin owns query names and meaning. |
| Notification presentation/destination strategy | Allow a site/session-scoped contribution for an existing notification type to decline or supply validated presentation and route intent. Keep original type ownership, reject conflicting matching strategies, and retain the core safe fallback. |

Add generic topic-admin and topic-list bulk-action contributions for the administrative scope below. Native currently has no equivalent topic-bulk mutation host or category-admin editor to plug into. `CategoryEditComposerTarget` edits a topic's category; it is not category administration. Category parity therefore requires a generic category load/save/form host as well as category-record decoding. These are explicit implementation prerequisites, not existing controls that only need a callback. Preserve unknown category settings on save. `TopicCategory` currently has no equivalent of topic/post plugin records. Do not add a nested category field to it as a shortcut.

### Caller usage before type details

The intended plugin flow is small. Registration declares a topic-reader capability and session-scoped dependencies. The plugin's decision reads its typed topic data. Once selected, its controller fetches a tree page, submits canonical content through the host, and commits graph references only if the host accepts the result. Post rendering and replies delegate to host operations.

```dart
// Illustrative proposed SDK usage, not code that compiles today.
final decision = switch (context.metadataAuthority) {
	MetadataAuthority.unresolved => const TopicReaderDecision.discover(),
	MetadataAuthority.authoritative =>
		nestedTopicData(context.topic.plugins).enabled
			? TopicReaderDecision.use(nestedReaderFactory)
			: const TopicReaderDecision.decline(),
};

final accepted = await reader.content.ingest((boundRequest) async {
	final page = await nestedApi.roots(boundRequest, request);
	return TopicContentResult(
		content: page.canonicalContent, // No flat stream replacement.
		value: page.graph,
	);
});
if (accepted != null && request.matches(controller.currentRequest)) {
	controller.mergeRootPage(accepted.value, accepted.postIds);
}

reader.presentation.post(postId, policy: ownsReplyNavigation);
reader.composer.reply(parentPostNumber: actualParent, origin: reader.token);
```

Derive signatures from these responsibilities. Ingestion captures the original lease, topic, and publication revisions before invoking the request callback. The host releases its operation ownership on success, failure, cancellation, and retirement. Do not expose private stamps or require the plugin to coordinate public begin/commit/abort methods.

The reader decision has three outcomes: decline, request authoritative discovery, or select a factory. The selected factory receives one scoped session, not the process-wide service graph. A separate reader request key captures tab, navigation, mode, target, sort, parent, depth, and generation. Content acceptance cannot by itself authorize a stale reader to mutate its graph or navigate.

Ingestion acknowledges accepted post IDs and a canonical revision. Rejected posts cannot be blindly installed as graph nodes. Existing Store publication can notify listeners between records, so the API must not promise atomic batch publication without implementing it. Graph reduction runs only after acknowledgement and another current-reader check.

### Resolve before resume and reader effects

Integrate resolution before both held-detail and fresh-detail chronological resume paths in `TopicDataSession.open`. Wrapping `TopicView` after core has already restored a flat position is too late.

For a cold or uncertain open, permit one ordinary unpositioned topic discovery read to obtain authoritative metadata. Keep it free of foreground visit side effects where the transport supports that distinction. Do not mount a flat viewport, start its timing, or resolve chronological last-read navigation while deciding. Preserve an explicit target separately so the selected plugin can request context around it.

Once resolved, keep exactly one reader's viewport, read reporting, paging, and live effects active. Close or suspend the old handle before activating its replacement. Preserve canonical content and drafts across the switch. Apply this path to standalone topics, list-backed sheets, PM entry, desktop panels, restored tabs, background refreshes, and cached navigation. A background discovery read may resolve metadata but must not perform a foreground visit.

The initial implementation may pay an extra discovery request for an unknown topic. Optimize only after equivalent activation, permission, and account guarantees are demonstrated. Do not accept speculative cached activation to save that request.

### Preserve canonical ownership

`TopicDataSession` remains the sole incoming topic/post publisher described in [Topic data ownership](../architecture/topic-data-ownership.md). Its new generic batch operation must use existing dispatch stamps, removal history, post-write holds, archive/bookmark authority, and per-record lease checks. A synchronous Store listener can retire a lease during a batch, so a single check before the loop is insufficient.

The plugin keeps post IDs, post-number lookup, display edges, real-parent metadata, counts, page state, and presentation state. It reads canonical entities through scoped handles. Never flatten roots into `TopicDetail.stream`, replace chronological stream authority with a partial tree, or write directly to Store.

Generic publication must distinguish complete records from partial updates and redaction. This is a concrete blocker in the current model. `Post.merge` preserves held `raw` when incoming `raw` is null and the version and update timestamp match. An ignored placeholder can have exactly that same revision with intentionally cleared content, so ordinary merging can restore the old raw body. `TopicDataSession._publishPosts` handles removal/bookmark admission and lease checks, but is not a complete redaction or per-post write-conflict API.

Add a generic authoritative content disposition to ingestion and apply it before ordinary merge. The plugin translates its placeholder flags into that disposition. Core applies generic clear/preserve rules without knowing those flags. The receipt also governs later competing refreshes under the original account authority. Prove that a placeholder clears both rendered and editable content and that stale ordinary reads cannot restore it. Do not expose a broad ingestion method that simply calls today's private `_publishPosts`.

Post mutation events are invalidation or accepted-write observations. The plugin can patch placement for a confirmed own reply, then reconcile the relevant graph. Reparenting, pin changes, deletions, and rank changes may require branch or root reload. Existing canonical after-write repair continues in its owner. The plugin must not create a second repair pipeline or a second mutable copy of posts.

## Live updates, timing, and list state

### Topic events

The server's initial `message_bus_last_id` is the replay cursor for `/topic/:id`. Core reserves the `/topic` channel namespace in `PluginRuntime`. Do not weaken that reservation or let the plugin subscribe through a forged channel scope.

Provide authorized topic-scoped event observation through the selected reader handle. Core retains transport, cursor, reconnect, and subscription ownership. It can expose typed common events and an opaque payload for plugin-owned interpretation where required. Ensure replay from the response cursor covers the gap between HTTP loading and observation. Deduplicate HTTP/live/own-write overlap by post ID and event identity. Retire subscriptions with the reader and original account.

Match the web's behavior for created, revised, rebaked, deleted, recovered, and acted posts.

- Fetch unknown created posts through an authorized canonical path and verify their topic after the await.
- Separate activity entries from ordinary tree nodes.
- Insert a confirmed own root reply immediately. Queue other users' roots behind a New replies action so reading does not jump.
- Ignore unrelated roots in context mode. Deliver children to the correct display container, including flattened descendants whose display parent differs from the real parent.
- Retain structural placeholders on deletion. Rehydrate revisions and actions through the canonical codec so action summaries remain valid.
- Reconcile counts and rank changes from the server. Do not increment every visible ancestor from a possibly duplicated event.

### Visit catch-up and visible timing

On an actual signed-in foreground root/context entry, send `track_visit=true`. Omit it for prefetch, speculative reads, child/activity paging, and background tabs. The server then records the visit and, for an effective nested topic, catches up the entire topic and clears its post notifications. This is separate from viewport timing.

Omitting `track_visit` suppresses signed-in visit/catch-up work. Show/context still schedules server topic-view accounting. Do not describe those reads as entirely free of server side effects or prefetch more trees than needed.

Continue reporting only posts actually rendered and read. Ranked rows can have decreasing post numbers. Collapsed descendants do not receive timings. Never synthesize timings for every number up to the highest visible or highest loaded post.

Visit catch-up is deferred server work. Do not treat HTTP completion as proof that all tracking and notification projections have already settled. Ask existing tracking/notification owners to reconcile using generic APIs and original-lease guards. Retries must tolerate delayed server state. Any provisional local visit projection belongs in the generic read owner and must not claim that invisible posts accrued reading time.

The plugin's list policy uses `has_new_replies` for the reply dot and suppresses numeric unread/new-topic badges. The server emits the reply flag only for applicable signed-in nested list rows with a previous visit, another last poster, and a bump after that visit. An absent flag on an authoritative list row means no reply dot. Its absence on sparse topic metadata is not proof of a caught-up list state.

Do not implement this by comparing last-read to the highest post number. Preserve `listReadStateKnown` semantics and route queue decisions through the same generic activity policy used by row presentation. Ordinary topics keep their existing behavior when the plugin declines.

### Notification routes

Consolidated replied notifications use `reply_to_post_number` as a bucket. Bucket 1 means topic root. With `consolidated_count > 1`, the destination is the bucket parent or root with `sort=new&collapse_replies=true`. Preserve those query values across notification selection, deep-link parsing, route storage, and tab restoration.

The plugin owns bucket semantics and labels. Core already owns replied's wire ID and name. `PluginRegistry._validateNotificationTypes` rejects a plugin declaration for that same type. Add a generic site/session-scoped notification presentation/destination strategy that can return a contribution or decline for an existing type, with explicit conflict handling and core fallback. The current decoder receives only a site URL and notification, so supply current capability evidence through the owned strategy's session rather than assume it has access to settings. Retain core ownership of the wire type and notification counters. Do not register a duplicate replied type or add a nested branch to the core resolver. Existing generic consolidated-count presentation can remain generic; bucket-parent routing and topic/post-specific nested labels belong in the plugin.

Absent or disabled plugins retain Native's existing safe fallback. That fallback derives a canonical topic route only from the stable notification envelope. It deliberately ignores arbitrary URLs inside plugin payload data. The new strategy must not weaken this boundary.

Sharing always produces the canonical `/t/:slug/:id/:post_number` link. Preserve a forum subfolder and same-site validation. Compatibility handling for old `/n/` links belongs in the plugin's link adapter, with fallback when unavailable.

## Administrative behavior

Reading is not staff-only. Administrative controls require current site availability, the appropriate topic/category permissions, and a current lease. Recheck at invocation; the server remains authoritative.

| Control | Required behavior |
| --- | --- |
| Per-topic mode | Staff who can edit the topic may enable or disable. Hide for PMs and when the global default makes disabling ineffective. Refresh topic and list metadata after success. |
| Pin root | Staff who can edit may toggle an eligible non-OP root. Use post ID. Maximum is 10 pins; unpin remains possible at the limit. Apply the returned complete list and reconcile root order. |
| Bulk topic mode | Add a generic topic-list selection/action host and contribute the operation from the plugin. Match enabled site, staff, no PMs, no global forced default, and actionable selection. Send the server bulk request once and use its changed IDs and errors rather than assuming every selected topic changed. |
| Category default | Show only when site feature is enabled and category edit is permitted. Save `category_setting.nested_replies_default` using a generic category plugin field path. |
| Convert existing category topics | Separate action after the category has been saved with default enabled. Confirm conversion of nondeleted regular topics directly in this category, excluding existing nested records and subcategories. POST once, show returned count, and retain the completion marker. |

Disabling per-topic mode deletes the `NestedTopic` record and its pins. If the global default is true, effective nested mode remains true despite the toggle response reporting the requested boolean. The refreshed server predicate decides the reader.

The category host must provide an authoritative detail/permission read, contribution mounting, save lifecycle, and preservation of unrelated `category_setting` and `custom_fields` values. The plugin default lives in `category_setting.nested_replies_default`. The conversion marker lives separately in `custom_fields.nested_replies_conversion_completed`. Saving one must not erase the other or another plugin's fields.

Pin is a toggle, so automatic retry after an uncertain response can undo a successful write. Category conversion and topic mode changes also need explicit uncertain-outcome recovery. Re-read authoritative state before offering another mutation. Do not replay an ambiguous action as a generic network retry.

The activity action appears only when `topic.has_activity_log` is true. Load 50 real entries per page, with server lookahead controlling `has_more`. Page 0 adds a synthetic topic-created entry with no normal post ID. Small actions and whisper action-code posts follow server visibility. Reuse permitted edit/delete/recover workflows for real entries. A live activity change refreshes page 0 without inventing an activity affordance for ordinary post deletion.

## Native component composition

Follow [Native component conventions](../component-library/conventions.md), the catalogue, and the styleguide. All controls import the public Native kit. Use Flutter layout, focus, text, and semantics primitives only to compose kit components.

| Reader need | Existing Native composition |
| --- | --- |
| Reader header and available body height | `DPageSurface` and existing specialized headed-reader conventions. Reuse shell sheet and header geometry. |
| Sort | `DSelect` with typed supported choices. |
| Reply, load more, new replies, parent context, all replies | `DButton` or `DButton.iconOnly`. |
| Disclosure | `DCollapsible` with kit-owned trigger/content behavior, or ordinary kit action controls operating on plugin state. Keep post and child collapse separate. |
| Ancestor path | `DBreadcrumb` and its existing item/link composition, using available overflow behavior. |
| Menus and context actions | `DDropdownMenu`, `DContextMenu`, and shared post/topic command presentations. |
| Errors, empty content, loading, confirmation, activity | Existing Native alert, empty, skeleton, dialog, sheet, and scroll components. |

Use existing post presentation for content and existing kit badges for author/pin state. Thread guides can be passive layout decoration. They must not become bespoke clickable rails, invisible collapse areas, or expanded hit strips. Phone touch handling remains owned by `DTouchTargets` and `DTouchFields`.

The available kit includes disclosure and breadcrumbs, so no new tree control is a prerequisite. If a required interaction cannot be composed using existing APIs, stop and ask the user before adding or extending a kit component. This plan does not authorize a new component, trigger option, animation, or hit area.

Verify narrow phone and desktop layouts, large text, RTL indentation, focus after collapse, keyboard activation, clear expand/collapse labels, placeholder semantics, loading announcements, and reduced motion. Preserve the focused post and meaningful back navigation across orientation changes.

## Plugin module and state map

Prefer these responsibilities over a single controller that owns networking, rendering, and core mutations.

```text
lib/src/plugins/nested_replies/
  nested_replies_module.dart       Registration and declared host dependencies.
  nested_replies_plugin.dart       Settings/record codecs and contributions.
  nested_replies_data.dart         Plugin records, capability and placeholder variants.
  nested_replies_api.dart          HTTP paths and tree response parsing.
  nested_replies_controller.dart   Graph, root/context state, generations and invalidation.
  nested_replies_navigation.dart   Canonical link intent, focus and history encoding.
  nested_replies_reader.dart       Native reader composition and lazy row projection.
  nested_replies_activity.dart     Activity paging and synthetic entries.
```

Split further only when responsibility or size warrants it. Settings, routes, API paths, and rank/depth logic must remain in this module even if the server implements them in core.

The plugin domain contains the following distinct data.

- A capability snapshot with site/account authority and topic mode.
- A tree view key with topic, root/context mode, requested/effective sort, target, context window, and collapse intent.
- A graph of canonical post references plus actual-parent and display-parent relationships.
- A page state per root list and per parent/depth/effective-sort child list, including preload-only versus fetched-page status.
- A placement state for expanded/collapsed posts, focused path, pending new roots, selection order, and semantic scroll anchors.
- An operation key with original lease, tab, reader identity, and generation for every asynchronous completion.

Sort/context changes reset incompatible pages and request generations. Failed paging retains accepted graph state. Retired work cannot clear a successor's loading flag, release its write hold, publish records, or navigate. Closing a tab retires its reader without deleting another tab's graph. Account changes at the same site URL retire all old work.

## Implementation sequence and completion criteria

1. Add generic topic reader resolution and lifecycle with a fake provider. Integrate both standalone and list-backed topic paths before resume. Prove default behavior with the provider absent, declined, and selected, including restored/background tabs.
2. Add provenance-aware plugin record decoding/merging and the generic activity/entry policies. Migrate every existing nested-specific core field and branch. Add plugin-owned record/settings codecs and migrate retained legacy payloads where applicable. The core-only model and reader must then contain no nested semantics.
3. Extract shared post/topic presentation and ordinary composer operations behind scoped public contracts. Migrate the ordinary reader to them. Prove existing reactions, polls, quotes, bookmarks, moderation, selection, drafts, and post-save behavior still use their original owners.
4. Add canonical metadata/post batch ingestion and reader event/read observations. Implement authoritative redaction before ordinary merge. Exercise original-lease retirement, stale read stamps, write holds, redaction, partial metadata, and subscription replay before using them in the feature.
5. Add the nested API adapter, typed graph, root/context loading, requested/effective sort, child paging, placeholders, depth boundaries, and terminal recommendations. Use sanitized fixtures reflecting the inspected server responses.
6. Build Native root/context readers, mobile branch navigation, expansion, lazy projection, anchors, and history restoration. Implement canonical link intent and replied-notification integration through generic APIs.
7. Connect accepted writes and live changes. Add pending new roots, child placement, canonical action refresh, activity log, foreground visit catch-up reconciliation, and visible timings.
8. Add topic/pin controls and topic-list bulk selection/action contributions. Build the generic category detail/save/form host before adding plugin category defaults and historical conversion. If category administration remains browser-only, document that explicitly as deferred parity rather than declaring full parity.
9. Verify enabled, disabled, unsupported, missing-plugin, account-switch, and permission-loss behavior. Run only directly affected test files and scoped analysis. Review the diff for feature logic outside the plugin and validate the feature on a server with nested replies enabled.

Each unit must leave its generic replacement usable and its migrated callers consistent. Do not add nested branches temporarily to bridge units. The first implementation task is reader arbitration with a fake plugin, because every subsequent feature depends on correct opening ownership.

## Verification matrix

| Area | Required observable checks |
| --- | --- |
| Plugin absence | Core manifest ignores feature fields, sends no `/n/` requests, renders no nested controls, and keeps ordinary entry/unread behavior. |
| Activation | Enabled site plus nested topic selects plugin; flat topic and PM decline; category defaults never opt old topics in locally; fresh omitted flag revokes cached activation; successful `/n/` alone cannot activate. |
| Availability failure | Missing settings, explicit false, 404, 403, timeout, malformed JSON, and 500 remain distinct. One failing forum does not affect another. Disabled controls disappear after a fresh denial. |
| Root paging | Separate OP; 20 ordinary roots; extra pins in stored order; duplicate-free subsequent pages; exact-multiple empty terminal page; recommendations only become resolved when returned. |
| Child paging | Preload is not page 0; merge preserves expanded descendants; independent parents load concurrently; duplicate events/pages do not duplicate rows; failed page retries do not advance. |
| Rank and depth | Requested Hot with effective Top paginates consistently; sort races discard old results; capped descendants retain actual parents; uncapped continuation uses `context=0`. |
| Context and links | Root, explicit post, `/last`, missing/deleted target, no ancestors, truncated ancestors, sibling samples, `collapse_replies`, subfolder links, sharing, notification query preservation, and cold restored routes. |
| Reader ownership | Only one reader runs effects; cached and fresh opening choose before resume; list-backed mobile sheets and desktop panels use the same selected reader; inactive tabs cannot mark visits or navigate. |
| Account and operation races | Switch account while obtaining credentials, loading roots/children/context, publishing a batch, submitting, reconnecting, or restoring an anchor. No old publication or successor-state cleanup. |
| Shared writes | Root/child reply, edit, queued/ambiguous submit, quote, flag, reaction, bookmark, delete/recover, reparent, and selection operate on the canonical post and original draft. No automatic chronological jump. |
| Visibility | Deleted ancestors retain children; stale bodies cannot bypass redaction; ignored reveal uses authorized cooked fetch; whispers/activity reflect permissions; OP behavior differs correctly. |
| Live updates | Cursor replay covers HTTP/subscription gap; own roots insert once; other roots queue; context ignores unrelated roots; capped child placement is correct; action summaries remain usable after refresh. |
| Read state | Foreground visit requests catch up server-side; prefetch/background/paging do not; only visible posts accrue timings; sparse topic data cannot clear the reply dot or remove unread queue entries prematurely. |
| Admin | Staff plus edit permission; pin root and ten-pin limit; unpin at limit; forced global default; uncertain pin outcome; PM denial; saved category default before conversion; completion marker. |
| Presentation | Phone focus/back restoration, desktop branch expansion, collapse focus, large text, RTL, keyboard, reduced motion, composer overlap, permission loss, and loading/error states. |

Use existing test locations as migration targets, especially `topic_detail_test.dart`, `model_boundary_test.dart`, `topic_summary_unread_state_test.dart`, `unread_topic_feed_test.dart`, `topic_reading_integration_test.dart`, and `topic_header_initial_state_test.dart`. Generic reader/data behavior belongs with the existing topic owner and plugin API tests. Feature behavior belongs under `test/plugins/nested_replies/`.

Run `test/plugin_dependency_boundary_test.dart`, directly affected plugin presentation/extension boundary tests, and individual changed topic/composer suites by file path. Extend source ownership checks to reject nested endpoint strings, setting keys, imports, and semantic branches in core. Allow only explicit composition, generic infrastructure, and plugin-owned fixture/test locations. Do not broaden an allowlist to accommodate feature logic.

Backend/web parity references include `spec/requests/nested_topics_controller_spec.rb`, the `spec/services/nested_topic/` suites, `spec/lib/nested_replies/tree_loader_spec.rb`, `post_tree_serializer_spec.rb`, and the `spec/system/nested_*_spec.rb` suites. The web's unit tests for nested controllers, context models, cache restoration, depth, ignored users, and collapse intent provide additional behavior examples. Port observable requirements, not framework-specific assertions.

## Decisions to preserve during implementation

The strict plugin boundary is required. The reader must keep canonical topic URLs and use shared post/composer owners. Server-side tree counts, rank scores, and visibility stay on the server. The initial discovery request is an accepted cost for correct availability and opening behavior.

No flat-view user preference exists in the inspected implementation. Do not add a new preference or offer a local mode switch as assumed parity. Do not copy the web's invisible collapse gestures, raw control geometry, or private controller delegation.

Resolve concrete gaps before their implementation unit: the exact authoritative-redaction disposition and competing-read rules, how the new notification strategy composes with core fallback, the scope of generic category administration, and whether any required Native interaction is missing from the kit. A missing kit capability requires the user's direction. A missing plugin API requires a generic contract in core, never a feature-specific workaround.

## Source map

Discourse paths below are relative to `/Users/joffreyjaffeux/Code/discourse`.

| Concern | Owning source |
| --- | --- |
| Effective mode and category creation defaults | `app/models/topic.rb:844`, `config/initializers/300-nested-replies.rb:9`. |
| Serialized mode and reply activity | `app/serializers/topic_view_serializer.rb:340`, `app/serializers/topic_list_item_serializer.rb:152`, `app/serializers/suggested_topic_serializer.rb:43`. |
| Endpoint routing and visits | `config/routes.rb:1529`, `app/controllers/nested_topics_controller.rb:35`, `:249`. |
| Root, child, and context contracts | `app/services/nested_topic/list_roots.rb`, `app/services/nested_topic/list_children.rb`, `app/services/nested_topic/show_context.rb`. |
| Visibility, preloads, counts, and depth flattening | `lib/nested_replies/tree_loader.rb`. |
| Node redaction and recommendations | `lib/nested_replies/post_tree_serializer.rb`. |
| Sort and score fallback | `lib/nested_replies/sort.rb`, `lib/nested_replies/hot_score_cache.rb`, `lib/nested_replies/hot_score_calculator.rb`. |
| Pins and mode mutation | `app/models/nested_topic.rb`, `app/services/nested_topic/toggle.rb`, `app/services/nested_topic/toggle_pin.rb`. |
| Bulk topic mode | `config/routes.rb:1557`, `app/controllers/topics_controller.rb:1136`, `lib/topics_bulk_action.rb:327`. |
| Category conversion | `app/services/nested_topic/convert_category.rb`, `frontend/discourse/app/connectors/category-custom-settings/nested-replies-settings-upsert.gjs`. |
| Reply graph lifecycle | `app/models/concerns/has_nested_reply_stats.rb`, `lib/post_revisor.rb:632`. |
| Route arbitration and models | `frontend/discourse/app/routes/topic/from-params.js:68`, `frontend/discourse/app/lib/nested-topic-model.js`. |
| Expansion and child pages | `frontend/discourse/app/components/nested/post.gjs`, `frontend/discourse/app/components/nested/post-children.gjs`. |
| Mobile context and restoration | `frontend/discourse/app/components/nested.gjs`, `frontend/discourse/app/services/nested-view-cache.js`, `frontend/discourse/app/lib/nested-view-cache-snapshot.js`. |
| Live events and commands | `frontend/discourse/app/controllers/nested.js`, `frontend/discourse/app/controllers/topic.js:1879`. |
| Notification context intent | `frontend/discourse/app/lib/notification-types/replied.js`, `app/models/notification.rb:464`. |

Native paths below are relative to this repository.

| Concern | Owning source |
| --- | --- |
| Typed records and contribution interfaces | `lib/src/plugin_api/site_plugin_api.dart`, `lib/src/models/plugin_data.dart`. |
| Scoped host ports and navigation | `lib/src/plugin_api/core_plugin_host.dart`, `lib/src/plugin_api/shell_extensions.dart`. |
| Registry ownership and reserved live channels | `lib/src/plugin_api/plugin_registry.dart`, `lib/src/plugin_api/plugin_runtime.dart`. |
| Notification fallback and duplicate-type rejection | `lib/src/plugin_api/notification_types.dart:328`, `lib/src/plugin_api/plugin_registry.dart:1141`. |
| Both topic mount paths | `lib/src/shell/main_content.dart:817`, `lib/src/shell/main_content.dart:984`. |
| Opening before held/fresh resume | `lib/src/shell/topic_data_owner.dart:795`, `lib/src/shell/topic_data_owner.dart:928`. |
| Canonical publication and raw-preserving merge | `lib/src/shell/topic_data_owner.dart:522`, `lib/src/models/post.dart:302`. |
| Private post presentation to extract | `lib/src/shell/topic_view.dart:4042`, `lib/src/shell/topic_view.dart:4177`. |
| Existing topic reply opening | `lib/src/shell/shell_controller.dart:6550`. |
| Category model without plugin settings storage | `lib/src/models/topic.dart:898`. |

The architecture must continue to satisfy [Topic data ownership](../architecture/topic-data-ownership.md), [Topic tracking reconciliation](../architecture/topic-tracking-reconciliation.md), and [Native component conventions](../component-library/conventions.md).
