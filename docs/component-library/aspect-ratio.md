# Aspect Ratio

`DAspectRatio(ratio: width / height, child: ...)` is exported by
`package:discourse_native/discourse_ui.dart`. It accepts every finite positive
ratio, including an empty child. It mounts Flutter's `RenderAspectRatio` directly,
so there is one layout owner and no extra widget wrapper. Debug constructors
assert invalid ratios; mount/update also throw `ArgumentError` in release.
Remote-media normalization remains in application adapters.

Flutter starts with bounded maximum width, or derives width from bounded height.
Minimum/maximum parent constraints win when the ratio cannot fit; a tight parent
can override it entirely. At least one axis must be bounded. Inside a
`FittedBox`/`UnconstrainedBox`, supply a finite dimension. The child receives
the resulting tight size. Text scaling does not stretch that reserved rectangle:
keep captions outside and scroll growing interactive content inside it.

The component owns no paint, clipping, semantics, input, focus, motion, media
requests or controllers. Children retain those responsibilities and their
state on ratio/theme/direction updates. In particular it does not dispose
borrowed media controllers or reconstruct playback when only the ratio changes.

## Frozen source and visual mapping

Inspected 2026-09-08; the frozen catalogue was not resnapshotted.

| Source | SHA256 |
| --- | --- |
| [Frozen Markdown](https://ui.shadcn.com/docs/components/base/aspect-ratio.md), preserved in `reference/aspect-ratio.md` | `7d0ebab187a210c255515d46b286d99cf55b16879d76075e2490646dbc80cda1` |
| [Official base-nova registry](https://ui.shadcn.com/r/styles/base-nova/aspect-ratio.json), raw bytes preserved in `reference/aspect-ratio.json` | `8600bbd8874ad9f0c3f60625b7def0960369a93c5cac09ee5a5fad7500500248` |
| Registry `registry/base-nova/ui/aspect-ratio.tsx`, decoded source content | `6df19df6b983c450361081b695dbf3541a6fe4a9d2ec148766991e4eb0bf6473` |
| [Registry-linked aggregate example](https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/aspect-ratio-example.tsx), raw source | `d81a6912343f21f28f6939a20012f3033edb523e64fd892c3c9148246df4ef6a` |
| [Linked Base UI API page](https://base-ui.com/react/components/aspect-ratio#api-reference), HTTP 404 response body | `b62922dd2540e51c9baa9b5e0c02a9d1a6983d315aa9fd87e21788d91f138af0` |
| Existing local `assets/app_icon.png`, copied as the offline styleguide image | `46534b6c4164c36465a9513e5ea1e36f28f5180a7a3b2ea524a2201bc1182eae` |

The registry implements a plain `div` with `relative aspect-(--ratio)` and
caller `className`; it does not import Base UI. The frozen installation's
Base UI dependency and now-missing API link do not require a Flutter dependency.
The current aggregate example additionally shows 21:9 and style-luma classes;
they do not replace the frozen base-nova dimensions or expand the catalogue.
The source is covered by the preserved `reference/LICENSE.shadcn.md`.

| Reference | Flutter mapping at 100% scale |
| --- | --- |
| Required `ratio`; `relative aspect-(--ratio)` | Required arbitrary `double ratio`, native ratio layout; callers compose `Stack` for positioned children. |
| `className` | Ordinary Flutter sizing, decoration, clipping and child composition. No preset-only or image-specific API. |
| 16:9, `w-full max-w-sm` | Width up to 384px; 384×216 at full reference size. |
| Square, `max-w-[12rem]` | Up to 192×192px. |
| Portrait 9:16, `max-w-[10rem]` | Up to 160×284.444px. |
| `rounded-lg bg-muted` | Caller `ClipRRect` using live `DTokens.radius` (large/base radius), and `DTokens.muted`. No border, shadow or padding. |
| Image `fill object-cover` | Tight child with `BoxFit.cover`, centered crop. Optional contain/rounding switches stay caller-owned. |
| `grayscale dark:brightness-20` | Color matrix with 0.2126/0.7152/0.0722 luminance coefficients, multiplied by 0.2 in dark themes; alpha unchanged. Read live brightness. |
| RTL figure `mt-2 text-center text-sm text-muted-foreground` | `DDirection(textDirection: rtl)`, caption outside the box, 8px gap, centered `DText.muted` at 14px/20px with native text scaling and configured font. |
| Native behavior | No ratio animation, focus stop, semantic label or hit target is invented. Normal descendants handle input, semantics, focus, scrolling and disposal. |

All seven example groups import the public library and use local state. Ordinary
actions use `DButton`; rich labels reset inherited single-line defaults so they
wrap. TextField and Slider retain existing baseline owners pending their own
catalogue tasks. The bundled sample image deliberately differs from the remote
Vercel avatar. An explicit package asset key works identically in root and
`profiles/full` without a runtime network request or asset fallback.

## Adoption audit

Searched every Dart file in core, all bundled `lib/src/plugins/`,
`packages/discourse_voice/lib`, and `profiles/full/lib`; also inspected native
package examples and the vendored boundaries.

- Migrated generic and topic onebox thumbnails. Preserved 88px/avatar sizing,
  normalized metadata, cover fit, border radius, cached decoding, links and errors.
- Migrated `LightboxThumbnail`'s reserved ratio. Preserved declared-width ceiling,
  contain fit, semantics/taps, loading geometry, gallery/zoom ownership and safe
  image-size normalization.
- Migrated Chat upload images and optimistic GIF preview. Preserved 420px/150px
  ceilings, no-upscale policy, contain fit, dominant-color fill, GIF controls,
  semantic actions, gallery state, loading/error and provisional-preview rules.
- Migrated inline and fullscreen playback ratio frames. The outer `InlineVideo`
  surface now uses constraints plus `DAspectRatio` instead of competing manual
  width/height division. A nested `LayoutBuilder` supplies the actual constrained
  size to existing cover decoding; the 720px unbounded-width fallback, optional
  caps, clipping, poster/activation, sessions, controls and scrolling remain.
- Migrated Skeleton card placeholders, ready content and their public snippets;
  updated Skeleton's relative-sizing API documentation.

Retained alternatives:

- `InlineVideoData`, playback requests/state, `ChatUpload`, `OneboxThumbnail`,
  `LightboxImage`, `Gif`, and image-decode helpers describe/normalize metadata or
  native playback intents. Their `aspectRatio` values are not layout owners.
- `YoutubeVideo`'s manual frame has a deliberate 200px minimum height that breaks
  16:9 on narrow columns and supplies macOS platform-overlay geometry. Replacing
  it with a strict ratio would change its embedded-player contract.
- `ComposerImagePreview.displaySize` calculates natural-size, authored-scale,
  no-upscale and two-axis bounds for editor measurement/selection. Its fixed
  decorated box is also a selection owner, not a generic ratio container.
- Image-grid mosaic columns deliberately stretch equalized heights; its carousel
  uses a fixed 400px track and per-image contain fitting. GIF and Voice grid
  `childAspectRatio` belongs to Flutter's sliver grid owner.
- `packages/video_player_avfoundation/example` and vendored WebRTC examples are
  upstream package demonstrations. They must not depend on the app UI library.

## Verification

- `flutter analyze --no-pub`: no diagnostics.
- `flutter test --no-pub --test-randomize-ordering-seed=random` with
  `test/ui/d_aspect_ratio_test.dart`, `test/styleguide/aspect_ratio_examples_test.dart`,
  `test/inline_video_test.dart`, `test/chat_uploads_test.dart`,
  `test/chat_uploads_accessibility_test.dart`, `test/oneboxes/onebox_test.dart`,
  `test/oneboxes/discourse_topic_test.dart`, `test/lightbox_test.dart`,
  `test/video_poster_decode_test.dart`, `test/chat_preview_test.dart`,
  `test/chat_preview_corpus_test.dart`, `test/chat_preview_totality_test.dart`,
  `test/native_inline_video_playback_test.dart`, `test/webview_inline_video_playback_test.dart`,
  `test/styleguide/skeleton_examples_test.dart`, `test/ui/d_skeleton_test.dart`,
  `test/d_button_adoption_test.dart`: 305 passed, seed `2654739856`.
- After the shared-asset correction, the 32 Aspect Ratio example tests passed
  again from the root (seed `443369763`) and from `profiles/full`
  (seed `1858729558`) after `flutter pub get --enforce-lockfile`. Both use the real asset bundle and image decoder.
- Coverage includes arbitrary and conflicting constraints; empty/unbounded
  behavior; state, focus, keyboard, pointer and semantics preservation; caller
  disposal; live palettes and direction; 200% text/scroll retention; exact cover
  geometry/filter/caption styles; media session/size/decode and adoption regressions.
- Final shared styleguide page plus Aspect Ratio examples: 40 passed, seed
  `29227221`, after marking the verified group implemented. Final analysis and
  touched-file formatting passed; `git diff --check` was clean.
- No Flutter pin or lockfile changed. No full-suite gate was required. Widget
  tests with platform overrides are not native device checks.

Browser inspection of the live official page confirmed 384×216, 192×192 and
160×284.4375 CSS-pixel rectangles at the documented maximum widths; the
portrait's 0.00694px difference from the exact arithmetic height is browser
layout quantization. The reference's large radius is 10px before applying the
app's radius variable. Light and Dark covers, square, portrait and Arabic figure
were inspected; computed image fit/filter and caption gap/type matched the
mapping above. The reference uses a small blurred Vercel avatar; the offline
Discourse sample intentionally has different image content.

## Native inspection

After the coordinator's exclusive desktop grant, inspected the ad-hoc signed
`Aspect Ratio Review.app` from
`/private/tmp/discourse-aspect-ratio-review-01a082a9/app/build/macos/Build/Products/Debug/`.
Bundle `org.discourse.aspect-ratio-review` and URL scheme
`discourse-aspect-ratio-review` were verified. Before launch every production
`lib/` file byte-matched the worktree; the only subsequent production change
marks the verified example group implemented. Runner/signing/fixture changes
exist only in that temporary copy.

- Compared native widescreen Light/Dark, square Dark, portrait Forest, and Arabic
  figure Plum at 360px/200%/RTL against the recorded official geometry and source.
  The image crop, 20% dark brightness, live radii, gap and caption treatment match
  the mapping. No unintended geometry or styling difference was found.
- Inspected arbitrary 1.37 → 2.72 ratio changes using the native slider; contain
  and corner toggles act independently. Inspected the four bounded/tight/height-
  only/unbounded-parent examples at 360px/200%/RTL, including outer scrolling.
- Edited the interactive note, used Tab to expose a visible focus border, and
  activated the counter with Enter. The note, counter and focus survived ratio,
  Plum → Light and RTL → LTR changes. Growing content remained reachable by
  scrolling inside the resized ratio frame.
- Inspected actual `OneboxCard`, `DiscourseTopicOnebox`, `LightboxThumbnail`,
  `ChatUploads`, `ChatPreviewBody` and `InlineVideo` widgets. Ready image data was
  served from bundled bytes by a temporary loopback-only server; separate paths
  held loading and returned 404. No account, credential or real server data was
  used. Confirmed cover/contain fits, fixed thumbnail sizes and reserved loading/
  error geometry in Light and narrow Dark/Forest/Plum RTL at 200%.
- The real optimistic GIF preview's pause action changed to Play GIF. The actual
  Lightbox gallery opened from its thumbnail and returned with Escape. Inline
  video activated lazily, paused, kept its 0:07/0:30 position across size/theme/
  direction changes, entered fullscreen and returned with Escape. Its session
  was explicitly fake and rendered a local image; this checks real presentation
  and route behavior, not AVFoundation/WebKit decoding or physical playback.
- Opened the complete native styleguide, searched for Aspect Ratio and displayed
  its registered widescreen preview and usage notes. Its AX tree exposes fewer
  nodes than the temporary harness; pointer navigation was used there. The
  harness exposed child image, button, slider and editable-text semantics.
- Quit only the isolated app via its application menu. The initial global
  inventory caught shutdown in progress; a subsequent global CUA inventory
  returned no `org.discourse.aspect-ratio-review` entry. No app-specific read was
  used after quit. Released the desktop slot to the coordinator.

The intentional remaining visual differences are the offline image content,
configured app palette/font/radius variables, native glyph shaping, and the
browser portrait's subpixel quantization documented above. No pixel-identical
cross-renderer claim is made. iOS/Linux devices, VoiceOver speech and real video
codec playback were not inspected. No system accessibility or real runner
setting changed.
