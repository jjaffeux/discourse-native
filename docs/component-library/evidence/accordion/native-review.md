# Accordion independent rendered and native review

Review date: 2026-09-09

Reviewer task: `01a085b9-6a74-7181-8252-f5bbe9c6e05b`

## Review inputs

- Official rendered reference: <https://ui.shadcn.com/docs/components/base/accordion>
- Frozen source and source-to-Flutter measurements:
  `docs/component-library/accordion-reference.md`
- Styleguide bundle:
  `build/macos/Build/Products/Debug/Accordion Review c44f.app`
  (`org.discourse.accordionreviewc44f`)
- Final embedded/build kernel SHA256:
  `4aa2785f5a67437389be0bb82516afa130e549e09a7584e1fc182dd4ccd81a2d`

The uniquely identified macOS debug bundle was built from review source commit
`8f24147b7870eebb55debd28d304eccb0cff0f07`. Its embedded kernel matched the
build kernel byte-for-byte, its entitlements contained only the expected
sandbox, JIT, file, network, audio, camera and debug allowances, and it passed
a deep strict ad-hoc signature check before launch. Temporary identity and
signing edits were restored byte-for-byte; dependency pins and lockfiles were
unchanged.

## Official browser inspection

The live Base UI page was inspected in light and dark themes across Basic,
Multiple, Disabled, Borders, Card and RTL. Pointer activation in Basic replaced
the open panel, Multiple retained independently open panels, and the disabled
trigger rejected pointer activation. Enter activated a focused trigger and the
focused state showed the documented border plus exterior ring.

Read-only rendered measurements confirmed 14/20 medium trigger text, 10px
vertical padding, 16px chevrons, logical start/end alignment, host radius,
50% disabled opacity, hover underline, no pressed fade, and a one-pixel focus
border surrounded by an exact three-pixel 50%-alpha ring. The browser's
transparent one-pixel border produces a 42px border box; the native mapping
retains the documented 40px desktop artwork and adds a 48px touch target on
touch platforms.

## Native macOS inspection

The styleguide rendered all seven Accordion examples. Basic supported pointer,
ordinary Tab, Return and Space activation with a visible exterior focus ring.
Multiple kept all three panels independently open. Disabled remained
discoverable but rejected pointer and keyboard activation. Borders preserved
the rounded root, 16px inset, undoubled final divider and unclipped focus ring.
Card used the accepted Card composition, and RTL reversed logical alignment and
chevron placement.

Dark/current, light and Forest custom palettes retained contrast and state
hierarchy. The first 360px/200% RTL pass exposed a clipped final row; the review
increased the Accordion preview to its measured 800px requirement and added a
widget-level bounds regression. The corrected preview showed every row before
the viewport boundary. Reduced motion changed panel state immediately without
an intermediate clipped frame.

The controlled example retained an edited native text field through collapse,
reopen and item reorder, kept both panels independently open, and rejected
activation while root-disabled. Native inspection then exposed stale controlled
state when an open dynamic item was removed. The example now prunes that value;
the final native follow-up confirmed the live state changed from
`profile, security` to `profile`, and re-adding Security left its panel closed.

The macOS accessibility tree exposed each heading trigger as one bounded button
and panel copy and the retained text editor as independent descendants. Widget
tests additionally cover expanded/button/header semantics, hidden-panel
exclusion and focus restoration. No spoken VoiceOver claim is made.

## Corrections made during independent review

- Corrected borrowed-controller to local-controller transitions, including
  simultaneous single/multiple mode changes.
- Removed duplicate null keys from unkeyed items and captured root disabled and
  outlined scope state so reused children rebuild correctly.
- Preserved focus geometry outside outlined clipping and painted the reference
  ring as an exact exterior band, including non-uniform radii.
- Removed an undocumented pressed-opacity fade.
- Increased the styleguide preview to keep the RTL 360px/200% sample visible.
- Pruned removed values from the controlled lifecycle example.

## Scope and limitations

- Native device inspection was macOS only. No iOS or Linux device was run and
  no spoken VoiceOver claim is made.
- Browser Geist and native host font rasterization differ, so this review does
  not claim pixel equality. It compares geometry, palette/state mapping,
  direction, interaction and semantic ownership.
- No application migration was made because the audited production disclosures
  are independent Collapsible owners rather than coordinated Accordion groups.
