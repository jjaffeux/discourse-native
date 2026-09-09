# Breadcrumb source evidence

Prepared on 2026-09-09 from the frozen 2026-09-08 Base UI/base-nova
reference.

## Reference integrity

- Documentation: `https://ui.shadcn.com/docs/components/base/breadcrumb`
- Frozen Markdown: `https://ui.shadcn.com/docs/components/base/breadcrumb.md`
- Frozen Markdown SHA256:
  `df168dd44f709ddb768995fbab0188c1934b6e95def1ba3726adf4f9302714b7`
  (matches `catalogue.json` exactly).
- Base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/breadcrumb.json`
- Registry response SHA256:
  `5e7a33d921824d659494dc90411393cdf795c0ad5c94631da5c2883924623350`.
- Linked main example source:
  `https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/breadcrumb-example.tsx`
- Main example source SHA256:
  `3880b085f86ee868367576aec07f021b955c14b72aa27d0749849d812032e34b`.

The frozen Markdown contains the full source for Basic, Custom separator,
Dropdown, Collapsed, Link component and RTL. Those six compositions are the
implementation scope; Installation maps to the public
`package:discourse_native/discourse_ui.dart` barrel.

## Reference-to-Flutter mapping

| Base-nova source | Flutter implementation |
| --- | --- |
| `nav[aria-label=breadcrumb]` | `DBreadcrumb`, a named semantic navigation container with an optional local `TextDirection` scope. |
| `ol.flex.flex-wrap.items-center.gap-1.5` | `DBreadcrumbList`, a centered `Wrap` with 6 logical-pixel horizontal/run gaps. `DBreadcrumbOverflow.scroll` is an explicit native extension for paths that must remain one line. |
| `text-sm`, `wrap-break-word`, `text-muted-foreground` | Explicit 14px font, 20px leading, normal weight/tracking, inherited host font and live `DTokens.mutedForeground`; text scales only through the inherited scaler. |
| `li.inline-flex.items-center.gap-1` | `DBreadcrumbItem` with a 4px centered inner wrap, allowing a long child to wrap instead of overflowing at 200% text. |
| link `transition-colors hover:text-foreground` | `DBreadcrumbLink` changes from muted foreground to foreground over 150ms on hover/focus, with zero-duration reduced motion. Return, Space and pointer share one callback. |
| routing `render` prop | `DBreadcrumbLink.route<T>` preserves a typed destination/callback. `DBreadcrumbRouteAdapter<T>` may wrap the sole interactive surface with route-library metadata or secondary-click behavior. |
| page `role=link aria-disabled=true aria-current=page text-foreground font-normal` | `DBreadcrumbPage` is a selected, disabled link semantic node with foreground 14/20 normal text and no activation. Flutter has no distinct `aria-current` flag; selected plus disabled communicates the current non-actionable destination. |
| separator `role=presentation aria-hidden`, 14px logical chevron | `DBreadcrumbSeparator` is excluded from semantics. The 14px chevron mirrors in RTL; a custom child replaces it. |
| ellipsis `role=presentation aria-hidden`, 20px box and 16px artwork | `DBreadcrumbEllipsis` is a centered 20px decorative box. Interactive use wraps it in a separately labeled `DButton`/Dropdown Menu trigger. |

Desktop links retain the measured 20px line box. On iOS/Android their
interactive bounds grow to 48px while text metrics remain unchanged. This is
the narrow native touch adaptation required by the library conventions.
Keyboard focus adds a 1px token-colored outline without changing layout; the
web source has no component-specific focus class, but a visible native focus
state is required. Focused links in scrolling paths are brought into view.

## API and behavior

- `DBreadcrumb`, `DBreadcrumbList`, `DBreadcrumbItem`, `DBreadcrumbLink`,
  `DBreadcrumbPage`, `DBreadcrumbSeparator` and `DBreadcrumbEllipsis` are
  exported from `discourse_ui.dart`.
- Default wrapping matches the registry. Horizontal scroll is opt-in and owns
  no external controller; focus uses Flutter `Scrollable.ensureVisible`.
- A null link callback produces a disabled link, removes focus entry and blocks
  semantic/pointer/keyboard activation. Borrowed focus nodes are never disposed.
- The optional route adapter wraps, rather than replaces, the component's sole
  focus/activation/semantics owner. This prevents duplicate link roles while
  allowing `LinkTarget`-style secondary navigation adapters.
- Dropdown and Collapsed examples compose the final shared Dropdown Menu
  primitives. Menu selection, roving focus, typeahead, Escape, overlay
  placement and focus restoration stay owned there.
- Colors, font family and focus color are read from the current host theme on
  every build. There is no cached palette, component overlay, or animation
  controller.

## Dependency preparation

Button is accepted on main at merge `eb6d8ea0d9417f0edc830c5ce715b52436f12c94`.
Dropdown Menu is not yet accepted. Source preparation integrates exact tested
candidate `d273c27e788bb3991c773c7432e0b8c927715651` from
`codex/review-dropdown-menu-candidate`, owned by reviewer task
`01a085cf-f401-7813-80da-7c687de8a5d5`. That candidate had 47 focused
Dropdown/Popover/Table/styleguide tests passing with seed 826145 and clean root
and full-profile analysis. Breadcrumb's reviewer must wait for Dropdown Menu's
accepted local-main merge, reconcile its accepted API/source, and verify the
affected collapsed/dropdown behavior. The prepared parent is not acceptance.

## Application adoption audit

Current core, all bundled plugins, packages and profiles were searched for
`breadcrumb`, hierarchy/path terminology, category ancestry and directional
chevrons.

- `topic_list_view.dart`: the genuine parent-category → category path in every
  topic row now uses `DBreadcrumb`, `DBreadcrumbList`, `DBreadcrumbItem` and
  `DBreadcrumbSeparator`. Existing `LinkTarget`, rich category badge rendering,
  controller callbacks, tertiary-tab behavior, labels and permission/data
  ownership remain in the app adapter. The 1.5px list spacing preserves the
  dense row's former 17px link-to-link separation around the new 14px artwork.
- `_CategoryHeaderIdentity` is retained. It combines a flexible, ellipsized
  parent action with an interactive current title, optional title menu and
  trailing header controls. Treating that compound toolbar as a selected,
  disabled breadcrumb page would create false semantics and break its flex
  contract.
- Category taxonomy fields retain their compact parent/child label inside one
  picker action; it is a selected value/disclosure, not navigation to a current
  resource.
- Instance Sidebar trees remain trees. User Menu, Aggregate, Group Activity,
  diagnostic event rows and Voice diagnostic rows use chevrons as drill-in
  affordances, not path separators.
- Chat drawer/header, topic inbox previous/next, composer tool paging,
  lightbox/image controls and diagnostic detail headers are back/step controls.
  They remain their native navigation owners rather than inventing breadcrumb
  ancestry.
- No additional genuine breadcrumb owner exists in bundled plugins or profile
  packages.

## Verification and remaining acceptance

Implementation tests cover exact metrics/gaps/artwork, live typed callbacks and
adapter values, pointer/Return/Space, disabled focus/activation, borrowed focus,
current-page/link semantics, decoration suppression, 48px touch bounds, RTL
mirroring, narrow wrapping, focus-driven horizontal scrolling, reduced motion
and collapsed Dropdown keyboard selection/focus restoration. Styleguide tests
mount every example at 240px/200% in Light, Dark and Forest and exercise real
route and collapsed-menu state. Focused topic-row tests preserve long-category
ellipsis, link callbacks and category hierarchy.

Official rendered browser comparison and real macOS inspection are deliberately
left to the required independent reviewer. No browser/native, VoiceOver, iOS or
Linux inspection is claimed by this implementation task.

## Independent review evidence

Reviewer task `01a08623-9d6e-7393-b3e8-fb4c402b8c71` inspected the live
official Base UI page in the approved browser. Computed geometry for the main
and documented examples confirmed 14px/20px normal text, 6px list gaps, 4px
item gaps, 14px separators, a 20px ellipsis, and a 28px `icon-sm` collapsed
trigger. Light and dark muted/current colors and the Arabic RTL ordering were
also compared with the native fixture. The live page was returned to its prior
state and the reviewer-created tab was closed.

An isolated, ad-hoc-signed macOS debug fixture was launched from the reviewed
component/examples source. Light, Dark, Forest and Plum palettes; pointer,
Return and Space callbacks; visible Tab focus; route state; RTL; 240px width;
200% text; reduced motion; wrapping and scrolling were exercised. Native AX
exposed one labelled Breadcrumb container with independent links/current page,
while decorative separators and ellipses stayed absent. The Dropdown and
Collapsed compositions exercised first focus, arrows, End, typeahead,
selection, Escape/trigger restoration and outside dismissal. A timed theme
control remains in the fixture so the final accepted Dropdown source can be
rechecked while its overlay is open.

A second offline fixture, `tool/breadcrumb_topic_row_review_main.dart`, mounts
the real `DiscourseApp`, `TopicListView`, topic row and category adapter against
fixed local API data. Native inspection showed the long parent/child category
path bounded in the production row, exposed both labelled links in AX, and
confirmed each callback navigates to the correct local category feed. These
macOS checks do not establish VoiceOver speech or iOS/Linux device behavior.

Dropdown Menu was accepted on local main at merge
`5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787`, with progress follow-up
`a5ad2b5883e7b16e1ef3535f8836b5a86581c2bd`. The prepared pin is an ancestor,
and its component, example and focused-test paths are byte-equal to the
accepted revision. After current-main reconciliation, all 48 affected
Breadcrumb/Dropdown/styleguide tests and both topic-row regressions passed
again with seed `826145`; root and full-profile analysis are clean. The final
native open-overlay check uses the rebuilt accepted-source bundle recorded in
the progress row.
