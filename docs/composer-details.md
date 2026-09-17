# Details in posts and the composer

Cooked `<details>` elements use the existing Native `DAccordion`. The first
direct `<summary>` supplies the title, with “Details” as the empty-title
fallback. The HTML `open` attribute sets the initial state. Nested bodies retain
post typography, site identity, plugin registry, link styling and post context.

The post composer offers **Insert → Details**. It wraps selected content, or
inserts an empty block, and focuses its summary. Details are inline document
content: one disclosure arrow, a borderless Native summary input and the normal
composer content beneath it. There is no separate formatting/upload toolbar,
body label, form border or inner scrolling area.

The body uses the same `ComposerEditor`, typography, selection tools,
autocomplete actions, clipboard and file pickers as its enclosing composer.
The main formatting, link, media, emoji and insertion controls follow the
deepest focused body, including nested details. Images, videos, galleries,
links and plugin content use their existing composer implementations and
canonical Markdown. Text scaling is applied once across nested content.

Enter in the summary moves into the body. Unmodified arrow keys at content
boundaries move between summary, body and surrounding prose; Escape exits the
block. Leaving a block at a document edge creates a text line when necessary.
Native caret-reveal requests from summary and body scroll the enclosing
composer, so long content remains editable without a nested scrollbar.
Right-clicking or long-pressing the disclosure arrow offers removal of the
wrapper while keeping its content, or deletion of the entire block. Ordinary
composer selection/deletion also remains available.

Details start expanded while authoring. Their disclosure state does not change
the post's authored `open` attribute. Collapsing retains edits and media.

Edits synchronously update canonical Markdown, drafts and submission. Summary
changes retain other attributes; body changes retain the opening and closing
tags and line-ending convention. Surrounding prose is preserved. The embedded
editors own selection, clipboard, undo and formatting shortcuts. Submission
disables them, and stale callbacks cannot change a submitting composer.

The enclosing draft owns all upload requests and placeholders. Picked, pasted
and dropped files are inserted at the selection inside the details body;
pending uploads prevent submission and are stripped from persisted drafts.
Collapsing a disclosure retains its uploads, while removing it cancels them.
Only the outer editor registers native drops, routing each to the deepest
body under the pointer. Embedded image hit testing accounts for outer scroll.

Recognition covers bare, quoted, smart-quoted and legacy unquoted summaries,
single-line blocks and multiline nested blocks. Code examples, escaped tags,
and incomplete markup remain ordinary source. If a body edit makes nested
markup incomplete, the change is retained in the draft and the block returns
to the outer source editor for correction. Main-field IME composition defers
projection. Plugin-specific composers retain their existing syntax policies.

The grammar follows Discourse's [details plugin][details] and [BBCode block
parser][bbcode]. No UI-kit API changes or dependencies are required.

[details]: https://github.com/discourse/discourse/blob/main/plugins/discourse-details/assets/javascripts/lib/discourse-markdown/details.js
[bbcode]: https://github.com/discourse/discourse/blob/main/frontend/discourse-markdown-it/src/features/bbcode-block.js

## Verification — 2026-09-17

- `flutter analyze --no-pub`: clean.
- 221 focused tests pass across details, source parsing, composer commands,
  drafts, inline uploads, upload submission, tables, cooked details and Native
  control adoption. New coverage includes selection wrapping, insertion focus,
  keyboard boundaries, shared link/image/video actions, nested toolbar routing,
  long-content caret scrolling, summary visibility and matching text scaling.
- The macOS debug fixture build passes. An isolated, ad-hoc-signed build of the
  production composer was inspected in light/wide, dark/narrow and RTL layouts.
  Native checks cover summary editing, entering the body, shared formatting and
  link insertion, collapse/expand, scrolling, and unwrapping while preserving
  content. A final-build check typed 40 paragraphs into details and verified that
  the outer viewport kept the last paragraph and caret visible. Upload lifecycle
  and video insertion use in-memory widget-test
  uploaders; no real forum upload or account write was performed. Mobile checks
  are widget tests, not device verification.

The in-memory fixture can be launched without a forum account:

```sh
flutter run -d macos -t tool/details_review_main.dart
```

It includes post/composer, light/dark, wide/narrow and RTL controls, plus access
to the component styleguide.
