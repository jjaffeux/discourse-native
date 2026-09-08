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
semantic `Theme.of(context).textTheme` roles; do not scale font sizes manually.
The site's radius, contrast policy, and native conventions take precedence over
literal web CSS. Avoid hardcoded light/dark swatches in reusable components.

Use logical constraints, directional padding/alignment and intrinsic text
height. Pointer layouts may be compact while touch controls retain accessible
hit areas. Support touch, hover, keyboard, visible focus, semantics, text
scaling, narrow layouts, RTL and reduced motion where applicable. Never expose
selected, error or loading states using color alone.

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
- Each component owns `lib/src/styleguide/examples/<component>_examples.dart`.
  Register its `ComponentExamples` in `component_examples.dart`. Only mark it
  `implemented` after acceptance and verification. The initial Button, Tooltip
  and Select groups are explicitly **baseline**, not completed catalogue work.
- Add runnable `StyleguideExample` entries for all variants, states, composition
  patterns, and meaningful edges. Include accurate usage code, interaction
  instructions, and intentional native adaptations. Examples import the actual
  public library and keep all sample state local. Break complex examples into
  their own StatefulWidgets rather than crowding a registration expression.
- Theme, viewport width, text scale, direction, and reduced-motion controls
  operate on a preview Navigator without changing the real app's settings.
  The viewport is clipped, bounded to available width, and scrollable. The
  reset control intentionally reconstructs example state; other controls must
  preserve it. A component may extend preview geometry when its behavior needs
  more space, provided the new API works for existing examples.
- `component_catalogue.dart` is generated from the frozen JSON via
  `dart run tool/generate_component_catalogue.dart`. Do not hand-edit it or
  silently resnapshot upstream to expand or reduce scope.

## Verification and workflow

The user's explicit focused-verification policy overrides CLAUDE.md's blanket
full-suite gate for this project. Format touched code, run static analysis and
meaningful focused interaction/regression tests, including downstream consumers
when shared primitives change. Run affected compatibility-package checks as
needed. Do not update unrelated lockfiles or the Flutter pin (3.47.2).
Inspect the running styleguide and changed app surfaces in representative
palettes and viewport sizes. Report exactly which platforms and interactions
were run; widget tests with target-platform overrides are not device testing.

The user authorized concurrent component tasks on 2026-09-08. Keep up to four
independent implementation tasks active. Each component gets a separate Codex
task and isolated worktree from latest local main, with its implementation
dependencies already merged. Implementers commit on `codex/ui-<component>`
and report to the coordinator; they do not merge. Reviews and merges remain
serialized. Reconcile shared exports, example registrations, app migrations and
progress metadata against previously merged components during coordinator review.

Builds, analysis and widget tests can run concurrently. Native UI inspections
share desktop focus: after preparing code and checks, notify the coordinator
that native inspection is ready and wait for an inspection slot before using
CUA. Continue other independent work while waiting. Release the slot by reporting
inspection completion or a blocking permission request to the coordinator.
The coordinator reviews, fixes or requests fixes, then merges with `--no-ff`
**from `/Users/joffreyjaffeux/Code/discourse-native` on main**. Preserve unrelated
changes. Never merge main into a component branch as the final project merge.

`progress.json` is the durable coordination record. Before implementation,
fill the row's task ID, branch, dependencies and concrete acceptance criteria.
Record decisions, migrations and retained alternatives, verification commands
and outcomes, limitations, implementation commit, then merge commit. Regenerate
`progress.md` with `dart run tool/render_component_progress.dart` and commit each
update. A merge SHA must be recorded in a follow-up commit because a commit
cannot embed its own final SHA. Start a dependent task only after local main
contains its dependencies and their progress updates; independent tasks may
start while other components are still in progress. Each implementer edits only
its assigned progress row; the coordinator preserves all other rows on merge.

After all 64 component rows are merged, create a final separate audit task to
improve shared code, API consistency, composition, themes, accessibility,
examples and missed app migrations. Review, verify and merge its changes before
marking the overall goal complete.
