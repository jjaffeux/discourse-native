# Bookmark transactions

`BookmarkTransactions` owns core and plugin bookmark operations. The shell
composes its ports and retains the existing `BookmarkHost` facade. The target
hosts bind core or plugin authority before they call the owner. Public plugin
contracts and `BookmarkWriteResult` remain unchanged.

Each `BookmarkAccountSession` captures one `SiteLease`. It owns target admission,
credentials, create/update/delete, reminder changes, bulk deletion, bookmark
revisions, projections, and repair scheduling. Its active sets belong to that
account. Captured release closures are idempotent and release only original
post holds. Account retirement discards session metadata without touching a
successor at the same URL.

`Store` remains canonical. The bookmark session updates only bookmark fields on
current records. Every projection checks both the original lease and its topic
revision between observable Store writes. A metadata repair cannot replace a
newer post body, checklist result, topic stream, title, or archive state.

`TopicDataOwner` receives `BookmarkReadProjection` for its original lease. It
captures revisions at read dispatch, including speculative reads, and asks the
bookmark owner to preserve newer metadata during publication. Post mutation
acknowledgements preserve canonical bookmark fields through the same port. Row
publication asks again after detail publication because a Store listener can
change bookmark authority synchronously.

`BookmarkTopicData` is the reverse port. Topic data keeps post hold accounting
and nonpublishing metadata transport. A `BookmarkTopicSnapshot` contains only
bookmark metadata. The bookmark session owns the repair revision and every
subsequent projection. Constructors do not resolve this reverse port, so owner
binding cannot recurse.

Bookmark and checklist writes may overlap. Other active post writes block post
bookmark admission. Bulk deletion reserves the topic and its currently known
bookmarked posts. The final post hold still replays deferred live invalidation
through the existing topic data owner.

An unreachable create returns a reconciled result and starts a metadata read.
It never retries the create. Plugin repair uses the captured target strategy.
Account menu refresh and loaded-list refresh check the original lease between
calls. AccountActivityController retains that lease for queued forced bookmark
reads and skips retired replays. A full list that has never loaded stays lazy.

`bookmark_transactions_test.dart` covers repair ordering, body preservation,
retirement between publications and account refresh callbacks, admission
retirement, uncertain outcomes, and forced refresh retirement. Existing shell,
opening-session, ordering, post hold, checklist, and editor tests pin the
unchanged user behavior.

`BookmarkLinkResolver` owns cached topic-list actions and asynchronous link
resolution. The shell supplies serving-forum lookup and current plugin resolver
capabilities. The resolver captures the existing `BookmarkAccountSession` for
its lease, revision guard and write admission. It reads topic payloads with
key-only credentials and never publishes those payloads or navigates. Returned
core actions retain the original account and revision guard, then use the
existing target host for writes. Plugin target identity and actions remain
owned by the plugin resolver. The resolver has no separate account state or
retirement path.

`bookmark_link_resolver_test.dart` constructs the resolver without a shell or
Flutter binding. It covers key-only request identity, replacement during
credential and topic reads, action retirement, active writes and current plugin
capabilities. `bookmark_shell_controller_test.dart` pins exact target identity
and nonpublication. `open_link_test.dart` drives the rendered context menus.
