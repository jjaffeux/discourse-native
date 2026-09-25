# Native component library conventions

Read [the brief](brief.md), [frozen catalogue](catalogue.json), [progress](progress.md),
and [migration inventory](inventory.md) before implementing a component.
Reference date: **2026-09-08**. The official
[All Components catalogue](https://ui.shadcn.com/docs/components) originally
defined 64 entries. The user removed Native Select on **2026-09-10**, leaving
63 components; `DSelect` owns both plain and rich selection fields.
The default links currently use Base UI. Other reference engines are supporting
material, not additional components. Toast includes Sonner; the old Sonner URL
and framework-specific form integration pages do not add catalogue rows.

## Ownership and API

- Public entrypoint: `package:discourse_native/discourse_ui.dart`.
- Component widgets: `lib/src/ui/components/d_<component>.dart`, named `DButton`,
  `DButtonGroup`, `DSelect<T>`, etc. Preserve useful existing D-prefixed APIs while
  extending them for the frozen reference. Remove obsolete source implementations
  and migrate imports; do not leave two rendering owners.
- Shared UI foundations: `lib/src/ui/foundation/`. Add shared primitives only
  when actual consumers justify them. Use relative imports internally, public
  barrel imports for app callers and example files.
- Generic components accept values, models describing presentation, builders,
  child widgets, controllers, and callbacks. They must not import app data,
  shell controllers, site models, networking, plugin services, or stores.
  Application adapters live in the owning shell/plugin directory.
- Use immutable typed options and enums, generic values for selection, nullable
  callbacks to disable actions, named parameters, and ordinary Flutter child /
  children / builder composition. Expose owned-versus-borrowed controller and
  focus-node lifecycle explicitly. Never dispose borrowed resources.
- Use Flutter FormField / Form integration for editable fields, including
  initial value, validation, save/reset and controlled-value updates where
  applicable. Do not invent a second app-wide form state system.
- Every public feature must work; no inert properties or illustrative-only
  control affordances. No TODOs. Document public behavior and constraints.

## Application design system

[Application design rules](../design/reference-rules.md) records the audited
local HTML reference, complete page recipes and the current shared scale. It
supersedes older component measurements for typography, spacing and geometry.
The live specimen is Foundations → Application design scale.

## Control consistency

The September 18 HTML redesign defines three button families through `DButton`:
`primary` for colored actions, `outline` for outlined actions, and
`transparentBackground` for clear toolbar actions. `secondary` aliases the
outlined treatment and `ghost` aliases the transparent treatment. Destructive,
link and inline actions retain their semantic roles; inline removes horizontal
insets for metadata. All variants retain shared focus and accessible targets.
Buttons use palette-derived muted accent fills, 1px outlines, the theme’s control
radius and no shadow. Outlined toggles use the same button palette, 1px border
and theme radius, with the hover fill and border retained while selected. Joined toggle
groups retain ownership of their outer corners and shared seams. See [button redesign](button-redesign.md) for formulas, adoption,
reference measurements and verification. Ordinary dropdown triggers use
`DDropdownMenuTrigger.button`; richer compositions render DButton and pass
through focus, expanded state and activation.

Use shared control geometry and paint from `foundation/control_style.dart`.
Button-like controls must use the Button styleguide's shared `DControlSize`
scale: general desktop `small` (24px), `regular` (34px), and `large` (40px).
Application surfaces use the [mockup presets](../design/control-size-parity.md)
for filters, fields, preferences, chips, toolbars, segments, window navigation
and footer actions. Do not normalize these to a general size.
On iOS, Android and Fuchsia, the same sizes render at 40/44/48px with
the same 12.5/13/14px labels and 12/14/16px icons as desktop. Touch targets remain at least 48px.
Platform comes from the inherited theme, including mobile web; resizing a
desktop window does not change its control density. Desktop small labels use
12.5px text with 18.75px leading; regular labels use 13/19.5 and large
labels use 14/21.
Mobile tab buttons use the approved `DButtonDensity.mobileNavigation` preset:
44px artwork and full 18px glyphs on every platform, including desktop previews.
The preset removes DIcon’s ordinary optical inset within the button.
It supersedes the size preset, grows with text scaling and retains a 48px target.
Mobile notification categories use the September 23 approved
`DTabListVariant.outlinePill`: outlined capsule tabs, an accent-filled selected
state and 6px gaps. Use the small control size; Tabs owns horizontal scrolling,
keyboard navigation, text scaling and the 48px touch targets. Labels retain
unread counts in semantics while the compact strip displays category names.
Topic header actions use `DControlSize.chip`: 24px artwork with intrinsic icon
width and the reference insets. Header taxonomy chips use `filter` (30.75px).
These supersede the earlier `compactToolbar` migration for these surfaces.
The density remains available to existing consumers with a deliberate fixed
32px icon surface; avoid applying it over an application size preset.
Chat reaction chips use the explicitly approved `DToggleDensity.reaction`:
28px artwork, 18px emoji, 12px counts with 16px leading, and symmetric 8px
horizontal padding. This density supersedes the size preset, grows with text
scaling and retains the 48px touch target. Emoji adapters inherit the toggle's
IconTheme so raster artwork follows the actual control metrics.
Start page density choices use `DToggleDensity.compactInset`: a 68×32px inset
frame around two 30×26px icon surfaces, matching the mobile mockup. The Native
group retains separate 48×48px mobile touch targets around those surfaces.
Topic header tags opt into `DBadgeSize.control`, which uses the filter control
height, label and artwork metrics on each platform. Other badges retain their
regular or compact status/count geometry.

Desktop composer block actions use the approved `DButtonDensity.composerBlock`
exception: 20px width, regular 34px height and unchanged 14px icons. The adjacent
add and drag actions remain transparent and share a 46px gutter including the
6px gap before text. `DDragHandle.density` passes this preset through to Button.
The preset retains standard geometry and accessible targets on touch platforms.

Extra-small controls have been removed; use small for compact actions. See
[the compact sizing update](compact-control-sizing.md).
Component size names are aliases of this enum. Do not introduce alternate
height enums, control-height wrappers, or padding/constraint size overrides.
The kit owns text-scaling growth and invisible accessible touch targets.
Prefer variant and size over local colors, radius or padding. Category identity,
the selected bookmark's themed fill inside an outline group, and explicitly
inventoried container geometry are the current exceptions in
`test/control_style_adoption_test.dart`. Review any new exception against a
concrete application requirement. Compare the Button **Control consistency**
example across palettes and states whenever changing a control foundation;
update its golden baselines only after visual review. See
[the migration and verification record](control-consistency.md).

Input, Input Group (including Combobox anchors), Select and multi-value Combobox
fields use the redesigned outlined palette through `DTokens.buttonTheme`, with
1px borders, the theme’s control radius and no shadow. Selection hover/open states
use the outlined hover fill and border. Other editable controls retain their existing
`DTokens.controls` styling. Buttons and button-based popup triggers also use
the theme’s control radius, independent of size. Keep the default
`DButtonShape.rounded` in application code; explicit pill shapes belong only to
documented design exceptions. Menu rows use 33.5px artwork (at least 48px interaction bounds on touch), 7px highlight corners,
7×8px item insets and 6px outer padding inside 10px popup corners. Keyboard focus uses a 1px ring separated by 2px. Hover, pressed and
open fills change immediately, without translating the control. The `AppTheme`
boundary derives colors from the current forum palette; category identity
retains its own color. Topic filters and header triggers use their application
presets; bottom actions use `action` (34px desktop, 44px mobile). All retain text
scaling and 48px touch targets.
See [the reference measurements and verification](linear-controls.md), which
supersede the earlier [contextual tint styling](contextual-tints.md).

Desktop topic-list and reader footers use `DCardFooter(rounded: true)` for
upper corners matching the Card radius. The kit clips the surface and paints
the top outline above its contents. `padding` supports existing toolbar spacing
and `backgroundColor`/`borderColor` accept semantic colors. Desktop footers use
`DTokens.footerBackground` (5% foreground mixed into background) and
`DTokens.footerBorder` (12%), matching `--surface-footer` and `--border-subtle`
in the September HTML reference. There is no shadow. Touch footers retain their
opaque background and top divider. Ordinary card footers retain their shared
spacing and square upper edge.

`DCard.backgroundColor` and `DPageSurface.backgroundColor` can supply a
translucent surface fill without changing descendant tokens, outlines or
clipping. Page Surface applies the fill only when framed. Custom forum
backgrounds use this option at panel boundaries so a single window effect
continues behind the sidebar, list and reader. Inner content stays transparent;
the fixed footers retain their own stronger fill and top border.

`DCard.borderRadius` and `DPageSurface.borderRadius` accept per-corner geometry
for window-adjoining panels; the Native Card owns both the outline and clip.
The macOS workspace passes its inset bottom-right window corner through split
layouts to the outermost panel. Other corners retain the forum's Card radius.

### Adjacent control spacing

Theme settings use the approved mockup form recipe: `SettingsSection` composes
a heading and outlined Native Card, with filled Native Input/Select fields.
`filled: true` uses a 10% foreground fill and 90% text without changing field
geometry. `DSliderVariant.ramp` owns the 26px gradient/checker/wave capsule and
ring thumb, retaining a 48px touch target. `DColorPickerSize.compact` provides
the 58px dotted colour grid and rounded popup swatch. `DToggleDensity.tile`
places the icon above the label; `DToggleGroup(expanded: true, inset: true)`
owns equal-width choices and their recessed frame. Ordinary variants retain
their existing defaults. See [live theme settings](live-theme-settings.md)
for the reference, persistence model and verification.

Use `DSpacing.controlGap` (6 logical pixels) between separate adjacent buttons,
toggles, toggle groups, selectors and menu triggers in action rows and toolbars.
The gap is measured between painted control surfaces. For compact icon actions
with larger touch targets, use `DButtonGroup.spaced` so the targets do not add
invisible padding to the visible gap.
Use it with `Row(spacing: ...)`, `Wrap(spacing: ...)` or a `SizedBox` between
conditional children. Dialog action footers use the same horizontal gap.
Use the general spacing scale for wrapped-row spacing, content, section gaps
and control internals. Joined `DButtonGroup` and `DToggleGroup` retain ownership
of their internal geometry. The Button styleguide’s Control consistency example
shows this standard across sizes and mixed control types.

## Theme, layout and interaction

`DTokens.of(context)` supplies semantic colors and fixed app geometry, with a fallback for
ordinary Material themes. `AppTheme` maps the real site palette into this
extension. Generic components read tokens during build; do not cache palette
colors in initState, route closures, or overlay entries. `DSpacing` and
`DMotion` supply shared geometry and motion. Typography uses the existing
unscaled `DiscourseTypography` size tokens with explicit application
leading, weight and tracking. There is no mobile typography multiplier. Theme text roles supply font families, not substitute
component metrics. Do not scale font sizes manually. Map the configured site
palette and font into semantic variables. The Native kit fixes panels at 14px,
primary buttons, unselected tab buttons and tags at 999px, selected tab buttons
at 14px, and ordinary controls at 8px, independently of the site radius.
Preserve contrast and native interaction without replacing the reference
appearance with Material or Cupertino defaults. A deviation needs a concrete
conflict and a specific rationale. Follow [visual fidelity](visual-fidelity.md).
Avoid hardcoded light/dark swatches in reusable components.

Use logical constraints, directional padding/alignment and intrinsic text
height. Pointer layouts may be compact while touch controls retain accessible
hit areas. Support touch, hover, keyboard, visible focus, semantics, text
scaling, narrow layouts, RTL and reduced motion where applicable. Never expose
selected, error or loading states using color alone.

The app and standalone styleguide mount `DFocusHighlight` above the Navigator.
Tab/Shift+Tab enables focus outlines; mouse/touch presses hide them until the
next Tab. Hovering and ordinary typing do not change that choice. Components
that paint from raw focus state must also check `DFocusHighlight.visibleOf(context)`
for their focus decoration. Keep actual focus, carets, selection and validation
styling independent. Standalone component hosts without this app policy retain
their default focus styling.

Interactive list rows (Item, Command, Combobox, Select, Navigation Menu and Dropdown Menu,
including context-menu and menubar consumers) use
`foundation/interactive_row.dart` to paint state changes immediately. Never
cross-fade row backgrounds: the outgoing and incoming highlights otherwise
overlap. Choice lists have one accepted active row shared by pointer and keyboard
navigation; local hover or focus must not paint a second active background.
Full-width topic rows use `DItemShape.fullWidth` with
`DItemSelectionStyle.leadingAccent`: square edges, immediate accent hover, and
a stronger selected tint with a directional leading border. The application
composes title, excerpt and metadata inside Item; the kit owns its interaction
paint. Other choice lists keep persistent selection in their checkmark/checkbox.
Theme thumbnail cards use Item's outline selection without a checkmark so their
height stays fixed when selected. The approved `DItem.cornerAction` slot places
an independent Native control at the top trailing corner. Item reveals it on
hover or focus and keeps it visible on touch platforms and with accessible
navigation. Reserve the corner in the header; Button retains action geometry,
keyboard handling, semantics and focus. See Item / Hover corner action.
Regression tests must inspect
painted decorations immediately and during the next animation frames, without
settling first.

Keep editable native semantics bounded to their actual field or editor. A
text-field role merged into a page or card can hide unrelated descendants from
native accessibility clients even when Flutter finds their labels in tests.
Check bounds, independent control ancestry and meaningful native AX output.
Prefix/suffix actions and surrounding buttons must remain separate controls.

Prefer Flutter's proven interaction owners (Actions, Shortcuts, Focus,
MenuAnchor, OverlayPortal, Navigator, ScrollController, FormField) over copying
React internals. Use the nearest Navigator for reusable component overlays
(`useRootNavigator: false` by default for dialog helpers) so composition works
inside the styleguide viewport and nested application surfaces. Theme changes
must reach open overlays; capturing a ThemeData at open time is insufficient.
Define focus entry/restoration, Escape/outside dismissal, collision handling,
scrolling, removal during callbacks, and async completion ownership.

## Styleguide

- Launch inside the app using the palette button in the bottom-left rail, or
  run `flutter run -d macos -t lib/styleguide_main.dart --no-pub` for independent
  sample data without app credentials or requests.
- The documentation shell uses the shared DSidebar component. Keep its compact
  navigation, 640px reading width, neutral local theme and preview/code panels
  aligned with [the measured design](styleguide-design.md). Previews receive
  the original app theme, not the documentation canvas theme.
- Each component owns `lib/src/styleguide/examples/<component>_examples.dart`.
  Register its `ComponentExamples` in `component_examples.dart`, with a short
  `description` for the page introduction and detailed `notes` for its disclosure. Only mark it
  `implemented` after acceptance and verification. The initial Button, Tooltip
  and Select groups are explicitly **baseline**, not completed catalogue work.
- Add runnable `StyleguideExample` entries for all variants, states, composition
  patterns, and meaningful edges. Include accurate usage code, interaction
  instructions, and intentional native adaptations. Examples import the actual
  public library and keep all sample state local. Ordinary example actions use
  the available DButton. Its baseline label defaults to one line, so rich labels
  must explicitly retain wrapping. Keep any native-button exception specific
  and justified under the existing adoption guard. Break complex examples into
  their own StatefulWidgets rather than crowding a registration expression.
- Theme, viewport width, text scale, direction, and reduced-motion controls
  operate on a preview Navigator without changing the real app's settings.
  The article is bounded; explicit viewport presets keep their requested width
  and scroll horizontally inside the clipped preview. The reset control
  intentionally reconstructs example state; other controls must
  preserve it. A component may extend preview geometry when its behavior needs
  more space, provided the new API works for existing examples.
- `component_catalogue.dart` is generated from the frozen JSON via
  `dart run tool/generate_component_catalogue.dart`. Do not hand-edit it or
  silently resnapshot upstream to expand or reduce scope.

## Verification and workflow

The user resumed the remaining catalogue on 2026-09-09 after the Sidebar and
styleguide review. Work is local only: commits and reviewer-owned merges into local
main are authorized. Do not push or perform other GitHub writes. Do not change
anything in App Store Connect or perform release/submission work. Public source
and documentation reads remain available.

The user's explicit focused-verification policy overrides CLAUDE.md's blanket
full-suite gate for this project. Format touched code, run static analysis and
meaningful focused interaction/regression tests, including downstream consumers
when shared primitives change. Run affected compatibility-package checks as
needed. Do not update unrelated lockfiles or the Flutter pin (3.47.2).
Inspect the running styleguide and changed app surfaces in representative
palettes and viewport sizes. Compare the rendered component with the official
reference at matching width, text scale and state; passing interaction and
overflow tests alone does not establish visual fidelity. Temporary local-data
fixtures that mount the real
production widgets can exercise migrated loading, empty, error and ready states
without changing account data. Record the actual surfaces inspected alongside
the styleguide examples. Report exactly which platforms and interactions
were run; widget tests with target-platform overrides are not device testing.

The user authorized concurrent component tasks on 2026-09-08, and on
2026-09-09 requested a new review-and-merge Codex task for each existing
unmerged item. Each future implementation must also create a new reviewer
task. The reviewer owns fixes, verification, integration and local main merge
without returning to the coordinator for approval. Follow the committed
[review and merge procedure](review-and-merge.md), including shared desktop
and main-checkout leases. The 17 backlog reviewers run independently; keep
up to five new implementation tasks running as dependencies become available.
Each component implementation uses its own isolated worktree from latest main
and `codex/ui-<component>` branch. Preserve original implementation task and
branch history alongside the reviewer task and branch in progress. Source
preparation alone does not satisfy reference/native acceptance or mark a row
merged. Reconcile shared exports, examples, app migrations and progress against
previously merged owners in the reviewer's own worktree.

For isolated ad-hoc macOS review bundles, omit restricted push/team/application
identity entitlements and read back the permitted debug entitlements. Preserve
required local debug capabilities; do not change the real app's provisioning or
OS security settings. Static strict signature verification does not by itself
prove launch eligibility; record the actual launch and source/kernel evidence.

Builds, analysis and widget tests can run concurrently in separate worktrees.
Native and browser actions share one desktop lease; acquire it directly using
`tool/component_review_lock.py`, finish the review and release it without a
coordinator gate. Main-checkout mutations use a separate exclusive `main`
lease. The reviewer fixes issues and merges with `--no-ff`
**from `/Users/joffreyjaffeux/Code/discourse-native` on main**. Preserve unrelated
changes. Never merge main into a component branch as the final project merge.

`progress.json` is the durable coordination record. Before implementation,
fill the row's task ID, branch, dependencies and concrete acceptance criteria.
Record decisions, migrations and retained alternatives, verification commands
and outcomes, limitations, implementation commit, then merge commit. Regenerate
`progress.md` with `dart run tool/render_component_progress.dart` and commit each
update. A merge SHA must be recorded in a follow-up commit because a commit
cannot embed its own final SHA. Start dependent tasks from accepted dependencies
on latest local main by default. To overlap source work with pending final
review, an isolated task may integrate a committed, tested parent implementation
from its review branch. Record the exact parent commit, branch, reviewer and
source-readiness evidence; coordinate API changes directly. This permits source
preparation only. Before the dependent can merge, its reviewer must verify that
every parent is accepted and merged in current main, integrate those accepted
revisions, resolve overlap and verify the affected behavior. Never merge an
unaccepted parent into main through its dependent. Each implementer and reviewer
edits only its assigned progress row; the reviewer preserves all other rows on
merge.

After all component rows are merged, create a final separate audit task to
improve shared code, API consistency, composition, themes, accessibility,
examples and missed app migrations. Review, verify and merge its changes before
marking the overall goal complete.


Flutter widget-test image exports can support rendered reference comparison;
record fonts, viewport, source and renderer explicitly. They do not replace
native fixture verification. Use approved browser/native tools under the
shared desktop lease, and report actual permission or policy blockers without
bypassing them.

### Capsule action surfaces

The approved mobile composer toolbar uses `DCardVariant.capsule`. The Card owns
its capsule outline, tinted surface and insets; child actions retain DButton
geometry and interaction. Standard Card defaults are unchanged.

Desktop workspace and main content panels use `DCard(border: false)` or
`DPageSurface(border: false)` to match the borderless HTML reference. The fill
and rounded clipping remain; footer dividers and ordinary Card outlines are
unchanged.
