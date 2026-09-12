# Button Group reference and acceptance mapping

Reference date: 2026-09-08. The frozen Base UI Markdown at
`https://ui.shadcn.com/docs/components/base/button-group.md` was downloaded
again on 2026-09-09 and its SHA-256 verified as
`9118d89c3e715a7e77ec0454be6a276c24d114c8b3099505bb463487e9545eda`.
The inspected registry source was
`apps/v4/registry/bases/base/ui/button-group.tsx` at the upstream `main` view;
its downloaded bytes had SHA-256
`23c66d61df078fb1604fa7ba3ad8d16550adbb2243af36584bb94d62f014914f`.
The twelve linked Base example sources were also downloaded and inspected.

## Source-to-native mapping

| Frozen source behavior | Native implementation |
| --- | --- |
| `role="group"`; author supplies `aria-label`/`aria-labelledby` | `Semantics(container: true, explicitChildNodes: true, label: semanticLabel)` creates a named boundary while retaining separate descendant controls. Flutter exposes no generic group `SemanticsRole`. |
| Horizontal `flex w-fit items-stretch` | `DButtonGroupOrientation.horizontal` uses normal Flex layout for controls and then sizes separators to their cross-axis extent; a caller can use max size plus `DButtonGroupExpanded` in a finite parent. The implementation avoids intrinsic measurement because rich controls such as `DSelect` use `LayoutBuilder`. Standard controls share the reference height. |
| Vertical `flex-col` | `DButtonGroupOrientation.vertical` uses vertical Flex layout; horizontal separators stretch to the widest control without imposing intrinsic measurement on arbitrary child controls. |
| First/last outer radii; square joined corners | A direct-child `DJoinedControlScope` resolves logical corners from live token or explicit control radii. RTL mirrors start/end. Nested groups install their own scope. |
| Later direct controls use `border-l-0` or `border-t-0` | The grouped `DButton` outline omits only its painted leading edge, preserving the other three borders and all focus/invalid rings. `DInput` uses the same joined radii and custom animated surface decoration so its shared leading edge is omitted without changing editing, focus, invalid or disabled behavior. |
| `*:focus-visible:relative *:focus-visible:z-10` | Each control owns visible focus. Passive, non-tabbable focus listeners identify the direct child to paint last, preserving its unclipped 3px exterior ring over adjacent surfaces. Layout, hit targets and ordinary Tab order remain unchanged. |
| Direct input uses `flex-1` | `DButtonGroupExpanded` is an explicit Flutter layout adaptation for any flexible child in a finite-width max-size group. Editing/controller/focus ownership stays with `DInput`. |
| Nested groups | An outer group adds the reference 8px gap when one of its direct layout children is another group. `DButtonGroupExpanded` is transparent for that check, and every nested group independently scopes its own controls. |
| `ButtonGroupSeparator`, default vertical, self-stretch, one-pixel cross-axis inset | `DButtonGroupSeparator`, default `Axis.vertical`, delegates live color and semantics to final `DSeparator` and applies the reference one-pixel inset. Horizontal is explicit for vertical groups. |
| `ButtonGroupText` rich render content aligned with controls | `DButtonGroupText` accepts any child, directional padding/alignment, live typography/icon tokens, and optional semantics replacement. It stays passive and unfocusable. |
| Buttons remain independent actions | The group owns no selected value, controller, callback, or arrow-key navigation. `DButton` callbacks, disabled/loading/invalid state, focus nodes, popup state, semantics and keyboard activation are unchanged. |
| Pointer/touch targets | Final `DButton` retains compact 24/28/32/36px desktop artwork and its existing native 48px touch targets. Group layout does not add hit-test gaps or handlers. |
| Live palette/font/radius, reduced motion | Children and text read `DTokens`/theme on every build. The scope stores only structural position, never colors, font, radius, controllers or state. Existing child motion uses `DMotion`. |

## Frozen compositions

The styleguide registers runnable sections for Composition, Orientation, Size,
Nested, Separator, Split, Input, Input Group, Dropdown Menu, Select,
Popover, and RTL. It also explains Button Group versus Toggle Group and
demonstrates the three public API parts. Each dependency composition now mounts
its public component: the documented Input example directly joins `DInput` and
its search action; `DInputGroup` owns its nested editor/addon surface;
`DDropdownMenu` owns split-menu focus and dismissal;
`DSelect` is the sole direct joined currency trigger; and `DPopover` owns its
detached content. `DJoinedControlScope.boundary` prevents popup descendants
from inheriting the trigger's joined geometry.

## Concrete acceptance criteria

- Horizontal and vertical groups retain only outside corners and do not double
  the painted leading `DButton` outline.
- RTL mirrors logical outside corners and visual order without changing source
  callback order or labels.
- Nested groups reset direct-child scope; popup/menu content does not inherit a
  broad button theme or radius override.
- Text and separators are passive; every action and field retains its original
  native role, focus, callback, editing state and enabled/invalid state.
- Tab reaches buttons and fields independently. The component provides no
  toggle selection or toolbar arrow-key contract.
- Small/default/large text and icon groups, narrow horizontal scrolling,
  200% text, light/dark/custom live tokens, reduced motion and 48px touch targets
  remain usable without changing local state.
- The styleguide accounts for every frozen documented composition and its code
  snippet uses the public library API.
- At least one appropriate production independent-action row adopts the group,
  with focused regression coverage for its existing callbacks and shortcuts.

## Official rendered inspection

The official Base UI Button Group page was inspected on 2026-09-09 in both
light and dark themes. The rendered examples confirmed compact equal-height
joined surfaces, one-pixel shared seams, logical outside radii, independent Tab
stops, the split Dropdown Menu, a three-option currency Select whose popup keeps
its own radius, and the full documented Composition, Orientation, Size, Nested,
Separator, Split, Input, Input Group, Dropdown Menu, Select, Popover and RTL
sections. Escape closed both inspected overlays and returned focus to their
triggers. The source hashes above remain the byte-level reference record.

## Application audit

`ContentNavigationControls` was migrated from a bare `Row` to a labeled
`DButtonGroup`. Back, forward and refresh are independent related actions (not
selection), and their existing shell callbacks, permission/enabled guards,
refresh lifecycle, shortcuts, tooltips and keys remain untouched.

Retained alternatives:

- `ForumTabsBar` and preferences/topic tab rows are navigation/selection and
  remain Tabs rather than being misrepresented as independent actions.
- Radio/checkbox/switch/toggle rows retain their selection owners; Button Group
  must not absorb Toggle Group semantics.
- Dialog and sheet action rows remain spaced/wrapping actions because joining
  destructive confirmation and cancellation would change their established
  modal presentation and narrow-layout behavior.
- Inline video failure link actions remain unjoined links rather than a split
  control; their destinations are separate alternatives and the row wraps.
- Composer toolbars remain overflow-aware toolbars. Their menu/navigation
  behavior and dynamic plugin ownership require the dedicated Toolbar/Menu
  components, not a passive group wrapper.

## Separator depth correction — 2026-09-12

The live `base-nova` registry combines a one-pixel `bg-input` separator with
Button's transparent border and `bg-clip-padding`. The adjacent transparent
pixel exposes the canvas, creating the two-tone recessed seam shown in the
reference. Native deliberately fills transparent button edges, so
`DButtonGroupSeparator` reserves that one transparent pixel on its logical
leading side instead. The rule uses `DTokens.colors.outlineVariant` (input),
keeps its one-pixel end insets, and mirrors in RTL or rotates for vertical
groups. An explicit color still overrides only the rule. This preserves the
existing outer button artwork and shared control painter.

Sources: <https://ui.shadcn.com/r/styles/base-nova/button-group.json> and
<https://ui.shadcn.com/r/styles/base-nova/button.json>.

Pixel regressions cover the transparent/rule pair in both orientations and
text directions; focused checks also cover the existing styleguide composition
and production New topic action accessibility.

Verification: root `flutter analyze --no-pub` is clean; 48 focused tests pass.
The draft-menu test `focuses loaded drafts and restores the trigger on Escape`
fails on both unchanged HEAD and the corrected separator. Four seam pixel
checks pass, and exported Flutter widget-test images were inspected in horizontal
LTR and vertical RTL (test font, 1× renderer). No native app inspection was run
for this correction.

## Full-height, button-colored seam — 2026-09-12 follow-up

User visual review supersedes the reference's end insets and canvas-colored
edge: both seam lines now fill the full group height (or width for vertical
groups). The color parameter supplies the adjacent button fill, with a 25%
black shade and 15% white tint forming the two edges. The default matches
secondary buttons; New topic explicitly supplies the live primary token.
This removes the gray line and the cut-off ends identified in the review.
