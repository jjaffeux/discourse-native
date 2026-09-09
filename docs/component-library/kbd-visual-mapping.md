# Kbd reference mapping

The 2026-09-09 source audit in [audit/kbd.md](audit/kbd.md) supersedes the
example and composition notes below; the measurements still apply.

The visual specification is the official [Base UI Kbd page](https://ui.shadcn.com/docs/components/base/kbd)
and its [base-nova registry source](https://ui.shadcn.com/r/styles/base-nova/kbd.json),
read on 2026-09-08. The frozen page hash remains
`3dd0b0dacf86f4b701ae35df3efe453ba1e9995a542e0a4a004a252f5bdd7978`;
the registry JSON SHA256 is
`4cfe2ba8e19f4d19d090eb039e3f1c041c9cfb379ce948237a9b5018203f7a6c`.
The catalogue has not changed. The page names `base-nova` as its component source.
The live reference was also rendered in a hidden browser in light and dark mode.
Computed styles confirmed 20 px height, 4 px horizontal padding and group gap,
12/16 px type at weight 500, no border, and a 6 px small radius from its 10 px
base. The app's default base radius is 4 px, giving a corresponding 2.4 px small
radius. Glyph widths follow each configured font; the reference uses Geist.

| Reference | Flutter implementation |
| --- | --- |
| Height and minimum width: 20 px; intrinsic width | `DKbd` has a 20 logical pixel minimum in both dimensions. Default text/icon keycaps are 20 px high. |
| Horizontal padding: 4 px; vertically centered | 4 px horizontal padding, no vertical padding, centered content. |
| Small sans-serif text, medium weight | `DiscourseTypography.xs`: 12 px, 16 px line height, weight 500 and zero tracking, using the host sans-serif family. Material text-role metrics cannot override these defaults. |
| Muted background and muted foreground | Live `DTokens.muted` and `DTokens.mutedForeground`; no border or shadow. |
| Small corner radius | Site base radius × 0.6, following the current [shadcn radius scale](https://ui.shadcn.com/docs/theming#radius). |
| Unspecified icon size: 12 px | Inherited icon size follows the 12 px small-label role, with matching foreground. Explicit child icon sizing is still possible. |
| Groups: centered items, 4 px gap | `DKbdGroup` centers items across each line with 4 px horizontal and run gaps. Optional separators remain ordinary children. |
| Inert, unselectable hint | `IgnorePointer`, `SelectionContainer.disabled`, spoken semantics, no focus node or action registration. |
| Tooltip foreground and translucent tint | `DKbdTheme` supplies the enclosing tooltip foreground and a 20% tint in light mode or 10% in dark mode, updated with its live theme. |
| Child/class customization | Typed text style, custom child, contextual colors and ordinary Flutter composition; group spacing/direction and spoken labels are explicit. |

The default geometry and appearance follow the reference. The following adaptations
resolve specific native requirements:

- A minimum height replaces the web's fixed height so native text scaling can
  enlarge labels without clipping. Groups wrap when constrained; text within a
  long keycap can wrap too. Both changes support the required narrow layouts and
  200% text. Icon scaling follows the same accessibility setting.
- The app's semantic palette and sans-serif typography remain live. The existing
  Tooltip uses a same-tone surface in some palettes, so its keycap tint follows
  its actual foreground. Literal web background-colored text would lose contrast
  on that surface. Tooltip positioning and the surface itself remain owned by
  the separately scheduled Tooltip component. The existing dark rail callout
  supplies its own matching foreground through the same scope.
- Existing optional hardware feedback remains an app extension: active keycaps
  use primary tokens, weight 600 and underline, with reduced-motion-aware
  transitions. Static/default keycaps retain the reference styling. The feedback
  listener never consumes keys or invokes actions.
- Apple modifier symbols and Linux modifier names describe the existing logical
  bindings. Sequence separators and spoken labels are presentation only. Custom
  compound children can use a row/group with 4 px spacing.

The seven public-library examples cover the frozen page's text/symbol, group,
inline text, button, tooltip, input-addon and RTL compositions, plus native
platform labels, feedback and scaling. They compose the available Button,
Tooltip and native TextField; their surrounding controls remain separate
catalogue entries. The reference button's outline and input's inline-end
position are composition props, not Kbd variants.

Verification includes a four-palette widget assertion of the default 20 px
geometry, 4 px padding/gaps, 12 px icons and type, medium weight, semantic colors,
small radius and absent border. Interaction, spoken semantics, lifecycle,
wrapping, RTL and live tooltip tests cover the native adaptations.

The corrected implementation was built and inspected in the isolated macOS app
`org.discourse.kbd.review4bea`, using the real styleguide and local-data harness
for the real search/help widgets. Light, Dark and Plum palettes, 360 px previews,
200% text, input focus/typing, RTL input layout, button click/F6, hover tooltips,
help mouse-wheel scrolling and Escape dismissal were inspected. Native AX
exported meaningful key/chord labels through the normal semantics lifecycle.
No VoiceOver speech or iOS/Linux device check is claimed. CUA's Command+K
injection reached Flutter as K with Meta false; that native chord remains
unverified, while logical macOS/iOS/Linux shortcut tests pass. Temporary signing,
diagnostics and fake-data harness changes are outside the repository.
The final explicit metric guard preserves the values used in that native
inspection. The first example was subsequently arranged into the reference's
two centered rows with 4 px gaps before the additional states; its final layout
is covered by the widget matrix, not a second native launch.
