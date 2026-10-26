# Phone bar parity

Reference: `discourse-native-mockups` at `847614e` (branch `test-mobile-layout`),
look A. The rules are in `app.css` under `[data-variant="a"]`; the place order
is `dockDests` in `App.tsx`.

## Places

The bar and its More menu are a phone's Start page, so Start is not a place.
Its order is Topics, the plugin panels (Chat), Bookmarks, Dashboard (staff),
Inbox, Users, the community shortcuts, Categories, Groups, Badges, Settings
and Preferences. Next come the places only the Start page used to offer:
Summary, Activity, the sections plugins contribute to Start (Chat's Channels
and Threads), and Drafts, which appears only while a draft can be resumed.
`_mobilePlaces` in `mobile_shell.dart` holds this one list. The dock, the More
menu, the history gestures' tab order and the fallback for a selection that
is no longer offered all read it.

## Geometry

`DMobileDockGeometry` is one pure value computed from the screen's foot (the
bottom safe inset, which is 0 while the keyboard is up), the text scale, and
anything that lifts the bar. The dock, the shell's footer, `DComposerDock`
and the topic timeline all read it. At width 390, a foot of 34 and the
default scale:

| Part | Value |
| --- | --- |
| Bar on a round screen | Full width, no side or bottom margin. Top corners 31, bottom corners square. Padding 6 at the top and sides and `6 + min(foot, 55 - 31)` = 30 at the bottom. 86 tall. |
| Bar on a square screen, or lifted by a minimized composer | The floating capsule, 6 in from every edge. |
| Footer pages clear | The bar plus its 6 top margin, 92. |
| Columns | `(inner - 3 * 4) / 4` = 91.5. Three places, then the ⋮ (40) and the icon-only action (50) in the fourth column. |
| Current page past the third place | Takes the ⋮'s slot. The four places share the room equally, and pressing the fourth opens More. |
| Current-place mark | 28 × 4 on the bar's top edge, bottom corners radius 3, in the foreground colour. Grows in over 200 ms. The current place has no fill. |
| Folded circle and topic timeline | Each sits on its corner's diagonal, `cornerAt(e) = max(6, min(55 - (55 - 6 - e/2) * 0.7071 - e/2, foot))` from both edges. That is 13.32 for the 48 circle and 15.37 for a 34 tall control. |
| Fill | `DTokens.wellFill`, the palette background with Oklch lightness lowered by 0.08. On a phone the plain ground is the same colour. |

The literal 55 stands for the screen corner radius the mockup assumes. The
app does not read the device's real radius.

## Validation

`test/d_mobile_dock_geometry_test.dart`, `test/d_mobile_dock_test.dart`,
`test/d_mobile_dock_item_test.dart`, `test/d_composer_dock_test.dart`,
`test/oklab_test.dart`, `test/topic_progress_motion_test.dart` and
`test/mobile_shell_test.dart`.
