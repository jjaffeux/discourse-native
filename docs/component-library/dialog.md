# Dialog

Frozen scope: 2026-09-08 shadcn Base UI Dialog. The frozen documentation is
[`dialog.md`](https://ui.shadcn.com/docs/components/base/dialog.md), SHA-256
`c4915883516dc53b58f8aa12a9fddc04fd2bd350c7f6ca842ce737025736bebf`.
The exact generated [`base-nova/dialog.json`](https://ui.shadcn.com/r/styles/base-nova/dialog.json)
read on 2026-09-09 has SHA-256
`40fc321d25eb9590d07db54b00d9bc1a74274a549aa06d5915a34ba302ed8b94`.
Its extracted file content, including the generated trailing newline, hashes to
`a45dec4ab558f224b510e4720d4f314d926bc443cc127184b6bba843494169d8`.
The upstream shadcn repository was checked at
[`3ba91b1cc83e1bbe4ab35a422ff2a694849c5048`](https://github.com/shadcn-ui/ui/commit/3ba91b1cc83e1bbe4ab35a422ff2a694849c5048).
Its abstract Base UI owner is
`apps/v4/registry/bases/base/ui/dialog.tsx`, SHA-256
`aba6df6cbf51a1edcc22e415a3a46a666fc8cb66729e47b3ed2ecd97f166adff`;
the public endpoint expands that owner with the Nova classes recorded below.
Behavioral details were checked against the official
[Base UI Dialog API](https://base-ui.com/react/components/dialog).

## Reference mapping

CSS pixels map one-to-one to Flutter logical pixels at 100% scale.

| Base-nova source | Flutter mapping |
| --- | --- |
| `fixed inset-0 bg-black/10 backdrop-blur-xs`, 100ms fade | Full route `ModalBarrier`, black at 10%, 4px backdrop blur and a 100ms fade; it remains pointer-modal even when dismissal is disabled. |
| `w-full max-w-[calc(100%-2rem)] sm:max-w-sm` | Full available route width with 16px margins and a 384px cap. The outer route scrolls only as a keyboard/large-text fallback. |
| `grid gap-4 rounded-xl bg-popover p-4 text-sm` | 16px part gap/padding, host radius ×1.4, live `DTokens.surface`, 14px type with 20px leading. |
| `ring-1 ring-foreground/10` | One logical-pixel exterior shadow ring using live foreground at 10%; the opaque popup prevents interior tint. |
| `fade/zoom 95`, 100ms | Backdrop fades independently; popup fades and scales from 95%. Reduced motion removes both durations and transformations. |
| close `top-2 right-2`, ghost `icon-sm`, Lucide X | Logical top/end 8px placement, 28px compact ghost surface, exact 16px two-stroke X artwork. Touch platforms retain DButton's larger invisible target and independent button semantics. |
| header `flex-col gap-2` | Vertical header with 8px gaps. |
| title `text-base leading-none font-medium` | Host heading family, 16px, 16px leading, weight 500, zero tracking, heading/route-name semantics. |
| description `text-sm text-muted-foreground` | 14px, 20px leading, weight 400 and live muted foreground. Links remain owned by their child widgets. |
| footer `-mx-4 -mb-4 ... gap-2 rounded-b-xl border-t bg-muted/50 p-4` | A true edge-to-edge final slot, 16px padding, 8px gaps, one-pixel top border, live muted alpha multiplied by 0.5 and matching lower radius. It is a row aligned to end when the viewport is at least 640px and a reversed full-width column below that. |
| examples use `max-h-[50vh] overflow-y-auto` | `DDialogScrollArea` caps an independently scrollable body at 50% of current viewport height so headers and sticky footers remain visible. |

The inherited host palette, font, radius, direction, text scale, view insets and
reduced-motion preference are read while the route is open. `SafeArea`, current
keyboard insets and an outer vertical fallback keep the popup reachable rather
than forcing a fixed desktop height.

## Public composition and behavior

`DDialog<T>` owns a declarative route and composes `DDialogTrigger`,
`DDialogContent`, `DDialogHeader`, `DDialogTitle`, `DDialogDescription`,
`DDialogFooter`, `DDialogScrollArea` and `DDialogClose<T>`. A null `open` value
uses local state; a non-null value makes state caller-controlled through
`onOpenChanged`, including the trigger, barrier, Escape, close, programmatic and
route-removal reason. Controlled dismiss requests leave the route mounted until
the caller supplies `open: false`.

`DDialogController<T>` is a borrowed imperative handle. `submit` exposes busy
state, returns the same Future for repeated activation, propagates failures,
and closes only when its original attachment and open session remain current.
`showDDialog<T>` is the route-oriented helper, builds content with a true route
descendant context and returns the typed close result. Both APIs use the nearest
Navigator unless `useRootNavigator` is explicitly set. Caller-scoped theme,
media and direction changes remain live while the helper route is open.

The route requests focus, loops traversal at both edges, optionally targets a
borrowed initial focus node, and restores a borrowed final node or the previously
focused trigger. Background pointers and focus stay blocked. Barrier and Escape
dismissal are independently configurable. Route removal detaches controllers
without disposing borrowed objects. Dialog content is lazily mounted with its
route. Nested calls use normal Navigator stacking rather than a second overlay
owner.

No Form state is invented. Fields, validation, save/reset and async persistence
remain with the caller. The frozen profile examples use the merged shared
`DInput` owner; richer Field composition remains with its separate catalogue task,
their editable semantics remain field-sized and footer/close buttons remain
independent controls.

## Application adoption audit

The audit searched core, all bundled plugins, the Voice package and compatibility
profile for `showDialog`, `Dialog`, `AlertDialog`, `CupertinoAlertDialog` and the
existing adaptive wrapper. It migrated two ordinary editable workflows with
useful coverage:

- Chat channel details now uses `showDDialog<void>` and `DDialogContent`. It
  preserves nearest-route ownership, disabled barrier dismissal, initial field
  focus, validation, loading lockout, error text, metadata diffing and the
  original async controller callback.
- Voice room create/edit now uses typed `showDDialog<VoiceRoomDraft>`. It keeps
  all native fields and switches, required-name semantics, the locally selected
  quality settings, cancellation, the typed draft, post-route controller
  resolution and asynchronous persistence outside the generic component.

Retained alternatives are narrow rather than unfinished Dialog copies:

- destructive/permanent-delete, flag, discard, status-toggle and other
  confirmations remain with Alert Dialog, including `DiscourseAlertDialog` and
  adaptive Cupertino alert actions, until that catalogue owner lands;
- `showShellSheet`, add-instance, Poll/Local Dates/GIF/reaction pickers and
  bottom/desktop adaptive routes remain Sheet, Drawer or Popover concerns;
- App Settings is a 768×720 navigation workspace with its own shell header, not
  the compact focused Dialog composition;
- composer link/gallery, emoji, media/full-screen, date/time, system file and
  platform permission dialogs retain specialized routing, native APIs or
  lifecycle contracts;
- vendored WebRTC examples are third-party sources and are not app adoption
  targets.

The merged Input owner supplies the single-line fields in the examples. Richer
Field composition remains with that separate catalogue owner; no substitute
Field public API is added here.

## Independent rendered and native review

The official rendered base-nova page was inspected in light, dark, Arabic RTL
and Scrollable Content states. The default popup measured 384×305 logical/CSS
pixels with 16px padding and gaps, a 14px radius, 16px/16px weight-500 title,
14px/20px description, and a 384×65 footer with 16px padding and 8px gaps. The
live `icon-sm` close surface measured 28×28 at logical top/end 8px, correcting
the provisional 32px task criterion. RTL moved it to logical start and mirrored
the actions; the scroll example retained its header above a 50vh body.

The final isolated macOS fixture at
`/private/tmp/discourse-native-dialog.qNoMNI/build/macos/Build/Products/Debug/Dialog Native Review.app`
mounted the actual Chat and Voice editors and the actual component styleguide.
The reviewed `d_dialog.dart` SHA-256 is
`f438edbbc8b0484044389d3df603bf09212ee40ad680628af930557563b80b5e` and
the final fixture kernel SHA-256 is
`662c83fdf2d391f64f8e5a34d14324bb5e6bf417c64d158fb810b0fb546a580c`.
The ad-hoc signature passed deep strict verification with only the documented
debug/sandbox entitlements.

Native CUA inspection covered Chat field editing and cancellation; Voice edit
and create in Plum, RTL and 200% text with independently scrollable bodies and
sticky actions; save validation; reduced-motion opening; Escape dismissal; and
closed-loop forward Tab traversal. Default, Scrollable Content and Arabic RTL
styleguide examples rendered with independent route, close, field and action
semantics. The isolated app was quit and the shared desktop lease released.

No physical iOS/Linux run or VoiceOver speech session was performed. Native
font shaping and antialiasing differ from browser rendering, so this review does
not claim automated pixel-identical cross-renderer output.
