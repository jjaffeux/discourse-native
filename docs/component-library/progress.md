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
| 7 | separator | planned | — | — | — | — |
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
| 19 | skeleton | review_ready | 01a08213-b4ca-77e1-a2aa-8a490808243e | codex/ui-skeleton | — | — |
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

### skeleton

Status: review_ready. Task: 01a08213-b4ca-77e1-a2aa-8a490808243e. Branch: codex/ui-skeleton.

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

**limitations**

- No iOS or Linux runtime/device inspection. A wireless iPhone was discovered, but no iOS CUA session or device deployment was performed; no Linux device was available.
- VoiceOver speech was not inspected. Normal native AX exposed the actual topic/chat/pagination/sidebar loading labels and ready-state replacements; styleguide AX remained sparse apart from native menus/text inputs. Single-label semantics, hidden descendants, live-region opt-out and focus/pointer exclusion passed widget tests. No forced global semantics diagnostic was used.
- Final native form editing and saving passed. Empty-name validation, palette-retained form draft state and the source-corrected table scroll below 256px passed automated interaction tests but were not completed in the final native session. The earlier window-loss incident and unsuccessful native Select All/unsupported key names are recorded precisely in verification; no application crash is inferred.
- Authenticated live accounts were not opened. Actual migrated TopicListView, ChatChannelView, ChatMessageStream and InstanceSidebar were inspected natively with gated local fake data, including loading completion. Remaining migrated screens and broader loading/error/pagination/session behavior were covered by the focused core/Chat regression suites.
- Shared overlaps for coordinator reconciliation: discourse_ui.dart, component_examples.dart, tokens.dart, own progress row and app/test imports in topic_view.dart, topic_list_view.dart, draft_list.dart, instance_sidebar.dart, user_activity.dart, user_summary.dart and Chat. No other component branch was imported or merged.

### Final audit

Status: planned. Task: —. Branch: —.

