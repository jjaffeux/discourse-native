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

`ComposerComponent<T>` and the `composer/document`, `composer/hybrid`, and
`composer/surface` modules remain the separate typed-component editor work.
They are not connected to the live field by this refactor. A new live component
uses the syntax policy path above rather than adding a second registry.

## Design choice and verification

Standalone builders keep the feature-specific types precise. A universal
component interface would need to treat inline emoji, editable task rows, and
interactive plugin blocks alike. The existing editor already owns their shared
invariants, so another interface would duplicate that ownership.

The existing rendered-editor tests pin source length, caret geometry, composition,
span cache identity, artwork retries, atomic deletion, gallery identity, and
undo. Plugin tests pin permissions and stale picker behavior. The composer plugin
boundary test also prevents built-in modules from importing bundled features.
