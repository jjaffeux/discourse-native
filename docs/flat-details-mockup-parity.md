# Flat details parity

Reference: `discourse-native-mockups` at `847614e` (branch
`test-mobile-layout`), look A. Most of these came in `f493c51`; the switch
fills and the presence circle came in `9839846`. Colours are named by the
mockup token and the `DTokens` value that stands for it. `--primary` is the
text (`foreground`) and `--secondary` the ground (`background`).

| Part | Reference | Owner |
| --- | --- | --- |
| Switch, off | Track `rgb(0 0 0 / .16)` dark, `.045` light, over what it sits on; 1px `--border-subtle` (12%) edge; knob `--mark-subtle` (`subtleMark`, 40%) | `DSwitch` |
| Switch, on | Track the accent (`controlTheme.primary`); knob white (`--content-on`) | `DSwitch` |
| Sidebar switch | Chosen side 18% of the text over the ground in dark, the ground itself in light; well edged by the 12% line | `DTabList.expandSelected` |
| Sidebar presence | Icon only. 34 on a phone, 30 on a desktop. Dot 10, pause 13. Transparent at rest, 8% of the text on hover, `--surface-raised` while open | `UserPresenceMenu(iconOnly: true)` |
| Date pill, resting | 5% of the text over what is under it, no edge | `StreamChip` |
| Date pill, pinned | `--surface-raised` (`raisedBackground`) with the 12% edge, no shadow | `StreamChip` |
| Floating calls | Opaque `--surface-menu` (`panelBackground`, 3%) with the 22% `--border`, no blur. Chat's jump to latest, a schedule's Today | `DButtonDensity.floatingCall` |
| Timeline excerpt | Under the author: 2 lines, 12.5 at line height 1.4, `--text-secondary` (62%), 2 above and below | `TopicProgressPanel` |
| Reaction grid, phone sheet | Columns `auto-fill minmax(44, 1fr)`, gap 2, cells 44 tall at the column's width, glyph 24, inset `0 4 4` | `ReactionGrid(inSheet: true)` |
| Avatar letter | `max(11, size × .42)`: 11 on a topic card's 20 poster avatars | `topic_card_metadata.dart` |

## Notes

- The topic progress trigger shares `StreamChip` with the date pill, so it
  takes the pinned look. The mockup's phone timeline pill is
  `--surface-raised` with the 22% `--border` at 34 tall, and its desktop one
  is a floating call at 26. Neither came in this range; both remain as the
  shared chip.
- A post's plain words have one owner, `post_plain_text.dart`, which the
  composer's reply context also reads. A post with nothing cooked gives its
  markup without the marks. The mockup's `unmark` removes `[label]` before it
  rewrites `[label](url)`, which leaves `(url)` behind; links are rewritten
  first here. Hidden and deleted posts show no excerpt.
- The phone reaction cells paint their whole 44 box through
  `DToggleVisualStyle.fillHeight`. The desktop popover keeps eight 30 cells.
- The mockup's onebox site badge letter also went from 9 to 11. The app's
  onebox header shows the site's icon only, with no letter fallback.

## Not ported

Chat's browse switch (Chats, Channels, Threads) takes the same chosen fill as
the sidebar's in the mockup, and its track and choices became pills. Here it
is the inset `DToggleGroup`, which about twenty other controls share, so it
needs its own variant before those values can change.

## Tests

`d_switch_test.dart`, `d_sidebar_tab_material_test.dart`,
`sidebar_profile_test.dart`, `stream_day_separator_test.dart`,
`d_button_test.dart`, `post_plain_text_test.dart`, `topic_progress_test.dart`,
`topic_progress_lifecycle_test.dart`, `mobile_reaction_sheets_test.dart` and
`mobile_topic_card_test.dart` pin these values.
