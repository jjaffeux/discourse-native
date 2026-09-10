# Sidebar reference and implementation

Reference family: official base-nova, retrieved 2026-09-09. Frozen catalogue
scope remains the 2026-09-08 Sidebar row.

- Documentation: https://ui.shadcn.com/docs/components/base/sidebar
- Registry: https://ui.shadcn.com/r/styles/base-nova/sidebar.json
- Committed registry bytes: reference/sidebar.json
- Registry SHA256: `02b1ea430fb246da062048f0161a01d1b34a2c787f6974958c9b20a3142120a6`
- Decoded source SHA256: `d08ce0624ed0a9a5ecb35698dadd11fe12ca87dd7dc78e02e7c5d9b7b5485a70`
- Upstream license: reference/LICENSE.shadcn.md.

## Geometry and behavior mapping

| Reference | Flutter |
| --- | --- |
| 16rem / 18rem / 3rem widths | 256 / 288 / 48 logical pixels, configurable |
| md breakpoint | Provider's bounded available width <768; configurable, docs use900 |
| sidebar / floating / inset | DSidebarVariant; floating 8px padding, border, small shadow and base radius (`rounded-lg`); inset content radius ×1.4 |
| offcanvas / icon / none | Zero inline width / icon width / always inline; mobile modal for collapsible modes |
| physical left/right | Physical panel side; directional text, padding and submenu border |
| 200ms transition | Linear desktop width; mobile presentation uses the accepted Sheet transition; zero with reduced motion |
| header/footer p-2 | 8px fixed slots; callers compose multiple children with 8px gap |
| content flex-1 overflow | Expanded slot with independent DSidebarContent scroll owner |
| sidebar background | Muted semantic panel token; caller override remains available |
| group p-2; label h-8 px-2 | 8px group padding,32px label minimum,8px horizontal inset |
| label text-xs/medium/70% | 12px,16px leading,500 weight,foreground70% |
| default h-8 / sm h-7 / lg h-12 | 32/28/48px minimum rows; optional height30 for docs |
| menu text-sm / sm text-xs | 14px/20px leading or12px/16px; selected500 |
| gap-2,p-2,SVG size-4 | 8px icon gap/horizontal inset,16px caller icon |
| active and hover sidebar-accent | Neutral semantic hover token, foreground; selected semantics also exposed |
| rounded-md / focus ring-2 | Live radius×0.8,2px ring painted without layout changes |
| action size-5, badge text-xs | 20px action;12px tabular badge; trailing content reserve |
| menu-sub mx-3.5 px-2.5 py-0.5 gap-1 | 14px margins,10px inset,2px vertical padding,4px gap,directional1px rule |
| skeleton h-8 icon/text size-4 | 32px row,16px skeletons,stable caller-controlled50–90% width |
| rail |16px pointer toggle,excluded from Tab; does not claim draggable resize |
| trigger | Exact Lucide PanelLeft 24-unit SVG,16px render,RTL flip |

At100% labels truncate as upstream; accessibility text can grow menu rows.
Typography inherits the live font family. Colors are read from DTokens in every
build, including an already-open route. Mobile composes the accepted DSheet
owner with an exact 288px default width, its border/shadow and no close button.
Sheet owns the nearest Navigator, modal barrier, closed-loop route focus,
Escape/outside dismissal and restored trigger focus. Provider shortcuts are scoped to its composition, not global
process bindings. Persistence is caller-owned; no browser cookie equivalent is
silently written. Header/footer remain visible while content scrolls.

## Public composition

Import `package:discourse_native/discourse_ui.dart`. Use DSidebarProvider above
a bounded Row with DSidebar and Expanded content. The provider state returned
by `DSidebarProvider.of(context)` exposes `open`, `openMobile`, `isMobile`,
`setOpen`, `setOpenMobile`, and `toggleSidebar`. An optional controlled `open`
and `onOpenChange` support app persistence. The provider defaults to open desktop
and closed mobile. A borrowed key can refer to DSidebarProviderState; all
borrowed focus,scroll and text controllers remain caller-owned.

DSidebar owns header/footer/rail slots and an expanded child. Content, Group,
GroupLabel/Action/Content, Menu, MenuItem, MenuButton/Action/Badge/Skeleton,
MenuSub/Item/Button, Header, Footer, Separator, Input, Trigger, Rail and Inset
are exported. MenuItem takes optional trailing action/badge and submenu slots.
Disclosure composes DCollapsible with caller state and `expanded` semantics.
showOnHover actions reveal on row hover/focus,
remain keyboard reachable, and stay visible on narrow surfaces. Actions with
`expanded: true` also stay visible and highlighted while their popup has focus.
Compose a project action using `DDropdownMenuTrigger`, passing its `focusNode`,
`open` state as `expanded`, and `toggle` callback to `DSidebarMenuAction`. The
borrowed focus node is never disposed by the action; the dropdown restores it
on Escape or selection. Null callbacks
disable actions. Icon menu callers should provide an icon and tooltip or
semanticLabel to preserve a useful collapsed navigation name.

### Project action dropdown verification — 2026-09-10

The application example's trailing project actions now compose the accepted
Dropdown Menu owner. They offer View Project, Share Project and a separated
destructive Delete Project action, with feedback scoped to the selected sample
project. The menu opens to the right on desktop and below with end alignment on
mobile, subject to the shared popup collision handling. The action's optional
`focusNode` and `expanded` parameters support keyboard focus restoration,
expanded semantics and visibility while the popup owns focus.

The original regression failed because View Project never appeared after
clicking the three dots. Focused Sidebar, Sidebar examples, styleguide page and
Dropdown Menu tests cover all three project actions, independent row selection,
hover visibility, Escape/Space reopening, outside dismissal, borrowed focus-node
replacement/disposal and a 360px RTL/200% iOS-platform widget fixture. Root
`dart analyze --fatal-infos` passes. Logs are
`/tmp/sidebar-project-dropdown-final-tests.log` and
`/tmp/sidebar-project-dropdown-final-analysis.log`.

Native macOS inspection used `lib/styleguide_main.dart` in the isolated
`Sidebar Menu Review d19e.app`, built from
`3bdaedac1e06870fc0b59f752db43db54abcac5a`. The actual
[reference demo](https://ui.shadcn.com/docs/components/base/sidebar) was opened
in Chrome and its project dropdown inspected. Native checks covered the current
dark app palette, Light, desktop and 360px previews; clicking project menus,
View/Share/Delete feedback, Escape dismissal and Return reopening with restored
focus; and mobile selection retaining the surrounding Sheet. Both the app and
reference tab were closed after inspection. Runner identity and entitlements
were temporary and restored; deep strict signature verification passed.

The final candidate also preserves the subsequently merged submenu-guide
contrast correction. The native-inspected menu action, row implementation and
entire Sidebar example remain byte-identical. No iOS/Linux device or spoken
screen-reader verification was performed; the RTL/200% case is widget-test
coverage.

Alignment follow-up: trailing actions and badges are vertically centered within
the primary row, independently of any submenu below it. This removes the fixed
4px top offset that put a 20px project action 2px above center in a 32px row and
keeps alignment proportional for taller rows. All 51 Sidebar, Sidebar example
and styleguide-page tests and fatal-info root analysis pass. The corrected
project-row alignment, menu opening and Share feedback were inspected in the
actual macOS styleguide with the current dark app palette.

## Dependency boundary

The actual registry lists Button,Input,Separator,Sheet,Skeleton,Tooltip and
use-mobile. Collapsible,Dropdown Menu and Avatar appear in example composition.
The frozen dependency list is therefore not a literal Flutter build graph.

- Tooltip, Separator, Skeleton and Scroll Area are shared generic owners.
- DSheet owns the mobile panel. Its optional exact side width preserves
  Sidebar's 18rem geometry; its default Sheet width policy stays unchanged.
  Sidebar keeps its own bounded content scroll region and fixed header/footer.
- DSidebarInput delegates to the accepted DInput and retains its styling and
  controller/focus adapter surface.
- DCollapsible owns project disclosure, keyboard activation and expanded
  semantics. The provider hides the complete group-label slot in icon mode,
  including composed interactive triggers.
- DDropdownMenu owns the workspace and account menus; selection updates local
  demo state. DAvatar supplies the account identity, including the 32px
  large-button icon state. DButton supplies recovery actions.

The original Sidebar acceptance remains recorded separately. The final-owner
composition review is tracked in [sidebar-final-composition.md](sidebar-final-composition.md)
and `finalCompositionReview`; the frozen catalogue graph is unchanged.

## Adoption inventory

The first app adoption is the corrected styleguide shell, integrated by the
coordinator using the public provider, panel, content, group, menu, button,
header and trigger parts. The component task exports/registers six independent
examples; [the coordinator's review](styleguide-design.md) records the actual
application adoption and its native verification.

The subsequent [main sidebar migration](sidebar-main-migration.md) adopts
Native Sidebar in `InstanceSidebar`. It uses lazy groups, menus and submenus,
Collapsible section headers, measured count/action space, and the public
header/footer, badge, skeleton and dropdown components. Site identity,
permissions, category/tag artwork, custom links, More-link promotion, search,
loading, routing and saved section state stay in the application adapter.
The existing ResizablePane owns its 208px default and 200–480px saved range.
Chat row actions are visible in mobile viewports and reveal on desktop
hover/focus; actions open a dropdown independently of row navigation.

The remaining app owners are:

- Chat drawer: channel/DM memberships, unread/mention counts, configurable
  sections and thread navigation; retains its current domain rendering adapter.
- Events and Voice contribute SidebarDestination/SidebarSection models to the
  preceding app owners; their permissions/room state are not generic widgets.
- Assign's member pane and topic details are content panels, not application
  Sidebar navigation. Existing resizable/topic pane behavior remains separate.
- AI,GitHub,Lazy Videos,GIFs,Local Dates,Poll,Prometheus Alert Receiver and
  Reactions have no independent application Sidebar renderer. Their content,
  pickers and menus remain with their catalogue owners.

## Verification

Focused run (seed9092026): `flutter test --no-pub test/d_sidebar_test.dart
 test/styleguide/sidebar_examples_test.dart test/styleguide/styleguide_page_test.dart`
passed16 tests. Coverage includes controlled/uncontrolled modes, keyboard
activation/toggle, offcanvas/icon/static widths, fixed header/footer scrolling,
physical-right modal, Escape/outside dismissal, focus restoration, selected
semantics,30px geometry,live open-route theme changes, removal,all six examples
at360px RTL200%,and existing styleguide registration/theme-state behavior.

Final implementation checkpoint: `47aabf60e65dff047cdf80dd6e29203a93fb8012`.
Final21 focused tests pass; root/full analysis and formatting are clean.
[Native comparison, build provenance, cleanup and limitations](sidebar-native.md)
records the actual macOS inspection and its native-discovered fixes.

Coordinator integration adds compact button semantic boundaries, verifies the
actual styleguide navigation, and sets the compact demos' breakpoint to 500px
while preserving the component default of 768px. The operational progress
dependencies originally listed Tooltip, Separator and Skeleton. Final-owner
composition evidence is recorded separately; the frozen website reference
graph remains unchanged in catalogue.json.

Pointer activation requests focus before calling the action. On iOS/Android,
menu/trigger/action hit areas have48px minimum bounds around compact visuals.
Leaving the mobile breakpoint clears openMobile, so returning does not reopen
an obsolete panel. Initial modal focus enters its shortcut subtree, making
Escape effective immediately. Menu/Content use the registry's gap-0; submenu
spacing is4px. Floating borders are painted without consuming icon width.
