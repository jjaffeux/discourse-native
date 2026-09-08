# Component library review checkpoint

Spinner, Tooltip and Avatar are merged into local `main` in
`/Users/joffreyjaffeux/Code/discourse-native`. The frozen catalogue is
**10 of 64 components complete**. Card is implemented and its automated checks
pass, but native inspection is waiting on a Codex app-access approval in
**Implement Card component**. Card remains unmerged.

The user's instruction is to finish this four-component batch, then pause for
review and directions. Only Card remains in the batch; no further component or
final audit task will be dispatched before the user gives directions.

## This batch

| Component | What is available | Real app adoption |
| --- | --- | --- |
| Spinner | Exact Lucide loader artwork, sizes/custom artwork, loading semantics and paused motion; six interactive example sections. | 98 busy-indicator constructions across core and plugins, including DButton; numeric progress remains owned by the pending Progress component. |
| Tooltip | Reference surface/arrow, placement/collision, hover/focus/touch, dismissal, controlled/imperative state, shared timing and cursor tracking; eleven examples. | Core/plugin hints and 105 implicit native-control hints, plus the shared rail adapter. |
| Avatar | Image/fallback lifecycle, three sizes, badges, groups/counts, RTL and accessible scaling; seven example groups. | User/forum pictures across shell, composer, topic lists, Chat, Voice, Assign, Events and GitHub. Existing media/cache/account ownership is preserved. |
| Card — unmerged | Seven composable parts, normal/small size, shared spacing, edge images, footer treatment and responsive header actions. | Groups, preferences, directories, aggregate panels, Chat, Poll, Events, Voice diagnostics and Skeleton examples. |

Earlier merged components are Direction, Typography, Kbd, Separator, Label,
Skeleton and Aspect Ratio. Button and Select still show explicit baseline
implementations; this is an incomplete catalogue, not a finished replacement
of every app control.

## Review

The palette button at the bottom-left of the real app opens the searchable
styleguide. Its examples use the same public components as the application,
with local sample state. Preview controls cover light/dark/site palettes,
width, text scale, RTL and reduced motion.

The independent styleguide entrypoint is available from the main checkout:

```sh
flutter run -d macos -t lib/styleguide_main.dart --no-pub
```

Reference styling comes from the frozen shadcn Base UI/base-nova sources.
The app retains its configured palette, font family and radius. Specific native
adaptations, including text-driven wrapping and focus ownership, are recorded
with their rationale in the component evidence.

- [Detailed progress and merge commits](progress.md)
- [Visual fidelity contract](visual-fidelity.md)
- [Spinner reference](spinner-reference.md) and [native evidence](spinner-native.md)
- [Tooltip reference and native evidence](tooltip-visual-mapping.md)
- [Avatar mapping](evidence/avatar/implementation.md) and [verification](evidence/avatar/native-review.md)
- [Pending Card mapping and adoption](/Users/joffreyjaffeux/.codex/worktrees/5995/discourse-native/docs/component-library/card.md)

## Verification limits

Focused component, styleguide and affected application tests were run during
integration, with formatting and static analysis. Native comparison used isolated
macOS apps and local-data fixtures mounting the actual migrated application
widgets. No iOS/Linux device or spoken VoiceOver verification is claimed.

The real macOS app built successfully from the ten-component main checkpoint
`6976336acc1cf7dd1a44da5bfa4ba7dbdf3dd799`. Full-profile locked dependency
resolution and static analysis also passed. The progress document records the
exact commands and logs. Compilation and bundling do not diagnose the user's
reported inability to start the real app; that startup issue remains unverified.

Spinner's evidence retains two unassigned diagnostic incidents: a forced-semantics
crash also reproduced with pre-migration consumers, and a separate native keyboard
event loop. The final normal-lifecycle and pointer checks passed; they are not
claimed as fixes for those incidents. Tooltip also records a transient CUA
accessibility-tree classification mismatch.
