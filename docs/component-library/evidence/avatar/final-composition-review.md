# Avatar final-owner composition review

Reviewer: `01a086cd-3f9e-76a1-86a6-7ef4e7f7e5e4`, branch
`codex/review-avatar-compositions`. This is a follow-up to accepted Avatar merge
`5c78eb9d5c9db5f37ac7eaf8deab2233944dcbd0`, not a replacement acceptance or a
re-merge of the original implementation branch. The original Avatar API,
networking adapters and production migrations remain unchanged.

## Source and acceptance scope

Native fixture source: `fda8a23dce3ac0d5e73ce6346744907b87e89ff2`, prepared
from accepted local main `7b09b62dc83b4c56665794be0548a659e0ed8c32` by merging
the reviewed branch into a new candidate based on main. Main was not merged
into the worktree. The subsequent test-only brace lint correction does not
change any library, example or fixture source.

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

Review bundle: `/private/tmp/Avatar Compositions Final 47e2 r2.app`.
Identity: `org.discourse.avatarcompositions.final.47e2.r2`;
scheme: `discourse-avatar-compositions-final-47e2-r2`.
The built bundle was copied and only that copy's identity/signature was changed.
Its embedded provisioning profile was moved out of the copy. The copied bundle
is ad-hoc signed without push/team/application-identity entitlements; readback
contains only app-sandbox, allow-jit, allow-unsigned-executable-memory,
disable-library-validation and network.client. Deep strict signature verification
passed. No real app provisioning or OS settings were changed.

SHA256 agreement across `.dart_tool/flutter_build/ecc69156f4b154d909a8d39094049b93/app.dill`,
the built Discourse bundle's kernel and the isolated review bundle's kernel:
`6d358f1f6cc33cb53c14be6dfe9fbce03c108cc3e4b96819ad50c7cdd864ec07`.

| Source | SHA256 |
| --- | --- |
| Avatar examples | `c1dcb12521a7c8e5224b3c7982306b4037baf28069fce699ce6eb814fe7bd97e` |
| Direction examples | `d2d9d99fbf4989c75743be7b6291ccd24aee68c674f8f1ad1d7b3a99a14e865b` |
| Generic Avatar | `732bc8917c8e8086fa359000de0ff4de90b07047ff4be51e79418074e5a9eac0` |
| Dropdown Menu | `bcc8a7d9bef188047f711197835c5bfbdb225606a565e85f05030ae6aa03bf22` |
| Native fixture | `f95ece9b388b140b04b6a1383b20b93aa1ed27197e4f42c8956143b114269f3b` |

## Native/reference acceptance

Pending the canonical FIFO desktop lease. The build has not yet been launched;
signature validation and widget tests do not claim native acceptance.
The historical `native-review.md` and screenshots remain valid for unchanged
Avatar presentation/adapters, but their temporary dropdown evidence does not
stand in for this final-owner review.
