# Placeholder plugin

`discourse-placeholder` is a bundled, reader-side native plugin. It activates
on placeholder declarations in topic posts, with no feature-specific HTTP
requests, site setting, or theme installation lookup.

Compatibility baseline: [upstream initializer at
08be8263cbfc6197b19e76999a31423c16f14a06](https://github.com/discourse/discourse-placeholder-theme-component/blob/08be8263cbfc6197b19e76999a31423c16f14a06/javascripts/discourse/initializers/setup.js).
The cooked div/span forms were also verified against the
[Placeholder Forms topic](https://meta.discourse.org/t/placeholder-forms/113533).
The baseline and representative inputs are recorded in
`test/plugins/discourse_placeholder/fixtures/upstream.json`.

## Supported behavior

- `.d-wrap[data-wrap=placeholder]` divs and spans with a nonempty `data-key`.
- `data-default`, comma-separated `data-defaults`, `data-description`, and
  `data-delimiter` (default `=`), plus rich descriptions inside the wrapper.
- Native Input or single-choice Select, composed with stacked Field. Labels
  sit above controls in a container that fills the post's available width. Each
  field has a subtle forum-accent tint and a 4 px leading accent rail, mirrored
  in RTL. Rich descriptions below controls inherit FieldDescription's muted
  helper-text typography. The field label is the declared key, with no added
  icon or caption.
- Substitution in headings, paragraphs, code, blockquotes, list descendants,
  `.md-table` descendants, and anchor hrefs. Other attributes remain unchanged.
- Clearing an input restores its declared substitution default. Empty and
  `none` values leave tokens unresolved. Definitions follow source order, with
  the last definition of a repeated key winning; repeated controls share values.
- Replacements always start from the original DOM. Values are literal text,
  including dollar signs and HTML-like strings. Link activation continues
  through the host's existing URL handling.

The reader's projection is applied before code highlighting and copy actions.
Quoted text uses the displayed HTML; selection editing opens the canonical
template when it differs from the projection. The post record is never changed.
Nested quote renderers share the containing post's field scope. Standalone
previews, revision history, chat, and composer authoring do not activate it.

## State and persistence

The module requires only the core user-id reader port. Its session owns
account-bound value leases; widgets own controllers, focus nodes, and the
150 ms rendering debounce. A late read cannot overwrite a touched key, and
detached or replaced-account leases cannot accept writes.

Values are saved in the application-support directory under
`plugins/discourse-placeholder/values-v1.json`, using PrivateFileDocument's
atomic, serialized, owner-only storage. Identity includes site URL, nullable
viewer id (anonymous is separate), topic id, post id, and placeholder key.
Expiry is seven actual days from reading or writing a value. Expired records
are pruned on access; reset removes the override; forgetting a site removes
all its records. Failed storage leaves the current interaction usable.

Native deliberately avoids the web initializer's seconds/milliseconds expiry
mismatch. A select without a declared or saved value displays a prompt until
chosen, rather than visually implying a value that has not been substituted.

## Verification

Run `flutter test test/plugins/discourse_placeholder
test/post_body_transform_plugin_test.dart test/post_text_selection_test.dart`
along with cooked-renderer and plugin manifest/boundary suites.
`PLACEHOLDER_RENDER_DIR=/absolute/path` enables light and dark/RTL/large-text
image exports from the responsive widget test for visual inspection.

`tool/placeholder_review_main.dart` provides a native review fixture using the
production plugin and a temporary private store. Its controls exercise light
and dark palettes, a 320 px column, 200% text, RTL, and post remounting. The
macOS review verified typing, select changes, live prose/code/link updates,
remount restoration, and the narrow/large-text/RTL layouts in both palettes.
The accent-rail review used the long `HOSTED_SITE_NAME` label from the reported
form, with rich helper text beneath its input and a separate select field.
It verified both palettes at 320 px with 200% text and RTL, typing with focus
retained, select changes, live substitutions, and values surviving remounting.
The 69 focused placeholder, selection, and control-adoption tests passed;
`flutter analyze --no-pub` reported no issues.

The full-width adjustment passed all seven placeholder widget tests and static
analysis. Native macOS review confirmed 720 px containers in both palettes and
320 px containers with 200% text and RTL in dark mode.
