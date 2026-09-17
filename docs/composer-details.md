# Details in posts and the composer

Cooked `<details>` elements use the existing Native `DAccordion`. The first
direct `<summary>` supplies the title, with “Details” as the empty-title
fallback. The HTML `open` attribute sets the initial state. Nested bodies retain
post typography, site identity, plugin registry, link styling and post context.

The post composer offers **Insert → Details**. Complete `[details]` blocks
become expandable embedded editors with Native summary and multiline body
fields, plus a remove action. The editor starts expanded for authoring. Its
disclosure state does not change the post's authored `open` attribute.
The body field accepts Markdown, including nested details source.

Edits synchronously update canonical Markdown, drafts and submission. Summary
changes retain other attributes; body changes retain the opening and closing
tags and line-ending convention. Surrounding prose is preserved. The embedded
fields own selection, clipboard, undo and formatting shortcuts. Submission
disables them, and stale callbacks cannot change a submitting composer.

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

## Verification

Focused tests cover source preservation, nesting, code examples, malformed
markup, insertion through the real toolbar, local undo and formatting,
submission locking, external history updates, disclosure activation, rich
post bodies, inherited typography, and narrow/dark layouts. Existing composer,
quote, table, cooked HTML and Native-control adoption tests are also included.

Static analysis and the macOS debug fixture build pass. A Flutter widget-test
render of the production post/composer widgets was inspected at 1000×800 in
light and dark themes, with Arial loaded for readable text (the inline code
font retained the test fallback). Live macOS interaction was unavailable
because another task held the shared desktop lease; widget tests are not
device verification.

The in-memory fixture can be launched without a forum account:

```sh
flutter run -d macos -t tool/details_review_main.dart
```

It includes post/composer, light/dark, wide/narrow and RTL controls, plus access
to the component styleguide.
