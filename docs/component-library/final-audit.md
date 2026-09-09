# Final component library audit

Audit owner: `01a0879a-c563-7fa0-a5df-49654971f6da`  
Audit branch: `codex/review-component-library-final`  
Initial base: `979ddf76ce50c0b32c6fee2ef599f03175c03139`

## Scope and conclusions

The frozen 2026-09-08 catalogue contains 64 unique component IDs. The durable
progress record contains the same 64 IDs exactly once in dependency-topological
order, and every component plus the four required final-composition follow-ups
is accepted and merged in local main ancestry. The existing rendered/browser
and native evidence remains the source-specific acceptance record for unchanged
components; this audit did not relabel widget-test captures as native checks.

The integrated source keeps one reusable rendering owner per component under
`lib/src/ui/components`, with public access through `discourse_ui.dart`.
`d_questionnaire_controller.dart` is intentionally split and re-exported by
`d_questionnaire.dart`. `src/shell/select.dart` is the documented compatibility
export for the accepted Select owner, not a second renderer. Generic components
have no Discourse data, networking, shell, store or plugin imports.

The audit found no substantiated missed production migration that could be made
without changing domain behavior. In particular, EventCalendar and
TopicCalendar still use `kalender` 0.29.1 through the shared theme while keeping
their event/domain controllers. The three retained Material date flows are
already documented Date Picker alternatives because they coordinate combined
date-time, account-zone/DST or guarded expiry behavior. The styleguide remains
available from the real app's bottom-left rail and uses the shared responsive
Sidebar.

## Fixes

- Marked Drawer implemented in the live styleguide and replaced its obsolete
  pending-review note with the accepted macOS/native limitation.
- Reconciled stale dependency-era notes for Tooltip, Aspect Ratio, Textarea,
  Label, Switch and Collapsible after their Button/Input/Field owners merged.
- Replaced Label's temporary Material `TextFormField` example with the accepted
  DField/DInput composition. The example owns and disposes its FocusNode while
  Form/DInput remain the validation, editing and reset owners.
- Added a catalogue regression requiring all 64 frozen components to be
  registered, implemented, described, documented, backed by at least one
  non-empty usage snippet, and free of duplicate example titles. Foundations is
  the only permitted extra documentation page.
- Removed the six stale `workflow.resume.activeTasks` entries only after their
  component rows, reviewer identities and accepted merge commits were verified.
  Their historical implementation/review provenance remains in the rows.

## Verification

- Locked dependency resolution passed at the repository root and
  `profiles/full` without lockfile or Flutter-pin changes.
- Baseline root and `profiles/full` `flutter analyze --no-pub` passed.
- The full styleguide test directory passed 367 tests with randomized seed
  `9092026` before fixes, establishing the integrated starting point.
- The focused post-fix matrix passed 100 tests with randomized seed `9092028`:
  styleguide page, Drawer, Label, Aspect Ratio, Tooltip, Textarea, Switch and
  Collapsible coverage.
- On the current-main candidate, root and `profiles/full` analysis passed and
  the complete styleguide plus DCalendar, DDatePicker, EventCalendar and
  TopicCalendar matrix passed all 415 tests with randomized seed `9092029`.
- The exact `f15c6f67` source built as a macOS debug styleguide. The isolated
  bundle used identifier
  `org.discourse.native.component-library-final-audit.f15c6f67`; copied and
  built kernels both have SHA-256
  `44554591e7f4241107cbc681643ec109cdf78eec25e9d630c629863e24fc0095`.
  Deep strict ad-hoc signature verification passed with the repository's seven
  permitted debug entitlements and no push, team or application identifier.
- Actual macOS inspection confirmed the responsive shared Sidebar exposes all
  64 component destinations. Drawer has no pending banner; its delivery example
  opened, exposed bounded radio controls, accepted another time and returned
  `Confirmed: 5:00`. Label's reconciled DField/DInput form rendered with shared
  geometry and accepted editable focus. The isolated app was quit and process
  disappearance confirmed. No browser comparison was repeated because the
  changed visuals compose already accepted component owners and Drawer's frozen
  reference/native evidence is unchanged.

The current-main candidate was merged locally with `--no-ff` as
`2b79f083247b2edd53353e873fde56e354acedf1`. The follow-up tracking commit is
recorded in `progress.json`; no remote or release action was performed.

## Intentional limitations

- This audit ran an actual macOS pass only. It does not claim iOS/Linux device
  testing or spoken VoiceOver/TalkBack verification.
- Font rasterizers can differ between the frozen browser reference and the host
  native renderer; the accepted component evidence establishes the documented
  geometry, styling, interaction and semantic mappings rather than pixel
  identity across rasterizers.
- Persian/Hijri/Jalali chronology remains an honest Kalender engine seam. The
  library does not mislabel Gregorian paging as an alternate calendar system.
