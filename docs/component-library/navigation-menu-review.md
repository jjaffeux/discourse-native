# Navigation Menu independent review

Reviewer: `01a08621-0e86-7a62-82b9-6a8eca71227f`.
Original implementation: `43ef3bca0725ed27f452ed141a6eda4bf120072e`.
Latest source fixes: `1bbdb00a`; current-main integration: `f1bb59ce`.

## Rendered reference and findings

On 2026-09-09, approved browser control opened the official
<https://ui.shadcn.com/docs/components/base/navigation-menu> page. The reviewer
inspected settled dark and light Getting started panels, Components switching,
and the With Icon panel. ArrowDown opened content and exposed expanded trigger
semantics. Settled screenshots showed the upward open chevron, muted active
trigger, full-width link highlight, left-aligned title/description and compact
rounded popup. With Icon showed distinct backlog, pending and completed icons.
The temporary reference tab was closed and its initial dark theme restored.

The frozen registry geometry remains the baseline (hashes in progress.json).
The current site's demo does not display an indicator; the Flutter composition
also demonstrates the frozen registry's optional indicator anatomy. Native
route callbacks replace web destinations, and the host owns live palette tokens.

The first actual macOS inspection successfully opened Basic in the isolated
app. It exposed stale trigger visuals/expanded semantics while the popup was
open, and centered instead of full-width Getting started links. Source review
identified the mutable inherited-state comparison and indicator clipping.
The new regression failed before the fix and passes afterward:

- Capture an immutable selected value in the inherited scope, so opening,
  switching and closing rebuild both trigger visuals and expanded semantics.
- Preserve horizontal overflow clipping while allowing the six-pixel indicator
  strip below the trigger; constrain its rotated diamond to eight by eight.
- Stretch rich content links across their panel and distinguish example icons.

Earlier review fixes cover true single-stop roving focus, direct-link arrow and
Home/End navigation, focused-item visibility at 200% in LTR/RTL, controlled
reconciliation, dismissal focus policy and borrowed-controller disposal.

## Verification

After integration onto main `2b9797fe047d14ce59c6080ea214337b0114dc96`,
98 focused Navigation Menu, Popover, Combobox and Button Group tests pass
with seed 860606. Root and full-profile analysis report no issues. Every other
component row and the workflow match that main revision exactly; the normalized
progress hash with Navigation Menu removed is
`af9ab3e1db1c31a78f22051f0cbc84673f48d67c0d69749688003c84488270b7`.

The rebuilt, ad-hoc signed and deep-strict verified fixture is:

`/tmp/discourse-navigation-review.SF87jt/source/build/macos/Build/Products/Debug/Navigation Menu Review 43ef3bca.app`

Bundle ID: `org.discourse.navigationmenureview.r43ef3bca`.
Kernel SHA-256:
`ca1ab6d1d9dfe4e36f3c8551e2bd82931821ef5c0f3d9d5fb6007c65b9c32464`.
Navigation Menu and its example source are byte-identical to `1bbdb00a`.
The fixture's Popover differs from the integration source only in documentation.
It includes the accepted Button Group popup boundary and byte-identical
joined-control foundation, reconciled in `3c11feff`.

Reconciliation `f1bb59ce` onto main `3178784b` leaves Navigation Menu, Popover
and the examples unchanged, so the source-specific test/build evidence remains
valid. Root/full-profile analysis passed again. All other progress rows and
workflow match that main revision (normalized hash with Navigation Menu removed:
`b06ac1979bec82649e0877f5f7e88b8bf3205d8c0aa86be998cd6df9a679141c`).

Further failing-before/passing-after regressions cover vertical arrow travel,
live orientation with an unchanged child and a real RTL destination callback.
The RTL callback exposed an inactive anchor read during inline-popup closing.
`1bbdb00a` retains the last inline anchor through exit and unregisters a custom
Popover anchor at deactivation rather than waiting for disposal. Permanent
removal and GlobalKey reparenting tests both pass; reparenting retains the open
popup and tracks its new position. This bounded shared-owner fix was coordinated
with the Popover reviewer and changes no API, default, Escape or layer policy.

## Corrected native acceptance

After the user's unlock confirmation and Avatar's ordinary-CUA recovery report,
this reviewer acquired desktop lease `8caace62449840aa979e9d23c07e9aae` at
2026-09-09 18:55:09 UTC. A fresh normal CUA session launched the exact-source
fixture above. Actual native AX states and screenshots verified:

- Dark/current and light Basic panels: active trigger background/upward chevron,
  left-aligned full-width links, compact popup and distinct icon-link symbols.
- Getting started → Introduction, With Icon → Done and the direct Documentation
  link update destination output; panel destinations dismiss the popup.
- Components exposes its two-column content. Logical arrow traversal and Down
  enter the first content link; Escape closes and visibly restores focus to
  Components. The current-page example highlights Documentation and routes to
  Examples, closing its popup and reporting `/examples`.
- Disabled does not open; Dynamic opens under parent control. Remove dynamic
  removes the open entry and popup; Restore dynamic restores the entry.
- Forest palette at 360 px, 200% text, RTL and reduced motion: the inline Arabic
  popup remains bounded and activates Introduction without the former inactive
  anchor exception. Basic Home/End reveal both the first trigger and offscreen
  Documentation link with visible focus. Down/Tab/Tab scroll the constrained
  popup to Typography; Return activates it and Reset clears the output.

The official rendered Arabic RTL example was also opened with ArrowDown and
inspected: right-aligned trigger order, upward chevron, right-aligned content and
focused-link highlight agree with the platform adaptation. This supplements
the earlier settled light/dark and icon-panel reference comparison.

Both temporary reference tabs are closed. The corrected native app was quit
through its own native menu; a scoped process check found no running fixture.
Desktop lease released before main integration. All review acceptance gates
are satisfied for the recorded source and representative native scenarios.
iOS/Linux devices and spoken VoiceOver were not run. Hover timing, controlled
rejection, vertical/live orientation and anchor reparenting are covered by
focused widget regressions rather than separate native scenarios.
