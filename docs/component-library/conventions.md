# Native component library conventions

Read [the brief](brief.md), [frozen catalogue](catalogue.json), [progress](progress.md),
and [migration inventory](inventory.md) before implementing a component.
Reference date: **2026-09-08**. The 64 entries linked by the official
[All Components catalogue](https://ui.shadcn.com/docs/components) define scope.
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

## Theme, layout and interaction

`DTokens.of(context)` supplies semantic colors and radius, with a fallback for
ordinary Material themes. `AppTheme` maps the real site palette into this
extension. Generic components read tokens during build; do not cache palette
colors in initState, route closures, or overlay entries. `DSpacing` and
`DMotion` supply shared geometry and motion. Typography uses the existing
unscaled `DiscourseTypography` size tokens with each shadcn component's explicit
leading, weight and tracking. Theme text roles supply font families, not substitute
component metrics. Do not scale font sizes manually. Map the configured site
palette, font and radius into shadcn's semantic variables and relative radius
scale. Preserve contrast and native interaction without replacing the reference
appearance with Material or Cupertino defaults. A deviation needs a concrete
conflict and a specific rationale. Follow [visual fidelity](visual-fidelity.md).
Avoid hardcoded light/dark swatches in reusable components.

Use logical constraints, directional padding/alignment and intrinsic text
height. Pointer layouts may be compact while touch controls retain accessible
hit areas. Support touch, hover, keyboard, visible focus, semantics, text
scaling, narrow layouts, RTL and reduced motion where applicable. Never expose
selected, error or loading states using color alone.

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
up to four new implementation tasks running as dependencies become available.
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

After all 64 component rows are merged, create a final separate audit task to
improve shared code, API consistency, composition, themes, accessibility,
examples and missed app migrations. Review, verify and merge its changes before
marking the overall goal complete.


Flutter widget-test image exports can support rendered reference comparison;
record fonts, viewport, source and renderer explicitly. They do not replace
native fixture verification. Use approved browser/native tools under the
shared desktop lease, and report actual permission or policy blockers without
bypassing them.
