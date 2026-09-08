# Component library progress

Generated from [progress.json](progress.json). Read the [brief](brief.md), [conventions](conventions.md), [catalogue](catalogue.json) and [inventory](inventory.md).

Coordinator task: `01a0816f-d4e0-7f93-9d6b-baeaf6961181`. Reference: 2026-09-08.

Foundation: **merged** on `codex/component-library-foundation`. Merge: 1b130d3323f9b7619bdead025fd76a57be402a97.

## Component implementation

| # | Component | Status | Task | Branch | Dependencies | Merge |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | direction | merged | 01a0818b-e20a-77d0-bb99-77691899dad7 | codex/ui-direction | — | e69458861e83f3989e2f06dd177805c572740a5a |
| 2 | typography | in_progress | 01a081e5-0bef-70a1-9ae3-7717028403e0 | codex/ui-typography | direction | — |
| 3 | spinner | planned | — | — | — | — |
| 4 | kbd | planned | — | — | typography | — |
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
| 19 | skeleton | planned | — | — | — | — |
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

Status: in_progress. Task: 01a081e5-0bef-70a1-9ae3-7717028403e0. Branch: codex/ui-typography.

### separator

Status: in_progress. Task: 01a08213-a2e5-7692-a127-f09d2a03094b. Branch: codex/ui-separator.

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

**limitations**

- Native inspection pending coordinator slot; no macOS runtime behavior is claimed yet.
- Linux device inspection is unavailable on this macOS host. Flutter devices also detected a wireless iPhone running iOS 26.6; it was not launched or controlled. iOS device behavior, VoiceOver speech and authenticated app screens remain uninspected; focused widget tests are not device verification.

### Final audit

Status: planned. Task: —. Branch: —.

