# Component library review checkpoint

Sidebar and the shadcn documentation correction are merged into local `main` in
`/Users/joffreyjaffeux/Code/discourse-native`. The frozen catalogue is now
**12 of 64 components complete**. Affected tests, static analysis and the real
macOS app build pass. **The user resumed the remaining components on 2026-09-09.**
The remaining 52 catalogue components and final audit are unfinished. The next
independent batch is Button, Badge, Input and Checkbox.

Commits and coordinator merges remain local. GitHub pushes or other writes and
App Store Connect changes are prohibited. The progress record tracks the active
queue; the evidence below preserves the reviewed Sidebar checkpoint.

## Sidebar and documentation correction

| Change | What is available | Adoption |
| --- | --- | --- |
| Sidebar | Provider, sidebar/floating/inset variants, offcanvas/icon/static modes, modal navigation, composition parts, focus and theme behavior; six interactive examples. | The styleguide uses the public Sidebar on desktop and in its narrow drawer. Forum and Chat retain their documented domain adapters. |
| Documentation layout | Compact navigation, neutral light/dark canvas, 640px article, matching title/spacing, centered previews, optional code and notes, working width presets and mouse scrollbar. | The same styleguide page is opened by the existing real-app palette button and the independent preview entrypoint. |

Sidebar merge: `93bfcf65f64868c92340f9aec8236d77585c3cd8`. Documentation merge: `0eb34a59ab5de86a1c28c6ebbf08ccb746dab9a5`.
The 160 affected tests passed; the final scrollbar change passed all 14
styleguide-page tests, including mouse dragging, exact preview width and state
retention. One frozen-catalogue/dependency check also passed after the evidence
update. The final scrollbar screenshot was blocked by the locked Mac; earlier
native desktop/narrow, light/dark, 200% text and navigation checks are recorded
in [the documentation design review](styleguide-design.md).

## Previous batch

| Component | What is available | Real app adoption |
| --- | --- | --- |
| Spinner | Exact Lucide loader artwork, sizes/custom artwork, loading semantics and paused motion; six interactive example sections. | 98 busy-indicator constructions across core and plugins, including DButton; numeric progress remains owned by the pending Progress component. |
| Tooltip | Reference surface/arrow, placement/collision, hover/focus/touch, dismissal, controlled/imperative state, shared timing and cursor tracking; eleven examples. | Core/plugin hints and 105 implicit native-control hints, plus the shared rail adapter. |
| Avatar | Image/fallback lifecycle, three sizes, badges, groups/counts, RTL and accessible scaling; seven example groups. | User/forum pictures across shell, composer, topic lists, Chat, Voice, Assign, Events and GitHub. Existing media/cache/account ownership is preserved. |
| Card | Seven composable parts, normal/small size, shared spacing, edge images, footer treatment and responsive header actions; eight examples. | Groups, preferences, directories, aggregate panels, Chat, Poll, Events, Voice diagnostics and Skeleton examples. |

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
The documentation canvas uses neutral light/dark colors and the configured
host font. Component previews retain the app palette, font and radius; the
canvas theme does not change the app or preview settings. Native adaptations,
including text-driven wrapping and focus ownership, have explicit source
mappings and rationale in the evidence.

- [Detailed progress and merge commits](progress.md)
- [Visual fidelity contract](visual-fidelity.md)
- [Spinner reference](spinner-reference.md) and [native evidence](spinner-native.md)
- [Tooltip reference and native evidence](tooltip-visual-mapping.md)
- [Avatar mapping](evidence/avatar/implementation.md) and [verification](evidence/avatar/native-review.md)
- [Card mapping and adoption](card.md)
- [Sidebar mapping and adoption](sidebar.md) and [component native evidence](sidebar-native.md)
- [Documentation design and native review](styleguide-design.md)

Saved native captures include [Avatar badges](evidence/avatar/native-light-badges.png),
[large-text RTL groups](evidence/avatar/native-forest-groups-full.png), and the
[real AvatarImage/ForumIcon fixture](evidence/avatar/production-dark-rtl-200.png).
Card's screenshot and AX evidence is inline in **Implement Card component**;
its mapping document records the inspected states and limits.

## Verification limits

Focused component, styleguide and affected application tests were run during
integration, with formatting and static analysis. Native comparison used isolated
macOS apps and local-data fixtures mounting the actual migrated application
widgets. No iOS/Linux device or spoken VoiceOver verification is claimed.

The real macOS app build (`flutter build macos --debug --no-pub`) passed from
`07539c2c57533835094f70b02e07cfbbba92896a` in the isolated coordinator checkout. Its complete Git tree
`f288c94ea575d48a3585b1ca6355e4d35ce0ddf3` exactly matches merged main `0eb34a59ab5de86a1c28c6ebbf08ccb746dab9a5`. A Discourse
process was using main's existing build directory, so that running bundle was
preserved. Full-profile locked dependency resolution and static analysis also
passed. The progress document records exact commands and logs. Compilation and
bundling do not diagnose the user's earlier startup issue; no startup fix is
claimed.

The isolated final styleguide bundle remains at
`/private/tmp/DiscourseStyleguideB104-20260909.app` for review. The Mac locked
before its final explicit-scrollbar screenshot. Native Cmd/Ctrl+K attempts
produced no visible response; the bindings pass widget tests. These limits
are recorded separately from the successful native Sidebar pointer, search,
Escape and focus-restoration checks.

Spinner's evidence retains two unassigned diagnostic incidents: a forced-semantics
crash also reproduced with pre-migration consumers, and a separate native keyboard
event loop. The final normal-lifecycle and pointer checks passed; they are not
claimed as fixes for those incidents. Tooltip also records a transient CUA
accessibility-tree classification mismatch.
