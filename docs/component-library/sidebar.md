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
| sidebar / floating / inset | DSidebarVariant; floating 8px padding, border, small shadow and radius ×1.2; inset content radius ×1.4 |
| offcanvas / icon / none | Zero inline width / icon width / always inline; mobile modal for collapsible modes |
| physical left/right | Physical panel side; directional text, padding and submenu border |
| 200ms linear | Desktop width and mobile slide; zero with reduced motion |
| header/footer p-2 | 8px fixed slots; callers compose multiple children with 8px gap |
| content flex-1 overflow | Expanded slot with independent DSidebarContent scroll owner |
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
build, including an already-open route. The native panel has no Material
surface elevation or stock drawer decoration; a transparent Material only
supports native text editing/ink descendants. Mobile uses nearest Navigator,
modal barrier, closed-loop route focus,Escape/outside dismissal and restored
trigger focus. Provider shortcuts are scoped to its composition, not global
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
Disclosure uses caller state and `expanded` semantics; it is not another
Collapsible implementation. showOnHover actions reveal on row hover/focus,
remain keyboard reachable, and stay visible on narrow surfaces. Null callbacks
disable actions. Icon menu callers should provide an icon and tooltip or
semanticLabel to preserve a useful collapsed navigation name.

## Dependency boundary

The actual registry lists Button,Input,Separator,Sheet,Skeleton,Tooltip and
use-mobile. Collapsible,Dropdown Menu and Avatar appear in example composition.
The frozen dependency list is therefore not a literal Flutter build graph.

- Tooltip,Separator,Skeleton are real imports of completed generic components.
- Native RawDialogRoute/Focus own Sidebar's mobile panel. No DSheet API or
  general sheet implementation is introduced.
- DSidebarInput is a small TextField styling adapter, not the complete Input
  catalogue entry. It delegates text/controller/focus/editing to Flutter.
- Disclosure is local sample state and ordinary widget composition; a future
  DCollapsible can be placed in the same slots without changing Sidebar.
- Trigger/menu actions are Sidebar-specific controls. DButton remains the
  available baseline for ordinary example recovery actions.
- Workspace/account example actions report local selection; general Dropdown
  Menu remains pending, as explicitly stated in the example notes.

Recommendation: implementation dependencies are Tooltip,Separator,Skeleton;
Sheet/Input/Collapsible are pending reference/composition relationships and
should not block this Flutter component. The coordinator owns dependency/order
metadata; this task leaves the frozen dependency list unchanged.

## Adoption inventory

The first app adoption is the corrected styleguide shell, owned concurrently
by the coordinator. This task exports/registers independent examples and does
not modify styleguide_page.dart,styleguide_chrome.dart or foundation_examples.dart.

Retained app owners require dedicated adapter work rather than a blind wrapper:

- InstanceSidebar: site identity, permission-filtered plugin destinations,
  categories/tags, persisted section disclosure/order, user menu, search,
  unread/urgent/dimmed badges, asynchronous navigation skeletons and panel
  switching. Its existing ResizablePane and shell responsive routing remain
  app owners. Replacing this entire navigation during the explicit docs-first
  redirection would widen scope. No claim of migration is made.
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

Exact implementation checkpoint: `226f463af31246120a7449dcddab9f7f9bbf6249`.
Final component/example rerun passed8 tests after rail/inset refinement; root
analysis and all6 touched Dart formatting checks pass. Full-profile analysis
passed before that local refinement. Native comparison awaits the coordinator
inspection slot; no CUA interaction or visual-parity claim has been made.
The sample-only macOS bundle has unique identity org.discourse.sidebarreview0cca,
passes strict deep ad-hoc signature verification and matches the build kernel
payload byte-for-byte (SHA256
`eb6055314193b447907b1e4ecc911f9a3f1a9da655da291850a240fe5d2e8965`).
Runner files are restored and no real-account app has been launched.
No iOS/Linux device or spoken VoiceOver verification is implied by widget tests.
