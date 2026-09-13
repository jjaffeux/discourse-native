# Button and trigger directions

Four interactive HTML/CSS proposals for the controls in the supplied screenshots.
Open `index.html` in a browser. Its appearance, radius and height settings update
all four proposals together. All prototype interactions are local to the page.

| Direction | Main action | Other buttons and triggers | Category identity |
| --- | --- | --- | --- |
| A — Quiet outlines | Forum blue | Almost transparent fill, subtle outline | Purple folder icon |
| B — Soft surfaces | Forum blue | Shared neutral fill, transparent outline | Purple folder icon |
| C — Neutral first | Foreground color | Almost transparent fill, subtle outline | Purple folder icon |
| D — Contextual tints | Soft blue fill | Neutral outlines; tracking has a blue tint | Purple tint on the same control shape |

Default proposed geometry: 32px height, 8px radius, 14px text at weight 500,
16px icons, 6px icon gap and 1px borders. Radius options are 4px (the saved forum
value), 6px and 8px. Height options use the UI kit's regular 32px and large 36px
scale; coarse pointers receive 44px targets. Dropdowns, search, icon buttons,
button groups and pagination share these rules. Color affects emphasis rather
than geometry. The shared focus outline is blue in every direction.

## Color provenance

`palette.json` contains only the appearance snapshot for dev.discourse.org saved
in Discourse Native, read on 12 September 2026. It is the app's resolved CSS
palette, not an estimate from the screenshot and not a newly authenticated
fetch. The public anonymous homepage currently selects Horizon, a different
theme; its purple accent was deliberately not substituted for the app palette.

| Forum variable | Dark | Light | Use |
| --- | --- | --- | --- |
| `--primary` | `#dddddd` | `#222222` | Text; neutral primary action in C |
| `--secondary` | `#222222` | `#ffffff` | Canvas |
| `--tertiary` | `#0f82af` | `#0088cc` | Accent actions and focus |
| `--primary-low` | `#313131` | `#e9e9e9` | Secondary surfaces |
| `--primary-low-mid` | `#7a7a7a` | `#bdbdbd` | Source for derived subtle borders |
| `--tertiary-low` | `#052d3d` | `#d1f0ff` | Soft accent surfaces |

The CSS prefixes these values with `--dn-` to prevent collisions with shadcn's
different meanings for `primary` and `secondary`. Proposed intermediate shades
use `color-mix()` from the saved palette. Black on the solid blue actions is a
contrast-derived foreground (4.83:1 dark palette; 5.39:1 light palette).
The folder's `#483576` is sampled from the supplied taxonomy screenshot;
it is category identity, not a forum root CSS variable. The icon is mixed with
the foreground in dark mode for legibility.

## Files

- `source.html`: editable fragment, including scoped styles and interactions.
- `index.html`: standalone browser export with the visualization runtime.
- `buttons.css`, `interactions.js`: readable extracts of the fragment's CSS and JS.
- `palette.json`: appearance values only; no account or authentication data.
- `meta-palette.json`: Meta's saved light/dark appearance, added on 13 September
  for native implementation regression checks. The original four HTML proposals
  continue to use the dev.discourse.org snapshot.

The standalone export loads the supplied visualization runtime's icon and
positioning assets from its approved CDNs. The proposals themselves do not
fetch forum data. The source fragment uses the host's icons when shown inline.

Reference: [shadcn Base UI Button](https://ui.shadcn.com/docs/components/base/button).
Local references: `docs/component-library/conventions.md`, the button catalogue,
button styleguide, `DControlStyle`, and `AppTheme.fromPalette`.

## Verification

Reviewed in the Codex browser in the saved dark and light palettes, including a
360px viewport with 36px controls; checked a 320px viewport for horizontal overflow
(none in the option, filter, action or taxonomy rows). Verified dropdown selection, bookmark state,
reply preview, pagination selection, and shared appearance/radius/height changes.
Computed styles confirmed the exact forum accent, 32px height and 8px radius.
The user selected D for application adoption. The HTML files preserve the
original comparison; [the implementation record](../../component-library/contextual-tints.md)
describes the shared Native controls, native adaptations and verification.
