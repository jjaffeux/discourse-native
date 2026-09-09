# Alert implementation and pending review

Frozen documentation: https://ui.shadcn.com/docs/components/base/alert.md,
SHA256 `a6d5f832b2384d4544d2d1d0aaa0fe315dd17031a0fb5395451fb09b0925dbf9`.
Registry: https://ui.shadcn.com/r/styles/base-nova/alert.json,
SHA256 `0799cfc29a481568f6e9b48e96518a446032350dec576bfe31b7f67b4b262028`.
Both are preserved in `reference/alert.*`. Original Lucide SVG URLs/hashes are
in `reference/alert-artwork.json`; artwork uses the existing Lucide ISC notice
in `reference/LICENSE.tooltip-lucide.md`. No raster artwork is present.

## Source mapping

CSS pixels map to logical pixels with a 16px rem root. These are source-derived
measurements, with widget geometry assertions; rendered reference comparison
and native inspection remain pending.

| Source | Flutter |
| --- | --- |
| `w-full rounded-lg border` | Available width, 1px token border, radius = host radius ×1 |
| `px-2.5 py-2` | 10px horizontal / 8px vertical inside border; title starts x11/y9 without icon |
| `grid gap-0.5`, SVG `gap-x-2` | 2px title/description gap, 8px icon/content gap |
| SVG `size-4 translate-y-0.5 row-span-2` | 16px original Lucide SVG, 2px down from content; text x35/y9 |
| `text-sm`, title `font-medium` | Host font family, unscaled 14px/20px leading, weights 400/500, tracking 0 |
| `bg-card text-card-foreground` | Live `surface` / `foreground` tokens |
| Description muted / destructive 90% | Live mutedForeground or destructive alpha ×0.9 (preserves existing alpha) |
| Action `top-2 right-2`, alert `pr-18` | Top/end 9px including border; reserve 72px including normal end padding |
| No shadow, hover or animation | Passive surface, no controller/timer/focus owner or Material elevation |

At 448px, a single-line title and description produce 60px height. Action
layout measures child hit bounds; reserves at least the source's 72px, expanding
for larger native controls. If less than 160px × text-scale remains for text,
the action moves below with 8px separation. This avoids CSS absolute-position
collisions at large text/narrow widths. Action top/end mirror in RTL; native
text uses natural line breaking rather than browser balance/pretty algorithms.
Arbitrary child links own their focus/callbacks and underline style. Multiple
paragraphs compose with 16px gaps. No editable Form state belongs to Alert.

`DAlertVariant.normal` maps default; `destructive` is the only other variant.
Frozen catalogue extraction captured Button's outline/xs props in this row;
they are not Alert variants. After integration with pinned main, actions use the completed DButton owner.
The reference action uses extraSmall (24px pointer visual bounds); native hit
bounds remain preserved. Examples cover basic, demo,
destructive, action, custom amber light/dark colors, original Arabic RTL,
static description-only and rich paragraphs/actions. Reference SVGs avoid the
app's 0.875 icon glyph inset; application icons remain domain artwork.

`liveRegion: true` expresses the source alert announcement through Flutter's
platform live-region bridge, without stealing focus. `false` supports static
history. Decorative icons are excluded and action semantics remain separate.
Platform announcement urgency and VoiceOver behavior need native verification;
widget tests are not device accessibility testing. Reduced motion introduces
no motion; composed children keep their own behavior.

## Adoption audit

Migrated actual inline error adapters in TopicListView (refresh and paging,
retaining retry keys), CategoriesPage, TagsPage, GroupsPage, GroupPage,
AggregateView partial refresh, UserActivity pagination, DraftList refresh,
PostRevisionHistory inline failures, UserSummary stale-data refresh, Badges
loading/pagination, Assign's loaded-list failure, and bundled GIF picker paging
errors. Preferences' persistent loading/saved/error announcement now composes
the same Alert owner with its existing semantic status colors. Existing
callbacks, null/async retry guards, account ownership, feed state and permissions
stay unchanged. ComposerTagRemovalNotice now composes all four parts, retaining
caller dismissal and existing seven-second controller lifetime.

Retained alternatives:

- Empty/page-scale initial loading/no-data/error messages: Empty task owns these;
  no duplication of its unmerged implementation or specialized Card renderer.
- Topic post notices: historical cooked post content with site-specific styles;
  retain the existing contextual post container and its cooked links rather than
  announce every historical post during scrolling. A future static Alert
  migration can be assessed alongside cooked-content typography/native review.
- Chat deleted-message runs/read markers and voice recording/diagnostic badges:
  timeline/disclosure/privacy status renderers, not general notification cards.
- Prometheus alert tables, Chart/Resizable/Table surfaces: specialized owners;
  no imports of their unmerged work.
- Field-local validation, media decode errors, transient SnackBars and dialog
  bodies: remain with Input/media/Toast/Dialog owners rather than introducing
  a card around every compact error string.

## Verification

Flutter 3.47.2 / Dart 3.13.2; enforced root and full-profile resolution. Pins
and all lockfiles unchanged. Focused tests passed (107 tests):

```
flutter test --no-pub test/ui/d_alert_test.dart test/styleguide/alert_examples_test.dart test/composer_tag_removal_notice_test.dart test/topic_list_view_lifecycle_test.dart test/categories_page_test.dart test/tags_page_test.dart test/groups_page_test.dart test/group_page_test.dart test/aggregate_view_test.dart test/post_revision_history_test.dart test/post_revision_history_ownership_test.dart test/gif_picker_test.dart test/d_button_adoption_test.dart
```

An additional 42 passed after DraftList adoption:

```
flutter test --no-pub test/ui/d_alert_test.dart test/draft_list_test.dart test/draft_list_recovery_test.dart test/account_activity_pagination_test.dart test/account_activity_rows_accessibility_test.dart
```

Assertions cover measured basic geometry, live-region opt-out, alpha and border
roles, proportional radius, live theme replacement, measured action wrapping,
RTL, keyboard Enter and pointer activation, 200% examples, controller notice
lifetimes, retry admission, stale account responses and existing permissions.
Root and full-profile analysis and touched formatting are required before the
source checkpoint. Full suite is intentionally not required by the user.

`tool/alert_review_main.dart` mounts actual ComposerTagRemovalNotice,
GroupsPage and GifPicker with local data. GIF artwork comes from a loopback-only
fixture server; no external accounts/requests. The GIF controller loads a local
result then fails pagination, ensuring the actual migrated inline error appears.
Other migrated full screens still require inspection during the native slot;
focused tests cover their state/callback regressions but do not replace that.

Status stays in_progress / awaiting_slot. No native app/browser has been launched
or inspected by this task; no pixel-parity or VoiceOver claim. Coordinator must
compare official rendered examples and inspect changed production surfaces
before review_ready/merge. Build identity and source evidence follows separately.

## Isolated build checkpoint

Source commit: `5f0418cc6a90faaa88c3df6adee1df232bff081c`. Root and full-profile
analysis passed with no issues. All 18 touched Dart files passed formatting;
`git diff --check` passed. There were no library/fixture differences from this
commit at build verification. Evidence-only follow-up commits do not alter code.

Built with `flutter build macos --debug --no-pub -t tool/alert_review_main.dart`
using temporary runner settings for product `Alert Review 38df`, bundle identifier
`org.discourse.alertreview38df`, URL scheme `discourse-alert-review-38df`.
Initial profile signing failed for the deliberately unique identifier. The local
build then disabled Xcode signing and applied an ad-hoc signature with sandbox,
JIT and loopback client/server entitlements; no provisioning or remote account
changes occurred. All temporary runner edits were restored byte-for-byte.

`codesign --verify --deep --strict --verbose=2` passed. The source `app.dill`,
build framework kernel and bundle-copied kernel all have SHA256
`e543ad77e1bf1c877db0a3c43c55a9e1e124fe239d725d8b6a38ee9f8a275a99`.
Exact paths and identity assertions are in `evidence/alert/build.json`.
The bundle resides only under this isolated checkout's build directory. It has
not been launched. Native review is pending, and this source is not merge-ready.

## Pinned-main integration checkpoint

Merged `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` into this component branch;
source merge commit `1efab06cb3b99177278ed941db63ec37f07ce849`. Every existing
component owner is byte-identical to pinned main. All non-Alert progress rows
are preserved. Group/Sidebar/Topic Inbox coordinator fixes remain; overlapping
changes retain only the intended Alert inline adapters. The final Button owner
now renders the reference action at `DButtonSize.extraSmall`, with independent
button semantics/callbacks and native hit bounds. Tests verify local toggling.

Integration verification: 129 focused tests passed across Alert/styleguide,
Composer tag notice, topic feed lifecycle, categories/tags/groups/group,
aggregate, revisions, GIF picker, drafts, activity pagination and Button adoption.
After adding the extra-small action regression, both styleguide tests passed.
Root/full-profile analysis and enforced resolution passed. Pins, lockfiles and
production runner files remain unchanged. Touched formatting and diff checks
passed. No full-suite claim.

Latest isolated bundle:
`build/macos/Build/Products/Debug/Alert Integration Review 38df.app` under this
worktree, ID `org.discourse.alertintegration38df`, URL scheme
`discourse-alert-integration-38df`. Built from the exact source merge commit via
`flutter build macos --debug --no-pub -t tool/alert_review_main.dart` with only
temporary unique runner identity and disabled Xcode signing. Runner files were
restored; no lib/tool/source differences remained at verification.

Ad-hoc signing uses only `com.apple.security.cs.allow-jit`,
`com.apple.security.cs.allow-unsigned-executable-memory`, `get-task-allow`, and
network client/server. Signed entitlement readback was checked on the app,
its executables/dylibs and bundled frameworks: no restricted application, team,
APNs or other identities; no embedded provisioning profile.
`codesign --verify --deep --strict --verbose=2` passed.
Source `app.dill`, framework kernel and app-copied kernel SHA256:
`43527a2e8cdda4ec7f3e8ed7079ac9ecab5bef98560d03cd866bbbbfcff2ddb8`.
Full paths, signed readbacks and signature output are recorded in
`evidence/alert/integration-build.json`; this supersedes the earlier bundle.

Still `in_progress` / `awaiting_slot`: Mac locked and browser separately denied
admin-policy verification. No CUA/browser/native launch, policy retry or
workaround occurred. Actual reference-rendered comparison and native inspection
remain required before review_ready or merge.

## Independent review

The reviewer rechecked the preserved registry/documentation/artwork hashes and
the public API, render-object geometry, live theme resolution, semantics,
keyboard ownership, reflow and RTL behavior. A fresh adoption audit found four
eligible persistent inline owners that the implementation checkpoint had missed:
UserSummary refresh, Badges loading/pagination, Assign's loaded-list failure and
Preferences status. These now use DAlert while preserving retry, loading and
announcement behavior. Their focused tests and the Alert/styleguide tests pass;
root and full-profile analysis report no issues.

## Final rendered and native acceptance

The earlier `awaiting_slot` notes are superseded. The independent reviewer used
the official Base UI Alert documentation to compare the basic, destructive,
action, custom-color and RTL examples in light and dark themes. The Flutter
styleguide matched the reference's compact border, radius, inset, icon/text
alignment and action placement. Its action changed from Enable to Disable and
updated the message, the Plum palette resolved live, and the 360 px Arabic RTL
examples wrapped without clipping or overlap.

The uniquely identified macOS predecessor build recorded in
`evidence/alert/final-review-build.json` was launched for the native gate.
Production ComposerTagRemovalNotice, GroupsPage and GifPicker alerts were
inspected in light and dark modes, RTL and 200% text. Dismiss and retry remained
separate accessible buttons; dismissal removed the notice, Groups retry reached
its loaded state, and narrow action content reflowed beneath the message without
collision. The styleguide alert exposed a distinct semantic container with its
action as a separate control. This acceptance is for macOS only; no iOS or Linux
device result is claimed.

After reconciling latest main, `DAlert`, the fixture and every inspected Alert
branch remained byte-identical; the only relevant styleguide change was its
acceptance label. The exact accepted source was rebuilt to the same unique
identity, with matching source/framework/copied kernel hashes and a passing deep
strict signature check. The evidence distinguishes that final build verification
from the behaviorally identical predecessor launch rather than claiming a second
native session.
