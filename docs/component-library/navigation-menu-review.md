# Navigation Menu independent review

Reviewer: `01a08621-0e86-7a62-82b9-6a8eca71227f`.
Original implementation: `43ef3bca0725ed27f452ed141a6eda4bf120072e`.
Latest source fixes: `1bbdb00a`; current-main integration: `2141e109`.

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

After integration onto main `4d79219df5ddc4c51e80defb02a0eb607dd6a3dd`,
69 focused Navigation Menu, Popover and Combobox component/example tests pass
with seed 860606. Root and full-profile analysis report no issues. Every other
component row and the workflow match that main revision exactly; the normalized
progress hash with Navigation Menu removed is
`17bf8ee5b713bb9d98e4713fd75ed0d10f0e78475c62fa39f469096f83f531a0`.

The rebuilt, ad-hoc signed and deep-strict verified fixture is:

`/tmp/discourse-navigation-review.SF87jt/source/build/macos/Build/Products/Debug/Navigation Menu Review 43ef3bca.app`

Bundle ID: `org.discourse.navigationmenureview.r43ef3bca`.
Kernel SHA-256:
`2c7d7c9417233550384fe7c99ddfb2ac504a221a278f131df2997957cb199d98`.
Navigation Menu and its example source are byte-identical to `1bbdb00a`.
The fixture's Popover differs from the integration source only in documentation.

Further failing-before/passing-after regressions cover vertical arrow travel,
live orientation with an unchanged child and a real RTL destination callback.
The RTL callback exposed an inactive anchor read during inline-popup closing.
`1bbdb00a` retains the last inline anchor through exit and unregisters a custom
Popover anchor at deactivation rather than waiting for disposal. Permanent
removal and GlobalKey reparenting tests both pass; reparenting retains the open
popup and tracks its new position. This bounded shared-owner fix was coordinated
with the Popover reviewer and changes no API, default, Escape or layer policy.

## Remaining acceptance

The corrected fixture still needs native verification of trigger visuals,
panel switching/activation, keyboard dismissal/focus, controlled/dynamic/
disabled examples, inline RTL, and narrow 200% reduced-motion/custom palettes.
The desktop lease was released during the final rebuild. No corrected native
acceptance or final merge is claimed by this checkpoint. iOS, Linux and spoken
VoiceOver have not been run.
