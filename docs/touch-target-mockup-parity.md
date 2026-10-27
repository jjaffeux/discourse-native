# Touch target parity

Reference: `discourse-native-mockups` at `847614e` (branch `test-mobile-layout`),
look A. The rules came in with `83cee2f`. Both live in `app.css` under
`[data-touch]`, which `App.tsx` sets on the frame of a narrow window. The app's
split is the platform, as everywhere else: iOS and Android are the phone
(`DControlStyle.isTouch`), and desktop keeps its sizes.

## The mockup's two rules

| Rule | Selector | What it does |
| --- | --- | --- |
| Invisible area | `[data-touch] :is(button, a[href], summary, [role=button], [role=tab], [role=switch], [role=checkbox], [role=radio], [role=menuitem], [role=option], [role=link])::after` | An absolutely placed layer, `min(0px, (100% - 44px) / 2)` from each edge. A control drawn under 44 keeps its look and is pressed across at least 44 by 44, centred on it. A control already 44 in an axis gains nothing in that axis. |
| Exceptions | `:not(.row-press__link, .glass-swatch):not(:has(button, a[href], [role=button], input, select, textarea))` | A control that holds another control gets no layer, because the layer would take its inner control's presses. Neither does a whole-row link, which already covers its row. |
| Fields drawn 44 | `[data-touch] .page-controls :is(input, select) { min-height: 44px }` | A page's own fields under its title are drawn 44 tall. A field cannot have an `::after`, so its drawn box is its whole target. |

Measured in the running mockup at 390 by 844 with `data-touch` set:

| Control | Drawn | Pressed across |
| --- | --- | --- |
| Header icons (menu, search, notifications) | 32 × 28 | 44 × 44 |
| Sidebar switch segments | 51 × 30.8 | 51 × 44 |
| Presence button | 34 × 34 | 44 × 44 |
| Topic row tag links | 37.8 × 18 | 44 × 44 |
| Users page "Filter users" field | 275.5 × 44 | the field |
| Channels page "Find a channel" field | 185 × 58 | the field |

## In the app

| Mockup | App |
| --- | --- |
| `::after` on every control | `DTouchTarget` round the press root of each kit control: `DButton` (and with it every kit part built on it, such as pagination, alert dialog and dropdown triggers), `DSwitch`, `DCheckbox`, `DRadioGroupItem`, `DToggle` (and `DToggleGroup`), `DTabTrigger`, `DBreadcrumbLink`, `DBadge.action`, `DItem`, `DCollapsibleTrigger` (and `DAccordion`), `DCommandItem`, `DNavigationMenu` links, `DMenubar` triggers, `DDropdownMenuItem`, `DSelect` trigger, options and scroll arrows, `DCombobox` options, and the sidebar menu buttons. |
| The layer's place in paint order | `DTouchTargets`, installed in `MaterialApp.builder` above the navigator, routes and toasts. A press that lands on no control is given to the control whose area holds it. The decision follows the mockup. The area lies at the control's place in paint order, so what paints over the control also covers its area (a sheet, a route, a later sibling). The area paints over what is under the control. An ancestor's clip hides it. A control that nothing can press, because it is ignored, offstage or under a barrier, has no area. |
| No layer on a holder | A `DTouchTarget` with another inside it has no area. |
| `.page-controls` fields at 44 | `DPageSurface.headed` wraps its controls in `DTouchFields`, and `DInput` is drawn at least 44 tall under it on a phone. Desktop keeps the 35.5 search field. |

Nothing about layout or painting changes. `DTouchTarget` is a pass-through
render box that registers with the scope, and the scope does work only on a
pointer down near a small control. The area is in the control's own
coordinates, as the CSS layer is, so a scaled control's area scales with it.

## Where the app differs, and why

- **A drawn control keeps its own presses.** In the mockup, overlapping layers
  resolve by DOM order, and a positioned later sibling's layer can lie over an
  earlier control's drawn body. With 33.5-tall menu rows, the bottom 5 points
  of each row press the next row. The app gives an area only the presses that
  would otherwise land on no control. Where two areas overlap and no control is
  drawn, the later painted one takes the press, as in the mockup.
- **The Channels field is 44, not 58.** The mockup's selector reaches the bare
  `<input>` inside the padded `<label>` that draws the Channels search, so the
  label grows to 44 + 7 + 7 = 58. That contradicts the rule's own comment ("as
  tall as a fingertip"). The app draws both page fields at 44.
- **Only text fields take the 44.** The mockup's page controls hold no
  `<select>`: its pickers there are `FilterPill` buttons, 30 tall with the
  invisible area. The app's `DSelect` pickers in the same place keep their 30.
- **Links inside text** (cooked posts, sentences) keep the bounds of their
  words. In Flutter they are text spans, not boxes, and the mockup's own audit
  exempts them too.
- **A press with a pointer device** on an iPad goes through the same area. The
  platform, not the pointer, decides, as it does for every other phone size in
  the kit.

## Tests

- `test/ui/d_touch_target_test.dart` covers the 7-point reach of a 30-point
  control (and not 8), one-axis growth, desktop, a drawn neighbour, overlapping
  areas, a surface painted over or under, clips, a route on top, a control
  nothing can press, a holder, a pressable row and a scroll drag. It also has
  one case for each small kit control.
- `test/d_button_test.dart`: a 30-point icon button on iOS and macOS.
- `test/d_page_surface_test.dart`: page fields are 44 on iOS and Android,
  35.5 on macOS, and 35.5 outside a page's controls.
- `test/app_touch_targets_test.dart`: the app installs the scope above its
  routes, toasts and shell.
