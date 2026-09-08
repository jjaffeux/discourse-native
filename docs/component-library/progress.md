# Component library progress

Generated from [progress.json](progress.json). Read the [brief](brief.md), [conventions](conventions.md), [catalogue](catalogue.json) and [inventory](inventory.md).

Coordinator task: `01a0816f-d4e0-7f93-9d6b-baeaf6961181`. Reference: 2026-09-08.

Foundation: **merged** on `codex/component-library-foundation`. Merge: 1b130d3323f9b7619bdead025fd76a57be402a97.

## Component implementation

| # | Component | Status | Task | Branch | Dependencies | Merge |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | direction | merged | 01a0818b-e20a-77d0-bb99-77691899dad7 | codex/ui-direction | — | e69458861e83f3989e2f06dd177805c572740a5a |
| 2 | typography | merged | 01a081e5-0bef-70a1-9ae3-7717028403e0 | codex/ui-typography | direction | 20f42345002e9b0946d1690acd6de6f83b7aa681 |
| 3 | spinner | in_progress | 01a08213-9960-79f1-8d90-9626f24a4b5a | codex/ui-spinner | — | — |
| 4 | kbd | review_ready | 01a0821b-27cc-7013-affb-99cae203b2a8 | codex/ui-kbd | typography | — |
| 5 | tooltip | planned | — | — | kbd | — |
| 6 | button | planned | — | — | spinner, tooltip | — |
| 7 | separator | in_progress | 01a08213-a2e5-7692-a127-f09d2a03094b | codex/ui-separator | — | — |
| 8 | label | planned | — | — | typography | — |
| 9 | badge | planned | — | — | spinner | — |
| 10 | input | planned | — | — | label | — |
| 11 | textarea | planned | — | — | label | — |
| 12 | checkbox | planned | — | — | label | — |
| 13 | radio-group | planned | — | — | label | — |
| 14 | switch | planned | — | — | label | — |
| 15 | toggle | planned | — | — | button | — |
| 16 | toggle-group | planned | — | — | toggle | — |
| 17 | slider | planned | — | — | label | — |
| 18 | progress | planned | — | — | label | — |
| 19 | skeleton | in_progress | 01a08213-b4ca-77e1-a2aa-8a490808243e | codex/ui-skeleton | — | — |
| 20 | aspect-ratio | planned | — | — | — | — |
| 21 | avatar | planned | — | — | — | — |
| 22 | card | planned | — | — | typography | — |
| 23 | empty | planned | — | — | typography | — |
| 24 | item | planned | — | — | separator | — |
| 25 | table | planned | — | — | typography | — |
| 26 | scroll-area | planned | — | — | separator | — |
| 27 | collapsible | planned | — | — | — | — |
| 28 | accordion | planned | — | — | collapsible | — |
| 29 | tabs | planned | — | — | button | — |
| 30 | resizable | planned | — | — | — | — |
| 31 | popover | planned | — | — | button | — |
| 32 | hover-card | planned | — | — | popover, avatar | — |
| 33 | dialog | planned | — | — | button | — |
| 34 | alert-dialog | planned | — | — | dialog | — |
| 35 | sheet | planned | — | — | dialog | — |
| 36 | drawer | planned | — | — | dialog | — |
| 37 | select | planned | — | — | popover, scroll-area | — |
| 38 | native-select | planned | — | — | label | — |
| 39 | field | planned | — | — | label, separator | — |
| 40 | input-group | planned | — | — | input, textarea, button, kbd, spinner | — |
| 41 | button-group | planned | — | — | button, separator | — |
| 42 | command | planned | — | — | input, dialog, scroll-area | — |
| 43 | combobox | planned | — | — | input, popover, command | — |
| 44 | dropdown-menu | planned | — | — | popover, checkbox, radio-group | — |
| 45 | context-menu | planned | — | — | dropdown-menu | — |
| 46 | menubar | planned | — | — | dropdown-menu | — |
| 47 | navigation-menu | planned | — | — | popover | — |
| 48 | breadcrumb | planned | — | — | button, dropdown-menu | — |
| 49 | pagination | planned | — | — | button, select | — |
| 50 | calendar | planned | — | — | button, select | — |
| 51 | date-picker | planned | — | — | calendar, popover, input | — |
| 52 | carousel | planned | — | — | button | — |
| 53 | toast | planned | — | — | button | — |
| 54 | alert | planned | — | — | typography | — |
| 55 | attachment | planned | — | — | dialog, spinner | — |
| 56 | marker | planned | — | — | spinner | — |
| 57 | bubble | planned | — | — | button, collapsible, popover, tooltip | — |
| 58 | message | planned | — | — | attachment, avatar, bubble, marker | — |
| 59 | message-scroller | planned | — | — | message, scroll-area | — |
| 60 | chart | planned | — | — | tooltip | — |
| 61 | data-table | planned | — | — | table, pagination, checkbox, input, dropdown-menu | — |
| 62 | sidebar | planned | — | — | sheet, tooltip, collapsible, input | — |
| 63 | input-otp | planned | — | — | input, field | — |
| 64 | questionnaire | planned | — | — | field, button, progress, card, dialog, native-select | — |

## Decisions and evidence

### Foundation

Status: merged. Task: 01a0816f-d4e0-7f93-9d6b-baeaf6961181. Branch: codex/component-library-foundation.

**acceptanceCriteria**

- Freeze every current All Components catalogue entry with reference URLs, documented sections/variants, dependency facts and hashes.
- Provide searchable catalogue and runnable baseline examples with usage, theme, viewport, text-scale, direction, motion and reset controls.
- Expose the styleguide from the bottom-left app rail, including before site load; preserve the mounted workspace on return.
- Verify the theme mapping, interaction and access behavior before the foundation merge.

**decisions**

- Keep D-prefixed public widgets in discourse_ui.dart; host maps palette into DTokens.
- Existing Button, Tooltip and Select are baseline examples until their sequential tasks replace them.
- Use native Flutter styleguide route and independent preview Navigator; no networking or credentials in examples.

**migrations**

- Bottom-left InstanceRail footer opens the styleguide; root workspace remains mounted.

**verification**

- Flutter 3.47.2 / Dart 3.13.2; flutter pub get --enforce-lockfile passed without lockfile changes.
- dart format --output=none --set-exit-if-changed on all foundation Dart files passed.
- flutter analyze --no-pub passed with no diagnostics.
- flutter test test/styleguide test/app_theme_test.dart test/app_settings_page_test.dart test/site_theme_app_test.dart --test-randomize-ordering-seed=random: 50 tests passed, seed 905880268.
- Tests cover catalogue/order accounting, search by documented capability, no-match state, local example state across theme/width changes, reset, 200% text at 320px and 1200px, Escape, bottom-left semantic label and hit target, entry before loading/with no sites, retained draft on return, default/custom tokens, reduced motion and live overlay theme.
- Built and ran macOS standalone styleguide. Fixed native launch-screen dismissal and Material selection/ink ownership discovered during runtime inspection.
- Inspected macOS dark/current and light previews, keyboard selection of Forest site palette, 360px viewport and 200% preview text; exercised example action and visible focus. Used isolated temporary app identity org.discourse.native.styleguide to avoid competing with normal Discourse navigation.
- Observed the styleguide palette button in the actual app rail; route entry/exit and retained workspace were verified through the real InstanceRail in widget tests.
- git diff --check passed.

**limitations**

- iOS and Linux devices were not run during the foundation phase. No new native platform dependency was introduced.
- Baseline Button, Tooltip and Select are explicitly unfinished catalogue implementations; their full reference behavior and migrations belong to their upcoming tasks.

### direction

Status: merged. Task: 01a0818b-e20a-77d0-bb99-77691899dad7. Branch: codex/ui-direction.

**acceptanceCriteria**

- Expose DDirection through discourse_ui.dart with explicit LTR/RTL, inherited direction, nearest-scope lookup and optional lookup, all using Flutter Directionality as the only provider.
- Update dependent layout and lookup consumers on live direction changes; preserve child state, text editing, focus, native reading-order keyboard traversal and directional semantics across nested overrides.
- Keep host light/dark/custom themes, text scaling and reduced-motion preferences intact; demonstrate directional layout and fixed LTR content boundaries without introducing rendering or focus ownership.
- Provide runnable public-API styleguide examples and usage covering installation, explicit direction, inherited lookup (useDirection adaptation), nested overrides, live changes, editable content and a live overlay.
- Audit core and all bundled plugins/packages for direction usages, migrate appropriate UI providers/lookups, and record retained native/markup alternatives and removed obsolete ownership.
- Pass touched-code formatting, static analysis and focused component/styleguide/downstream tests; inspect isolated macOS examples in representative themes and widths; record device limitations before review_ready.

**decisions**

- D-prefixed DDirection wraps Flutter Directionality; TextDirection is the public value type. A null textDirection inherits the nearest Flutter/provider scope. DDirection.of and maybeOf are idiomatic equivalents of useDirection; of requires a direction ancestor and maybeOf returns null when absent.
- Keep an identical Directionality child structure when explicit/inherited direction changes so state and borrowed resources remain mounted. Direction has no colors, animation, input state, overlay, controller or focus node of its own.
- The frozen link/outline button variants and email/password/submit types belong to the reference demonstration, not Direction properties; demonstrate real native input/action composition without implementing those separate catalogue components.
- Installation is the existing public Dart barrel import; no package, Flutter-pin or lockfile change. Direction owns no hover/pressed/disabled/loading/error state, focus traversal, theme, animation or overlay lifecycle; composed native controls own those behaviors.
- Three real examples cover live inherited/explicit direction with retained local editing, nested RTL/LTR URL boundaries and nearest lookup, and a MenuAnchor whose overlay observes the native scope. Native buttons/menu items remain sample composition, not completed catalogue Button/Menu components.
- All acceptance criteria pass for implementation, focused widget/regression checks and the native scenarios recorded below; iOS/Linux devices and live authenticated app screens remain explicitly unverified.

**migrations**

- styleguide_page.dart: replace the preview Navigator Directionality provider with DDirection; the existing Right to left control updates all mounted examples.
- Core: migrate 9 direction lookups in main_content.dart, resizable_pane.dart, users_page.dart, composer_panel.dart, topic_list_navigation.dart, topic_header_tags.dart and forum_tabs_bar.dart to DDirection.of through discourse_ui.dart, preserving reading-lane physical alignment, resize signs, toolbar arrows and text measurement.
- Chat plugin: migrate 3 chat_drawer.dart lookups for composer overlap geometry, resize delta and resize cursor to DDirection.of without changing plugin state, permissions or callbacks.
- Audited lib, every lib/src/plugins module, packages (including vendored Dart sources), and profiles for Directionality/TextDirection/direction boundaries. There was no obsolete custom Direction implementation to delete; the one direct app provider and all 12 direct app lookups were replaced.

**retainedAlternatives**

- Flutter WidgetsApp/MaterialApp remains the host locale-direction owner. DDirection reads that native provider; generic components do not impose a new global LTR default.
- event_calendar_data.dart retains the TextDirection supplied by kalender to its frame generator. ShapeBorder paint/path overrides and TextPainter/TextDirection values retain the native API types; these are caller-supplied rendering contracts, not competing providers.
- Cooked HTML/Markdown, code and URL rendering are unchanged; content direction remains owned by their renderer/markup. The nested example explicitly fixes its URL island to LTR. There were no custom code/URL Directionality wrappers to replace.
- Existing baseline Button/Tooltip/Select owners remain for their later catalogue tasks; native MenuAnchor owns the demonstration overlay.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 confirmed. flutter pub get --enforce-lockfile passed with no lockfile changes.
- dart format --output=none --set-exit-if-changed lib/discourse_ui.dart lib/src/plugins/chat/chat_drawer.dart lib/src/shell/composer_panel.dart lib/src/shell/forum_tabs_bar.dart lib/src/shell/main_content.dart lib/src/shell/resizable_pane.dart lib/src/shell/topic_header_tags.dart lib/src/shell/topic_list_navigation.dart lib/src/shell/users_page.dart lib/src/styleguide/component_examples.dart lib/src/styleguide/examples/direction_examples.dart lib/src/styleguide/styleguide_page.dart lib/src/ui/components/d_direction.dart test/resizable_pane_test.dart test/styleguide/direction_examples_test.dart test/styleguide/styleguide_page_test.dart test/ui/d_direction_test.dart: all 17 files already formatted.
- flutter analyze --no-pub passed with no diagnostics, including the new tests and all core/plugin imports.
- flutter test --no-pub test/ui/d_direction_test.dart test/styleguide/direction_examples_test.dart --test-randomize-ordering-seed=random: 20 passed, seed 3516659226. Covers missing/inherited/explicit/nested providers, native interoperability, retained editing selection/state/focus, directional geometry and semantics, Tab/Shift+Tab/Enter, live open-menu direction/theme, menu selection/Escape/outside dismissal/restoration/removal, and all three examples in light/dark/Forest/Plum with narrow 320/360px layouts and 200% text/reduced motion.
- flutter test --no-pub test/styleguide/styleguide_page_test.dart --plain-name "Direction examples": passed after correcting the test to scroll the lazy detail list back to its preview control.
- Coordinator independently ran flutter test --no-pub test/ui/d_direction_test.dart test/styleguide test/resizable_pane_test.dart test/chat_drawer_test.dart test/users_page_test.dart test/composer_toolbar_test.dart test/topic_header_tags_test.dart test/topic_list_navigation_test.dart test/forum_tabs_bar_test.dart test/app_settings_page_test.dart --test-randomize-ordering-seed=random: all 186 passed, seed 4165766908; inspected /tmp/direction-coordinator-regression-tests.log. Includes real styleguide navigation/controls and live RTL resize focus/sign regression. No unchanged passing suite was repeated.
- Built and ran flutter run -d macos -t lib/styleguide_main.dart --no-pub with a PTY from /private/tmp/discourse-native-direction.F27Xzr. Temporary PRODUCT_NAME DiscourseDirectionStyleguide, bundle org.discourse.native.styleguide.direction, and disabled development signing isolate it from the normal app; none of those runner changes are in this branch.
- CUA inspected the running macOS Direction editor in the 1280x860 logical window: typed a local draft, saved via Tab/Enter, switched inherited LTR to RTL, and confirmed draft/saved value and directional arrow/field/action geometry. Inspected current dark and light previews, Forest palette at 360px and 200% text, and scrolling to the saved value without overflow.
- CUA inspected the nested example at 360px/200% Forest: Arabic RTL outer section, wrapping fixed LTR URL, inherited LTR lookup, and resumed RTL sibling. In Plum at 360px/100%, inspected the RTL native menu, visible arrow-key focus, Enter selection, restored trigger focus, and Escape dismissal while keeping the styleguide open.
- git diff --check passed; catalogue snapshot, native runners, pubspecs and lockfiles are unchanged.
- Rebuilt the final committed native examples and confirmed Direction is marked implemented and its live editor renders in the running catalogue.
- Coordinator final review of branch HEAD 1642d8d7bb6c8b5786ed9b5ba348d9bf9e6fbe40 accepted the provider API, three examples, one preview provider plus 12 app lookups, focused regression evidence and completed macOS inspection. No remaining implementation issue was identified. Merge reconciliation affects only progress metadata.
- After merging from the repository main checkout, git diff confirmed all non-progress files exactly match reviewed branch HEAD 1642d8d7bb6c8b5786ed9b5ba348d9bf9e6fbe40; the main worktree is clean. The merge preserves both parents and adds no code change beyond the verified component branch.

**limitations**

- Native device inspection was macOS only. iOS/Linux device behavior and VoiceOver speech were not run; screen-reader direction semantics and native keyboard behavior are covered by widget tests.
- Authenticated core and Chat screens were not exercised in a live signed-in session. Their migrated geometry, resizing, toolbar, measurement and state behaviors were verified by the focused downstream tests listed above.
- Live direction and custom-theme changes while a menu is already open were verified in widget tests. Manual native preview-setting clicks follow normal outside-click dismissal, so the native menu was inspected after selecting its palette/direction.
- The initial isolated build needed temporary signing adjustments; a long CUA approval wait and synthesized command-key attempts required app relaunch/reselection before successful native checks. Those tooling interruptions did not require production code changes.

### typography

Status: merged. Task: 01a081e5-0bef-70a1-9ae3-7717028403e0. Branch: codex/ui-typography.

**acceptanceCriteria**

- Expose reusable DText plain/rich semantic variants for h1, h2, h3, h4, paragraph, lead, large, small, muted and inline code, plus directional blockquote/list composition through discourse_ui.dart; account for all 14 frozen sections.
- Keep DiscourseTypography the only numeric size/line-height owner and AppTheme/TextTheme the live style owner; preserve platform fonts, caller emphasis, site tokens and the unchanged nonlinear platform/app TextScaler composition.
- Use native Text/InlineSpan selection under the caller's SelectionArea, heading/list semantics, intrinsic wrapping and directional geometry; demonstrate keyboard-focusable composed actions without adding typography-owned interaction or overlay state.
- Cover the frozen table composition with native Flutter Table, semantic headings, column alignment, wrapping and themed borders/striping; leave general table behavior to the later Table catalogue entry.
- Provide runnable public-API examples for every frozen section plus article/rich-code/interactive content, nested lists, empty/long text, RTL, live light/dark/site themes and 200% narrow layouts; keep usage code accurate.
- Audit all core and bundled plugin UI; migrate meaningful existing headings and secondary prose while preserving roles, permissions, state and accessibility; document retained authored HTML/Markdown/composer and control-specific typography.
- Pass formatting, static analysis and focused component/example/migration/theme/text-scale regression tests; inspect an isolated macOS styleguide and available affected screens, record evidence/device limitations, then mark review_ready and commit without merging.

**decisions**

- Frozen Markdown SHA256 verified as 3ff202e83d6c90b2521ec471af07cab3c59314028c51ef8d040b3218ec9a9541. The live HTML now redirects to Typeset; the captured original examples define scope, not Typeset.
- Native adaptation: use existing headlineLarge/headlineMedium/headlineSmall/titleLarge for h1-h4, bodyLarge for reading, titleLarge for lead, titleMedium for large, labelLarge for small and bodyMedium for muted/code. Keep the app's paired leading and theme heading emphasis instead of literal CSS sizes/tracking/balanced wrapping.
- Use native Text and Text.rich plus caller-owned SelectionArea; inline code spans can fragment and remain selectable with a rectangular text background, while standalone code can use token radius/padding. Use the existing bundled JetBrains Mono for code only; all other families come from TextTheme.
- Block/list spacing belongs to explicit Flutter composition instead of CSS sibling selectors and scroll margins. Directional quote borders and list markers follow DDirection/Directionality. Typography introduces no animations, overlays, focus nodes or network/business state; composed native controls retain their interaction ownership.
- Table is a documented native Table composition in the examples, not a second public table engine. Existing authored markup and composer renderers continue to own their formatting, source offsets, specialized selection and heading mappings.
- DText.headingLevel separates document hierarchy from visual role (1-6, with 0 opting out). DProse supplies explicit reading flow; DBlockquote supplies a directional italic quote boundary; DTextList supplies wrapping native list/item semantics with optional ordered continuation. Empty flows/lists occupy zero height.
- DText.styleOf resolves live, unscaled TextTheme roles for rich spans. Native Text still owns shaping, wrapping and selection. Standalone code backgrounds fit the text even in a full-width prose flow; caller alignment and current token radius remain effective.
- Seven runnable examples cover every frozen section, full and RTL articles, rich actions, nested/ordered/empty lists, long and empty text, explicit truncation, and native table alignment. Table/article usage includes the complete self-contained sample table class. Marked implemented only after the checks and native inspection below.
- No global type scale, AppTheme, AppTextScaleRegion, source renderer, native runner, dependency, Flutter pin or lockfile was changed. No separate typography implementation existed to remove; migrated callers now delegate their semantic text rendering through the public library.

**migrations**

- Core: EmptyState title and secondary introduction; Settings title/section headings/help text; shared ShellSheet and desktop add-site title; group management form/Logs headings. Visual roles are preserved while semantic heading levels now match page/dialog hierarchy.
- Bundled plugins: Chat channel title/description (including its medium emphasis), Poll and Local Dates composer dialog titles, GIF picker title, Voice room-chat title, and Events cooked fallback heading. Existing controllers, callbacks, permissions, localization/markup data and asynchronous ownership stay in the app/plugin.
- Scaling fixes justified by the migrated surfaces: Settings header has a minimum rather than fixed 52px height; its percentage has an intrinsic width with a 64px minimum; Voice room-chat heading uses Expanded beside Close. Normal-size geometry remains covered by the existing tests.
- Audited 120 core text-consumer files and all bundled plugin directories: Assign, Chat, Discourse AI, Events, GitHub, Lazy Videos, GIFs, Local Dates, Poll, Prometheus Alert Receiver, Reactions and Voice. Also inspected package API/Voice and full-profile sources; these contain no additional native presentation owner requiring migration. Removed redundant legacy Button/Select imports from migrated public-barrel consumers.

**retainedAlternatives**

- DiscourseTypography remains the only numeric size/leading owner; AppTheme maps Material/Cupertino and site themes; AppTextScaleRegion composes nonlinear platform scaling and the app preference unchanged.
- Cooked HTML/Markdown, rich composer/markdown highlighting, quote/code blocks, oneboxes, emoji and user-content links retain their distinct rendering/selection/source-offset contracts and authored h1-h6 mapping. Generic prose is not a parser or replacement for those systems.
- Native control labels, form fields, menus, tabs, dense metadata, notification snippets, topic titles with emoji/unread spans, and specialized alert/event/onebox tables retain explicit semantic roles or renderer-owned styles. Their composition, interaction and domain semantics differ from document prose; the Button/Table/etc. catalogue tasks retain ownership of those component APIs.
- Assign/AI/Reactions and other sheets already delegate titles to the migrated shared ShellSheet or native AlertDialog theme; do not insert redundant text owners. Package bridge/transport and compatibility runners contain no additional Typography UI to migrate.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 confirmed; flutter pub get --enforce-lockfile passed with no lockfile changes. Frozen Typography Markdown hash verified, and official new-york-v4 Typography demo source inspected alongside the captured examples.
- flutter analyze --no-pub: passed with no diagnostics after the final component/layout/test fixes (log /private/tmp/typography-analysis.log).
- flutter test --no-pub test/ui/d_typography_test.dart test/styleguide/typography_examples_test.dart --test-randomize-ordering-seed=random: 13 passed, seed 3875140872. Tests cover all theme roles/native families/caller emphasis, nonlinear scale, heading levels/opt-out/labels, quote/list direction and semantics, nesting/empty lists, wrapping/truncation, code selection/copy using macOS and Linux target-platform overrides, native action focus/Enter/Space/Shift+Tab, live tokens and table header/cell semantics.
- flutter test --no-pub test/styleguide test/typography_boundary_test.dart test/app_text_scale_test.dart test/app_theme_test.dart test/site_theme_app_test.dart test/discourse_typography_adoption_test.dart test/app_settings_page_test.dart test/add_instance_sheet_test.dart test/add_instance_lifecycle_test.dart test/group_page_test.dart test/chat_channel_info_view_test.dart test/gif_picker_test.dart test/voice_room_view_test.dart test/event_card_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/plugins/local_dates/local_date_composer_component_test.dart --test-randomize-ordering-seed=random: 226 passed, seed 1788584063; /private/tmp/typography-regression-tests.log. This includes the actual migrated owners, all eight app zooms, authored cooked content, live site themes, and source scale ownership.
- After the native layout refinements: flutter test --no-pub test/ui/d_typography_test.dart test/styleguide/typography_examples_test.dart test/app_settings_page_test.dart --test-randomize-ordering-seed=random: 18 passed, seed 959805661; /private/tmp/typography-final-component-tests.log. Explicit regressions verify fitted code backgrounds, unbroken code wrapping, the taller settings heading and a single-line zoom readout.
- flutter test --no-pub test/styleguide/styleguide_page_test.dart --plain-name "Typography preview controls": passed; /private/tmp/typography-preview-final-test.log. The real searchable styleguide preserves rich-action state through Plum/360px/200%/RTL and resets it through the preview Navigator. Test waits for native Navigator reconstruction rather than assuming a single frame.
- Every example was rendered at 320px and 960px, 200% text, both directions, reduced motion, and Light/Dark/Forest/Plum in widget tests without overflow or unexpected truncation. Intentional one-line ellipsis is asserted separately.
- Built and ran flutter run -d macos -t lib/styleguide_main.dart --no-pub from isolated /private/tmp/discourse-native-typography.lr3l_nr8. Temporary PRODUCT_NAME DiscourseTypographyStyleguide, bundle org.discourse.native.styleguide.typography and disabled development signing stayed only in that copy. Selected that exact .app path with CUA and raised it before interaction.
- CUA native styleguide inspection: current dark and Light headings; 360px/200% Forest quote/attribution, nested ordered lists, table wrapping/borders/striping/alignment; Plum wrapping code; fitted code backgrounds after refinement; mouse selection through a rich code span; visible Tab/Shift+Tab focus and Enter/Space activation; retained details after Plum-to-Light theme change; Arabic RTL headings, right-side quote rule/list markers, mirrored table columns and fixed LTR code island at 360px/200%. Final hot restart loaded implemented status and the completed usage examples.
- CUA inspected actual EmptyState at 360px and 100/200%, Add-a-site dialog at 200%, Poll dialog in Plum at 200%, and Settings in its deliberately neutral dark theme at 200%, including the final single-line 200% readout and growing heading. A temporary lib/styleguide_main.dart harness used the repository's in-memory fake stores/API and actual widgets; it was never added to this worktree. Open/close and preview changes made no real account or settings writes.
- Focused tests caught a duplicated table semantic wrapper (Flutter already supplies table/rows) and zero heading-level handling; native layout inspection led to fitted standalone code backgrounds and an intrinsic-width settings percentage. All were corrected and covered by focused checks. An early automated Select All chord quit the isolated process because the machine uses AZERTY (CUA key a visibly types q); no native copy-shortcut success is claimed from that attempt.
- dart format --output=none --set-exit-if-changed on all 22 changed/new Dart files passed with zero changes. git diff --check passed. Only Typography's progress row changes, with progress.md regenerated by dart run tool/render_component_progress.dart; native runners, dependencies, lockfile, Flutter pin and global typography/scaling owners are unchanged.
- Coordinator reviewed committed branch HEAD c1b6e1f513b47287101155fdaabfb585b458533f, the complete public component, all seven runnable examples and usage, core/plugin migrations, semantic/scaling/selection tests, and exact passing regression/analysis logs. Native inspection evidence and device limitations were reviewed. No remaining implementation issue was found; merge conflicts were confined to progress metadata, reconciled while preserving the concurrent workflow and other task rows.
- Post-merge comparison confirmed lib/, test/ and docs/typography.md exactly match the reviewed component branch. Only previously committed workflow/progress documents differ; all three concurrent component task rows are preserved.

**limitations**

- iOS and Linux devices were not run. Platform overrides in widget tests validate Flutter keyboard/scaling behavior but are not device testing.
- Authenticated live app/plugin sessions were not opened. Native app-screen inspection used actual widgets with in-memory fixtures; other migrated views were verified by focused owner tests.
- Native mouse selection and composed keyboard actions were inspected. Copy/Select All shortcuts were verified in widget tests for macOS/Linux, not conclusively through CUA on this AZERTY machine; the native Cocoa Edit menu is not the Flutter SelectionArea context menu.
- Table is fully accounted for as the frozen typography composition; general Table component behavior belongs to its later catalogue task. No implementation issue remains known after the focused checks.

### spinner

Status: in_progress. Task: 01a08213-9960-79f1-8d90-9626f24a4b5a. Branch: codex/ui-spinner.

### kbd

Status: review_ready. Task: 01a0821b-27cc-7013-affb-99cae203b2a8. Branch: codex/ui-kbd.

**acceptanceCriteria**

- Public DKbd and DKbdGroup cover text, custom icon/child, grouped and inline hints, button, tooltip, input-addon and RTL composition. Kbd className maps to typed Flutter styling/composition; outline and inline-end are demo-control props, not Kbd variants.
- Match base-nova default geometry, type, spacing and semantic color roles: 20 px keycaps, 4 px padding/gaps, 12/16 px sans medium text, no border, small relative radius and tooltip tint. Preserve intrinsic height, wrapping at 200% and narrow widths, live light/dark/site palettes and reduced motion.
- DShortcut and DShortcutKeycaps preserve existing bindings and sequential highlight feedback without handling actions, format platform modifiers and named keys with spoken labels, and clear stale feedback on lifecycle/visibility changes.
- Search core and all bundled plugins; migrate tooltip ownership, shortcut help, search hints and suitable plugin shortcut hints while preserving dispatch, permissions, focus, state and overlay ownership. Record retained alternatives.
- Runnable public-library examples demonstrate every frozen section plus logical shortcuts, static/highlighted/icon states, scaling, direction and live compositions using available native controls. Focused rendering/semantics/theme/layout/keyboard/lifecycle and caller tests pass, analysis is clean, and macOS is inspected in the serialized desktop slot.

**decisions**

- Reference scope remains the frozen Kbd page (SHA256 3dd0b0dacf86f4b701ae35df3efe453ba1e9995a542e0a4a004a252f5bdd7978). Inspected actual official base-nova registry source (SHA256 4cfe2ba8e19f4d19d090eb039e3f1c041c9cfb379ce948237a9b5018203f7a6c) and rendered light/dark reference. The detailed source-to-Flutter measurements and narrow adaptations are in docs/component-library/kbd-visual-mapping.md; catalogue scope is unchanged.
- Existing app Actions/Shortcuts and app_shortcuts.dart remain binding owners. The Kbd library owns presentation and optional non-consuming hardware feedback only; Button, Tooltip and Input Group remain their separately scheduled catalogue entries.
- Native APIs are DKbd(label) / DKbd.child with required spoken label, DKbdGroup(children) with wrapping/direction/spacing/semantic label, DKbdTheme for ancestor tooltip colors, and retained typed DShortcut/DShortcutKeycaps APIs. No CSS prop string or parallel action registry is introduced.
- Default keycaps use explicit DiscourseTypography.xs (12 px), 16 px leading, weight 500 and zero tracking with the host sans-serif family. Live DTokens supply muted colors and small radius (site base × 0.6). Surfaces are borderless with 20 px minima and 4 px horizontal padding; icons default to 12 px. Intrinsic growth and wrapping preserve native text scaling. Tooltip tint follows its actual foreground at 20% light / 10% dark for contrast on the existing surface. Apple and Linux notation describe unchanged app bindings.
- Optional non-consuming shortcut feedback preserves sequence progression, is disabled for static hints, uses logical activator equality through theme rebuilds, and clears on visibility, app lifecycle and view focus changes. The group has spoken English defaults with caller semanticLabel overrides; sequences visibly say then.
- Seven public-library examples cover the two reference key groups before additional text/symbol/custom-icon states, groups/sequences/inline typography, platform formatting, working button/tooltip, focusable search input, RTL/LTR islands and narrow/large-text/empty groups. Existing Button/Tooltip and native input composition remain visibly identified as separate catalogue work.

**migrations**

- Moved DKbd, DShortcut and DShortcutKeycaps out of theme/d_tooltip.dart into the public Kbd component owner; DTooltip now composes it and announces shortcut labels. Updated core tooltip/hint imports to discourse_ui.dart and baseline DButton to the shared owner.
- Keyboard help now renders CharacterActivator hints through DKbd and wraps key groups beside wrapping labels; its sheet/scroll/focus/dispatch owners are retained.
- ForumSearch replaces plain platform string plus redundant Tooltip with static DShortcutKeycaps sourced from the existing primaryShortcutForPlatform binding; supplementary hints hide below 280 logical pixels of field width while input and clear/advanced controls retain ownership.
- Rail callout uses the shared group with bounded Flexible layout and contextual keycap foreground/tint; the obsolete intrinsic-height wrapper was removed. Existing rail/tab/sidebar/navigation/new-topic/reply/draft shortcut hints now resolve to the shared public implementation.
- Bundled Local Dates replaces embedded modifier text in its Insert menu label with an optional typed MenuSerializableShortcut on ComposerToolbarContribution; composer menu passes it to its existing MenuItemButton formatter. Site gating, editing availability, callbacks and both quick-insert shortcut bindings remain unchanged.

**retainedAlternatives**

- Flutter MenuItemButton retains native menu shortcut presentation for composer formatting and Local Dates; it aligns accelerator columns and participates in the existing menu semantics. Keycap boxes would duplicate that native rendering owner.
- Help instructions and docs remain prose; emoji keycap names are content identifiers, not keyboard hints. Search hints are intentionally omitted when the field is too narrow. No additional standalone hint owner was found in the other bundled plugins or compatibility wrappers.
- DTooltip/rail overlay positioning, gestures and native menu/sheet ownership remain with their scheduled Tooltip/menu/sheet components; this task changes only their Kbd presentation and necessary wrapping/semantics.

**verification**

- Official frozen page and base-nova registry source read. Hidden-browser light/dark renders and computed styles confirmed 20 px height, 4 px padding/group gap, 12/16 px medium type, no border and the relative small radius. Read the coordinator’s updated visual-fidelity contract; documented mapping in docs/component-library/kbd-visual-mapping.md.
- flutter pub get --enforce-lockfile passed in root and profiles/full without lockfile or Flutter pin changes.
- flutter analyze --no-pub passed with no issues in root and profiles/full after the final explicit typography metrics. All touched Dart files were formatted; git diff --check passed.
- flutter test --no-pub test/ui/d_kbd_test.dart test/styleguide/kbd_examples_test.dart test/keyboard_shortcuts_help_test.dart test/d_button_test.dart test/d_tooltip_test.dart test/forum_tabs_integration_test.dart: 70 passed after the geometry/color corrections, covering reference dimensions and palettes, live tooltip tint, semantics, keyboard actions, lifecycle cleanup, help wheel scrolling/Escape and rail/tab integrations.
- flutter test --no-pub test/ui/d_kbd_test.dart test/styleguide/kbd_examples_test.dart: 21 passed after explicit 12/16 typography metrics and the reference-first example arrangement. Custom Material role metrics cannot override the reference; host font family remains live. Matrix covers light/dark/forest/plum, 240/360/900 px, both directions and 200% text; component long-label cases also include 80 px.
- flutter test --no-pub test/forum_tabs_integration_test.dart test/content_navigation_controls_test.dart test/draft_list_test.dart test/keyboard_navigation_test.dart test/styleguide/styleguide_page_test.dart: 91 passed during migration. Rail number-shortcut test rerun after removing the obsolete intrinsic-height wrapper passed.
- flutter test --no-pub test/forum_search_clear_accessibility_test.dart test/poll_composer_panel_test.dart test/ui/d_kbd_test.dart: 43 passed during migration, covering search-hint scaling, preserved clear-focus/query state, typed Local Dates menu hints, permissions and dispatch.
- Isolated macOS styleguide and local-data harness built with flutter build macos --debug --no-pub. Product Discourse Kbd Review at /private/tmp/discourse-kbd-native-4bea uses verified bundle/signature org.discourse.kbd.review4bea. Runner, signing, diagnostics and fake-data fixtures remain outside the repository; the primary app was not launched or modified.
- Native CUA inspected corrected Kbd rendering in Light, Dark and Plum, including 360 px / 200% input and tooltip compositions, RTL input, focus/typing, pointer activation and F6 (counter 0→2). Actual ForumSearch accepted a query and omitted the supplementary hint when narrow. Actual shortcut help wheel-scrolled to its final Search row at 200% text and Escape dismissed it. Native AX exported meaningful chord/key labels through the normal semantics lifecycle.
- The final explicit metric guard preserves the values used by the palettes just inspected natively. The first example was subsequently arranged into the two centered reference groups with default 4 px gaps; the final arrangement is covered by the widget matrix. The isolated native app was quit and confirmed absent from cua.listApps; the serialized desktop slot was released.

**limitations**

- Native Command+K remains unverified: CUA super+k and Meta_L+k reached the passive Flutter diagnostic as Key K with Meta false. Logical macOS/iOS/Linux focus-shortcut tests pass. No VoiceOver speech check is claimed; native AX inspection and widget semantics checks are distinct.
- iOS and Linux were not inspected on devices during this task; a wireless iPhone is detected on the host. Widget target-platform overrides are not device tests.
- Default spoken key names and sequence separator are English; callers can override spoken labels and compose localized DKbdGroup content.

### separator

Status: in_progress. Task: 01a08213-a2e5-7692-a127-f09d2a03094b. Branch: codex/ui-separator.

### skeleton

Status: in_progress. Task: 01a08213-b4ca-77e1-a2aa-8a490808243e. Branch: codex/ui-skeleton.

### Final audit

Status: planned. Task: —. Branch: —.

