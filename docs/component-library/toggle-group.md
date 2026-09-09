# Toggle Group reference mapping

Frozen reference date: 2026-09-08. Source inspection: 2026-09-09.

## Sources and acceptance

- Documentation: `https://ui.shadcn.com/docs/components/base/toggle-group`
- Frozen Markdown: `https://ui.shadcn.com/docs/components/base/toggle-group.md`
- Frozen Markdown SHA-256: `a24be2fab3d5a4bc103d27c39f046530191c526ff6c970e19919aebcf2cd1702` (reproduced exactly)
- Registry: `https://ui.shadcn.com/r/styles/base-nova/toggle-group.json`
- Registry response SHA-256: `9f103af4a048ec392cb09b886985ec733a360a0033cc7138349f1775851a89d4`
- Behavior API: `https://base-ui.com/react/components/toggle-group.md`
- Behavior Markdown SHA-256: `4a19b1f1ed82381e3ca03ef4745875e2bfe59f6e84de52e20376f777c9cecf31`

Acceptance requires single and multiple generic value selection, Base UI's
clearable single selection, controlled/local/borrowed-controller ownership,
ordered change values, dynamic items, group and item disabled policies,
horizontal/vertical orientation, looping roving arrow focus and Home/End.
The complete documented Default/Composition, Outline, Size, Spacing, Vertical,
Disabled, Custom and RTL examples must remain interactive. Live palette, font,
radius, direction, scaling and reduced-motion changes cannot reset selection.

## Source-to-Flutter mapping

CSS pixels map one-to-one to Flutter logical pixels at 100% text scale.

| base-nova / Base UI source | `DToggleGroup<T>` |
| --- | --- |
| `flex w-fit`, horizontal default | axis `Flex` with horizontal default and compact content |
| `orientation="vertical"`, `items-stretch` | vertical `Flex`, stretched item widths and Up/Down navigation |
| 2026-05-17 `spacing=2` default | two 4px units = 8 logical pixels; `spacing=1` is 4px |
| `spacing=0`, `rounded-none` | connected items remove inner corners |
| joined `px-2`, icon-side `p*-1.5` | connected text items use 8px horizontal padding, reduced to 6px on an inline icon edge; standalone Toggle retains its accepted 10px |
| outline `border-l-0` / `border-t-0`, first edge restored | one logical leading/top shared seam without double-width borders |
| first/last `rounded-l/r/t/b-lg` | direction-aware exterior group corners using the live host radius |
| `focus:z-10`, `focus-visible:z-10` | each real `DToggle` paints its outside-only focus ring above adjacent seams |
| `size=sm/default/lg` | accepted Toggle 28/32/36px artwork and 14/16px icons |
| `value`, `defaultValue`, `onValueChange` arrays | `values`, `initialValues`, `onChanged` typed immutable lists |
| `multiple=false` | one pressed value at a time; activating it again yields an empty list |
| `multiple=true` | independently pressed items, emitted in declaration order |
| `loopFocus=true` and orientation | direction-aware arrow roving, disabled-item skipping, Home/End and optional edge stop |

`DToggle` remains the only visual, activation and pressed-semantic owner.
`DToggleGroup` supplies values, geometry and focus coordination. A caller-owned
controller and item focus nodes are borrowed, never disposed, and borrowed
focus traversal flags are restored when removed or when the group disposes.
Internally created focus nodes and local selection are group-owned.

The reference does not require a selection. `allowEmptySelection` therefore
defaults to true; native required-choice adapters may set it false. A controlled
group without `onChanged` is noninteractive, matching the accepted controlled
Toggle convention. Narrow groups scroll along their axis by default rather
than overflowing; compact reference artwork remains unchanged. Touch platforms
retain Toggle's invisible 48px target while desktop artwork stays compact.

## Documented examples and Field composition

The styleguide covers the lead multiple outline icon group; text outline;
small/default sizes; default 8px, connected 0px and vertical 4px spacing;
vertical multiple selection; disabled state; Arabic RTL; controller/dynamic
items; and the controlled four-tile font-weight Custom example. The custom
tiles are 64px minimum squares with 24px/24px `Aa`, 12px/16px captions and
`xl` radius (`1.4 ×` live host radius). They grow under text scaling.

The frozen Custom example is a `FieldLabel + ToggleGroup + FieldDescription`
composition. After Field's accepted local-main merge at `5cd7f369`, the example
now uses `DField`, `DFieldLabel` and `DFieldDescription` directly. The group
remains the owner of its multiple independent pressed controls, so the accepted
Field contract intentionally does not place a `DFieldControl` around it.

## Application audit

The composer gallery grid/carousel selector is a genuine required single
selection. It now uses a controlled `DToggleGroup<ComposerGalleryMode>` while
`ComposerMediaEditingCoordinator` and `ComposerController` retain markup,
selection, editor-focus and callback ownership. The group uses connected
spacing 0 and 48px targets inside the horizontally scrollable toolbar.

Rich-editor bold/italic commands remain momentary transformations: their
visual state follows the current text selection and activation mutates markup,
so they are not persistent Toggle Group values. Forum, topic, group and
preferences tabs remain navigation. Radio/checkbox/switch settings retain
their semantic owners. Image carousel paging remains `DCarousel`; selecting
grid versus carousel markup is distinct from rendering a carousel.

The remaining Material `SegmentedButton` sites were inspected independently.
Diagnostics kind and content-alignment controls intentionally fill their field;
topic-move and update-channel choices select form/settings modes; revision and
calendar selectors are navigation/view adapters, with the calendar also using
an app-specific primary selected surface. They retain selected-choice ownership
and geometry rather than being recast as compact pressed-button groups during
this migration.

## Prepared verification boundary

Source implementation: `d6a9be0d00c160dffa7daf67e8f2f4cefa00c336`.
Latest-main integration handoff: `1f97c825115e5511d857ec255bd875bf6ec34398`.
Reviewer: `01a085e6-4bb7-7e13-9e2a-98992292b4b3` on
`codex/review-toggle-group`.

The implementation task verifies source hashes, focused component/styleguide
tests, composer consumer regressions, root and full-profile analysis, and a
macOS source build. Official rendered comparison and actual native interaction
remain required and are owned by the new independent reviewer. No physical
iOS/Linux device or spoken VoiceOver claim is made.
