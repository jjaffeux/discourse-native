# Avatar final-owner composition review

Reviewer: `01a086cd-3f9e-76a1-86a6-7ef4e7f7e5e4`, branch
`codex/review-avatar-compositions`. This is a follow-up to accepted Avatar merge
`5c78eb9d5c9db5f37ac7eaf8deab2233944dcbd0`, not a replacement acceptance or a
re-merge of the original implementation branch. The original Avatar API,
networking adapters and production migrations remain unchanged.

## Source and acceptance scope

Native fixture source: `3b202d5eb89e51565c5f4ae9c293ce0eb36f25ca`, prepared
from accepted local main `1770316fcc06f665747d6598f43dde1d093f4420` by merging
the reviewed branch into a new candidate based on main. Main was not merged
into the worktree. Automated runtime verification was completed at
`fda8a23dce3ac0d5e73ce6346744907b87e89ff2`; subsequent changes only correct a
test brace lint and the displayed Direction usage snippet. The final native
bundle was rebuilt to include that exact snippet source as well. A subsequent
coordinated Dropdown follow-up, prepared commit
`7110ef80b2190f3a17c6a78fbae05fe857a29d38`, adds popup-local focus scrolling and
single RTL chevron mirroring alongside the isolated registration-order fix.
It was initially integrated for source preparation. The owning reviewer has now
accepted this exact Dropdown source in local-main merge
`85f9265bf2593a7edc0693582b7eadf1c6645b8d`, tracking commit
`d647400602824226d70d1328fba2a141195dc559`. Git blob
`b5c53b46b86b28f8d8a9b6375b4798fdf7c233b6` is identical between the prepared
parent, Avatar's inspected source and the accepted merge. The parent gate is
cleared; final current-main reconciliation is still pending. Avatar withdrew
its waiting desktop request during the earlier rebuild and rejoined only after
the updated bundle was ready.

Accepted final owners are Button
`eb6d8ea0d9417f0edc830c5ce715b52436f12c94` and Dropdown Menu
`5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787`. The candidate also includes the
Calendar adoption-guard correction `9834f36a9c4c44f1792e9970bf0a9abfcbedd47d`,
Combobox dependency ordering correction `892e1a97`, and Hover Card owner's
Chat semantics test correction `7b09b62dc83b4c56665794be0548a659e0ed8c32`.

- Replace both Avatar and Direction temporary `MenuAnchor`/`MenuItemButton`
  example sites and their snippets with accepted `DDropdownMenu`/`DButton`.
- Match the reference Avatar dropdown's 32px circular ghost trigger, 128px
  grouped menu, Profile/Billing/Settings, separator and destructive Log out.
- Complete plain three-member and three-member-plus-icon groups alongside
  existing count/size groups. Add separately named, locally acting group buttons.
- Preserve caller-owned focus, independent actions, outside/Escape dismissal,
  nested dialog restoration, live palettes/direction, large text and image state.
- Keep original acceptance evidence for unchanged generic Avatar and adapters;
  independently render and inspect the affected final compositions.

## Reference and measured mapping

Frozen [Avatar documentation](https://ui.shadcn.com/docs/components/base/avatar)
Markdown was retrieved again on 2026-09-09 and still hashes to
`921178487423ff56f4de4aa29b09541733b59359ae746fe63a8b765ae8b153d9`.
The supporting official example sources were inspected:

| Source | SHA256 |
| --- | --- |
| [avatar-dropdown.tsx](https://raw.githubusercontent.com/shadcn-ui/ui/main/apps/v4/examples/base/avatar-dropdown.tsx) | `23ad4bb4a84e895ac1efe13755fbd7cd746b09e7dd2fd7e7a2b9c3df46020643` |
| [avatar-group.tsx](https://raw.githubusercontent.com/shadcn-ui/ui/main/apps/v4/examples/base/avatar-group.tsx) | `da325a98cec9e5c76ef9e5e53729c0d0a7788711a4f77afa0471dbabdcb75133` |
| [avatar-group-count-icon.tsx](https://raw.githubusercontent.com/shadcn-ui/ui/main/apps/v4/examples/base/avatar-group-count-icon.tsx) | `d2662cf083ec5fd9de2a98bfa934b51bfcbda138beab8b91ae5f164bb9a0b50a` |

At 100% on macOS, the actual Avatar trigger and child both measure 32×32 logical
pixels in widget tests. `DDropdownMenuContent(width: 128)` uses its accepted
4px padding and offset, grouped 14px rows, token radius, separator and destructive
colors. Avatar's existing 24/32/40px sizes, 8px overlap and 2px group rings remain
unchanged; three standard members occupy 80px before a count is added.

The trigger uses a rich `DButton.label` with zero padding, not fixed icon-button
bounds: the latter clipped the accepted scalable fallback at 200%. Its actual
64px avatar and button bounds now agree at 200%, with font scaling still owned
only by Flutter. The reference has no trigger tooltip. Removing an extra tooltip
avoids a new popup on focus restoration consuming the next Escape before an
enclosing dialog. The explicit accessible action name remains.

Desktop group actions retain the 8px overlap. On touch platforms this extra
interactive demonstration uses a separated Wrap: constraining actions to 32px
overlapping group cells would defeat Button's 48px tap targets. Tests verify
separate ≥48px bounds and independent activation on iOS/Android platform overrides.
The noninteractive reference group examples remain overlapping on all platforms.

## Focus-order correction

Direction's live LTR→RTL first-row label exposed a shared Dropdown Menu bug:
`didUpdateWidget` removed and reinserted an existing State's registration, moving
the first visual row to the end of the insertion-ordered navigation list. Home
then selected the second action. The owning Dropdown reviewer
`01a085cf-f401-7813-80da-7c687de8a5d5` confirmed this narrowly scoped correction.
The same registration key is now replaced in place. Tests cover label changes,
disable/re-enable, borrowed focus-node replacement, Home/arrows/typeahead,
preserved active focus and borrowed resource disposal. No public API changed.

## Automated verification

Flutter 3.47.2 / Dart 3.13.2; no pin, dependency lock or runner-source changes.
Root and full-profile locked pub resolution passed earlier in this review;
their manifests/locks are unchanged in the refreshed candidate.

Passed on the refreshed source, seed `9082026`:

```sh
flutter analyze --no-pub
# No issues; 3.7s after correcting a test-only braces lint.
# From profiles/full:
flutter analyze --no-pub
# No issues; 3.2s.

flutter test test/ui/d_avatar_test.dart \
  test/styleguide/avatar_examples_test.dart \
  test/styleguide/direction_examples_test.dart test/d_dropdown_menu_test.dart \
  test/d_button_test.dart test/d_popover_test.dart test/ui/d_dialog_test.dart \
  test/styleguide/dropdown_menu_examples_test.dart \
  test/styleguide/styleguide_page_test.dart test/d_button_adoption_test.dart \
  --no-pub --test-randomize-ordering-seed=9082026 --reporter expanded
# 129 passed.

flutter test test/styleguide/input_group_examples_test.dart \
  test/styleguide/item_examples_test.dart test/d_table_test.dart \
  --no-pub --test-randomize-ordering-seed=9082026 --reporter expanded
# 17 passed; all existing downstream Dropdown Menu compositions covered.
```

After integrating the prepared combined Dropdown correction, source `3b202d5e`:

```sh
flutter test test/ui/d_avatar_test.dart \
  test/styleguide/avatar_examples_test.dart \
  test/styleguide/direction_examples_test.dart test/d_dropdown_menu_test.dart \
  test/d_popover_test.dart test/ui/d_dialog_test.dart \
  test/styleguide/dropdown_menu_examples_test.dart \
  test/styleguide/input_group_examples_test.dart \
  test/styleguide/item_examples_test.dart test/d_table_test.dart \
  --no-pub --test-randomize-ordering-seed=9082026 --reporter expanded
# 114 passed, including popup-local scroll and RTL chevron regressions.
flutter analyze --no-pub
# Root: no issues, 7.2s. Full profile: no issues, 2.4s.
```

The earlier broad regression run identified an unrelated stale Chat hover
assertion. It reproduced in a clean detached checkout at main `9834f36a` using
`flutter test test/chat_message_tile_thread_preview_test.dart --plain-name
'hover shows a compact action for the exact message' --no-pub --reporter expanded`.
Line 939 expected tooltip text and focus flags on the tooltip wrapper; actual
accessible name was `Reply`. The Hover Card owner independently confirmed its
pre-Hover baseline and corrected the test to inspect the actionable DButton,
retaining strict label/focus/tap semantics, tooltip lookup, 48px bounds and
activation checks. Its accepted merge above includes 56 passing Chat tests and
27 UserCardTarget/account/Hover Card tests. These are owner-reported results;
this review does not claim to have rerun those unrelated unchanged suites.

## Exact-source isolated native fixture

Built with `flutter build macos --debug --no-pub -t tool/avatar_review_main.dart`.
The actual Avatar, Direction and group-action example builders are mounted along
with the production `AvatarImage` and `ForumIcon` adapters. HTTP is intercepted
with local pending/error/PNG responses. All actions mutate only local sample state.
Controls expose light/dark/Forest/Plum, 360px, 200%, RTL and reduced motion; the
actual full styleguide remains reachable from the same executable.

Review bundle: `/private/tmp/Avatar Compositions Final 47e2 r4.app`.
Identity: `org.discourse.avatarcompositions.final.47e2.r4`;
scheme: `discourse-avatar-compositions-final-47e2-r4`.
The built bundle was copied and only that copy's identity/signature was changed.
Its embedded provisioning profile was moved out of the copy. The copied bundle
is ad-hoc signed without push/team/application-identity entitlements; readback
contains only app-sandbox, allow-jit, allow-unsigned-executable-memory,
disable-library-validation and network.client. Deep strict signature verification
passed. No real app provisioning or OS settings were changed.

SHA256 agreement across `.dart_tool/flutter_build/ecc69156f4b154d909a8d39094049b93/app.dill`,
the built Discourse bundle's kernel and the isolated review bundle's kernel:
`05aeba9c6a9c5bc19df2f42788c06cb9b2d15af6761ade1343e14d2d434943ef`.

| Source | SHA256 |
| --- | --- |
| Avatar examples | `c1dcb12521a7c8e5224b3c7982306b4037baf28069fce699ce6eb814fe7bd97e` |
| Direction examples | `7a965dc38afd194d1555cf042f74ab0d4f9a1adb168bcb72b38601abb5b9ee13` |
| Generic Avatar | `732bc8917c8e8086fa359000de0ff4de90b07047ff4be51e79418074e5a9eac0` |
| Dropdown Menu | `018e7a7be589f01679a66a459e4242540ae6b81554290a8d725b071c711c7987` |
| Native fixture | `f95ece9b388b140b04b6a1383b20b93aa1ed27197e4f42c8956143b114269f3b` |

## Native/reference acceptance

Native pass completed across two sessions on 2026-09-09 with the exact r4 bundle above.
The canonical desktop lease was acquired at 18:28:41 UTC. Approved CUA launched
the isolated app and exposed its actual fixture controls and screenshots.

- Light, dark and Forest dropdowns show the circular trigger, three ordinary
  rows, separator and destructive Log out. Pointer Profile, keyboard End/Enter
  Log out, Home/Down/Down/Enter Settings, outside dismissal and Escape worked.
  Enter reopened the menu after activation; Escape restored the visible trigger
  focus ring.
- Group actions expose three independent accessible buttons. Pointer Lee and
  sequential Tab/Enter activation of Chris, Lee and Evil Rabbit produced their
  separate local statuses and visible focus rings.
- Plum at 360px, 200%, reduced motion was inspected in both LTR and RTL. The
  64px Avatar trigger and anchored menus remain visible. The fixed 128px Avatar
  menu wraps Settings onto two lines at this text scale; it remains selectable.
  The Direction menu flips above its low trigger and wraps its labels within
  the available surface. Home/Enter selects `RTL`; End/Enter independently
  selects `Second action`.
- Production AvatarImage/ForumIcon loading and error fallbacks were observed.
  Ready changes the Avatar accessibility node to an image; the local checker
  bitmap became visible before the styleguide transition. The saved ready
  screenshot precedes that final decode frame. The forum action increments only
  the local counter to 1.
- The actual full styleguide renders the corrected plain three-member group,
  three count-size rows and three-member-plus-icon group. Its Dropdown example
  exposes the final-owner description and controls.

Captured evidence:

- [Light menu](final-native-light-dropdown.png),
  [dark menu](final-native-dark-dropdown.png),
  [Forest menu](final-native-forest-dropdown.png).
- [Escape focus](final-native-escape-focus.png),
  [independent group keyboard action](final-native-group-keyboard.png).
- [Plum RTL 200% Avatar menu](final-native-plum-rtl-200-dropdown.png),
  [Plum LTR 200% Avatar menu](final-native-plum-ltr-200-dropdown.png),
  [Plum RTL 200% Direction menu](final-native-plum-rtl-200-direction.png).
- [Production error](final-native-production-error.png),
  [ready state before decode completion](final-native-production-ready.png),
  [full styleguide groups](final-native-styleguide-groups.png).

The pass stopped while opening the styleguide's View code panel: approved CUA
reported, "The Mac is locked and automatic unlock could not unlock it. Ask the
user to unlock the Mac manually before continuing." No alternate UI route,
unlock bypass, OS settings change or further CUA action was attempted. The
desktop lease was immediately released. The isolated r4 app remains running;
cleanup must wait for manual unlock. No browser tab was created by this task.

After the user confirmed manual unlock, a new FIFO lease was acquired at
18:51:40 UTC. Ordinary CUA app binding, actual AX/screenshot retrieval and
interactions succeeded. Recovery was relayed to the waiting reviewers.

Both displayed final-owner snippets were verified: Avatar uses the borrowed
focus node, ghost DButton and grouped 128px DDropdownMenu; Direction places its
live-label Builder outside DDropdownMenuItem. The official Avatar page was
opened in one task-created in-app browser tab. Its light and dark open Dropdown
and three-member-plus-icon group were visually compared with the native captures.
Read-only DOM measurement found menu width 128px, height 129px, padding 4px,
radius 10px and four 28px rows, with destructive Log out separated from the
ordinary group. This supports the structural/metric mapping; theme colors,
platform font rasterization and local initials/checker artwork remain deliberate
native adaptations, not pixel-identical portraits or screenshot-scale equality.

- [Displayed Avatar snippet](final-native-avatar-snippet.png).
- [Official dark dropdown](final-reference-dark-dropdown.png),
  [official light dropdown](final-reference-light-dropdown.png),
  [official group with icon](final-reference-group-icon.png).

The reference theme was restored to its initial dark state (verified by the
document class), the sole created browser tab was closed and the fresh tab list
was empty. Quit was invoked from the isolated r4 app's own menu; a fresh CUA
inventory confirmed its identity absent. Other apps were untouched. The desktop
lease was released before integration work. No further native source change was
needed. Native live-open theme updates, nested dialog Escape
and touch hit targets are covered by widget tests, not claimed newly native
tested. No spoken VoiceOver or iOS/Linux device pass is claimed.

The later accepted Button Group changes add DJoinedControlScope-dependent
Button geometry and a Popover scope boundary. Source inspection found no such
scope in Avatar, Direction or this fixture: the fallback resolves the same
radius, keeps the regular border/clip behavior, and the boundary returns null.
The inspected ungrouped behavior is equivalent; affected tests must be rerun
after final current-main reconciliation. Generic Avatar and the exact Dropdown
implementation remain byte-identical to the inspected source.

The historical `native-review.md` and screenshots remain valid for unchanged
Avatar presentation/adapters. The new final-owner native/reference gate is now
complete; final current-main reconciliation and affected verification precede
the local merge.
