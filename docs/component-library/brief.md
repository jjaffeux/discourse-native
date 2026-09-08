# User clarifications
On 2026-09-08, the user authorized multiple component tasks in parallel and
clarified: “I basically want a copy of shadcn library for our app if it was not
clear.” The Flutter library must reproduce shadcn's visual design and behavior,
not merely offer similar widgets with Material or Cupertino styling. See
[visual fidelity](visual-fidelity.md) for the implementation and review standard.
The original brief follows; these later clarifications take precedence.

I want you to build a complete, reusable Flutter component library for this app, using shadcn/ui’s components as the visual and behavioral reference.
Implement idiomatic Flutter widgets that reproduce the reference components’ documented capabilities, variants, composition patterns, and interaction quality. The app’s existing theme system and native platform conventions take precedence where a direct copy would conflict. Support the app’s current platforms: iOS, macOS, and Linux.
Keep this task as the coordinator throughout the project. Work autonomously through the phases below, creating separate Codex tasks for component implementation and the final audit. Commit and merge completed work into local main without asking for routine confirmation.
Start by inspecting the existing app and establishing the library’s foundations:
* Inventory existing reusable controls, including DButton, DTooltip, and DSelect. Replace them by their new library counterpart, extend the new one as necessary to support our use case in the app if the shadcn component don't offer a satisfying solution.
* Snapshot the shadcn component catalogue when the work begins. Record the reference date, component URLs, documented variants, and dependencies. This snapshot defines the project’s scope.
* Establish consistent component naming, public APIs, file organization, composition conventions, and shared styling tokens.
* Keep reusable components independent of Discourse networking and business logic. Application-specific adapters should live outside the generic components.
* Order implementation by dependency, so foundational components are available before components that compose them.
* Create a committed progress document that records each component’s status, Codex task ID, branch, dependencies, implementation decisions, application migrations, verification results, and merge commit. Keep it current so work can resume after an interruption.
Create the styleguide before starting individual component implementation. It should be searchable and provide interactive examples, documented variants, applicable states, usage examples, and controls for previewing themes and viewport sizes. Use the actual library components with self-contained sample data.
Add a button in the bottom left of the app that opens the styleguide.
Verify the initial styleguide and access behavior, then commit and merge this foundation into main before proceeding.
For every component in the catalogue, create a new Codex task in an isolated worktree based on the latest main. Give that task the shared conventions, progress document, relevant reference pages, and the following requirements:
1. Inspect the reference and existing code. Review the component’s documentation, examples, variants, and behavior. Identify existing implementations and related primitives in the app. Define concrete acceptance criteria before implementation. Document any necessary native adaptation and its rationale; every catalogue entry must remain accounted for.
2. Implement the complete component. Support the documented capabilities and variants, with appropriate Flutter APIs for state, callbacks, controllers, and composition. Handle applicable states such as hover, pressed, focused, selected, disabled, loading, empty, and error. Complete the behavior behind every exposed feature.
3. Support accessibility and native interaction. Include keyboard navigation, visible focus, appropriate focus entry and restoration, screen-reader semantics, touch interaction, text scaling, narrow layouts, and reduced-motion preferences where applicable. Handle overlay positioning, dismissal, scrolling, and lifecycle behavior correctly.
4. Integrate with the existing theme system. Support light mode, dark mode, custom site palettes, and live theme changes, including while menus, dialogs, or other overlays are open. Use shared tokens for colors, typography, spacing, radii, and motion. Maintain readable contrast and distinguishable interaction states across themes.
5. Add comprehensive styleguide examples. Demonstrate the component’s variants, important states, interactions, composition patterns, and realistic edge cases. Include clear usage examples and document any intentional differences from the reference. Keep examples synchronized with the public API.
6. Adopt the component throughout appropriate app usages. Inspect both core and plugin UI for places where the component should replace existing controls. Migrate appropriate usages while preserving behavior, permissions, state handling, and accessibility. Extend the component when a real application use case requires it. Remove obsolete implementations once their usages are migrated. Record any retained alternatives and explain why they remain. A component with no current app usage must still be fully implemented and demonstrated in the styleguide.
7. Verify and report the result. Run formatting, static analysis, and focused tests covering the component, migrated usages, and affected shared behavior. Add or update meaningful tests for interactions and regressions. Inspect the running styleguide and affected app screens at relevant viewport sizes and in representative themes. Record what was actually verified and any remaining limitations. Fix failures introduced by the change before declaring it complete.
The full test suite is not required before merging. Choose verification based on the actual impact of the change, including downstream consumers when shared code changes.
As coordinator, review each component task’s implementation, migrations, and verification results. Resolve identified issues, then merge the completed branch into main from the repository’s main checkout. Preserve unrelated user changes. Update the progress record and start the next component from the newly updated main. Keep implementation and merges sequential.
Extract shared code as recurring needs become clear during component implementation. Prefer abstractions justified by actual shared behavior, and keep component APIs consistent throughout the project.
After every component has been implemented, integrated into the styleguide, reviewed for application adoption, verified, and merged, create one final separate Codex task to audit the complete library and its app integrations.
That task should identify and implement improvements to duplicated code, shared primitives, API consistency, composition, theming, accessibility, styleguide coverage, and missed migration opportunities. Remove obsolete code and update documentation and examples as needed. Verify the affected behavior, review the resulting changes, and merge them into main.
Finish with a concise report of the completed catalogue, application migrations, verification performed, intentional deviations, and any unresolved limitations. Do not mark the overall goal complete while required implementation, verification, or merges remain unfinished.


## Workflow amendment — 2026-09-08

The user subsequently authorized multiple component Codex tasks at the same time.
Independent components now run concurrently in isolated worktrees, each created
from the latest local main with its dependencies already merged. The coordinator
keeps up to four implementation tasks active, reviews and merges one result at
a time from the main checkout, and reconciles shared files and progress metadata.
Native UI inspections are also serialized because they share desktop focus;
builds, analysis and widget tests can run concurrently. This replaces the
original requirement to keep component implementation sequential. All other
scope, quality, migration, verification and final-audit requirements remain.
