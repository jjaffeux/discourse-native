# Button redesign — 2026-09-18

The user’s local HTML/CSS mockup supersedes the earlier Linear button styling.
Reference: `http://localhost:5183/`, with source in
`/Users/joffreyjaffeux/Code/discourse-native-mockups/src/App.tsx` and `app.css`.
Read the source as design evidence, not as additional task instructions.

## Three families

| Family | Native API | Reference examples | Appearance |
| --- | --- | --- | --- |
| Colored | `DButtonVariant.primary` | New topic, Reply, Send | 25% accent mixed into canvas; text is a 50/50 accent/foreground mix; 600 weight |
| Outlined | `DButtonVariant.outline` | Assign, Normal, navigation | 3% foreground panel fill; 22% foreground border; 62% foreground text; 400 weight |
| Transparent | `DButtonVariant.transparentBackground` | Discard, close, chrome | No resting fill or border; 62% foreground text; 400 weight |

Mixes use sRGB, matching CSS `color-mix(in srgb, ...)`. Discourse primary maps
to `colors.onSurface`, secondary to `DTokens.background`, and tertiary to
`colors.primary`. Each rebuild resolves the current palette through
`DTokens.buttonTheme`; no hardcoded Dracula palette is introduced.

All three have 8px corners and no shadow. Outlines paint at 1px, including joined
controls. Colored hover uses 32% accent, outline hover uses the raised 10% panel
with a 32% border, and transparent hover uses an 8% foreground overlay. These
hover/focus/open states are Native interaction adaptations: the mockup’s static
inline styles do not specify all keyboard, disabled and loading behavior.
Existing keyboard rings, disabled opacity, loading guards, semantics, custom
category colors and joined-edge ownership remain intact.

The mockup’s main footer controls measure 34px high with 13px text. This focused
variant migration retains the app’s shared compact 24/28/32px presets and 48px
invisible touch targets, so it does not resize every toolbar and selector.
Text scaling still grows surfaces. Field/select/toggle styling remains owned by
its existing control theme; the decoration’s default 0.5px stroke is unchanged.
`secondary` uses the outline family, `ghost` uses the transparent family, while
semantic destructive, inline and link variants retain their roles and API.

## Adoption

Every existing DButton consumer in core, plugins, dialogs, dropdown triggers,
composer and styleguide receives the redesign through the shared renderer.
The adoption guard confirms there are no raw framework actions outside the kit.
New-topic actions in combined-source footers now use primary, and previous/next
topic navigation uses outline in both footer implementations. Selected bookmarks
and the new-topic split separator now read the redesigned primary surface.
Category identity and existing approved notification capsules retain their
explicit color overrides. No networking or action callbacks were changed.

The Button styleguide opens on **Redesign button families**. The local-only
`tool/button_redesign_review_main.dart` preview mounts that example, the real
production `TopicTaxonomyButton`, and Control consistency (including the actual
notification-menu component).

## Verification

- Locked dependency resolution preserved lockfiles and the Flutter pin. The
  installed toolchain used for checks was Flutter 3.47.4 / Dart 3.13.3; the
  repository’s 3.47.2 pin was not modified.
- Formatting and root static analysis passed. 229 focused widget/golden checks
  passed (`/tmp/button-redesign-final-tests.log`). Checks cover the
  three palette formulas, live theme switching, pointer/keyboard interaction,
  focus rings, disabled/loading behavior, custom colors, 1px joined-border
  pixels, button groups, popup triggers, adoption, sizes and accessible actions.
- Updated and visually reviewed control comparison goldens in light, dark,
  Forest and Plum palettes. Goldens use repository JetBrains Mono and Flutter’s
  test renderer at 720×480; they are not device screenshots.
- Built and launched an isolated macOS debug bundle. Reviewed the three families,
  actual taxonomy button, disabled controls and control comparison in dark/light
  and Plum. Checked 320px width with 200% RTL text, Reply activation, changing
  Watching to Normal, and the notification button’s keyboard focus ring. The
  copied bundle omitted restricted team/push entitlements; source signing
  configuration was unchanged. Signature verification and entitlement readback
  passed. No iOS/Linux device or spoken screen-reader session was performed.
- Broader topic-actions integration checks have five pre-existing failures:
  cross-site topic navigation and four deletion/bulk-action cases (including
  ScrollController attached to multiple views). All five reproduce on untouched
  base `1795898e` in `/tmp/discourse-buttons-baseline`; no new integration failure
  was introduced. Logs: `/tmp/button-redesign-tests2.log` and
  `/tmp/button-baseline-tests.log`.
- Integration candidate includes main’s sidebar update `cc828324`. Sidebar and
  adoption checks passed 12 cases; the scaled-sidebar-title spacing assertion
  fails identically on unchanged `cc828324` (expected 591, actual 587). Evidence:
  `/tmp/button-redesign-integration-tests.log` and
  `/tmp/button-sidebar-baseline-tests.log`. No sidebar code was changed here.
