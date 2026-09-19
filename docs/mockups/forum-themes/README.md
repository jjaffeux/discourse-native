# Forum theme design studies

Three interactive HTML/CSS directions for forum settings. These are standalone
local prototypes; no Flutter application code or forum account data is changed.

```sh
python3 -m http.server 8786 --bind 127.0.0.1 --directory docs/mockups/forum-themes
```

- [01 — The gallery](http://127.0.0.1:8786/?design=gallery): miniature forum cards,
  Slack-inspired library/custom tabs, and a supporting preview. Best for browsing.
- [02 — The studio](http://127.0.0.1:8786/?design=studio): compact palette choices
  beside a persistent, larger preview. Recommended for creating themes.
- [03 — The quick switch](http://127.0.0.1:8786/?design=compact): a compact dialog
  with swatches, two-column names, and a short preview. Closest to current settings.

The direction links retain pending selections while switching layouts. All three
include forum-default inheritance, light/dark/system modes, all 13 reference
palettes, search, and a custom theme builder. The HTML entry point also opens
from disk; serving it enables clipboard support more reliably.

## Palette source and assumptions

`themes.js` snapshots the exact raw palette declarations in
`/Users/joffreyjaffeux/Code/discourse-native-mockups/src/app.css`, served by
http://localhost:5183/ and inspected on 2026-09-19. Display names match its
`src/App.tsx` catalogue:

Dark, Neutral, Grey Amber, Shades of Blue, Latte, Summer, Dark Rose, WCAG,
WCAG Dark, Dracula, Solarized Light, Solarized Dark, and Clover Dark.

The sample forum is Discourse Meta, with Neutral as its illustrative default.
Production should resolve the actual forum default dynamically. The 5183 source
contains color schemes, not independently packaged layout themes; this study
therefore explores color customization. Scheme thumbnails preserve each scheme's
original mode; the live preview uses the selected light/dark/system mode.

Opposite-mode variants swap primary/text and secondary/background, following the
reference. Other colors remain unchanged. Clover Dark declares only primary,
secondary, and tertiary; its undeclared status colors use Neutral as a documented
prototype fallback. The raw snapshot does not invent additional Clover tokens.

## Working interactions

- Select a palette or return to the forum default, then apply to the sample forum.
- Reset pending changes to the previously applied selection and mode.
- Search built-in palettes, including an empty-result state.
- Create a theme from a built-in or saved palette; edit its name and seven hex colors.
- Preview valid color changes immediately; invalid fields disable save/apply/export.
- See body text contrast feedback (AA threshold 4.5:1). This is not a complete
  accessibility audit; accent, muted, and status colors need separate evaluation.
- Save a custom theme to the library, then apply it separately or apply directly
  from the editor. The latter also saves it to the library.
- Export portable version-1 JSON, copy it, and import it with schema validation.
- Swap the base light/dark definition or generate a surprise starting palette.
- Saved custom themes and applied preferences use browser localStorage under
  `discourse-forum-theme-studies-v1`; they are scoped to the prototype origin.
  Unsaved editor work is discarded when leaving the custom-theme tab.

Forum navigation and sample forum content are illustrative. They are not controls.
The preview's New topic label is a visual sample, not a publishing action.

## Native component mapping

The project UI kit, catalogue and styleguide were consulted. HTML is an explicitly
requested design artifact, not a replacement for Native application components.
A chosen implementation should compose existing controls imported through
`package:discourse_native/discourse_ui.dart`:

- DDialog / DDialogContent for the forum-settings dialog.
- DTabs for library/custom sections; DToggleGroup for color-mode controls.
- Existing Native selection controls for theme choice, with DCard/decorative
  palette previews as appropriate to the selected direction.
- DInput and DField for names and hex colors; DSelect for starting palettes.
- DButton for save/apply/reset/import/export and DAlert for feedback.

Use existing sizes, focus handling, semantic tokens and selection behavior. If
implementation requires an absent component or API, follow AGENTS.md and ask
before extending the kit. This study does not authorize a new native color picker.

## Verification

- `node --check app.js` and `node --check themes.js` passed.
- Browser inspection of all three directions and the custom editor.
- All 13 palette buttons exercised, with their selected states verified.
- Dracula's dark preview colors compared with the reference declarations.
- Custom hex edits, invalid-hex disabling, body-text contrast failure (1:1),
  saving, applying, and persistence after reload exercised.
- Import tested with malformed JSON and a valid seven-color palette; export
  content inspected for the imported name.
- Search tested with two Solarized matches, no matches, and keyboard clearing.
- Narrow layouts inspected, including a 390 CSS-pixel content width for the
  studio editor and compact library/editor, with no horizontal overflow.
- No browser console errors or warnings reported during the review.

These are browser prototype checks, not Flutter tests or physical-device tests.

## Adopted native direction

The implementation combines the gallery's section sidebar with the studio's
controls and live preview. Native settings use concise labels, real topic rows
with fictional content, and the existing Native controls. Presets apply
immediately; custom changes apply on Save theme. See
`../../component-library/evidence/forum-themes-review.md` for verification.
