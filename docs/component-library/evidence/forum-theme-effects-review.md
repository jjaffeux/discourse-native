# Custom theme noise and transparency

Reviewed on 2026-09-23.

The custom theme editor uses existing Native `DSlider` and `DField` components
for independent noise intensity and panel transparency. Noise defaults to 20%
and can reach zero without removing the gradient. Color strength does not
change grain intensity. Panel transparency defaults to 10% and is limited to
0–20%; content panels stay at least 80% opaque and footers at least 95% opaque.
At zero transparency, both are opaque. Controls and overlays retain their
existing opaque fills.

Both settings belong to each light/dark background and survive saving,
import/export, and palette resolution. Older JSON backgrounds without these
fields receive the new defaults. Invalid values, including transparency above
20%, are rejected on import. No Native component API or styling changed.

Verification:

- `dart analyze`: no issues.
- 40 focused tests passed across `appearance_background_test.dart`,
  `forum_background_noise_test.dart`, `forum_theme_editor_test.dart`,
  `forum_theme_preview_test.dart`, and `forum_theme_test.dart`. Coverage includes
  keyboard endpoints, independent mode drafts, saving/reopening, legacy JSON,
  rendered grain at zero/default/full intensity, smooth gradients, unchanged
  grain when transparency changes, nested canvases, and narrow RTL layouts at
  2× text with macOS/iOS target overrides.
- `site_theme_app_test.dart` also exercised the real desktop and mobile shell.
  Its two maximum-text-size cases fail while finding `settings-rail-button`;
  both failures reproduce on unchanged baseline `de9b76d39` in a temporary
  worktree. They are unrelated to custom theme effects.
- Built `tool/continuous_background_review_main.dart` using Flutter 3.47.4,
  matching `.fvmrc`, and launched an isolated ad-hoc signed macOS bundle with
  the existing review entitlements. Inspected the actual custom editor and
  production preview in dark and light appearance drafts, wide and narrow
  windows, plus the Native Slider styleguide's Filled strength and Default
  examples. Confirmed native slider labels/values, noise Home → 0%, transparency
  End → 20%, and no increase past that cap. The smooth gradient remains visible
  in the preview. The fixture uses in-memory forum settings and offline data.

No physical iOS/Android testing or full-suite run was performed.

Merged into local main as `34401f864`. Integration verification found a stale
44px preview-footer assertion: main's shared desktop controls had already grown
from 28px to 34px in `236d81627`, giving the padded footer a 50px height. Updated
that assertion to the current layout; no production geometry changed.
All 40 focused checks pass on main after that adjustment; static analysis is clean.
