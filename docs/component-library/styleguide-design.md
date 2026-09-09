# Documentation design correction

The user reviewed the original Flutter styleguide on 2026-09-09 and requested
much closer fidelity to shadcn. They then explicitly prioritized implementing
Sidebar before using it in the styleguide. This follow-up covers that component
and the documentation shell; the remaining component queue stays paused.

## Reference

Inspected the rendered [official Card documentation](https://ui.shadcn.com/docs/components/base/card)
and [component catalogue](https://ui.shadcn.com/docs/components) on 2026-09-09.
The reference browser was in dark mode. DOM measurements establish:

| Reference | Documentation implementation |
| --- | --- |
| 30px navigation rows with 2px gaps; 12.8px type | DSidebarMenuButton with 30px minimum visual height; 13/18px host-font text and compact grouping |
| 30/36px page title, 600 weight, −0.75px tracking | Explicit matching title metrics |
| 16/24px muted introduction | One-sentence ComponentExamples.description |
| 640px article | Bounded, centered content with responsive outer padding |
| Neutral background, quiet selection, separate scrolling navigation | Local documentation DTokens theme and actual DSidebar composition |
| 1px preview border and 18px radius | Rounded preview/code panel with centered sample content |
| Small controls and code disclosure | Compact theme/width toolbar, optional advanced settings, reset, code reveal and copy |
| Right-hand page navigation | Example selection plus functional usage/notes links on wide windows |

The app font remains the configured host font, rather than loading the website's
Geist font. On macOS the header reserves space for native traffic lights. Touch
platforms receive accessible interaction targets; large text can grow controls.
These adaptations do not replace component geometry with Material defaults.

## Composition and state

The documentation shell uses DSidebarProvider, DSidebar, DSidebarContent,
DSidebarGroup, DSidebarGroupLabel, DSidebarMenu, DSidebarMenuItem,
DSidebarMenuButton, DSidebarHeader and DSidebarTrigger. The sidebar is 240px on
desktop; below 900px the shared modal navigation owns focus and dismissal.
Cmd/Ctrl+K opens navigation when necessary and focuses its search field. Selection
closes mobile navigation while retaining the search. No custom navigation
renderer remains in the styleguide.

The header's light/dark toggle changes only the documentation canvas. Preview
palettes resolve from the original app ThemeData, with local light/dark/Forest/
Plum overrides. Their nested Navigator preserves overlays and sample state;
preview settings, code disclosure and window resizing do not reset examples.
Reset intentionally remounts the selected example. Palette changes and example
data never persist to app settings.

Explicit 360/768/1024px previews keep their requested logical width. Wider
previews scroll horizontally within the article, with a visible mouse-draggable
thumb. Sidebar demos use a 500px breakpoint so their desktop panel is visible
inside the 640px article and their modal variant can be reviewed at 360px. The
public component's default breakpoint remains 768px. Sidebar panels receive a
500px preview height so their fixed footer and independent content scroll fit.

Implementation status no longer adds a second line to every navigation item.
Unimplemented pages explain their pending state, and Button/Select retain a
visible baseline notice. Detailed implementation notes and frozen reference
coverage are available below each example. The foundation example composes the
actual Card and existing Button with theme swatches. Compact documentation
controls are styleguide-only native adapters; pending catalogue controls are
not marked complete by this correction.

## Verification

Final implementation: `6d8c63edcbcd8372408a4a5ec8ccc9d8479e5bbb`.

- All 160 affected styleguide, Sidebar and Button-adoption tests passed at
  `f19ded8b11fab0a90b0312c22d2af11a7051d1e0`, using
  `flutter test --no-pub test/styleguide test/d_sidebar_test.dart test/d_button_adoption_test.dart --test-randomize-ordering-seed=2847364191`.
  This includes actual shared-Sidebar adoption, narrow search, state retention,
  component registration, 200% text, theme isolation and example interaction.
- After adding the explicit horizontal scrollbar, all 14 styleguide-page tests
  passed with `flutter test --no-pub test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=1283551953`.
  The new mouse-drag assertion checks real scroll movement in a
  1024px preview, then verifies state survives returning to 360px. Log:
  `/private/tmp/styleguide-preview-scroll-tests.log`.
- Formatting and `git diff --check` passed. Root and full-profile
  `flutter analyze --no-pub` are clean. Full-profile
  `flutter pub get --enforce-lockfile` passed without changing dependencies.
- `flutter build macos --debug --no-pub -t lib/styleguide_main.dart` passed on
  the final implementation. The isolated bundle uses identifier
  `org.discourse.native.styleguide.b104.20260909`, display name
  `Styleguide Review B104`, and its own URL scheme. Its compiled kernel matches
  the source build, SHA256
  `90f5d1b5d4689ca2a660441be25859071c9f9c9f15bf3dc10817147efc373342`.
  Deep strict ad-hoc signature verification passed. The copied app is at
  `/private/tmp/DiscourseStyleguideB104-20260909.app`.

### Native observations

The coordinator inspected the source checkpoints `61013543`, `09a2d3d1` and
`f19ded8b` in the isolated macOS app. Screenshots and accessibility observations
are inline in the coordinator task. Desktop captures were 1144×768, representing
the 1280×860 logical window; the actual narrow window was 517×860.

- Neutral dark and light documentation, compact selected navigation, page
  geometry, toolbar and code disclosure were compared with the official page.
- Documentation light mode left the host preview dark until its own Light
  option was selected. The Light dropdown's focus fill is now neutral.
- Foundation actions retained their count through code disclosure and preview
  settings. Swatch captions wrapped as whole labels at 200% text and 360px.
- Search and pointer selection opened Card; its example was horizontally
  centered. Resizing to an actual narrow window hid desktop navigation and
  exposed the shared Sidebar trigger. The drawer retained the search, Escape
  dismissed it and the trigger regained its visible focus ring. Searching for
  Sidebar and choosing it closed the drawer and opened the correct page.
- Sidebar's desktop demo was visible inside the compact article after the
  example breakpoint adjustment. Selecting Inbox reported "Inbox selected";
  the state survived switching to the actual 1024px preview.
- Native review identified a compact navigation semantic target spanning the
  entire row. `09a2d3d1` isolates each button's semantic bounds and removes the
  observer Focus node's extra semantic container. A regression test verifies
  the compact button's exposed bounds match its actual hit area.

### Limits

The Mac locked before the last screenshot of the final explicit scrollbar.
That final scrollbar appearance and native drag remain unverified; its mouse
interaction is covered by the passing widget test. Earlier synthetic native
horizontal-scroll and Cmd/Ctrl+K attempts produced no visible response. The
shortcut bindings pass widget tests; no native shortcut success is claimed.
Some native accessibility trees exposed only editable fields and popup items,
so pointer coordinates were used when the tree lacked controls. No spoken
VoiceOver, iOS/Linux device run or pixel-diff equality is claimed.

The final review bundle remains available for the user's review. No real
account app was launched or changed during the isolated inspection. The real
app build and local-main merge are recorded in [the checkpoint](review-checkpoint.md).


## Current review previews

The coordinator exported the current Foundations page in Light and Dark using
Flutter's widget-test renderer at 1270×847 logical pixels / 2× output. The
explicitly loaded fonts are system SFNS and Flutter's Material icon font. This
shows the actual widgets and layout, independently of the locked desktop.

The render source is `c5d37bd18148337f3a6be894c27c44af920f0e2c`; its complete
styleguide and Sidebar source matches `6d8c63ed` byte for byte. The temporary
export harness completed successfully (`/private/tmp/styleguide-b104-render.log`).

Previews and their JSON provenance are under
`/Users/joffreyjaffeux/.codex/visualizations/2026/09/08/01a0816f-d4e0-7f93-9d6b-baeaf6961181/`:
`styleguide-current-dark.png`, `styleguide-current-light.png`, and
`styleguide-preview-provenance.json`. These previews do not complete the pending
native scrollbar/keyboard inspection or replace component reference comparison.
