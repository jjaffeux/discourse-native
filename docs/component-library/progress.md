# Component library progress

Generated from [progress.json](progress.json). Read the [brief](brief.md), [conventions](conventions.md), [catalogue](catalogue.json) and [inventory](inventory.md).

Coordinator task: `01a0816f-d4e0-7f93-9d6b-baeaf6961181`. Reference: 2026-09-08.

Foundation: **merged** on `codex/component-library-foundation`. Merge: 1b130d3323f9b7619bdead025fd76a57be402a97.

## Sequential implementation

| # | Component | Status | Task | Branch | Dependencies | Merge |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | direction | in_progress | 01a0818b-e20a-77d0-bb99-77691899dad7 | codex/ui-direction | — | — |
| 2 | typography | planned | — | — | direction | — |
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

Status: in_progress. Task: 01a0818b-e20a-77d0-bb99-77691899dad7. Branch: codex/ui-direction.

### Final audit

Status: planned. Task: —. Branch: —.

