# Composer ownership

The live editor keeps Markdown as its canonical document. Feature modules own
their syntax and artwork. The editor owns source offsets, selection, IME
composition, history, overlap resolution, and span caching.

## Core features

`lib/src/shell/composer/components/` contains the built-in feature modules.
`link.dart`, `code.dart`, `details.dart`, `list.dart`, `table.dart`,
`video.dart`, and `upload.dart` own their syntax policies, projections and
editor behavior, and declare no widget. Their widgets live beside them in
`code_editor.dart`, `details_editor.dart`, `table_editor.dart`,
`list_item_editor.dart`, `link_pill.dart` and `link_dialog.dart`;
`image.dart`, `gallery.dart`, `quote.dart`, `todo_marker.dart`, `blockquote.dart`
and `emoji.dart` construct their own presentation. Image and gallery toolbars and
menus also live with their features. The mobile image toolbar receives the
shared history controls from the panel. Lossless parsers live beside their
feature in `*_source.dart` files when they need a separate module.

The controllers never import a widget library of the shell or the UI kit
barrel. A projection owns its source geometry: the spans, hidden tail, keys and
caret rules around a component. The widget placed inside its span comes from `ComposerArtwork`
(`composer/artwork.dart`, what the document controller draws itself: media,
quotes, pills, links, keycaps and task checkboxes) and `ComposerComponentArtwork`
(`composer/component_artwork.dart`, the core components whose widgets embed an
editor bound to their `ComposerController`). `components/core_artwork.dart`
is the one implementation, and `ComposerEditor` installs it on the composer at
mount, which shares it with the document controller. A controller rendered in
a plain field names its own artwork; drawing a component with none installed
throws, because that is a wiring error rather than a state to render around.
A projection starts editing its component through `ComposerComponentEditor`,
the interface the editor widgets' States implement, reached through the pill
key the projection handed to the artwork.

`core.dart` constructs built-in policies once per composer. Plugin targets retain
their existing reduced set of core features. Link policy configuration stays
in the Markdown editor because its linkify settings can change during editing,
and the link policy reads the artwork lazily for the same reason.
`topic_emoji_picker.dart` binds the shell to the emoji picker for forum
composers; plugin composers bring their own emoji host.

`MarkdownEditingController` coordinates these features. It keeps retained keys
and document-dependent state, then calls the artwork with explicit values and
callbacks. Emoji owns its pending artwork loads per editor and suppresses
completion callbacks after disposal. The shared media pipeline still owns the
cached bytes and network request deduplication.

`source_projection.dart` preserves UTF-16 offsets when widgets replace Markdown
characters. Its shared normalization also prevents hidden source from changing
component height or hit geometry. Feature renderers must preserve their source
range length. They cannot independently change selection or history.

Video previews use the existing syntax policy path through `video.dart`.
Image-style media tokenization and upload Markdown remain shared in
`image_source.dart`, alongside the existing upload preparation pipeline.
Oneboxes remain cooked-content renderers in `lib/src/shell/oneboxes/`.

## Plugin features

The live extension point is `ComposerSyntaxPlugin` in
`lib/src/plugin_api/composer_syntax.dart`. A plugin declares one namespaced
`ComposerSyntaxKind` and creates a policy for each composer. The registry supplies
policies through the existing site runtime. Core composer modules do not import
bundled plugin implementations.

The policy parses source into projections. Each projection owns its collapsed
artwork, raw-source rules, caret boundaries, and edit or removal actions. Actions
must check the current editor and verify captured source before applying changes,
including after asynchronous pickers. Live settings and permissions come from
the policy context's state reader.

Poll, Events, Local Dates, and Mermaid keep their composer behavior in their
plugin directory's `*_composer.dart` module. Plugin entry points delegate their
composer hooks to that module. Parsers, sheets, and embedded editors remain
supporting files beside it. Existing syntax IDs and site enablement stay in the
plugin registration path.

## Design choice and verification

Standalone builders keep the feature-specific types precise. A universal
component interface would need to treat inline emoji, editable task rows, and
interactive plugin blocks alike. The existing editor already owns their shared
invariants, so another interface would duplicate that ownership.

`projected_component_input.dart` defines a sealed input-only handle for quotes,
images, galleries and syntax occurrences. These handles carry source identity,
UTF-16 ranges and caret behavior. They do not render, capture UI context or own
feature state. `MarkdownEditingController` owns collapsed lookup, adjacent
component commands and native source-edit planning. The panel decodes key events,
keeps native proposal lifecycle guards and dispatches typed commands to the
existing feature owners. Containment, boundary lookup and leading block selection
retain their distinct nested precedence. Source equality preserves retained keys;
exact parser-target identity guards deferred deletes. Input handles never become
widget keys.

The existing rendered-editor tests pin source length, caret geometry, composition,
span cache identity, artwork retries, atomic deletion, gallery identity, and
undo. Plugin tests pin permissions and stale picker behavior. The composer plugin
boundary test also prevents built-in modules from importing bundled features.

## Opening and setup

`composer/opening_owner.dart` owns creation admission for new topics, messages,
and continuations, plus delayed new-topic setup. Shell captures the source site, account lease, tab, feed and route. The
owner prepares a plan containing the exact draft key and initial taxonomy.
Shell builds and registers the editor, starts setup and publishes presentation.
Metadata loading therefore does not block the first editor frame.

Each setup session keeps its account lease, editor and draft identity. Registry
membership admits retained editors even when another draft is selected. Account
retirement, editor removal and owner disposal suppress late setup results.
The owner resolves placeholder categories and tag-list seeds, updates the current
category's tag minimum and applies its template after draft restoration.
`ComposerController` keeps authority over untouched tags, text and templates.

`ComposerOpeningPresentation` supplies selection, registry membership, source
validity, replacement confirmation and publication. `ComposerOpeningMetadata`
provides canonical taxonomy and capability services. Neither port gives the
standalone owner access to `ShellController`. Draft persistence and restore
ordering remain in `ComposerDraftCoordinator`. Category changes reuse the setup
owner for templates and tag validation.

`composer/existing_topic_opening_owner.dart` prepares reply reuse/creation and
post/topic edit plans. Its continuations keep the original account lease and
exact editor. Quote insertion waits for that editor's draft restoration and
checks the exact originating reader route, including when another reader is
focused. Raw edit loading follows retained editors across tab changes and keeps
stored whitespace and caret matching intact. Shell builds, registers, selects
and publishes editors. The owner reads canonical posts for whisper policy through
Store and receives only editor membership and reader-validity capabilities.
Draft restoration and persistence remain in `ComposerDraftCoordinator`.

## Upload transactions

`ComposerController` keeps the public upload commands and read-only upload views.
Its private `_ComposerUploadTransactions` in `upload_transactions.dart` owns
batches, rows, pending requests, prepared media, cancellation, retry, progress,
placeholder lifetimes, insertion anchors and gallery upload targets. It is a
part of the controller library, so consumers cannot import a second upload API.

The owner uses `_ComposerUploadEditor` for current admission and target policy,
gallery source queries, editor access, notices and notifications. The existing
Markdown editor and history remain authoritative. The composer delivers source
changes synchronously, advancing its source baseline before cancellation can
re-enter the listener. The upload owner keeps exact insertion transforms beside
anchor movement and amends history when undo restores a settled placeholder.

Gallery authoring remains in the composer. An opaque upload-edit handle captures
pending gallery destinations before a source edit and retargets them afterward.
Removing or dissolving a gallery demotes its pending uploads to standalone
insertion. Stale picker results resolve a surviving gallery or use the existing
standalone fallback without recreating a removed gallery.

One lazy owner survives document resets, retaining unique upload IDs and settled
token registrations. Clear, plugin attachment restoration and disposal retire
pending requests and prepared resources. A preparation that finishes after
retirement releases its output without starting an upload. Embedded editors keep
forwarding uploads to their canonical parent document. Plugin targets retain
their existing insert-Markdown or retain-attachment policy.

The upload controller, preparation, inline upload, panel, attachment, submission
and media-editing tests pin these behaviors, including rendered controls,
selection, undo, stale pickers and retry order.

Each pending upload retains its prepared file, source anchor and batch identity
across retry. A separate private attempt owns its cancellation signal and active
callback lifetime. Retry retires the prior attempt and creates a new one;
settlement disowns further progress even while a failed row remains visible.
Preparation, progress and completion require the exact active attempt. Processing
publication may synchronously cancel the upload, so admission is checked again
before invoking the preparer. Late prepared output is still released.

This separates retained upload resources from a physical attempt without changing
public upload APIs or UI behavior. A captured abort completer alone would leave
settlement authority implicit; the attempt owns both facts. Upload preparation
and inline/submission/attachment tests pin cancellation, retry reuse, placeholder
settlement and stale progress isolation.

## Target modes

`composer/target.dart` owns the sealed `ComposerTarget` family. Importing
`composer/controller.dart` also exposes these internal types. The public plugin
SDK continues exposing only its existing controller, target request, kind and
policy contracts.

Construct a concrete target for the operation. `ComposerMode` is a derived read
value, never a constructor argument.

- `ReplyComposerTarget` requires existing topic identity and privacy. Its
  `replyingTo` operation changes reply selection while retaining the exact
  draft key, site, topic and source tab metadata.
- `PostEditComposerTarget` requires a post ID and post number.
  `TopicEditComposerTarget` requires the first-post ID and derives post number 1.
  Both belong to `PostEditingComposerTarget`, the type body-edit helpers accept.
- `CategoryEditComposerTarget` and `TagsEditComposerTarget` carry existing
  topic identity and taxonomy seeds. Their optional `firstPostId` is cached
  plugin context, not a post write destination. Mega-topic windows may omit it.
- `NewTopicComposerTarget` and `PrivateMessageComposerTarget` belong to
  `TopicCreationComposerTarget`. They carry origin metadata and an optional
  exact draft-key override. A private message requires a recipient string,
  which may be empty while recipients are being chosen. Only that target has
  `withRecipients`.
- `PluginComposerTarget` requires its registry-provided policy and retains the
  host's unmodifiable opaque request payload. Its namespaced kind and draft
  key come from that policy. It has no existing topic ID or slug.

`ExistingTopicComposerTarget` is the shared type for real existing-topic
identity. Body-edit, taxonomy, reply and creation helpers accept the family
that supplies their required write data. Common presentation and draft reads
have neutral projections for inapplicable fields; they do not grant a write
destination or an operation-specific copy method. Validation switches over the
concrete target family, including non-null plugin policy and PM recipients.

Server persistence identity remains `(siteUrl, draftKey)`. Local recovery
copies also belong to an account. `DiscourseInstance.draftOwner` retains the
original local draft owner through sign-out and restart. That owner keeps the
legacy storage address; other accounts use a separate persistence prefix.
Unknown legacy ownership never grants an account access to those drafts.
Each composer session captures its local storage address before asynchronous
work, while every account namespace shares the real site's storage queue.
Reconnect preserves local copies. Explicit disconnect clears them after its
signed-out snapshot is durable.

The existing `topic_<id>`, `new_topic`, `new_private_message`, allocated
creation keys, listed keys and plugin policy keys retain their exact spelling
on the server. Compatibility parsing remains in `ComposerDraft` and
`UserDraft`; targets do not re-encode stored drafts.

`tabId` records the initiating reader tab. Shell controller membership owns a
forum composer, and creation routing uses the separately captured submission
tab. Plugin surfaces retain their own composer lifetime. A new PM and a reply
or edit in an existing private topic both use private upload policy. Whisper
selection remains a separate reply constraint, and retargeting a non-reply is
ignored. Original edit text remains controller state and retains its exact
whitespace for conflict detection.

The concrete hierarchy keeps current callers direct. An envelope with nested
intent, draft identity and provenance wrappers was considered and rejected
because those wrappers add caller coordination without changing ownership.

## Submission transactions

`ShellController.submitComposer` and `recheckComposer` adapt results from the
private `_ComposerSubmissionOwner` in `shell/composer_submission.dart`. The owner
admits Send synchronously, runs preparers, drains active and retired draft saves,
executes account-bound requests, and decides accepted, refused, unresolved or
inactive outcomes. Check again only reads and settles the original attempt.

One immutable attempt captures the editor, concrete target, whisper selection,
account lease, author and active tab before asynchronous work. Create content,
metadata, durations and draft sequence are frozen after preparation and the two
draft barriers. Edits freeze outgoing content and exact conflict baselines at
admission. Accepted metadata advances its own baseline before body writing;
body refusal does not erase that success. Unknown edit failures retain the
existing retryable edit presentation.

The editor holds one private sealed submission value. Preparing carries an
attempt identity without sent facts. Sent, checking and unresolved values require
the original opaque `ComposerSubmission` and derive identity from it. The public
`ComposerState` and UI getters derive from this value. Only matching preparation
can retain a snapshot, so later retention cannot rewrite frozen facts. Checking
and unresolved transitions require that snapshot; calling them before retention
does nothing.

Refusal, positive absence, enqueue, document reset and disposal retire the whole
value. Editing or retargeting while unresolved does not rewrite the sent facts.
Unresolved text remains editable and drafted while Send stays blocked. Upload
and authoring admission retain their existing state policies.

Replies capture a fresh account-bound ordinary topic stream before dispatch,
without publishing the read. Confirmation retains that stream's maximum post ID
and requires one newer post with the frozen author, normalized raw and exact
public or whisper type. Positive confirmation also requires all newer candidates
to be examined. A missing pre-send boundary or ambiguous positive lookup leaves
the attempt unresolved. This is a conservative boundary, not a server receipt. A previously hidden post above the boundary or another client's identical
reply during the request cannot be distinguished without server request identity.

New topics are reconciled through their draft, the review queue and the
reader's created topics. A direct create advances the draft sequence, but
core's `NewPostManager#enqueue` leaves it alone, and so does a moderator's later
approval, which creates the topic from a queued payload that names no draft. A
draft still at the sent sequence therefore settles only a private message,
which core never queues. Before dispatching a new topic, the owner reads the
reader's pending posts (`/posts/:username/pending.json`) and retains the newest
reviewable ID. A lost answer settles as queued when a pending copy with the
frozen title and raw sits above that ID, and as created when the created-topic
lookup finds it. Only an untouched draft with neither reports that nothing was
posted; a moved draft stays unresolved. A failed queue read, or an identical
copy with no pre-send boundary, also leaves the attempt unresolved.

Account authority and editor authority are checked separately. Retiring an
editor prevents further writes and editor mutation, but an already accepted
write can still publish canonical data for the original current account.
`TopicDataSession` owns accepted posts, reconciliation reads and publication.
Submission keeps feature metadata and draft projections, and delegates draft
ordering and cleanup to `ComposerDraftCoordinator`. Typed retargeting preserves
the coordinator's site and draft identity.

The shell consumes completed results for retained-editor registration, route
metadata, topic navigation, message folders and origin-feed refresh. It checks
the captured lease after synchronous notifications before continuing. Topic
creation routes to the tab active at Send, with the existing active-tab fallback
when that tab no longer exists. Selecting a different composer never changes the
attempt's editor identity.

## Opening messages and continuations

`ComposerOpeningOwner` owns creation admission and draft setup for new topics,
private messages, and topic continuations. The shell captures navigation facts,
then builds, registers, and publishes the returned target. Its message and
continuation facades contain no recipient, draft-selection, or privacy policy.

Private-message preparation stays synchronous. It checks the reader's permission,
or a group's messageable permission when explicitly supplied, and requires a
non-topic route with a tab and feed. It normalizes recipients and selects any
retained editor owning the shared private-message draft before the shell performs
its usual replacement. Starting the editor restores that draft and focuses the
recipient-targeted message.

Continuation preparation captures a site lease, tab, and source topic. Public
continuations wait for taxonomy and composer capabilities; private continuations
keep the source's privacy and recipients. Preparation revalidates the current
source after metadata and replacement awaits, when the shell accepts the returned
plan, and before inserting text after editor publication. A source becoming private or
public, losing continuation permission, changing route/account, or losing the
reader's private-message permission abandons the attempt. Private recipients are
read from the current source after those awaits, exclude the author when others
remain, and include the source groups. Public continuations select the source's
creatable category and its minimum tag count.

Each continuation allocates a fresh draft key, starts a new draft, and inserts the
source link only while its account, route, and retained editor still belong to
the opening. It never restores the unrelated shared private-message draft.
`ComposerCreationPresentation` supplies retained-editor selection and current
source snapshots; taxonomy and drafts retain their existing authorities.

Extending the existing owner shares replacement admission and draft lifetime
policy. A separate continuation owner would need the same collaborators and
would split those rules again. Plans expose only the target, source ownership,
and required tag count needed to construct the editor. Direct owner tests and
`topic_reply_as_new_topic_test.dart`, `group_message_composer_test.dart`, and the
composer opening/draft integration tests pin these contracts.

## Saving and closing a retained editor

The retained-composer registry owns `saveAndClose`: admission, the closing state,
draft preservation, deciding whether an empty draft must be deleted, retiring
the editor, and restoring it when closure fails. Shell exposes that command as
`saveComposerAndClose`. The panel provides only a presentation callback that
waits for its closing dock to paint, then renders the typed outcome as a toast,
notice, or discard confirmation. It no longer coordinates separate hide,
prepare, close/delete, and restore operations.

The command checks exact registry membership after synchronous closing-state
publication and every await. Closing a previous account or editor cannot close
its successor. Failure restoration applies only to the original retained editor,
including when the presentation callback itself fails. A successful remote draft
save may remove the redundant local snapshot; preservation is established by the
draft coordinator's existing storage contract, not by retaining both copies.

`ComposerController.hasPendingOperation` is the shared admission fact for close,
opening replacement, and discard presentation. Submission, body loading, uploads,
discard and checking must settle first. Closing and discarding requests already
in progress remain silent; another pending operation can produce a user notice.
Draftless changed editors return a confirmation outcome without being hidden.
`prepareComposerForClose` remains available for callers that only need to ensure
a draft is safe while retaining its editor.

The registry already owns membership and draft detach/retire, so it can make the
save-or-delete decision without a second close owner forwarding those operations.
The draft coordinator still owns storage, draft conflict handling and persistence
ordering. Close safety, docking, navigation and draft integration tests cover the
transaction, including publication retirement and replacement during the paint
boundary.

## Tag eligibility

`TopicTagSearch` owns the shared eligibility policy used by category changes,
existing-topic metadata transactions and initial tag-route seeding. A selected
tag matches an explicit non-null ID or a case-insensitive name. A tag route can
also match the returned slug. Missing IDs never identify unrelated tags.
Forbidden searches and disabled matches are rejected; the first matching result
retains the server's ordering and cannot be bypassed for a later enabled result.

The two queries accept the caller's actual domain input (selected tag or route),
without a flag that silently changes identity semantics. The model handles only
matching and eligibility. Callers retain their distinct request lifetimes,
selection revision checks and error policies, including keeping selected tags
when validation fails to reach the server.

## Gallery picker admission

`ComposerMediaEditingCoordinator` captures the composer, its lifecycle
revision, and the picker operation before publishing the loading state. The
same ownership predicate gates opening the platform picker and consuming its
result. A listener that replaces the composer during loading publication
therefore cannot open an orphaned picker. Completion or cleanup of that
operation also cannot alter the replacement composer's picker state.

`composer_media_editing_coordinator_test.dart` covers both replacement during
publication and replacement while the picker future is pending.
