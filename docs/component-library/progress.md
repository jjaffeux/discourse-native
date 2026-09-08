# Component library progress

Generated from [progress.json](progress.json). Read the [brief](brief.md), [conventions](conventions.md), [catalogue](catalogue.json) and [inventory](inventory.md).

Coordinator task: `01a0816f-d4e0-7f93-9d6b-baeaf6961181`. Reference: 2026-09-08.

Foundation: **merged** on `codex/component-library-foundation`. Merge: 1b130d3323f9b7619bdead025fd76a57be402a97.

## Component implementation

| # | Component | Status | Task | Branch | Dependencies | Merge |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | direction | merged | 01a0818b-e20a-77d0-bb99-77691899dad7 | codex/ui-direction | — | e69458861e83f3989e2f06dd177805c572740a5a |
| 2 | typography | merged | 01a081e5-0bef-70a1-9ae3-7717028403e0 | codex/ui-typography | direction | 20f42345002e9b0946d1690acd6de6f83b7aa681 |
| 3 | spinner | merged | 01a08213-9960-79f1-8d90-9626f24a4b5a | codex/ui-spinner | — | — |
| 4 | kbd | merged | 01a0821b-27cc-7013-affb-99cae203b2a8 | codex/ui-kbd | typography | 8d0936ff13346650682f3b04e55b612074bd3f66 |
| 5 | tooltip | in_progress | 01a0829c-ba0d-7282-a010-7e26f190dd4f | codex/ui-tooltip | kbd | — |
| 6 | button | planned | — | — | spinner, tooltip | — |
| 7 | separator | merged | 01a08213-a2e5-7692-a127-f09d2a03094b | codex/ui-separator | — | 855f131dc0bdaadaf5aea034a9cd78dbbe06b7b1 |
| 8 | label | merged | 01a0825a-9fe1-7700-878c-f448801c0851 | codex/ui-label | typography | 9bbc2806020646451fd1c283d347283fe4e45f67 |
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
| 19 | skeleton | merged | 01a08213-b4ca-77e1-a2aa-8a490808243e | codex/ui-skeleton | — | fc43a2bdb09ba15b703c0a84863941cde7b009d5 |
| 20 | aspect-ratio | merged | 01a082a9-b9d4-79f0-8a0d-cc48e700cc67 | codex/ui-aspect-ratio | — | 60a3c432c8ba92b9676125b9527776b2d55c5a13 |
| 21 | avatar | in_progress | 01a082d2-4434-73b1-8ab4-88c9b2ba9b66 | codex/ui-avatar | — | — |
| 22 | card | in_progress | 01a082d9-6c59-7443-8e64-f76105fd5e56 | codex/ui-card | typography | — |
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
- Coordinator follow-up: the styleguide Reset action now uses public DButton. The ordinary-action adoption guard retains explicit per-file exceptions for the native Direction menu and Typography rich-text focus examples, including their displayed usage snippets; no general app-action exemption was added.

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
- After Spinner exposed the stale baseline guard, coordinator ran flutter test --no-pub test/d_button_adoption_test.dart test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=random: 9 passed, seed 1006078620, including actual Direction/Typography state preservation and reset. Touched files are formatted, flutter analyze --no-pub and git diff --check pass. Logs: /private/tmp/component-button-adoption-fix.log and /private/tmp/component-button-adoption-fix-analysis.log.
- Coordinator rebuilt the real repository-root macOS app after Label and Aspect Ratio integration: flutter build macos --debug --no-pub succeeded at main 4b5bd8b7d6fecb5a11d01732e8fe7ff7bbba0b98 with all seven currently merged catalogue components. Artifact: /Users/joffreyjaffeux/Code/discourse-native/build/macos/Build/Products/Debug/Discourse.app. Log: /private/tmp/discourse-main-label-aspect-build.log. The real account app was not launched; this verifies compilation and bundling, and does not diagnose the user-reported startup problem.

**limitations**

- iOS and Linux devices were not run during the foundation phase. No new native platform dependency was introduced.
- Baseline Button, Tooltip and Select are explicitly unfinished catalogue implementations; their full reference behavior and migrations belong to their upcoming tasks.

### shadcn visual fidelity correction

Status: merged. Task: 01a0816f-d4e0-7f93-9d6b-baeaf6961181. Branch: codex/ui-shadcn-fidelity.

**acceptanceCriteria**

- Match reference geometry, explicit typography metrics, semantic colors, relative radii, borders, artwork, states and motion; idiomatic Flutter interaction owners do not justify a different visual design.
- Recheck merged Direction, Typography and Separator; correct unjustified differences and inspect actual rendered examples before merging corrections.
- Require official registry/source mappings and rendered visual comparison in every current and future component task.

**decisions**

- Direction owns no intrinsic visual styling. Separator source confirms a one-pixel square-ended border-colored horizontal/vertical rule, matching the implementation.
- Typography corrections restore 800-weight h1, tight heading tracking, 28px paragraph leading, 14px Small leading, reference inline-code padding, list indentation, base text in lists/quotes/tables and heading-specific article gaps.
- Kbd, Spinner, Skeleton and Label tasks received the clarified design specification before merge. Native desktop inspections remain serialized.

**verification**

- Official frozen Typography Markdown preserved verbatim with original SHA256; Separator registry source captured and hashed with upstream MIT license.
- Initial focused typography, four-palette examples, nonlinear text scaling and adoption checks: 17 passed. Static analysis passed without diagnostics.
- Final impact run covered Typography, all styleguide groups, scaling boundary, adoption guard, Settings, Add-a-site and Poll: 73 passed, one existing styleguide navigation test needed its outer scroll position targeted explicitly after note/preview geometry changed (seed 446229861). The repaired Typography preview test passed (seed 3779910838); no production scrolling behavior changed.
- The final run includes the new original-text specimen and balanced-heading layout check. flutter analyze --no-pub passed with no diagnostics.
- Isolated macOS build completed at /private/tmp/discourse-shadcn-fidelity.4xigijr8/app/build/macos/Build/Products/Debug/Shadcn Fidelity Review.app using real Settings, EmptyState and Poll fixtures with in-memory stores. Native visual inspection is pending the shared desktop slot.
- Compared the native original-text specimen at 768px Light and 360px Dark with a browser reconstruction of the exact frozen CSS utilities using corresponding app colors and a system font. This was a local reconstruction because the original Typography HTML now redirects; no claim of pixel-identical live-site rendering is made.
- Inspected the real EmptyState at 200%, actual Settings heading/layout with visible Tab focus, and real Poll dialog in Plum at 200%. Escape dismissed the dialogs; all stores and data were isolated in-memory fixtures.
- Native visual review prompted exact CSS border-box spacing (1px h2 border in addition to 8px padding; 2px quote border in addition to 24px inset) and a guard against balancing that introduces additional breaks within words at 200%. Rebuilt and re-inspected the final source at 360px/200% with RTL/reduced motion, including the corrected heading and directional quote.
- Final component and all eight Typography examples passed 14 focused tests after the border correction, then 14 after the native large-text refinement. Final flutter analyze --no-pub passed. The native build source was byte-compared with the reviewed source.
- Native application Info.plist and ad-hoc signature verified: Shadcn Fidelity Review, org.discourse.shadcn-fidelity, isolated discourse-shadcn-fidelity URL scheme. All runner/signing/fixture adjustments were confined to /private/tmp. Native app quit and comparison tab closed after inspection.
- Coordinator reviewed final branch aee3b24c113b2c5cc1793fbff9973d77ffca5c4c and reconciled only progress/contract metadata against main. All reviewed Dart code, tests and preserved reference source match the native-inspected branch exactly.

**limitations**

- The app keeps its configured fonts, palettes and radius. Native font shaping and soft line breaks can differ from browser rendering. Plain h1 uses a conservative compact measure; rich headings retain native span layout so selection/copy remains intact.
- The original Typography live HTML redirects to Typeset; comparison used the preserved original source and an explicitly identified local CSS reconstruction. No automated pixel-exact cross-renderer comparison is claimed.
- iOS/Linux devices and VoiceOver speech were not inspected for this follow-up. Normal Flutter semantics and selection behavior remain covered by the focused tests; the styleguide AX tree exposed fewer nodes than the initial app fixtures.

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
- Keep DiscourseTypography as the single numeric size owner; reproduce the frozen shadcn weights, leading and tracking while preserving app fonts, semantic colors and the inherited nonlinear platform/app TextScaler.
- Use native Text/InlineSpan selection under the caller's SelectionArea, heading/list semantics, intrinsic wrapping and directional geometry; demonstrate keyboard-focusable composed actions without adding typography-owned interaction or overlay state.
- Cover the frozen table composition with native Flutter Table, semantic headings, column alignment, wrapping and themed borders/striping; leave general table behavior to the later Table catalogue entry.
- Provide runnable public-API examples for every frozen section plus article/rich-code/interactive content, nested lists, empty/long text, RTL, live light/dark/site themes and 200% narrow layouts; keep usage code accurate.
- Audit all core and bundled plugin UI; migrate meaningful existing headings and secondary prose while preserving roles, permissions, state and accessibility; document retained authored HTML/Markdown/composer and control-specific typography.
- Pass formatting, static analysis and focused component/example/migration/theme/text-scale regression tests; inspect an isolated macOS styleguide and available affected screens, record evidence/device limitations, then mark review_ready and commit without merging.

**decisions**

- Frozen Markdown SHA256 verified as 3ff202e83d6c90b2521ec471af07cab3c59314028c51ef8d040b3218ec9a9541. The live HTML now redirects to Typeset; the captured original examples define scope, not Typeset.
- The initial adaptation to generic TextTheme metrics was superseded by the user clarification to copy shadcn. The coordinator follow-up restores the exact frozen typography metrics, reference body text and spacing; TextTheme supplies live font families and DTokens supplies semantic colors.
- Use native Text and Text.rich plus caller-owned SelectionArea; inline code spans can fragment and remain selectable with a rectangular text background, while standalone code can use token radius/padding. Use the existing bundled JetBrains Mono for code only; all other families come from TextTheme.
- Block/list spacing belongs to explicit Flutter composition instead of CSS sibling selectors and scroll margins. Directional quote borders and list markers follow DDirection/Directionality. Typography introduces no animations, overlays, focus nodes or network/business state; composed native controls retain their interaction ownership.
- Table is a documented native Table composition in the examples, not a second public table engine. Existing authored markup and composer renderers continue to own their formatting, source offsets, specialized selection and heading mappings.
- DText.headingLevel separates document hierarchy from visual role (1-6, with 0 opting out). DProse supplies explicit reading flow; DBlockquote supplies a directional italic quote boundary; DTextList supplies wrapping native list/item semantics with optional ordered continuation. Empty flows/lists occupy zero height.
- DText.styleOf resolves live, unscaled TextTheme roles for rich spans. Native Text still owns shaping, wrapping and selection. Standalone code backgrounds fit the text even in a full-width prose flow; caller alignment and current token radius remain effective.
- Seven runnable examples cover every frozen section, full and RTL articles, rich actions, nested/ordered/empty lists, long and empty text, explicit truncation, and native table alignment. Table/article usage includes the complete self-contained sample table class. Marked implemented only after the checks and native inspection below.
- No global type scale, AppTheme, AppTextScaleRegion, source renderer, native runner, dependency, Flutter pin or lockfile was changed. No separate typography implementation existed to remove; migrated callers now delegate their semantic text rendering through the public library.
- The coordinator visual-fidelity follow-up adds an original-text specimen (eight total examples), plain-heading balance with native wrapping limits, and exact border-box insets. See the dedicated visualFidelity record for source mapping, checks and remaining platform differences.

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

Status: merged. Task: 01a08213-9960-79f1-8d90-9626f24a4b5a. Branch: codex/ui-spinner.

**acceptanceCriteria**

- Provide public DSpinner with a 16 logical-pixel default, arbitrary positive sizing, live inherited/explicit color, stroke width and custom rotating artwork; keep async/business state in callers.
- Reproduce the official shadcn/Lucide Loader2 SVG artwork on every platform with a 24-unit view box, rounded 2-unit scalable stroke, 16px default geometry and 1s linear clockwise rotation; expose one customizable native loading status with a decorative opt-out, no focus or interaction interception.
- Stop motion for reduced-motion preferences, inactive applications and disabled ticker subtrees; handle live updates, removal and restoration without leaked animation work.
- Demonstrate all frozen sections with interactive customization, four reference sizes (12/16/24/32), loading buttons, badge/input/empty compositions, start/end placement, cancellation/retry, RTL, narrow layouts and 200% text.
- Audit core and every bundled plugin, migrate circular indeterminate indicators including DButton and remove AdaptiveActivityIndicator ownership; preserve determinate progress and document retained linear/typing alternatives.
- Format/analyze and run focused component, styleguide and migrated-consumer regressions, then inspect an isolated macOS styleguide using the coordinator inspection slot.
- Inspect official registry/source in addition to frozen docs, record a concise reference-to-Flutter visual mapping, correct unjustified visual differences and inspect the final rendered examples before review_ready.

**decisions**

- Frozen spinner.md SHA256 verified as 9c7185da74c70d9b9bb7c3b894e14bb62e2a07c264bed76a786ab7f38325d654; catalogue variant/size=sm/align values belong to demonstration Button/Badge/Item/Input Group/Empty controls, not Spinner props.
- The clarified shadcn fidelity requirement supersedes the initial platform-artwork choice. DSpinner now renders the exact default Lucide Loader2/loader-circle SVG path through the existing flutter_svg dependency on all platforms; the custom example uses the exact LoaderIcon SVG. No new package or catalogue entry.
- Composition uses ordinary children and directional Flutter layout. Spinner owns no Button/Badge/Input Group/Empty APIs and no loading completion, errors or cancellation state.
- DSpinner defaults to 16 logical pixels, follows inherited IconTheme color and uses DTokens.foreground as fallback; explicit color and SVG view-box strokeWidth are supported. Stroke scales with size. Whole-panel callers retain 24px boxes and constrained inline callers retain their existing dimensions; DButton now uses the 16px default.
- Use a native loadingSpinner semantics role and a single caller-localizable live label, with semanticLabel=null for decorative artwork. DButton retains its existing name, Loading value, disabled state, tooltip and async ownership.
- Reduced motion pauses the reference SVG rotation at its current position while keeping indeterminate busy semantics. Default and custom motion stops for inactive apps and disabled ticker subtrees and resumes without disposing borrowed state. DMotion.spin matches Tailwind’s 1s linear infinite animation.
- No networking, completion callbacks, error state, focus nodes or overlay ownership were added to DSpinner. Example completion/validation/cancellation controls use local sample state.
- Visual mapping in docs/component-library/spinner-reference.md records exact SVG path/view box/stroke/cycle and companion Button/Badge/Input Group/Empty/Item source geometry. App theme colors, surface radius and font family remain native integration points; large text can wrap instead of clipping status text.
- Implementation, reference mapping, consumer regressions and final native correction checks are complete. Spinner is review_ready for the coordinator; only this component row and its generated evidence are updated. Device/VoiceOver gaps and the unassigned native keyboard incident remain explicit limitations.

**migrations**

- Replaced 97 direct indeterminate circular/adaptive usages in 57 core/plugin source files and migrated DButton loading to DSpinner (98 busy-indicator constructions total). All app callers use the public discourse_ui.dart barrel; DButton imports the component internally.
- Removed shell/adaptive_activity_indicator.dart and migrated its callers in aggregate_view, draft_list, instance_rail, lightbox and topic_list_view. Updated adaptive Apple tests to exercise DSpinner.
- Core adoption covers app loading, account menus/presence, forum/sidebar loading, badges/categories/tags/groups and member/activity views, topic lists/actions/taxonomy/ownership/move-post dialogs, composer image workflows, bookmarks/reactions/likes, emoji/search/pickers, preferences, update installation and video/photo loading.
- Bundled plugin audit: migrated direct circular usages in Assign, Chat (channel/thread/search/message actions/composer), AI summary, GIFs and Voice. Reactions uses the migrated shared reaction presenter. Poll, Events, GitHub, Lazy Videos, Local Dates and Prometheus Alert Receiver have no additional direct circular spinners; existing DButton consumers inherit the new rendering.
- Updated emoji-picker, reaction-list and user-presence regression assertions to the public DSpinner instead of the Material implementation, preserving loading/error/permission/async tests on macOS.
- Added a dedicated spinner_examples.dart with six runnable examples for all frozen documented sections: customizable sizes/artwork, Button, Badge, Input Group, Empty and RTL. Installation/usage are documented through the public barrel.
- Fidelity follow-up updates 16 additional consumer test files and the shared activityIndicators test finder to the public DSpinner, so loading assertions continue exercising the new artwork on Linux as well as Apple platforms. Numeric progress remains separate.

**retainedAlternatives**

- instance_rail.dart retains the CircularProgressIndicator with value: updates.progress because update-download percentage is meaningful. update_sheet.dart and composer_panel.dart retain numeric LinearProgressIndicator values for update downloads and composer uploads.
- Horizontal indeterminate bars in badges/categories/tags, bookmark actions, revision history, user-directory empty/loading status, Assign searches/group refresh, Events cards/directory/participants and Chat pinned refresh retain their linear layout for the separate Progress catalogue entry; they do not duplicate circular spinner ownership.
- loading_skeleton.dart and content placeholders remain owned by the concurrent Skeleton task. Vendored video-player example loading bars are upstream sample UI outside the app component migration.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 verified. Root and profiles/full flutter pub get --enforce-lockfile passed with no lockfile or pin changes.
- dart format --output=none --set-exit-if-changed on all 69 touched/new Dart files passed (0 changes). Final root flutter analyze --no-pub passed (no issues, 2.6s); profiles/full flutter analyze --no-pub passed (no issues, 1.6s). git diff --check passed; no lockfile, Flutter-pin or repository platform-runner changes.
- flutter test --no-pub test/d_spinner_test.dart test/adaptive_apple_widgets_test.dart test/d_button_test.dart test/styleguide test/emoji_picker_test.dart test/reactions_row_accessibility_test.dart test/user_presence_widget_test.dart --test-randomize-ordering-seed=random --reporter expanded: 86 passed, seed 4000949775.
- flutter test --no-pub test/d_spinner_test.dart --plain-name 'an open dialog receives live palette changes without replacing its spinner' --reporter expanded: 1 passed. An already-open dialog retains Spinner state, receives a site-palette update and dismisses via Escape.
- Component tests cover identical reference artwork under iOS/macOS/Linux target-platform overrides (not device execution), default and custom motion pause/resume/removal, app inactivity, TickerMode, reduced motion with unchanged busy semantics/no numeric value, decorative semantics/input/focus exclusion, 12/16/24/32 sizing and tight constraints, live light/dark/Forest/Plum colors, all 11 DButton variant colors and disabled named-action semantics.
- Example tests exercise all six examples at 280px with 200% text and RTL, state retention across palette changes, customization, inline start/end placement, button failure/completion, disabled validation with preserved text, rejection/retry/send, empty-state cancel/fail/retry/complete, and styleguide search/registration.
- Broader migration command: flutter test --no-pub test/add_instance_sheet_test.dart test/aggregate_view_test.dart test/anchored_picker_test.dart test/assigned_group_view_test.dart test/badges_page_test.dart test/categories_page_test.dart test/chat_browse_channels_view_test.dart test/chat_channel_info_view_test.dart test/chat_channel_view_lifecycle_test.dart test/chat_composer_test.dart test/chat_header_button_accessibility_test.dart test/composer_image_gallery_test.dart test/composer_image_test.dart test/d_button_adoption_test.dart test/do_not_disturb_dialog_test.dart test/draft_list_test.dart test/emoji_picker_test.dart test/gif_picker_test.dart test/group_page_test.dart test/groups_page_test.dart test/inline_video_test.dart test/lightbox_test.dart test/plugin_dependency_boundary_test.dart test/post_revision_history_test.dart test/preferences_page_test.dart test/reaction_presentation_test.dart test/reactions_row_accessibility_test.dart test/styleguide test/tags_page_test.dart test/topic_create_button_accessibility_test.dart test/topic_header_tags_test.dart test/topic_list_view_lifecycle_test.dart test/topic_taxonomy_fields_test.dart test/user_presence_widget_test.dart test/voice_room_view_test.dart --test-randomize-ordering-seed=random --reporter expanded. Seed 4125606634: 578 passed / 5 failed initially. Four introduced test expectations/navigation issues were corrected and all passed in the final 86-test run; the remaining pre-existing adoption-allowlist failure is recorded under limitations.
- Isolated macOS build: flutter build macos --debug --no-pub --target lib/styleguide_main.dart passed in /private/tmp/discourse-ui-spinner-native, producing Spinner Styleguide.app with bundle ID org.discourse.native.styleguide.spinner. Ad-hoc signing and removal of the unused push entitlement stayed only in the temporary copy; repository runners unchanged.
- Final custom-artwork review: explicitly oversized child icons are fitted into the requested diameter. flutter test --no-pub test/d_spinner_test.dart test/styleguide/spinner_examples_test.dart --test-randomize-ordering-seed=random --reporter expanded: 27 passed, seed 33603198, including the open-dialog and oversized-artwork regressions. The isolated macOS build was refreshed successfully after this change.
- Native macOS slot used and explicitly released. Verified 12/16/24/32 sizes, custom artwork/accent/32px selection and pause, live current-dark to Light palette with retained sample state, DButton loading followed by visible Tab focus and Return completion, and Forest 360px/200%/RTL/reduced-motion payment status with wrapping and directional placement.
- Temporary-only Migration fixtures mounted real UserMenuMessage and GifPicker with local gated data, no actual account requests. In Plum 360px/200%/RTL/reduced motion, both actual loading surfaces completed failure/retry/loading/completion or empty-state transitions. The initial artificial 310px GIF fixture height overflowed at 200%; using the native picker maximum height of 540px eliminated that fixture-only overflow. Normal semantics lifecycle remained stable.
- Official base-nova registry, rendered Spinner page, Lucide loader-circle/loader SVGs and Tailwind spin source inspected. The independent SVG fixture raster comparison passes exactly with the existing flutter_svg renderer. Source mapping: docs/component-library/spinner-reference.md; third-party attribution: licenses/lucide.txt.
- Fidelity follow-up: flutter test --no-pub test/assigned_group_view_test.dart test/chat_channel_info_view_test.dart test/preferences_page_test.dart test/voice_room_view_test.dart test/invite_list_test.dart test/topic_filter_test.dart test/users_page_test.dart test/chat_composer_test.dart test/chat_channel_view_lifecycle_test.dart test/chat_browse_channels_view_test.dart test/topic_list_view_lifecycle_test.dart test/topic_view_lifecycle_test.dart test/native_inline_video_playback_test.dart test/inline_video_test.dart test/chat_message_tile_thread_preview_test.dart test/topic_progress_lifecycle_test.dart test/d_spinner_test.dart test/adaptive_apple_widgets_test.dart test/d_button_test.dart test/styleguide test/emoji_picker_test.dart test/reactions_row_accessibility_test.dart test/user_presence_widget_test.dart test/post_likes_account_generation_test.dart test/user_card_account_lifecycle_test.dart --test-randomize-ordering-seed=random --reporter expanded: 583 passed, seed 2556737142. Updated loading-state assertions retain native editing, disabled/busy semantics, account/lifecycle isolation and asynchronous consumer coverage.
- Fidelity follow-up: dart --suppress-analytics format --output=none --set-exit-if-changed on 24 changed Dart files passed with 0 changes; final root flutter analyze --no-pub passed in 3.1s and profiles/full in 1.6s, no issues. git diff --check passed. No SDK/pin/lockfile or repository runner edits.
- Refreshed isolated macOS build passed at /private/tmp/discourse-ui-spinner-fidelity/build/macos/Build/Products/Debug/Spinner Fidelity.app, bundle org.discourse.native.styleguide.spinner.fidelity. Its DSpinner, examples and DButton sources match the final worktree bytes. Spinner Baseline.app was preserved for the bounded forced-semantics comparison recorded below. All native inspection followed the coordinator slot grants.
- Follow-up native comparison completed: exact base 5fd6658b UserMenuMessage/GifPicker/DButton and bare native-indicator shim repeated the forced-semantics SIGSEGV at 0x48 with the same AccessibilityBridge::CreateRemoveReparentedNodesUpdate / CommitUpdates frames. Baseline report SHA-256 109d039d154e65ce4cc92f8a8cad45fa2e6cc9467d0b7e8b0af4691ddc6e2a17. New DSpinner is not necessary for that diagnostic crash; underlying framework/fixture cause remains unresolved.
- Final SVG native app inspected with normal semantics lifecycle: all six reference sections across current dark/Light/Forest/Plum; custom size/color/pause and live-theme state retention; reference Button states and real DButton Tab/Return completion; badge leading/trailing/completion; input editing/validation/rejection/retry/send; empty cancel/fail/retry/complete; Forest 360px/200%/RTL/reduced-motion payment status. Actual UserMenuMessage and GifPicker loading/error/retry/completion fixtures passed under Plum 360px/200%/RTL/reduced motion with no crash or overflow. Precise app identities and observations: docs/component-library/spinner-native.md.
- Native-found example corrections: keep input error rings outside their filled interior, use intrinsic amount width at the payment row end with a large-text cap, and replace stale waiting instructions after completion. flutter test --no-pub test/styleguide/spinner_examples_test.dart --test-randomize-ordering-seed=random --reporter expanded: 13 passed, seed 2614942230. Root flutter analyze --no-pub clean in 2.6s; formatting/diff checks pass; refreshed isolated native build succeeds with matching source bytes.
- Final bounded native reinspection passed on the already rebuilt source-matched Spinner Fidelity.app using pointer-only navigation: Light input rejection kept the interior white inside the red error ring; both cancelled and completed Empty states showed the nonbusy description; Light payment amount reached the inline end at Fit/100%/LTR and 360px/200%/RTL with the full normal title and wrapping Arabic large text. No overflow, crash or unresponsive episode occurred in this pass. Prior full examples and real core/GIF fixture checks were not repeated.
- After the final correction pass, only the isolated Spinner app was quit through its own native menu. A subsequent global cua.getState snapshot confirmed all three Spinner bundle identifiers absent. Desktop slot released to the coordinator for Avatar. No further native actions or follow-on component work are planned.
- Coordinator reviewed stable clean Spinner HEAD 3c0192067f2b5543afe33ce71ce5e9deb9f469cf, its exact Lucide path and motion/lifecycle semantics, six complete example sections, app-wide adoption, final native corrections and explicit diagnostic limitations. Reconciled shared exports, imports and registrations against the seven previously merged components; retained the existing adoption guard correction, Skeleton replacements and Aspect Ratio media contracts.
- Coordinator combined-main verification: 738 focused component, styleguide, Button-adoption and affected loading/account/media/Chat/Voice consumer tests passed, seed 1778345709. The exact command and output are in /private/tmp/component-spinner-integration-tests.log. All 87 touched Dart files were formatted; merge-introduced duplicate imports and directive ordering were corrected. Final flutter analyze --no-pub is clean (7.7s), git diff --check passes, and generic Spinner/example source remains byte-identical to the reviewed native-inspected branch. The existing f5549d51 adoption guard was preserved and passed in the combined run.

**limitations**

- iOS and Linux devices were not run; target-platform widget tests do not substitute for device testing. flutter devices listed macOS 26.6.2 (darwin-arm64), Chrome and a wireless iPhone on iOS 26.6; no Linux device was available. The wireless phone was not used or modified. VoiceOver spoken output and authenticated app screens have not been inspected. The final SVG app’s six examples, actual core/GIF fixtures and three final example corrections were inspected on macOS.
- Forced-semantics diagnostic crash reproduces with pre-migration native consumers. The new DSpinner is not necessary to trigger it, but its framework/fixture root cause is unresolved. Reports and exact reproduction are retained in docs/component-library/spinner-native.md and ignored local artifacts; no forced-semantics instrumentation is committed.
- On the first relaunch for the three final example corrections, the native Theme menu stopped responding after typed search. Verified Spinner Fidelity PID 13780 was at 97.6% CPU, with no crash report; a one-second passive sample showed repeated FlutterKeyboardManager/FlutterChannelKeyResponder/FlutterEmbedderKeyResponder message processing. Cause remains unassigned. Sample SHA-256 7fc2c30a768983cea7dd552c4f042f98fae0b80c8c4d6fcd0e2a0020ef8887fd. The app quit normally through its native menu. Final correction inspection subsequently passed using pointer-only navigation under a new slot grant; that success does not establish a cause or fix for the keyboard event loop.

### kbd

Status: merged. Task: 01a0821b-27cc-7013-affb-99cae203b2a8. Branch: codex/ui-kbd.

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
- Coordinator reviewed the full API and migrations, exact Base Nova source mapping, corrected compact keycap metrics, native inspection and documented modifier-injection limitation. Reconciled Separator imports and example registration while retaining the newer shadcn Typography styles; combined checks follow.
- Coordinator integration: 176 selected tests passed (seed 2125845405) covering Kbd, the whole styleguide, Button/Tooltip, keyboard help, search, forum tabs and composer/Local Dates menu dispatch. That command also requested a nonexistent local_date_shortcut_test.dart; it was a test-path error, not a failing case. The two actual Local Dates component/lifecycle test files then passed all 6 cases. After resolving alphabetical import ordering, flutter analyze --no-pub passed with no issues. Reviewed final import deduplication, format and git diff --check.

**limitations**

- Native Command+K remains unverified: CUA super+k and Meta_L+k reached the passive Flutter diagnostic as Key K with Meta false. Logical macOS/iOS/Linux focus-shortcut tests pass. No VoiceOver speech check is claimed; native AX inspection and widget semantics checks are distinct.
- iOS and Linux were not inspected on devices during this task; a wireless iPhone is detected on the host. Widget target-platform overrides are not device tests.
- Default spoken key names and sequence separator are English; callers can override spoken labels and compose localized DKbdGroup content.

### tooltip

Status: in_progress. Task: 01a0829c-ba0d-7282-a010-7e26f190dd4f. Branch: codex/ui-tooltip.

### separator

Status: merged. Task: 01a08213-a2e5-7692-a127-f09d2a03094b. Branch: codex/ui-separator.

**acceptanceCriteria**

- Expose DSeparator through discourse_ui.dart with horizontal/default and vertical Axis orientation, themed line, explicit length for unbounded axes, centered cross-axis space, thickness, directional indent/endIndent, and ordinary Flutter composition.
- Support bounded, intrinsic-height row, narrow, scrolling and explicitly sized unbounded layouts without overflow; retain RTL geometry and host text-scaling ownership.
- Exclude decorative separators from semantics and keyboard focus; expose caller-localized non-interactive labels for meaningful separators without inventing a resizer role or stealing adjacent controls focus/touch input.
- Read shared tokens on every build for live light/dark/site-palette changes; retain special application separator colors and spacing. No animation, controller, networking, business state or overlay ownership belongs in this widget.
- Provide interactive public-API styleguide examples and accurate usage for Usage, Vertical, Menu, List and RTL, including configurable geometry/semantics, responsive menu actions, list scrolling and empty state.
- Audit core and all bundled plugins/packages, migrate genuine Divider/VerticalDivider and equivalent separator uses, and document retained framework, border, resize and content-rendering ownership.
- Pass formatting, static analysis and focused component/styleguide/migration regressions; inspect an isolated macOS styleguide in representative widths/themes after coordinator grants the native slot, and record actual evidence plus unavailable device/VoiceOver/authenticated-screen coverage.

**decisions**

- Frozen 2026-09-08 source hash verified as b0c3b29e2b3852570144159da0ee5681074c1ddb1727d2f720a7b211f1259120; documented component prop is orientation. React className/style/render adapt to typed geometry/color properties and normal Flutter composition, with no additional package.
- DSeparator uses Flutter Divider/VerticalDivider as its rendering owner, with explicit library defaults and live DTokens.border. Default cross-axis space is the line thickness; migrations preserve previous native spacing explicitly.
- A separator fills bounded available length. A Row in unbounded height can use IntrinsicHeight with stretched children or supply length; a separator with no finite parent length and no length naturally collapses along that axis rather than inventing a dimension.
- Decorative is the default. Meaningful separators require a non-empty caller-localized semanticLabel; Flutter has no separator SemanticsRole, so they expose a static labeled semantics boundary with no actions or keyboard focus. Labels on decorative separators are rejected to avoid silently inaccessible intent.
- Hover, pressed, selected, disabled, loading, error, keyboard activation, controllers, overlays and animation are not Separator states. The sample menu/list actions retain native control focus/touch behavior; the host owns text scaling and reduced-motion preferences.
- Five real examples cover configurable horizontal semantics/insets/emphasis, horizontally scrolling intrinsic-height navigation, responsive menu descriptions/actions, a mutable separated list with empty state, and Arabic RTL plus explicitly sized unbounded composition. Narrow menus retain every destination and switch separator orientation rather than hiding Help.
- All 73 authored native Divider/VerticalDivider call sites were migrated. DSeparator delegates painting/intrinsic sizing to Flutter with explicit default thickness/space/insets/radius, excludes decorative semantics and ignores pointer input, so only the public component owns application dividing rules. Existing AppTheme DividerTheme mapping remains necessary for framework-internal controls.
- Coordinator advance review requested the public DButton owner for ordinary example actions. Vertical navigation, responsive menu actions and list controls now use DButtonVariant.flat with label composition; all three vertical usage snippets match. A fresh DefaultTextStyle inside menu labels deliberately removes DButton's compact single-line default so descriptions wrap without silent truncation. No adoption-guard exception was added.
- Native macOS inspection covered all five examples and real migrated widgets in temporary local fixtures. The day, picker and sheet adapters remain application-owned; their fixture registration and signing adjustments are outside the repository. Final example text uses singular 1 item and the list snippet matches the rendered subtitle layout.
- Acceptance criteria are satisfied for the implemented API, migrations, automated checks and recorded macOS scenarios. Separator is implemented in the styleguide and review_ready for coordinator review; uninspected platform/screen-reader/authenticated flows remain explicitly limited below.

**migrations**

- 53 Divider/VerticalDivider usages in core shell files now use public DSeparator: list rows and loading-list boundaries, user/preferences/group panes, sheets, pickers and native-menu compositions, topic/date streams, diagnostics, drafts, badges, bookmarks, search, uploads and the instance rail. Horizontal height and vertical width become orientation-independent space; prior 17/24 spacing and specialized colors are preserved.
- 19 dividing rules migrated in Assign, Chat, Discourse Events, GIFs, Local Dates, Poll and Voice plugins. Existing permission checks, list lazy construction, async ownership and callbacks are unchanged; Chat unread marker keeps its error color and visible New label, Assign keeps its ledger color.
- The styleguide pane separator uses DSeparator. Public barrel export and dedicated separator_examples.dart registration added. Existing barrel imports were extended and redundant baseline control imports removed where a new complete barrel import already supplies them.
- Three equivalent container rules migrated: forum tab gaps retain 1×18 geometry and hover/selected visibility, MessageInboxTitle retains its 18px line and 10px margins through space: 21, and instance sidebar section boundaries retain their sliver insets and spacing.
- Updated the existing anchored picker, topic day separator, group list geometry and forum tab tests to assert public DSeparator boundaries while preserving their behavior assertions. Audited all lib/src/plugins modules, packages (including vendored Dart libraries) and profiles; no additional authored package/profile separators were found.

**retainedAlternatives**

- Flutter Divider and VerticalDivider remain the sole paint/intrinsic-layout owners inside DSeparator. Framework-internal menu/control separators and AppTheme DividerTheme remain native. No authored PopupMenuDivider call sites existed; a future PopupMenuEntry separator must retain that framework entry contract.
- Container/ShapeBorder/BoxDecoration borders on pane edges, cards, tab selection indicators, pickers and controls remain part of their surface/layout ownership. Prometheus alert tables retain TableBorder for coordinated table grid painting; these are not independent content separator widgets.
- ResizablePaneHandle and the Chat thread split retain adjustable handle rendering and their hit/focus/drag geometry; they belong to Resizable, not the non-interactive Separator.
- Cooked HTML hr rules remain in the HTML renderer/CSS adapter to preserve markup, margins and content-selection ownership. StreamDaySeparator keeps date semantics, floating behavior and callbacks while its visual rule uses DSeparator.
- LoadingSkeleton and indeterminate activity indicators remain owned by the concurrent Skeleton and Spinner tasks. Only rules between loading rows changed on this branch; their placeholder content and business state are untouched.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 verified. flutter pub get --enforce-lockfile passed without dependency, pin or lockfile changes.
- flutter analyze --no-pub passed with no diagnostics after migration imports and tests were corrected.
- flutter test --no-pub test/ui/d_separator_test.dart test/styleguide/separator_examples_test.dart --test-randomize-ordering-seed=random: all 21 passed, seed 3679188485. Covers bounded/unbounded/intrinsic sizing, parent constraints, RTL insets, decorative/meaningful static semantics, pointer pass-through and Tab/Enter, live token/fallback/override colors, native MenuAnchor intrinsic sizing and open-menu theme updates/focus restoration, real example actions/list scrolling/empty state and catalogue navigation. Every example also renders at 320/760px, 200% text and RTL with reduced motion in light/dark/Forest/Plum.
- flutter test --no-pub test/anchored_picker_test.dart test/topic_day_separator_test.dart test/group_page_test.dart test/group_member_menu_ownership_test.dart test/preferences_page_test.dart test/forum_tabs_bar_test.dart test/aggregate_view_test.dart test/chat_drawer_test.dart test/user_menu_button_accessibility_test.dart test/user_menu_message_accessibility_test.dart test/user_menu_site_identity_test.dart test/draft_list_test.dart test/instance_actions_accessibility_test.dart test/forum_search_clear_accessibility_test.dart test/topic_create_button_accessibility_test.dart test/topic_actions_menu_test.dart test/topic_list_filter_menu_ownership_test.dart test/emoji_picker_test.dart test/bookmark_ui_test.dart test/diagnostics_panel_test.dart test/badges_page_test.dart test/users_page_test.dart test/composer_toolbar_test.dart test/assign_plugin_test.dart test/assigned_group_view_test.dart test/chat_channel_info_view_test.dart test/chat_transcript_test.dart test/chat_search_test.dart test/event_card_test.dart test/gif_picker_test.dart test/voice_diagnostics_view_test.dart test/voice_room_view_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_widget_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=random: all 548 passed, seed 3396198342. Covers 36 affected core/plugin/styleguide test files, including actual list geometry, permission and menu/sheet lifecycle regressions.
- Built flutter build macos --debug --no-pub -t lib/styleguide_main.dart successfully from isolated temporary copy /var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/discourse-native-separator.3ka532q1. PRODUCT_NAME DiscourseSeparatorStyleguide, bundle org.discourse.native.styleguide.separator, and signing changes exist only in that temporary copy.
- git diff --check passed. Production native runners, dependency lockfiles, Flutter pin and frozen catalogue are unchanged.
- dart format --output=none --set-exit-if-changed on all 61 touched Dart files passed (0 changes). Only the assigned Separator progress row differs from the dispatch base.
- flutter test --no-pub test/message_inbox_page_test.dart test/sidebar_width_test.dart test/event_sidebar_boundary_test.dart --test-randomize-ordering-seed=random: all 19 passed, seed 3080551253. These additional final-audit checks cover the migrated inbox-title and sidebar container rules, constrained inbox navigation and sidebar layout/lifecycle.
- After the DButton review fix: flutter test --no-pub test/styleguide/separator_examples_test.dart --test-randomize-ordering-seed=random passed all 10 examples tests, seed 2524191817. The responsive menu interaction test now runs at 320/760px with 200% text and asserts RenderParagraph.didExceedMaxLines is false for all three descriptions; list tests assert DButton disabled/enabled behavior after clear/add.
- CUA selected /var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/discourse-native-separator.3ka532q1/build/macos/Build/Products/Debug/DiscourseSeparatorStyleguide.app with cua.getApp and used the window Raise action after the coordinator granted the native slot. All interactions used this distinct product/bundle and lib/styleguide_main.dart. No production runner changed.
- Native macOS: searched the catalogue and inspected horizontal Separator in Light and Dark. Toggled Meaningful boundary, Asymmetric insets and Emphasize boundary; visually confirmed line thickness/insets and retained switch state after a live Dark/RTL change. Decorative versus meaningful semantics were tested through Flutter semantics, not claimed from VoiceOver speech.
- Native macOS: inspected Dark vertical navigation, visible DButton keyboard focus, and successive Tab/Return activation of Docs and Source across the rules. Inspected the wide responsive menu, selected Help, then switched to Forest site, 360px preview, 200% text and reduced motion; descriptions stayed readable, separators changed to horizontal and inner scrolling revealed retained Selected: Help.
- Native macOS: inspected Arabic RTL and asymmetric horizontal insets in Forest/Plum at 360px and 200%, including the fixed-length vertical rule beside wrapping text and the explicit horizontal length in an unbounded row. Inspected the Plum list, selected Item 2, scrolled through Item 12 while preserving selection, cleared to an empty list with no rules, and added a first item with no trailing rule.
- Native migrated fixtures: instantiated actual StreamDaySeparator, AnchoredPickerContent and showShellSheet with local callbacks in temporary separator_native_fixtures.dart. At Plum/360px/200%, clicking the date then the rule produced exactly one date activation. Picker selection, typing Alpha to filter, the selection marker and header/footer rules worked. Switching the mounted picker to Light retained its query and Alpha selection. Real sheet header/footer rules rendered in Plum and Light; footer close and Escape dismissal returned to the retained picker. The sheet uses its existing root Navigator and inherited root text scale; it is not claimed as a 200% dialog check.
- Native inspection completed and the shared desktop slot was explicitly released to coordinator before final documentation/checks. No approval block or native component failure occurred. No further CUA or focus actions were performed after release.
- Final flutter test --no-pub test/styleguide/separator_examples_test.dart --test-randomize-ordering-seed=random passed all 10 after the native-observed singular-item text correction, seed 1551245093. flutter analyze --no-pub passed with no issues (4.4s). dart format of the two changed example/test files reported 0 changes. The unchanged 588-test component/migration result was not repeated.
- Final refreshed isolated flutter build macos --debug --no-pub -t lib/styleguide_main.dart passed with the DButton examples, implemented status and final usage/count text. This build occurred after releasing the desktop slot, with no app focus or CUA action.
- Coordinator accepted the completed native inspection, reviewed the component, migrations, DButton cleanup and wrapping regression, and reported no remaining implementation issue before final commits. The corrected DButton adoption guard on combined main is owned by coordinator review; no local guard exception or unmerged component code was introduced.
- Coordinator reviewed the full DSeparator API, sizing and semantics tests, core/plugin migrations, final DButton examples and wrapping regression, and recorded macOS evidence. Reconciled shared exports, example registration and duplicate public imports with merged Typography while preserving every other progress row and the native inspection queue.
- Coordinator combined-main verification: 132 tests passed, seed 970432551, covering DSeparator, all merged styleguide examples, the corrected DButton adoption guard, anchored pickers, date separators, tabs, inbox/sidebar layout, Chat drawer and Poll/Local Dates sheets. An import accidentally removed during conflict cleanup was restored before this successful run. flutter analyze --no-pub passed with no issues; 61 changed Dart files were already formatted and git diff --check passed. Logs: /private/tmp/separator-coordinator-tests-final.log and /private/tmp/separator-coordinator-analysis-final.log. The final worker tip changed only its implementation SHA record; the verified Dart files were preserved byte-for-byte while including that final metadata commit.

**limitations**

- Native device inspection was macOS 26.6.2 on darwin-arm64. Linux device inspection is unavailable on this host. Flutter devices detected a wireless iPhone running iOS 26.6, but it was not launched or controlled; iOS device behavior is unverified.
- VoiceOver speech was not run. Static boundary labels/actions/direction are covered by widget semantics tests. CUA exposed limited AX content outside native popup/dialog surfaces, so pointer locations came from observed screenshots where necessary.
- Authenticated core/plugin screens were not inspected in a signed-in session. Native migration evidence uses the actual date/picker/sheet widgets with local temporary fixtures, while the broader app/plugin migrations are covered by the 567 focused regression tests already listed.
- Live theme changes in an already-open native MenuAnchor are verified by widget tests. Native palette settings normally dismiss menus on outside interaction, so manual overlay evidence covers rendering after selecting the palette, plus dismissal and preserved local state.
- The native inspection preceded final styleguide implemented metadata and a singular-item/usage-text correction. Those non-behavioral text changes were verified by the final focused example test run and refreshed isolated build without reacquiring desktop focus.

### label

Status: merged. Task: 01a0825a-9fe1-7700-878c-f448801c0851. Branch: codex/ui-label.

**acceptanceCriteria**

- Account for the frozen Installation, Usage, Label in Field, RTL and API Reference sections, with hash 7263b641bac78acd5ec6cfbffefeddda484eaedb1d32b8a73a675b53da0644c2. Export DLabel through discourse_ui.dart without external runtime dependencies.
- Match the official registry Label metrics: text-sm=14 logical pixels, font-medium=weight 500, leading-none=line height 1, gap-2=8 pixels in composed rows, zero outer padding/border/radius, select-none and disabled opacity 0.5. Preserve host font family, live DTokens foreground, inherited text scaling/direction and unconstrained wrapping.
- Use the title/label slots of native Flutter controls for association, full-row touch activation, one accessible control name/state, one keyboard focus target, visible focus, and disabled/busy guards. Keep native InputDecoration and Form validation ownership and do not add an HTML ID registry or a second form/focus system.
- Demonstrate basic checkbox labeling, disabled states, rich wrapping content, native form labels/descriptions/errors and submission/reset, Arabic/Hebrew RTL, and lifecycle/state retention with runnable public widgets and accurate snippets.
- Audit core and every bundled plugin; migrate appropriate checkbox/switch label titles, preserve native field labels and non-control metadata, and document retained alternatives.
- Format and analyze, pass focused component/example/migration/downstream tests, build and verify an isolated macOS app identity, then inspect styleguide and real migrated production surfaces only after coordinator grants the shared desktop slot.

**decisions**

- The official base-nova registry source renders a styled native HTML label with ordinary element props. The catalogue outline variant, horizontal orientation, and button/submit types belong to neighboring controls in the Field demo, not Label variants.
- DLabel accepts child composition, optional TextStyle emphasis and enabled state. It derives the host font family from DText small and reuses DiscourseTypography.sm for the unscaled 14px metric, then applies shadcn weight 500, line height 1 and zero letter spacing. Existing native control slots own association, activation and semantics as temporary composition while Checkbox/Switch/Input/Field are pending. Their tasks must port shadcn visuals while preserving native behavior.
- The linked Base UI Label API and .md endpoint return HTTP 404 on 2026-09-08; inspected the frozen Markdown and official shadcn base-nova registry source instead. No missing API is inferred.
- The label creates no focus target, gesture handler, overlay, animation, controller, networking or business state. Native owners retain lifecycle and interaction; disabled content uses full-subtree opacity 0.5, a forbidden pointer cursor, disabled semantics, IgnorePointer and ExcludeFocus. Callers must also disable the native control callback.
- Visual fidelity mapping: HTML label -> DLabel content in an existing native label slot; flex items-center/gap-2 -> centered Row with 8 logical pixels for icons/spans; text-sm/font-medium/leading-none -> 14 px/500/1; select-none -> SelectionContainer.disabled; disabled opacity-50 -> Opacity(0.5); peer-disabled cursor/pointer rules -> forbidden cursor and interaction suppression. The component has no default outer padding, border, radius or background. Native control hit areas and control visuals belong to their respective controls, which are not implemented by this task.
- docs/component-library/label-visual-mapping.md records the official registry URL, raw registry SHA256 89b01e14fd39dceece9fa421e71e78ea83286bd43a2ca1c2f55d2e8d3958fff2 and UTF-8 label.tsx content SHA256 b3b7b21d2877838fc73713df48a47248392de04a3b3fafa8961369f33ab14530, with the exact visual mapping and FieldDemo handoff.

**migrations**

- Core: AppSettingsModal GIF switch, Preferences linked-post notifications, InviteEditor send-email option, PostFlagEditor legal confirmation, TopicMovePosts chronological order, UserStatusEditor pause notifications, and GroupPage membership/read-state/SMTP/unknown-sender options now use DLabel. Existing permission, busy, validation and callback ownership remains unchanged.
- Bundled plugins: Poll public-voter/automatic-close settings; Local Dates end/countdown/time options; Events all-day and dynamic boolean fields; Voice privacy acknowledgment, room options, push-to-talk and auto-status settings use DLabel.
- VoiceDiagnosticsView replaces its unassociated caption-plus-switch Row with a native SwitchListTile using DLabel and one combined semantic control. Tapping the recording caption now enters the existing consent flow; busy/start/stop callbacks are retained. Its old DecoratedBox surface becomes Material with the same color/border/radius so native focus and ink remain visible.

**retainedAlternatives**

- Native InputDecoration.labelText is temporarily retained in existing core/plugin fields to preserve accessible naming, focus/error behavior, descriptions and validation. Input and Field own its future shadcn visual port; floating native appearance is not a blanket final exception. The Label page's larger payment/billing FieldDemo, FieldLabel, descriptions, errors and field-set composition belong to the scheduled Field task.
- Core user/group/topic result lists, image selection, aggregate/feed/post selection, topic property metadata, revision section captions, badges, menu labels and action text retain their existing list/typography owners. They are selection content or descriptions rather than standalone control labels.
- Every bundled plugin was searched: Assign and Chat use native field labels and selection/message content; Discourse AI, GitHub, Lazy Videos, GIFs, Prometheus Alert Receiver and Reactions contain no standalone input label needing replacement. GitHub issue labels are domain badges. Poll/Local Dates/Events/Voice migrations are listed above. packages/discourse_voice is a native bridge; profiles/full shares this same bundled UI and has no separate label renderer.

**verification**

- Frozen Label Markdown SHA256 verified as 7263b641bac78acd5ec6cfbffefeddda484eaedb1d32b8a73a675b53da0644c2; inspected https://ui.shadcn.com/docs/components/base/label and https://ui.shadcn.com/r/styles/base-nova/label.json. Linked Base UI Label HTML/.md endpoints returned HTTP 404.
- flutter pub get --enforce-lockfile passed on Flutter 3.47.2 / Dart 3.13.2 without lockfile changes.
- flutter analyze --no-pub passed with no issues. All touched Dart files formatted; git diff --check passed.
- flutter test --no-pub test/ui/d_label_test.dart test/styleguide/label_examples_test.dart test/voice_diagnostics_view_test.dart test/app_settings_page_test.dart test/preferences_page_test.dart test/user_status_editor_test.dart test/invite_list_test.dart test/post_flag_editor_test.dart test/post_flag_editor_ownership_test.dart test/topic_move_posts_ownership_test.dart test/group_page_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/event_composer_test.dart test/voice_room_view_test.dart test/voice_diagnostics_panel_test.dart test/styleguide/styleguide_page_test.dart test/d_button_adoption_test.dart test/ui/d_typography_test.dart --test-randomize-ordering-seed=random: 267 passed, seed 1867985777. Log: /private/tmp/ui-label-regression-tests.log.
- After final centered rich-content mapping and test cleanup, flutter test --no-pub test/ui/d_label_test.dart test/styleguide/label_examples_test.dart --test-randomize-ordering-seed=random: 19 passed, seed 1609358833. Log: /private/tmp/ui-label-final-component-tests.log. Component checks cover native label/row and semantic activation, checked/disabled semantics, one Tab stop/Space/Shift-Tab, removal during activation, disabled descendants, non-selectability, exact text metrics, live light/dark/Forest/Plum/default themes, RTL and 200% text at 216px and 720px. Example checks cover required input naming/focus/error/save/reset, rich-label wrapping and independent terms action, RTL interactions, theme/width/scale/direction/motion state retention and Reset.
- Built the temporary in-memory fixture target build/label-inspection/main.dart with flutter build macos --debug --no-pub -t build/label-inspection/main.dart. Final app: build/macos/Build/Products/Debug/Discourse Label.app. Actual Info.plist verified CFBundleName/Executable=Discourse Label, CFBundleIdentifier=org.discourse.native.label-review, URL scheme=discourse-label-review. Temporary Xcode/Info overrides were restored. Fixture mounts the real PostFlagEditor, VoiceMeshPrivacyDialog and VoiceDiagnosticsView as well as ComponentStyleguidePage. Ad-hoc signature verified with codesign --verify --deep --strict. The app was launched only after the coordinator granted the desktop slot.
- Coordinator prereview follow-up: added label-visual-mapping.md with raw registry and source-content hashes, reused DiscourseTypography.sm, and clarified that native control visuals are temporary and the full FieldDemo belongs to Field. flutter analyze --no-pub passed; flutter test --no-pub test/ui/d_label_test.dart test/styleguide/label_examples_test.dart --test-randomize-ordering-seed=random: 19 passed, seed 4088727084. Logs: /private/tmp/ui-label-prereview-analysis.log and /private/tmp/ui-label-prereview-tests.log.
- macOS CUA on 2026-09-08: styleguide label-text clicks, Tab/Space activation with visible native control focus, disabled pointer guards and live Light/Dark themes passed. Forest rich content plus its independent terms action wrapped at 360px/200%. Plum Arabic/Hebrew RTL leading controls and label clicks passed at 360px/200%. The Plum native form at 360px/200% showed the empty validation error, focused from its email label, accepted literal reader@example.test input, saved locally, and reset field/checkbox/result/error. Screenshots: build/label-inspection/screenshots/{light-disabled,dark-enabled,forest-rich-360-200,plum-rtl-360-200,plum-form-error-360-200,plum-form-saved-360-200}.png.
- macOS actual production widgets in local fixtures: PostFlagEditor in Dark preserved explanation and checked legal confirmation through busy-disabled state and a retained local error, then returned successfully on retry. VoiceMeshPrivacyDialog in Forest at 200% text fit without clipping, toggled from its label and cancelled. VoiceDiagnosticsView in Forest opened the existing consent flow from Recording Off; Cancel kept it off, confirm updated the local fixture to Recording On, and caption activation stopped it. No account data, network calls, room join or actual recording was involved. Screenshots: build/label-inspection/screenshots/{post-flag-busy,post-flag-retained-error,voice-privacy-forest-200,voice-diagnostics-consent,voice-diagnostics-on,voice-diagnostics-off}.png.
- Native macOS AX snapshots exposed the named legal and privacy checkboxes with checked value, and one named Recording Off/On switch with the corresponding off/on state. Snapshot excerpts: build/label-inspection/{post-flag-busy,voice-privacy,voice-diagnostics-on,voice-diagnostics-off}-ax.txt. Widget semantics checks additionally verify required input naming, combined controls, disabled state and semantic activation.
- Quit only Discourse Label.app through its native menu. A subsequent global CUA getState confirmed org.discourse.native.label-review was absent; released the desktop slot to the coordinator. docs/component-library/label-visual-mapping.md records the inspection evidence. Example group marked implemented only after this verification; mergeCommit remains null.
- Coordinator reviewed the generic API, all control-label migrations and focused regression coverage at stable HEAD 1c8348cf85aa76001d701837545e123eff06eafc. Reviewed native Light disabled, Plum RTL at 360px/200%, and actual PostFlagEditor retained-error screenshots; checked native consent/busy/retry evidence and explicit Input/Field handoffs. Reconciled the public barrel, example registrations and progress metadata while preserving newer Kbd, Skeleton and Typography work.
- Coordinator combined integration check on main: flutter test --no-pub test/ui test/styleguide plus Voice diagnostics, Settings, Preferences, User Status, Invites, Post Flag, Topic Move, Groups, Poll, Local Dates, Events, Voice room/panel and DButton adoption regressions passed all 374 tests, seed 4174198982. flutter analyze --no-pub passed with no diagnostics in 10.3s; all 22 touched Dart files passed format checking, and git diff --check passed. Logs: /private/tmp/component-label-integration-tests.log and /private/tmp/component-label-integration-analysis.log. Generic Label, its examples and their focused tests are byte-identical to the inspected worker source.

**limitations**

- iOS and Linux are uninspected on devices. A wireless iPhone was detected but has not been run. No new native platform dependency is introduced.
- The macOS styleguide route exposed only its native search field through the CUA accessibility snapshot. Preview semantics are verified by widget tests; production dialog/view snapshots exposed the named control states. VoiceOver speech was not run.
- Checkbox/Switch/TextFormField and baseline DButton visuals in Label examples are temporary until their catalogue tasks implement the reference controls. This task completes Label only and does not exempt those components or FieldDemo from shadcn fidelity.

### skeleton

Status: merged. Task: 01a08213-b4ca-77e1-a2aa-8a490808243e. Branch: codex/ui-skeleton.

**acceptanceCriteria**

- Provide public DSkeleton rectangular/circular geometry with configurable dimensions and directional radius; compose fractional widths and aspect ratios with native layout widgets.
- Support standalone pulsing and synchronized DSkeletonRegion composition, explicit static placeholders, live reduced-motion and TickerMode changes, safe disposal and live light/dark/site token updates.
- Expose one caller-supplied loading label per region; exclude placeholder descendants from semantics, pointer interaction and keyboard focus. Preserve caller-owned loading/error/ready state and scroll geometry.
- Demonstrate interactive geometry, avatar, card, text, form, table and RTL compositions at narrow widths and 200% text, with accurate public API usage and local loading/ready/error controls.
- Audit core and all bundled plugins; migrate the existing LoadingSkeleton/LoadingSkeletonBlock owner and every caller while preserving labels, loading conditions and reading-lane geometry. Keep Spinner migrations separate.
- Format and analyze touched code, run focused component/styleguide/migrated-screen regression tests, and inspect an isolated macOS styleguide after coordinator slot approval; report actual device and accessibility evidence.
- Treat official base-nova registry styling as the design specification; preserve frozen example geometry, map muted/radius/pulse exactly, document concrete native conflicts, and inspect corrected examples plus real migrated surfaces before review_ready.

**decisions**

- Frozen Skeleton Markdown hash matches cab955b03db8fe7a9f4e5bc71be4f72054782d29476b19fb2029f569a880df16; documented props are empty. Web className geometry maps to Flutter dimensions, BorderRadiusGeometry, FractionallySizedBox and AspectRatio; RTL language controls are demo state, not Skeleton props.
- Move and extend the existing shell rendering owner while matching the official source: muted fill, medium radius (site base × 0.8), and a 2-second 1 → 0.5 → 1 pulse using Cubic(0.4,0,0.6,1). This supersedes the earlier legacy 675ms/0.62 timing decision.
- DSkeletonRegion is presentational loading composition, not a request/state owner. Explicit expand:true preserves existing bounded application loading panels; default intrinsic region sizing supports inline library compositions.
- Render the frozen Card frame explicitly from registry measurements (16px padding, 4px header gap, 16px section gap, foreground/10 outer ring, xl radius). Remove generic framed panels elsewhere. Local demonstration state controls sit outside reference compositions; no Material Card/Skeleton styling is substituted.
- DSkeletonRegion adds keyboard-focus exclusion to the preserved pointer/semantics exclusions. DSkeleton.animate=false opts a shape out; region animate=false, reduced motion and TickerMode disable the shared pulse.
- Public API, frozen scope mapping, native adaptations and the complete adoption audit are documented in docs/component-library/skeleton.md.
- Supersedes the earlier derived-fill decision: the initial Light defect was surfaceContainerHighest #FFFFFF on floating #FFFFFF, while actual muted is #F1F3F5. Removed DTokens.skeleton, its 16% foreground blend and unjustified decorative contrast threshold. DSkeleton now reads DTokens.muted directly; only sidebar callers override color to tokens.background because their backdrop equals muted.
- Inspected official Skeleton/Card registry JSON, theme radius scale and Tailwind pulse documentation on 2026-09-08. Current aggregate registry examples differ from the frozen document; retained frozen 16:9 Card, 32px form controls and five table rows. Reference-to-Flutter mapping and measured palettes are in docs/component-library/skeleton.md; frozen catalogue unchanged.

**migrations**

- Removed shell/loading_skeleton.dart; migrated all ten regions and their shapes to DSkeletonRegion/DSkeleton through discourse_ui.dart.
- Migrated topic_list_view (topics/messages/filters), topic_view (initial/recommendations/earlier/later), draft_list, user_activity, user_summary and instance_sidebar; explicit expand:true retains bounded viewport geometry and existing caller-owned labels/loading guards.
- Migrated bundled Chat initial-channel and bidirectional pagination skeletons. Preserved minimum message heights, request ownership and loaded/error behavior; made placeholder gutter/alignment directional.
- Migrated skeleton assertions in topic and Chat lifecycle tests and moved/extended the old owner tests under test/ui/d_skeleton_test.dart; added interactive styleguide tests and all seven registered examples.
- The navigation sidebar uses the public optional color override on its shapes. Core content and Chat keep the default muted fill. All other loading ownership and geometry migrations remain as recorded.

**retainedAlternatives**

- Audited all 12 bundled modules plus packages/discourse_voice/lib and profiles/full/lib. Only Chat had additional shape skeleton owners; Assign, AI, Events, GitHub, Lazy Videos, GIFs, Local Dates, Poll, Prometheus Alert Receiver, Reactions and Voice had none.
- Indeterminate busy indicators remain in the concurrent Spinner scope; no Spinner migration is claimed.
- Avatar/emoji identity and inline-size fallbacks, SiteImage authenticated loading/error builders, Chat dominant-color image surfaces and unavailable-image error placeholders retain their media behavior and existing owners.
- Unsupported-route placeholders and composer/inline PlaceholderAlignment atoms are navigation or text-layout representations, not content loading skeletons.

**verification**

- Frozen Markdown SHA256 verified with shasum -a 256; official Skeleton reference inspected on 2026-09-08.
- Flutter 3.47.2 / Dart 3.13.2; flutter pub get --enforce-lockfile passed without lockfile changes.
- flutter analyze --no-pub passed with no diagnostics.
- flutter test test/topic_list_view_lifecycle_test.dart test/topic_view_lifecycle_test.dart test/chat_channel_view_lifecycle_test.dart test/draft_list_test.dart test/user_summary_test.dart test/coherent_initial_render_test.dart test/connection_session_integration_test.dart --no-pub --test-randomize-ordering-seed=random: 206 passed, seed 3315690589.
- flutter test test/ui/d_skeleton_test.dart test/styleguide test/activity_section_lifecycle_test.dart --no-pub --test-randomize-ordering-seed=random: 81 passed, seed 1795106859.
- Component checks cover standalone/synchronized pulse, static opt-out, live motion/TickerMode changes, disposal, accessible label replacement, pointer and Tab exclusion, intrinsic/expanded/unbounded dimensions, fractional/aspect-ratio geometry, circle/directional/default radius and live light/dark/site/fallback themes.
- Styleguide checks cover search/registration, all seven examples at 320px/200%/RTL/Plum and 1024px/100%/LTR/Forest, loading/ready/error/retry transitions, keyboard slider adjustment, form validation/saving/theme retention, card actions and horizontal table scrolling. Existing styleguide access/Direction/tokens tests passed.
- Built isolated temporary macOS styleguide with flutter build macos --debug -t lib/styleguide_main.dart --no-pub at /private/tmp/discourse-native-skeleton.alyOd3/build/macos/Build/Products/Debug/Skeleton Styleguide.app; distinct product/bundle identity and all signing adjustments are outside the repository.
- Source audit found no remaining old LoadingSkeleton/LoadingSkeletonBlock imports or usages. git diff --check passed.
- Historical, before the shadcn fidelity correction: After the native palette fix: flutter test test/ui/d_skeleton_test.dart test/styleguide/component_tokens_test.dart test/styleguide/skeleton_examples_test.dart --no-pub --test-randomize-ordering-seed=random: 35 passed, seed 465275359. That former derived-fill/contrast regression was subsequently removed by the source-fidelity correction; it is not a current design criterion.
- Formatted all 16 touched Dart files with dart format; final dart format --output=none --set-exit-if-changed and git diff --check passed.
- Historical, before the shadcn fidelity correction: macOS 26.6.2 arm64 CUA: selected exact isolated app path and raised it under the coordinator-granted slot. Visually inspected all seven example groups. Geometry: circle/diameter pointer changes, Tab focus with visible halo, arrow keys changed diameter 56 to 64, pulse pause/static companion.
- Historical, before the shadcn fidelity correction: Native Light: caught the old white-on-white fill, rebuilt the derived token fix and confirmed visible avatar/lines. Exercised Loading → Ready → Error → Retry. Native Forest: 360px preview, 200% text, RTL and reduced motion together; inspected avatar/card/text/form placeholders and ready form rendering.
- Historical, before the shadcn fidelity correction: Native Plum: inspected pulsing table rows; dragged the horizontal scrollbar to reveal later columns and verified Ready retained the position. Inspected explicit RTL avatar placement and mirrored asymmetric corners. Reported completion to release the inspection slot.
- flutter devices reported macOS, Chrome and a wireless iPhone; native interaction was performed only on macOS.
- Coordinator review: migrated Use site radius, Retry, Follow and form Save example actions to public DButton.flat. flutter test test/styleguide/skeleton_examples_test.dart --no-pub --test-randomize-ordering-seed=random passed 18 tests, seed 3352427373; final analysis and isolated native build passed. This cleanup followed the recorded styleguide native inspection.
- The real-widget native fixture exposed an over-traversing Chat public-barrel import. Corrected it in 71e2d595 after primary implementation 941f6e37. flutter analyze --no-pub passed; flutter test test/chat_channel_view_lifecycle_test.dart --no-pub --test-randomize-ordering-seed=random passed 41 tests, seed 2088169370.
- Temporary-only offline fixture smoke check: flutter analyze --no-pub lib/styleguide_main.dart and flutter test test/native_skeleton_fixture_test.dart --no-pub passed (1 test). The fixture mounts actual TopicListView, ChatChannelView and ChatMessageStream with existing gated API fakes and an in-memory image client; HttpOverrides rejects unexpected real HTTP clients. Initial and both pagination regions render without widget exceptions and dispose cleanly.
- Source-fidelity checks: flutter analyze --no-pub passed. flutter test test/ui/d_skeleton_test.dart test/styleguide/skeleton_examples_test.dart test/coherent_initial_render_test.dart --no-pub --test-randomize-ordering-seed=random: 38 passed, seed 2017906744. Tests now measure rendered Avatar/Card/Text/Form/Table/RTL sizes and gaps, the exact full pulse cycle, and sidebar fill override. The final rendered DecoratedBox assertion passed a follow-up run of the five coherent-initial-render tests with the same seed.
- Temporary live palette probe: Light muted/content/highest #F1F3F5/#FFFFFF/#FFFFFF; Dark #1A1C20/#212429/#272B32; Forest #EEF6F0/#F8FCF9/#CBDDD0; Plum #2B2030/#211725/#49354F. Muted equals sidebar background in all four. Half-opacity muted/content contrast was 1.054, 1.049, 1.031, 1.053: intentionally subtle decorative treatment, not a text-contrast requirement.
- Final temporary offline fixture: flutter analyze --no-pub lib/styleguide_main.dart, flutter test test/native_skeleton_fixture_test.dart --no-pub (1 test), and flutter build macos --debug -t lib/styleguide_main.dart --no-pub passed. The smoke test mounts actual TopicListView, ChatChannelView, ChatMessageStream and InstanceSidebar, completes local fake API gates, verifies all loading regions disappear and the ready topic/message render, and disposes without exceptions. Fixture toolbar, fake data, signing adjustments and test remain outside the repository.
- Final source-fidelity macOS 26.6.2 arm64 CUA inspection under the exclusive coordinator-granted slot: inspected the exact rebuilt isolated Skeleton Styleguide.app using normal semantics. Visually inspected all seven example groups: 48px reference demo and 100x20 pill, 40px Avatar composition, Card padding/header gap/16:9 cover/outer ring, three-line Text, Form labels/inputs/group gaps, five-row three-column Table, and mirrored RTL avatar/lines. No added generic frames remained.
- Final native palette/constraint evidence: Light geometry/Avatar/Card/Table; Dark topic list at 360px, 200% text, RTL and reduced motion; Forest Chat first load and Text/Form at 360px, 200% text, RTL and reduced motion; Plum Form/Table/RTL examples; actual Plum Chat pagination at 360px, 200% text and RTL. Reduced-motion changes stopped the visible pulse. No overflow was observed in these combinations. Light and Dark actual sidebar placeholders remained distinct from their muted backdrop using the local background override.
- Final native real-widget transitions: TopicListView exposed Loading topics and rendered rows; ChatChannelView exposed Loading chat channel with the real composer separate; ChatMessageStream displayed a real local message between Loading older messages and Loading newer messages; InstanceSidebar exposed Loading navigation alongside real navigation items. Show local data completed the fixture gates: Loaded local topic and the local chat message appeared, both pagination loading labels disappeared, and sidebar loading was replaced by its ready categories/navigation. No authenticated account or real HTTP request was used.
- Final native demonstration actions: Avatar Loading -> Ready -> Error rendered; Card Follow changed to Following; Form literal text input changed Ada to AdaGrace and public Save visibly displayed Saved: AdaGrace. These final source-matched checks supersede the earlier ready-form-only limitation. Empty-name validation and the corrected table horizontal scroll below 256px remain covered by widget tests rather than final native interaction.
- Native input incident triage: a batch of field click, super+a, typeText(Grace), and scroll lost the targeted window on the AZERTY host. No new Skeleton/Discourse/Flutter diagnostic crash report was found. The cause is unconfirmed; no application crash or production defect is claimed. Retrying with the native Edit menu and literal input succeeded in editing/saving, although Select All did not select the existing text and the CUA key names backspace/delete were unsupported. No source change was made for this tool/input incident.
- Final native cleanup: quit only the isolated Skeleton app through its native app menu. A subsequent app-specific AX query reopened the fixture, so quit again and used cua.getState() to confirm Skeleton absent from running apps. Released the desktop slot to the coordinator before final documentation work.
- Official Skeleton/Card base-nova registry response bytes and decoded UTF-8 TSX content SHA256 values were verified on 2026-09-08 and recorded beside their exact source URLs in docs/component-library/skeleton.md. Both sources still match the documented muted/radius/pulse and Card frame mapping.
- Coordinator reviewed all generic code and app migrations, source measurements/hashes, motion and semantics tests, and final normal-semantics macOS evidence on real topic/Chat/sidebar loading-to-ready fixtures. Reconciled shared barrel/example registrations and imports with Kbd, Separator and corrected Typography; no component or migration defect found. Combined integration checks follow.
- Coordinator integration: flutter test --no-pub test/ui/d_skeleton_test.dart test/styleguide test/topic_list_view_lifecycle_test.dart test/topic_view_lifecycle_test.dart test/chat_channel_view_lifecycle_test.dart test/draft_list_test.dart test/user_summary_test.dart test/coherent_initial_render_test.dart test/connection_session_integration_test.dart test/activity_section_lifecycle_test.dart --test-randomize-ordering-seed=random passed 312 cases, seed 2377581763. The catalogue accounting case initially read progress.json before its merge conflict was resolved; after reconciliation its isolated rerun passed (1 case, same seed). Final flutter analyze --no-pub passed with no issues after removing two duplicate public imports. Touched merge files formatted; git diff --check passed. No production behavior fix was required during reconciliation.

**limitations**

- No iOS or Linux runtime/device inspection. A wireless iPhone was discovered, but no iOS CUA session or device deployment was performed; no Linux device was available.
- VoiceOver speech was not inspected. Normal native AX exposed the actual topic/chat/pagination/sidebar loading labels and ready-state replacements; styleguide AX remained sparse apart from native menus/text inputs. Single-label semantics, hidden descendants, live-region opt-out and focus/pointer exclusion passed widget tests. No forced global semantics diagnostic was used.
- Final native form editing and saving passed. Empty-name validation, palette-retained form draft state and the source-corrected table scroll below 256px passed automated interaction tests but were not completed in the final native session. The earlier window-loss incident and unsuccessful native Select All/unsupported key names are recorded precisely in verification; no application crash is inferred.
- Authenticated live accounts were not opened. Actual migrated TopicListView, ChatChannelView, ChatMessageStream and InstanceSidebar were inspected natively with gated local fake data, including loading completion. Remaining migrated screens and broader loading/error/pagination/session behavior were covered by the focused core/Chat regression suites.
- Shared overlaps for coordinator reconciliation: discourse_ui.dart, component_examples.dart, tokens.dart, own progress row and app/test imports in topic_view.dart, topic_list_view.dart, draft_list.dart, instance_sidebar.dart, user_activity.dart, user_summary.dart and Chat. No other component branch was imported or merged.

### aspect-ratio

Status: merged. Task: 01a082a9-b9d4-79f0-8a0d-cc48e700cc67. Branch: codex/ui-aspect-ratio.

**acceptanceCriteria**

- Export public DAspectRatio with required arbitrary finite positive ratio and ordinary child composition; use Flutter ratio layout, document tight/bounded/unbounded constraints and keep clipping, imagery, colors and loading caller-owned.
- Match frozen 16:9 (max 384px), square (max 192px), portrait 9:16 (max 160px) and RTL figure examples, using rounded-lg/muted/cover/grayscale/dark 20% brightness with live palette, font and radius tokens and an 8px caption gap.
- Preserve descendant state, semantics, pointer and keyboard input, focus, and caller-owned media/controller lifetimes across ratio, theme and direction updates; respect native text scaling and scrolling.
- Audit all core and bundled plugins, migrate appropriate ratio presentation including inline video, oneboxes, lightbox and Chat, preserve normalization/fit/clipping/loading/lifecycles, and record retained metadata, grid and playback APIs.
- Add comprehensive offline public-library examples for reference compositions, arbitrary ratio changes, constraint behavior, interaction/state retention, large text and RTL with Light/Dark/Forest/Plum previews and DButton actions.
- Format/analyze and pass focused component/example/migration/downstream checks without changing Flutter pin or lockfiles; inspect actual rendered reference examples and representative real migrated widgets in an isolated local-data macOS app after the coordinator grants the native slot; record exact evidence and limitations.

**decisions**

- Public DAspectRatio accepts every finite positive ratio and mounts Flutter RenderAspectRatio directly, with debug assertions and release mount/update validation. Parent constraints take precedence; at least one axis must be bounded. Child composition owns paint, clipping, semantics, focus, input, state and controllers.
- Preserved frozen Markdown and registry JSON under docs/component-library/reference; exact URLs, raw/source-content hashes, CSS measurements, native mapping and adoption exceptions are documented in docs/component-library/aspect-ratio.md. The linked Base UI API currently returns HTTP 404; registry uses a plain CSS ratio div and needs no Base UI dependency.
- Frozen examples retain 384x216 widescreen, 192px square, 160x284.444 portrait, live base radius/muted/cover/grayscale and 20% dark brightness, plus an 8px-gap 14px/20px RTL caption. Local bundled Discourse imagery substitutes for the remote reference avatar.
- An explicit packages/discourse_native/src/styleguide/assets/discourse.png asset declaration and key works in both the root application and the compatibility profile; no runtime network or asset-fallback owner is introduced.

**migrations**

- Core inline_video now uses DAspectRatio for outer capped geometry and inline/fullscreen playback. Removed competing manual ratio sizing while retaining finite-width fallback, actual-size poster decoding, clipping, taps, async sessions, disposal and scrolling.
- Generic/topic onebox thumbnails and lightbox reserved-image slots use DAspectRatio, preserving metadata normalization, widths, cover/contain fit, clipping, loading/error, links and gallery ownership.
- Bundled Chat upload images and optimistic GIF previews use DAspectRatio; preserve no-upscale/caps, contain fit, dominant fill, loading/error, semantics, playback toggles and gallery behavior.
- Skeleton card placeholder/ready compositions and public snippets now use DAspectRatio; updated relative-sizing API docs.

**retainedAlternatives**

- Media model aspectRatio values, image-decode normalization and native playback requests are metadata/transport, not widget layout owners.
- YouTube keeps its 200px minimum-height native overlay sizing; ComposerImagePreview retains authored scale, no-upscale, fixed selection/measurement bounds; image mosaic equalized heights and fixed carousel track are deliberate layout policies.
- Voice/GIF sliver grid childAspectRatio stays with Flutter grid layout; upstream video_player_avfoundation and vendored WebRTC example apps do not depend on this application library.

**verification**

- Acceptance criteria recorded before implementation. Frozen Markdown hash verified; official registry raw and source-content hashes recorded. Other component rows and workflow metadata compared with base and preserved.
- Format check passed for 15 touched Dart files; flutter analyze --no-pub passed without diagnostics.
- Focused component/examples/media/Chat/Skeleton/adoption command recorded in aspect-ratio.md: 305 passed, randomized seed 2654739856. Includes ratio/session retention, pointer/keyboard/focus/semantics, normalization/size caps, offscreen disposal and async race/decode checks.
- After shared asset correction, 32 example tests passed from root (seed 443369763), and 32 passed from profiles/full (seed 1858729558) after enforced-lockfile pub get. Neither Flutter pin nor any lockfile changed.
- Browser inspection of official examples confirmed 384x216, 192x192, 160x284.4375 CSS-pixel boxes; native reference rounded-lg is 10px before app token substitution. Verified object-cover, grayscale, dark brightness(0.2), and RTL caption at 8px gap / 14px font / 20px line-height. Light and Dark reference renders inspected.
- Isolated Aspect Ratio Review macOS app built and inspected at /private/tmp/discourse-aspect-ratio-review-01a082a9/app/build/macos/Build/Products/Debug/Aspect Ratio Review.app. Bundle ID org.discourse.aspect-ratio-review, separate URL scheme, package asset, ad-hoc signature and byte-identical production lib source verified before launch. Only the example implemented-status declaration changed afterward.
- Native reference comparison: widescreen Light/Dark, square Dark, portrait Forest, RTL figure Plum at 360px/200%; image crop/dimming/radii/caption matched recorded geometry and token mapping. Arbitrary ratio 1.37 to 2.72, contain/corner toggles, all constraint examples and outer scrolling inspected.
- Native interactive example: edited local draft, visible Tab focus, Enter increment, retained draft/counter/focus across ratio and live theme/direction changes; inner scroll preserved access to 200% text.
- Actual production OneboxCard, DiscourseTopicOnebox, LightboxThumbnail, ChatUploads, ChatPreviewBody and InlineVideo inspected using bundled image bytes on a temporary loopback-only fixture. Verified cover/contain/caps, ready/loading/error slots, GIF pause-to-play, gallery open/Escape, video lazy activation/pause/0:07 position retention/resizing/fullscreen/Escape. No real account data or video codec playback used.
- Full native styleguide search and registered Aspect Ratio preview inspected. After quitting only the isolated app, a subsequent global CUA app inventory returned no org.discourse.aspect-ratio-review entry; desktop slot released to coordinator. No real runner, SDK or system accessibility setting changed.
- Final component tests passed (5 tests, seed 1837891262) after ensuring semantics handles are disposed on assertion-failure paths as well as success.
- After marking the verified example group implemented, final shared styleguide page plus Aspect Ratio examples passed: 40 tests, seed 29227221. Final flutter analyze --no-pub and touched-file formatting passed; git diff --check was clean.
- Coordinator reviewed the arbitrary-ratio API and native RenderAspectRatio ownership, all media and Skeleton migrations, constraint/session regressions, exact source mapping and recorded native reference/media checks at stable HEAD bb218f825349d7df407f5cb6827bc955954de447. The package asset correction was verified in root and profiles/full. Preserved newer Label and all main workflow metadata while importing only this component row; the isolated app and its in-process loopback fixture server are closed.
- Coordinator integration check on main passed all 313 focused Aspect Ratio, actual media, Chat, Skeleton, styleguide and adoption tests (seed 837280413). All 32 Aspect Ratio examples also passed from profiles/full using the shared asset bundle (seed 1032379873). Root and profiles/full flutter analyze --no-pub passed without diagnostics; root/full flutter pub get --enforce-lockfile left pins and lockfiles unchanged. All 15 touched Dart files passed format checking and git diff --check passed. The generic component, examples and all migrated media/Skeleton source files are byte-identical to the native-inspected worker source. Logs: /private/tmp/component-aspect-ratio-integration-{tests,analysis}.log and /private/tmp/component-aspect-ratio-full-{tests,analysis}.log.

**limitations**

- The offline Discourse image intentionally replaces the remote Vercel avatar; app palette/font/radius variables and native glyph shaping differ from web defaults. Browser portrait height quantization is 284.4375px versus exact Flutter arithmetic 284.4444px. No unintended layout/style difference remained and no pixel-identical cross-renderer claim is made.
- No iOS/Linux device, VoiceOver speech or physical codec-playback check. The native media fixture mounted real widgets with a fake session; platform-override widget tests are not device checks.
- The full styleguide exposes fewer native AX nodes than the temporary harness, so its search/navigation used visible pointer targets; component child semantics and keyboard/focus behavior were inspected in the native harness and automated tests.

### avatar

Status: in_progress. Task: 01a082d2-4434-73b1-8ab4-88c9b2ba9b66. Branch: codex/ui-avatar.

### card

Status: in_progress. Task: 01a082d9-6c59-7443-8e64-f76105fd5e56. Branch: codex/ui-card.

### Final audit

Status: planned. Task: —. Branch: —.

