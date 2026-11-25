# Scrollbars and sheet search parity

Reference: `discourse-native-mockups` commit `540cbac` on `test-mobile-layout`
(tip `ab471b3`), the small, separate items of that commit: scrollbars
without tracks, the sheets that look something up, a sheet's buttons, the
Clover palette's danger and Discourse's mark. Line numbers are at the tip.
The other items of `540cbac` (assigning, recipients, the topic foot, toasts,
post news, share sheets) belong to other documents.

## Checklist

| Mockup change | Native | Verified by | State |
| --- | --- | --- | --- |
| `app.css` 6163–6193: a desktop scrollbar is only its thumb. No track, no corner fill, `--primary` at 24%, 36% on hover, round, a 10 gutter with a 3 transparent border (a 4 thumb). A phone's overlaid scrollbars are the system's; what hides its scrollbar keeps it hidden. | `DScrollThumb` names the thumb colours (`color`, the ink at 24%, and `activeColor`, 36%) and a 3 inset around the 4 thumb. The theme's automatic Material scrollbar resolves 36% while hovered or dragged. The kit's `DScrollBar` tracks a hover over its painted thumb and a thumb drag and paints 36% for either. Neither draws a track: Material's `trackVisibility` stays false and `RawScrollbar` shows none. The ink is `DTokens.foreground`, the palette's text. `showScrollbar: false` is unchanged. | `test/d_scroll_area_test.dart`: the automatic desktop scrollbar hovered (36%, the 3 inset clear, no track below the thumb), the kit thumb at rest, hovered, moved off, dragged and let go (24% / 36%, no track, clear gutter), and the thumb at 24% on four surfaces in both directions. Pixel reads at 1x and 2x. Each fails with the old inset or with no hover colour. | Done |
| Same rule, phone. | Flutter draws no system scrollbar on iOS or Android, so the kit's thumb stands in on a phone, in the same ink, overlaid as before. It never takes room. | Covered by the same tests, which do not depend on platform for colour. | Done, with this note |
| `App.tsx` 9597 `Sheet` `search`: on a phone a sheet that looks something up opens on its field, with no title over it, and keeps the height it has had (`MenuSheet hold`). | `showShellSheet(search: true)`: on a touch, draggable sheet the header is left out, so the body's first line, a `SheetSearch`, sits under the grabber; the title remains the sheet's semantic label; `search` implies `fillAvailableHeight`, the app's fixed opening height. Desktop dialogs keep their title. | `test/shell_sheet_test.dart` "a sheet that looks something up opens on its field" on iOS and macOS. | Done. No sheet in this slice uses it: the mockup gives it to Change owner, Assign and Reassign (the assignment slice) and Chat's channel picker. |
| 52862–52905 `SHEET_INPUT`, `SheetSearch`, 40845 `keepField`: on a phone the field is the filled capsule led by a magnifier, a press anywhere in it typing in it, and what is pressed in the sheet leaving the keyboard where it is; on a desktop the sheet's line. | `lib/src/shell/sheet_search.dart`. `SheetSearch` on touch: the kit's quiet `DInputGroup` at `DControlSize.floating` (40) with the magnifier addon leading and an optional `trailing` at its end, with 17-point text in a phone choice sheet; the group puts a press anywhere in it into the field. On a pointer layout: the borderless `DInput` at 15/1.4 over a 1 hairline, as the keep sheet already drew it. `SheetSearchHold`, given the field's focus node, excludes what the sheet lists from focus while the field has it, on touch only, so a press there leaves the keyboard up; desktop keyboard traversal is untouched. | `test/sidebar_taxonomy_parity_test.dart`: the capsule is 40 tall on the sheet's 19.6 inset, 351 wide, led by the magnifier; a press on the magnifier focuses the field; a row, a filter and Reset leave it focused (fails with the hold removed); the desktop field is the hairline line with no icon or capsule. | Done |
| 9945–10022 `MoveSheet` uses `SheetSearch` for Search topics, the list under it in `keepField`. | `topic_move_posts.dart`: the existing-topic search is a `SheetSearch` with the app's "Search by topic title or ID" (or message) as its hint, no floating label; the results and the chronological-order checkbox are in the hold. | `test/topic_move_posts_ownership_test.dart`: on iOS the field is the 40 capsule with its magnifier and picking a destination leaves it focused; on Linux it is the line. Existing move tests pass unchanged. | Done. The rest of `MoveSheet` (Segments in place of the toggle group, labels, the row look) predates `540cbac` and is not taken here. |
| 43028 `SidebarKeepSheet`: `SheetSearch`, and a press on anything under it leaves the keyboard up. | `sidebar_taxonomy_editor.dart`: the search line is the `SheetSearch`; the filters, list and the footer's actions are in the hold. The sheet keeps its title, as the mockup's does. | As above. | Done |
| 47960 `GifSheet`: `SheetSearch`, the GIFs under it in `keepField`. | `gif_picker.dart`: the field is a `SheetSearch` (exported through the plugin SDK) with the clear button as its `trailing`; the grid is in the hold. The sheet keeps its "Search GIFs" heading, as the mockup's does. | `test/gif_picker_test.dart`: the capsule with its magnifier on Android, none on macOS; the existing flow passes. | Done |
| 9702–9737, 47568–47610: `SecondaryButton` and `PrimaryButton` take `icon` before the label and `grow` to share a row equally (`SHEET_BUTTON`: inline-flex, centred, gap 7, pill, 13). | Nothing to change: `DButton(icon:)` draws the icon before the label (`DButtonIconPosition.start` is the default), and `Expanded` around each `DButton` in a `Row` shares the row equally with the content centred. | A probe at 300 wide on iOS and macOS: two pill `DButton`s at `DControlSize.field` in `Expanded`, 146 each, icon 12 wide 6 before the label, the content's middle on the button's centre. The kit's icon gap is 6 where the mockup draws 7; it is the kit's for every button and was left alone. | Not applicable: the kit already covers it. The only user, the share sheet, is another slice's. |
| 51547–51564 Clover: `attention` (danger) `#e45735` instead of its green. | `forum_theme_presets.dart` `clover-dark`: `danger` `0xFFE45735`; accent, highlight and success stay `0xFF39845B`. | `test/forum_theme_test.dart` pins both; `palette_contrast_test.dart` passes. | Done |
| `public/discourse-mark.svg` as the favicon and Tauri icon. | `assets/logo_mark.svg` is the same artwork: the same six paths, the bubble written as arcs where the mockup has curves, the viewBox squared. Its container ships white for the app icon's dark ground; the in-app loading mark recolours it to the theme's text. `assets/app_icon.png` is the mark with a near-black container on white, as the mockup's Tauri icon draws it, full-bleed for the platforms' masks where the Tauri icon has its own rounded tile. | Compared the SVG sources and the rendered icons. | Not applicable: no user-visible difference to change. |

## Kit changes

- `DScrollThumb`: `colorOn` (a contrast-chosen opaque thumb) is replaced by
  `color` and `activeColor`, the ink at 24% and 36%; `containerInset` is 3.
  Needed by the scrollbar item. Callers of the inset (boards' gutters, the
  composer panel's edge, the page-edge test helper) follow the constant.
- `DScrollArea` and `DScrollBar` lose `backgroundColor`, which only chose the
  thumb's contrast; its callers (`DCommand`, `DSelect`, `DDropdownMenu`,
  `DCodeViewer`, `DCodeEditor`, `CodeBlock`) stop passing it and `DCommand`'s
  scope drops the colour it only forwarded. `DScrollBar` paints the active
  thumb while hovered or dragged. Kit test: `test/d_scroll_area_test.dart`;
  styleguide: the Scroll Area page's "Ink thumb" example.
- No kit change for the sheet's buttons or the sheet search: the search field
  is an app-level composition of `DInputGroup` and `DInput` in
  `lib/src/shell/`, with Flutter's `ExcludeFocus` for the hold.

## For a sheet that looks something up

```dart
showShellSheet(
  context: context,
  title: l10n.assignPost,   // the semantic label; drawn only off a phone
  search: true,
  builder: (context) => Column(children: [
    SheetSearch(focusNode: field, hintText: l10n.searchUsers, onChanged: …),
    Expanded(child: SheetSearchHold(focusNode: field, child: results)),
  ]),
);
```

The state that owns the sheet owns the `FocusNode`. Plugins import both
widgets from `discourse_plugin_sdk.dart`.
