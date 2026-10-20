# List virtualization audit

The October 2026 notification scrolling fix exposed a wider pattern: some scrollable surfaces mounted every row, or placed a lazy list inside an unbounded outer scroller. This audit renders confirmed instances in bounded viewports or windowed rows while retaining Native row controls and actions.

## Coverage and measurement

The source inventory started at `b875a469b504f5cf80428e0c809c0146bf484b50` and covered 164 scroll-related matches in 86 shell and plugin files, plus their shared Native list owners. Matches include wrappers and declarations; they are not 164 independent viewports. The implementation started at `46a4d91cfede4b48f4862f4b6d7ba5047f441873` and was rebased onto current main before integration.

The table counts **initially mounted production rows**, including offstage elements (`skipOffstage: false`), after settling a controlled widget fixture. Normal and double text scales use the same data. Most fixtures, including the live draft strip, are 390 by 844 logical pixels; menu fixtures are 900 pixels tall, with desktop width 900. Select and Combobox use the default 800 by 600 widget viewport and a 320-pixel anchor, with the actual inherited MediaQuery preserved. Baseline tests were run before changing each production path. These counts establish reduced mounting and layout work, not physical iPhone frame times or scroll latency.

| Surface | Fixture rows | Baseline mounts | Candidate mounts, normal / double text |
| --- | ---: | ---: | --- |
| Saved destination bookmarks, full page | 200 | 200 / 200 | 14 / 3 |
| Desktop notification feeds, core and plugin | 200 | 200 / 200 | 15 / 5 |
| Phone plugin notification feeds | 200 | 200 / 200 | 12 / 4 |
| Category picker, phone | 220 | 220 / 220 | 18 / 11 |
| Editable topic tag picker, phone | 220 | 220 / 220 | 38 / 20 |
| Editable topic tag picker, desktop | 220 | 220 / 220 | 25 / 13 |
| Read-only topic tag picker, phone | 220 | 220 / 220 | 15 / 13 |
| Read-only topic tag picker, desktop | 220 | 220 / 220 | 14 / 7 |
| Composer image carousel | 200 | 200 / 200 | 7 / 7 |
| Pinned chat messages | 20 | 20 / 20 | 13 / 5 |
| Calendar day entries | 200 | 200 / 200 | 8 / 4 |
| Voice membership dialog | 200 | 200 / 200 | 11 / 5 |
| Voice invite suggestions, phone | 200 | 200 / 200 | 9 / 2 |
| Voice invite suggestions, desktop | 200 | 200 / 200 | 8 / 1 |
| Native Select options | 200 | 200 / 200 | 15 / 9 |
| Native Combobox options | 200 | 200 / 200 | 16 / 10 |
| Flat Native dropdown actions, phone and desktop themes | 200 | 200 / 200 | 16 / 6 |
| Actual composer saved-draft menu | 202 | 202 / 202 | 20 / 8 |
| Live composer draft tabs, both text directions | 200 | 200 / 200 | 5 / 5 |
| Assignment results, drawer and dialog | 200 | 200 / 200 | 8 / 4 |

Core phone notifications were already lazy in the preceding fix; the current menu regression mounts 12 / 4 in its taller fixture. Production notification feeds normally request 30 rows, with a configurable maximum of 60. The 200-row fake host stresses the public feed contract. Pin measurements use the real parser cap of 20.

## Behavior retained

Notification panels own one viewport. Core feeds use their existing sliver constructors on desktop too. `PluginUserMenuSection.sliverBuilder` is an optional explicit opt-in; the required arbitrary box builder keeps its existing contract. Chat and Assign opt in, and registry ownership wraps both callbacks. Loading, errors, empty states, dismissal and footer actions have coverage in both layouts.

Saved destinations share one lazy sliver before the existing server bookmark sliver. Category and tag pickers retain search, authorization and selection behavior. The gallery change applies to the horizontal carousel; its complete grid editor keeps its document layout. Final images remain editable and draggable. Bounded pin, calendar and Voice viewports retain their final-row actions and fixed form controls.

Native Select keeps short menus on their existing natural layout. Long menus use exact row extents and preserve group semantics, selected-item reveal, keyboard navigation, typeahead and logical focus after option reorder. Long bounded Combobox lists retain variable-height custom rows, group semantics, accepted controlled highlights, initial selection reveal and custom equality. Filtering and option replacement cancel pending reveals. Pointer highlights retain scroll positions. Unbounded inline content keeps its existing eager fallback.

Flat dropdown navigation uses complete row metadata rather than mounted registrations. New pointer-down claims cancel pending keyboard reveals, keyed updates retire stale work, and focused or expanded rows stay alive. Retained submenu triggers keep valid layout transforms during exit animations and parent scrolling. The actual composer draft menu uses this path without a caller migration.

Assignment results use one bounded Native scrollbar/list viewport. Optional radio collection navigation preserves arrow order, accepted-choice Tab/Shift+Tab entry, one-step group exit, controlled rejection and Form reset. Query, ownership, focus and data changes retire pending reveals. A prototype that merely made rows lazy was rejected because arrows wrapped among mounted clients; the complete collection contract is required.

The live draft strip keeps its existing scroll container and natural Native tab height. Only nearby tabs, the two entry edges and focused actions mount; width spacers preserve the original 170-pixel tabs and 6-pixel gaps. Native document tabs accept optional borrowed focus nodes. The host owns their lifetime and the complete traversal order, while Native retains action handling. Offscreen selection, close actions, viewport resize, RTL traversal, rapid Tab/Shift+Tab and newer outside-focus claims have dedicated regressions. Retained composer checks exercise standard and glass material, semantics, docking, minimize/restore and the same editor State.

## Unchanged and constrained paths

- Topic and post feeds, server bookmarks, activity and drafts pages, directories, chat feeds, GIF and emoji results, and Voice participant grids already use lazy delegates. `DCommandList` already switches to lazy rendering above 64 results.
- `ListView(children: ...)` builds descriptors eagerly but mounts and lays out children lazily. Source syntax alone was not treated as proof of the notification mounting problem.
- Existing bounds include server bookmark menus (20), post likers (25), built-in reaction user payloads (50), profile summary collections (6), new-tab destinations (5), recently closed destinations (8 or 16), site suggestions (10), and forum tabs (20). A cap establishes a growth bound; it does not establish fast rendering.
- Standalone box constructors and the currently unreachable invite menu retain their supported layout contracts. No current phone benefit is claimed for dormant routes.
- Rich post documents, intrinsic-width code blocks, Native tables, expanded deleted-message content, gallery grids, selected chips and image indicators need their own selection, document or control design. They were not converted by a blanket replacement.
- Flat Native dropdowns become lazy above 64 immediate children when they have an explicit width and bounded height. Headers, separators, actions, checkboxes and submenu triggers are supported. Structural groups, radio groups, arbitrary wrappers, intrinsic width, unbounded direct layouts and `scrollable:false` retain eager compatibility behavior.
- Native radio groups retain their default arbitrary-child behavior. Lazy callers opt into complete ordered choice metadata and a guarded reveal callback. The assignment picker uses this path; other radio compositions are unchanged.

The complete baseline source inventory and dispositions are recorded in [list-virtualization-coverage.json](data/list-virtualization-coverage.json).

## Reproduction

The committed regressions count mounts and exercise far-row actions. Run the relevant files explicitly, for example:

```sh
flutter test --no-pub test/menu_list_virtualization_test.dart test/ui/option_list_virtualization_test.dart
flutter test --no-pub test/destination_bookmarks_ui_test.dart test/composer_image_gallery_test.dart
flutter test --no-pub test/ui/dropdown_list_virtualization_test.dart test/draft_list_test.dart
flutter test --no-pub test/d_radio_group_navigation_test.dart test/assignment_list_virtualization_test.dart
flutter test --no-pub test/global_search_panel_test.dart test/topic_tag_picker_test.dart test/topic_header_tags_test.dart
flutter test --no-pub test/composer_draft_tabs_virtualization_test.dart test/composer_mockup_parity_test.dart test/d_document_tab_focus_test.dart
flutter test --no-pub test/src/plugins/discourse_events/topic_calendar_test.dart
flutter test --no-pub test/voice_room_view_test.dart --name 'membership management|invites|mobile Voice inset forms|room dialog account ownership'
flutter test --no-pub -d <iphone-simulator-id> integration_test/list_virtualization_test.dart
```

The iPhone runner also supports focused replays with `--name 'Native dropdown lists'` or `--name 'Live draft tabs'`. The dropdown fixture preserves physical pixel ratio and places triggers inside the safe area; an open-popup assertion and a positive mount count prevent a dismissed menu from passing the measurement.

Validation is scoped to the owning app and Native component suites, the changed pin/Voice behaviors, targeted analysis, and the iPhone integration helpers. Retained composer tests cover standard and glass material with semantics enabled. These checks establish rendering bounds and the exercised interactions. Physical-device frame timing remains unmeasured.
