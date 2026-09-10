# Avatar online ring follow-up

Reviewed 2026-09-10 against Discourse core checkout
`/Users/joffreyjaffeux/Code/pr-discourse` at
`2e9dc47bd88ec564395bfc00b3c15d614164e4ca`.

Sources:

- `plugins/chat/assets/stylesheets/common/chat-user-avatar.scss`, SHA256
  `7f54519636c1bddbdeaf851980e355eafb21258ab3b4f40b8c901763b3586851`.
- `plugins/chat/assets/javascripts/discourse/components/chat-user-avatar.gjs`,
  SHA256
  `bebca8c8bf0f3f8750f64222d8b2601b6033493cb28b556d85c6372b9822526c`.

## Mapping

| Core | Native |
| --- | --- |
| `.is-online` derives from Chat presence membership | Chat retains its live `onlineUserIdsListenable` and passes the boolean to `DAvatar.ring` |
| avatar border-box keeps its declared width/height | enum, explicit-dimension and intrinsic-frame avatars keep their former outer extent |
| `padding: 2px` | private ring layout insets image/fallback content by 2 logical pixels on every side |
| outer `inset ... 1px var(--success)` | 1px border from live `DTokens.success` |
| underlying `inset ... 2px var(--secondary)` | live `DTokens.background` remains visible as the second 1px band |
| online state is a CSS class | `ringSemanticLabel` combines with the identity label so status need not rely on color |

The default avatar border is replaced while the ring is active, matching core's
single success/background treatment rather than stacking an unrelated third
stroke. Badge/flair positioning continues to use the unchanged outer bounds.
Chat's private `_OnlineAvatar` rendering owner was removed; it now supplies its
existing presence result, URL, fallback and fixed size to the public component.

## Verification

- Root `flutter pub get --enforce-lockfile` passed without lockfile changes.
- `flutter analyze --no-pub` passed with no diagnostics.
- `profiles/full`: enforced locked resolution and `flutter analyze --no-pub`
  passed with no diagnostics.
- 216 focused tests passed with seed `9082026` across `d_avatar_test.dart`,
  `avatar_examples_test.dart`, `chat_message_tile_thread_preview_test.dart`, and
  `chat_shell_integration_test.dart`. Coverage includes exact 32→28 and 28→24
  inset geometry, intrinsic-frame extent preservation, semantic labels, live
  presence entry/leave, site success/background colors, direct-message/sidebar
  reuse and group-flair coexistence.
- `flutter build macos --debug --no-pub -t tool/avatar_review_main.dart` passed.
  The inspected ad-hoc copy was
  `/private/tmp/avatar-ring-review.Mwd5cx/Avatar Ring Review 6d2e.app`, bundle
  `org.discourse.avatarringreview6d2e`. Its read-back entitlements retained
  sandbox, JIT, network, selected-file and local camera/audio debug capabilities
  while omitting push, developer-team and application-identifier entitlements;
  deep strict signature verification passed.
- Native macOS 26.6.2 arm64 inspection covered the source-matched fixture and
  registered Avatar styleguide page. The ring retained fixed geometry in light,
  dark, Forest and Plum palettes; LTR/RTL, wide/360px, 100%/200% text and reduced
  motion. Both fallback and decoded local image were inspected. Native AX named
  them `Chris, Online` and `Evil Rabbit, Online`. The isolated app was closed,
  confirmed absent from a fresh app inventory, and the desktop lease released.

No iOS or Linux device run and no spoken VoiceOver run were performed. Widget
platform overrides are not device testing. The core comparison used its exact
current source and geometry; no browser pixel-diff claim is made.
