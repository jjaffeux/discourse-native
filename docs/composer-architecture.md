# Composer ownership

The live editor keeps Markdown as its canonical document. Feature modules own
their syntax and artwork. The editor owns source offsets, selection, IME
composition, history, overlap resolution, and span caching.

## Core features

`lib/src/shell/composer/components/` contains the built-in feature modules.
`emoji.dart`, `image.dart`, `gallery.dart`, `todo.dart`, `quote.dart`,
`blockquote.dart`, `mention.dart`, and `hashtag.dart` construct their own
presentation. `link.dart`, `code.dart`, `details.dart`, `list.dart`, `table.dart`,
`video.dart`, and `upload.dart` own their existing syntax policies and editor behavior.
Image and gallery toolbars and menus also live with their features. The mobile
image toolbar receives the shared history controls from the panel.
Lossless parsers live beside their feature in `*_source.dart` files when they
need a separate module.

`core.dart` constructs built-in policies once per composer. Plugin targets retain
their existing reduced set of core features. Link policy configuration stays
in the Markdown editor because its linkify settings can change during editing.

`MarkdownEditingController` coordinates these features. It keeps retained keys
and document-dependent state, then calls feature builders with explicit values
and callbacks. Emoji owns its pending artwork loads per editor and suppresses
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

The existing rendered-editor tests pin source length, caret geometry, composition,
span cache identity, artwork retries, atomic deletion, gallery identity, and
undo. Plugin tests pin permissions and stale picker behavior. The composer plugin
boundary test also prevents built-in modules from importing bundled features.

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

Persistence identity remains `(siteUrl, draftKey)`, scoped to the current
account session by the draft coordinator. The existing `topic_<id>`,
`new_topic`, `new_private_message`, allocated creation keys, listed keys and
plugin policy keys retain their exact spelling. Compatibility parsing remains
in `ComposerDraft` and `UserDraft`; targets do not re-encode stored drafts.

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
