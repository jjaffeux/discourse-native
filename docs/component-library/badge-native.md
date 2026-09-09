# Badge native review checkpoint

Status: **awaiting an explicit coordinator inspection slot and an unlocked Mac**.
Browser-only reference inspection and widget-renderer comparison are complete;
see `badge.md` and `evidence/badge/`. No native launch or native interaction
checks were performed. This component is not `review_ready` yet.

## Prepared app

- Implementation commit: `299671abd77fb176781e966e67f12b34e1e52edd`.
- Source task: `01a083ac-c98c-7fe0-878d-54ee3bcbebb9`, branch `codex/ui-badge`.
- Temporary source: `/private/tmp/discourse-badge-review-bebb9`.
- App: `/private/tmp/discourse-badge-review-bebb9/build/macos/Build/Products/Debug/Badge Review BEBB9.app`.
- Bundle ID: `org.discourse.native.badge.bebb9`.
- Display name: `Badge Review BEBB9`; URL scheme `badge-review-bebb9`.
- Target: `tool/component_review/badge_main.dart`.
- Flutter 3.47.2 / Dart 3.13.2; `flutter build macos --debug --no-pub -t tool/component_review/badge_main.dart` succeeds.
- Ad-hoc signature re-applied after Flutter assembly; `codesign --verify --deep --strict` passes.
- Product name, bundle ID, URL scheme, ad-hoc signing and removal of the unused
  push entitlement exist only in the temporary copy. Repository runners and the
  user's running application are unchanged.
- All `lib/**/*.dart`, `tool/component_review/*.dart` and `test/support/*.dart`
  bytes match the current checkout. Sorted path + NUL + content manifest SHA256:
  `de4845384d03b98c2b256b14c0c3f8c0fad05be958ff607c891701a0371934e8`.
- Built kernel SHA256: `67aa39c270c5d327475f7b1d3e510b4e8dbe5ceff410366afff2a45958aa5d49`.

## Pending inspection plan

Compare the actual [official Badge page](https://ui.shadcn.com/docs/components/base/badge)
and the native Badge examples at matching width, 100% text and corresponding
light/dark states. Confirm 20px bounds, 12/16px type, border-box insets, 12px SVGs,
rounded-4xl computed radius, six variants, hover and focus rings. Preserve host
font/palette differences explicitly instead of claiming pixel equality.

Inspect Light, Dark, Forest and Plum; 360px / 200% / RTL / reduced motion; local
loading completion/restart; links and return; pointer-to-keyboard action focus;
disabled state and invalid status. Open Migration fixtures and inspect real
GroupsPage membership pills, exact TopicUnreadBadge counts, UserCardTarget's
staff and 123-badge profile, and ChatDrawerChannelsView's 99+ numeric badge.
Review the narrow large-text Chat metadata adaptation. The fixture uses only
in-memory stores/API and the `.invalid` site; do not navigate to real sites.

The Mac was reported locked by the coordinator. Respect that boundary and wait
for an explicit slot. Do not launch the app or browser while another task owns
the desktop. Record observed evidence and limits here after the slot, then
release it explicitly.

## Automated evidence

- 254 focused tests pass with seed 792026. Full command and output:
  `/private/tmp/badge-final-tests.log`. It covers Badge, examples, source-matched
  real-widget fixtures, Spinner composition, Groups/group members, user-card
  accessibility/account lifecycle, user-menu/plugin menu, Chat drawer/shell and
  topic-list lifecycle. The earlier 3px minimum-width Chat overflow was fixed
  and the real-shell test now guards usable title width and lower metadata.
- Root and `profiles/full` analysis pass without diagnostics. Locked dependency
  resolution passes without lockfile or SDK pin changes.
- Widget tests cover pointer-to-keyboard focus transfer, Enter versus Space link
  behavior, borrowed node lifecycle, disabled/invalid semantics, full accessible
  counts behind visual caps, hover, four live palettes, static geometry, 48px
  touch hit testing, large RTL labels, 0/1/4/12 host radii at 300%, local navigation,
  loading completion/restart and sample state retention.
- iOS target-platform widget checks are not iOS device testing. No iOS/Linux
  device run, VoiceOver speech or native focus success is
  claimed at this checkpoint.

- Browser followup: 39 focused tests pass, seed 792027
  (`/private/tmp/badge-browser-fix-tests.log`); actual widget export harness passes
  (`/private/tmp/badge-export.log`). Reference screenshots and test-renderer
  images are clearly distinguished in `evidence/badge/`. The signed isolated
  bundle was rebuilt after the radius and SVG corrections, without launching.
