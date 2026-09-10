# Quiet dock implementation and review

Reviewed on 2026-09-10 against local main
`c1bacb3e06c84fac8bb7720314055b13c78c4a83` with Flutter 3.47.2.

## Implemented behavior

The production composer adopts the approved Quiet dock composition for new
topics, replies, whispers and post edits. The [component inventory](components.md)
and [HTML study](index.html) describe the design and its supported features.

- New topics use a labeled Native `DInput` for the title and the existing
  category/tag pickers.
- Reply context uses a muted `DItem` with the author, post number, topic title
  and existing cached excerpt disclosure. Post edits use a passive muted item
  with a small **Topic** label above the emphasized title.
- The Reply/Whisper dropdown uses `DDropdownMenuRadioGroup<bool>` and radio
  items with explicit accessible labels and typeahead text. Permission checks,
  mandatory whisper targets and submission guards remain in their existing
  owners. The audience description appears only inside the menu.
- `DButtonGroup` exposes the existing bold, italic, inline-code and link
  commands above the live editor. The topic composer suppresses its redundant
  selection toolbar; direct `ComposerEditor` consumers, including chat, retain
  that toolbar by default. Quote selection normalization still runs.
- Upload, emoji and eligible plugin insert actions remain in the footer, using
  Native buttons and a Native dropdown. Plugin-owned header/footer slots and
  existing poll/date editors remain intact.
- Draft feedback uses existing draft status for draft-capable topics/replies.
  Post edits retain their current Cancel / Discard changes confirmation and do
  not acquire saved edit drafts.

No generic UI kit component or API was added or extended. The existing live
editor, source/projection model, uploads, undo, plugin dispatch, draft store,
submission admission and docking controllers retain ownership of behavior.
The approved study's other designs, preview switch, audience banner and
unsupported authoring features are absent.

Default dock placement and outer sizes are unchanged. The scrollable body has
enough minimum height for the context, formatting row and rich content. Short
bottom docks scroll that content while retaining the footer and editor state.
Rich-content test fixtures use a representative side-dock height; a separate
280px-bottom-dock test checks toolbar access and editor retention through scroll.

## Verification

Root `dart analyze` and `profiles/full` `dart analyze` both completed with no
issues. Touched Dart files are formatted, `git diff --check` passes, and
`node --check docs/composer-mockups/mockups.js` passes.

The focused run completed with **277 passing tests and two pre-existing
failures** across these files:

```text
test/composer_panel_controls_test.dart
test/composer_picker_modal_test.dart
test/composer_upload_panel_test.dart
test/poll_composer_panel_test.dart
test/composer_quote_panel_test.dart
test/discourse_ai_proofreading_test.dart
test/composer_authoring_submission_test.dart
test/composer_selection_toolbar_accessibility_test.dart
test/composer_docking_test.dart
test/composer_viewport_overlay_test.dart
test/composer_drafts_integration_test.dart
test/composer_upload_submission_test.dart
test/emoji_composer_panel_test.dart
test/composer_close_safety_test.dart
test/composer_draft_failure_test.dart
test/composer_toolbar_test.dart
```

Run them together with `flutter test --no-pub` and `--reporter expanded`.
Coverage includes selection-preserving formatting, keyboard commands, quote
normalization, loading/submission guards, image/gallery lifecycle, modal
pickers, plugin insertion, draft restoration, whisper submission, docking,
short-dock scrolling, 360px layouts and edit context at 1x/2x/3x text scale.
The header typeahead-and-Enter case runs with the macOS platform variant.

The same two failures reproduced in a clean detached checkout of the baseline:

| Test | Existing failure |
| --- | --- |
| `composer_toolbar_test.dart`: editing a projected Wikipedia link replaces its full source | The test casts the link dialog's already-migrated `DInput` to `TextField`. |
| `poll_composer_panel_test.dart`: an open date dialog cannot apply during submission | Its `enterText` finder no longer locates an `EditableText` in the existing date picker. |

They are recorded rather than reported as passing. Native link behavior is
covered by the existing focused tests; the native date editor was opened and
applied successfully in this review.

## Native review

[The local review entry point](../../tool/quiet_dock_review_main.dart) mounts
the real `AdaptiveShell` with in-memory account/post/draft fixtures, the bundled
plugin registry and a separate preferences prefix. It was built with:

```sh
flutter build macos --debug --no-pub --target tool/quiet_dock_review_main.dart
```

For this review only, the build used product name `QuietDockReview`, bundle ID
`org.discourse.native.review.quietdock`, disabled automatic signing, and the
existing permitted debug entitlements in `tool/button_group_review.entitlements`.
The original Xcode configuration was restored immediately after building. The
isolated bundle passed strict signature verification and actually launched as
`/tmp/QuietDockComposerFinal.app`; production provisioning was not changed.

Using the approved native UI surface, the review inspected:

- New topic, reply, whisper, mandatory-whisper reply and post-edit states in
  light and dark palettes, using side and bottom layouts.
- The muted reply card, cached excerpt expansion, passive edit topic label,
  header dropdown, foreground whisper icon and supported footer actions.
- Native keyboard Reply/Whisper selection, selected-text formatting, and
  pointer/keyboard opening of Insert, including a fresh empty composer.
- Creating and applying a two-option poll and applying a local date; both
  appeared as live editor atoms through their existing plugin editors.
- Switching left/bottom/right, minimizing/restoring an edited post, and
  cancelling the existing dirty-edit discard confirmation with text retained.
- The running Native styleguide's Item and muted Item examples.

The independent source review found no remaining blockers after correcting
large-text reply-row geometry, dropdown typeahead labels and the redundant
selection popup's interference with the new toolbar.

This was macOS desktop verification with local fixtures. No iOS/Android device
run, real server submission or OS image-picker upload was performed; those
paths retain the focused widget coverage described above.

The final inspected source and copied bundle are identified by SHA-256:

```text
composer_header.dart       e4030f127f1c71374a920fa291279b73f5e7aa40779ad8f55c80fa19b34345d6
composer_panel.dart        e68b146fb5062617f29ed1fb712d1041dbf6a44fdff9c1ddd6afa4538c38b3ac
composer_reply_context.dart 8aadbef5db8c647a15d1b0cc595b650035e58a3055465e02d5f56bc3fd6cd337
quiet_dock_review_main.dart 275641816d8ec35435058c8d80da776668ddbdef28e253e04930483238349ca8
kernel_blob.bin            453c50482d32eec0f8c2c2d0f559c24bcce0c485ed27fd942274328b0bfbdaf1
```
