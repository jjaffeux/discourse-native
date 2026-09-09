# Button Group native acceptance

Date: 2026-09-09. Reviewer: `01a085f4-2a6b-7c82-9dc3-c9b14d76b355`.

Inspected source: `cff5dfc2b34035806d29ab551f25b5908515c018`.
The exact isolated `/private/tmp/ButtonGroupReview-cff5dfc2.app` build,
source hashes, copied kernel hash, restricted signing and bundle identity are
recorded in [native-preparation.json](native-preparation.json).

The reviewer held the serialized desktop lease for all native actions. The
approved CUA surface bound to the exact app path after a fresh session reset;
native clicks, literal text entry, Tab, arrows, Escape, accessibility trees and
screenshots worked. The app was quit through its native menu and the lease
released after inspection. The normal account app and provisioning were not
modified. Screenshot and AX observations are retained in the review task's
tool history; no separate automated native image-diff baseline is claimed.

## Observed acceptance

All 13 fixture pages use the real public examples, including the two parent
closeouts, and the app bar mounts production `ContentNavigationControls` with
an offline shell. Light, dark, Forest and Plum palettes were inspected across
the pages. Native width controls exercised 440/320px, text controls 100/200%,
and direction controls LTR/RTL. Reduced motion was enabled throughout.

- Composition: separate Archive and Report actions changed the displayed
  result independently; disabled Snooze did not change it. Named action and
  navigation boundaries retained distinct accessible button children. Joined
  artwork had compact equal-height controls, outside corners and single seams.
- Orientation and sizes: vertical Zoom actions had the correct top/bottom
  join; small/default/large text and icon groups had distinct compact sizing.
- Nested groups: entering `draft` used the actual editor. Tab reached the
  separate Voice mode action, with a complete visible exterior focus ring;
  the editor retained its text and nested controls retained their own shape.
- Separator/split: the separator fitted the compact Create/+ group instead
  of expanding the group to the fixture's height.
- Field/input/text: the label focused the editor. `retained query` survived
  the Search action's invalid state, a dark-theme change, and Forest at RTL,
  200% and 320px. Invalid label/ring and wrapping description remained visible,
  with separate field, passive text and action semantics and no overflow.
- Input Group composition: `voice note` survived enabling voice mode (editor
  became noneditable while its text remained exposed), disabling voice mode,
  and changing Forest/RTL/200% to Plum/LTR/100%. Attachment and voice actions
  remained separate from editing and from the outer joined geometry.
- Dropdown Menu: the joined More follow actions trigger opened four distinct
  actions on a separately rounded popup. Arrow input highlighted an item;
  destructive styling was visible. Escape removed the popup and restored a
  complete visible exterior ring on the joined trigger.
- Currency Select: typing `42.50`, opening the three-option popup and choosing
  Euro updated the currency to `€` without changing the amount. The popup
  retained independent rounded corners; trigger focus was visibly restored.
- Popover: the Copilot split trigger opened the separate rounded task surface
  with its heading and description. Escape removed the surface and restored
  the trigger's exterior focus ring.
- RTL: Arabic Archive and Report each produced their corresponding result;
  the visual order and logical outside edges were mirrored.
- Select parent: Next changed `Actions: 0, mode: week` to
  `Actions: 1, mode: week`; choosing Month then produced
  `Actions: 1, mode: month`. Back/Range/Next remained separate accessible
  controls inside the real joined group at 320px.
- Input Group parent: literal editing was reflected in the Search result.
  Loading exposed `Search, Value: Loading` and retained the edited value
  across a light-to-dark change. Clear remained independently actionable,
  emptied/focused the search editor and displayed `Cleared`. Finishing loading
  restored Search; editing the separate URL field and Copy displayed
  `Copied URL`. The system clipboard payload was not independently read.

## Limits and source-equivalent closeout

The production navigation fixture exposed the actual three controls and their
geometry/semantics but its offline empty shell disables history navigation.
Active shell history, shortcuts and refresh callbacks are covered by the
focused production widget tests, not claimed as authenticated native tests.
Spoken VoiceOver, physical iOS/Android devices and Linux were not exercised.
Browser/native comparison is qualitative because font rasterization differs.

The fixture-only page heading used a context above `MaterialApp`, so its text
was too dark in dark/Plum palettes. Closeout wraps only that heading in a
`Builder` to read the selected theme; actual component/example contexts,
controls, layout and state ownership are unchanged. This heading correction
is statically verified, not represented as a new native capture. Promoting
Button Group's catalogue status to implemented is acceptance metadata only.
The completed component pass is retained for these source-equivalent changes,
as required by the review protocol. Any final-main overlap is recorded
separately with affected verification.

## Nested-spacing correction — 2026-09-10

The live Base UI Nested example was re-inspected after a visual mismatch was
reported. Its outer group measured 252px wide and applied an 8px gap between
the 32px attachment group and the 212px composer group. The voice affordance
was inside the composer's single rounded Input Group surface.

The corrected candidate was then built from
`tool/button_group_review_main.dart` and inspected through the exact debug-app
path while holding the desktop lease. Light/LTR/100% at a 440px fixture width
and dark/RTL/200% at 320px both showed the two complete rounded groups, the 8px
gap, and the voice action inside the input surface. Native accessibility exposed
the named outer group, attachment button, composer field, and voice button as
separate descendants. Spoken VoiceOver and physical mobile devices were not
exercised in this follow-up.
