# Select reference mapping

Native Select was removed at the user's request on 2026-09-10. `DSelect` now
owns all plain and rich selection fields. Callers use explicit `enabled`
guards for busy or unavailable controls and null-valued options for clearable
placeholders. Production fixtures are available in
`tool/select_consumers_review.dart` and `tool/voice_review_fixture.dart`.
The source-preparation evidence below describes the earlier implementation.

Removal verification: 363 focused widget tests passed with seed `391447`,
covering components, styleguide examples and migrated application surfaces.
Root and `profiles/full` static analysis passed. Live native inspection was
not run because the shared desktop lease was occupied.

Task: `01a085bb-1d11-7f52-a7bd-667348469087`  
Branch: `codex/ui-select`
Reviewer task: `01a085e1-1106-7ba1-a30c-15a8a7a5bd22`
Reviewer branch: `codex/review-select`

## Source evidence

- Frozen shadcn/Base UI Select Markdown SHA256: `fc566bd829748e1caec337728e3198a951599be1c4c96f132e20d62266e2d0a9`
- Base Nova registry SHA256: `425e9b0a28b72617f18fabd75384050113295b88e7ba01c35bede2c72bd5d476`
- Prepared against tested Popover pin: `d99562f0f6973c9dc3f566eea02d9b00c6de4f7b`

The Popover pin is not accepted main. The Select reviewer must integrate accepted Popover main before final merge. The source-preparation branch was reconciled with accepted Native Select main metadata `5a26e5713719988f69930a7f02b3373b530d050a`, preserving its plain/simple consumers.

## Geometry and visual mapping

- Trigger height is 32px by default and 28px for small controls, with 14px text and 20px line height. At larger accessibility scales the control grows to retain the scaled line plus 10px (6px small) instead of clipping it; rows and group labels use the same intrinsic-line adaptation while preserving 28px pointer rows at 100% and 48px touch rows.
- Trigger padding follows the reference directional shape: compact leading content, trailing 16px chevron, input border and proportional token radii.
- Focus and invalid rings render outside the trigger so grouped or adjacent composition can preserve joined exterior geometry.
- Disabled state uses reduced opacity without replacing the trigger or item semantics.
- Popup minimum width is at least 144px. Popup uses Popover offset/collision behavior, an 8px-style rounded surface, border/ring/shadow, and foreground/background tokens.
- Popup rows are 28px pointer rows with check indicator space, item text, hover/highlight state and disabled-option skipping.

## Ownership mapping

- `DSelect<T>` is the public rich Select rendering owner and a `FormField<T>`.
- `DSelect.controlled` is the explicit controlled-null API.
- `DMultiSelect<T>` maps the Base UI multiple-selection mode.
- `DSelectItem`, `DSelectOption`, `DSelectGroup` and `DSelectSeparator` expose item/group/separator composition.
- `DSelectField<T>` remains only a source-compatible adapter for existing `DropdownMenuItem` and `InputDecoration` callers.
- `DPopover` remains the overlay lifecycle, dismissal and collision owner. Select uses its public placement hook for selected-row alignment and does not duplicate Popover.
- Borrowed `FocusNode`, `DPopoverController` and `ScrollController` are not disposed by Select.

## Behavior mapping

- Pointer, touch and keyboard can open the popup.
- Keyboard supports arrow navigation, Home/End, Enter/Space selection, Escape dismissal, Tab containment while open and typeahead.
- Selected-row alignment is used for keyboard/mouse opening when there is enough viewport room. Touch or insufficient-space openings fall back to edge-safe Popover placement.
- Focus restores to the trigger when the popup closes from option focus.
- RTL, text scaling, narrow layout and live theme changes are covered by focused widget tests.
- Repeated-letter typeahead cycles matching enabled options, modified shortcuts are ignored, and an externally controlled `open` transition enables/focuses the option nodes even when no internal open request occurred.
- Disabled selected values fall back to the first enabled focus target. Non-scrollable selected rows use their actual center for overlap placement; bounded lists reveal the selected row around the viewport center and expose working scroll arrows immediately.

## Independent review corrections

- Restored the documented disabled opacity and multiplicative dark input tint, including light/dark destructive border and ring alpha, and exposed invalid state through native validation semantics.
- Corrected controlled-open focus synchronization, disabled-selected focus fallback, no-current arrow navigation, repeated-letter typeahead, lower-half selected-row alignment and the initially inert scroll-down affordance.
- Added a real multiple-selection/custom-value styleguide example and focused regressions for every correction, including measured 200% trigger/row growth.

## Button Group composition

Button Group's currency example uses public `DSelect`, with the accepted Popover retaining popup ownership. Select's own Button Group example now uses `DButtonGroup` for Back, Range and Next; a horizontal viewport keeps the complete joined control reachable at narrow widths and large text. Adjacent actions and controlled selection remain independent, and popup content remains outside the joined geometry.

## Source-preparation verification

- Reconciled source head: `f3966666d772f5835a804a17f86eacb5bdf30a37`
- `flutter test --no-pub test/d_select_test.dart test/preferences_page_test.dart test/assignment_sheet_test.dart test/voice_room_view_test.dart --test-randomize-ordering-seed=391447`: 115 passed.
- Root and `profiles/full` `flutter analyze --no-pub`: no issues.
- `flutter build macos --debug --no-pub -t lib/styleguide_main.dart`: succeeded without launching the app.
- Built kernel SHA256: `a20eb06d6f350a0d2cec122b1ddcd3f873c9d4f88772fd443c8ba0abe057383d`; application identifier `org.discourse.native.dev`; `CDHash=059b47bf1c10d2135b76bdaca92f5316ee920185`; `TeamIdentifier=6T3LU73T8S`.
- `git diff --check`: clean.

Rendered browser comparison and native interaction acceptance remain reviewer-owned.
