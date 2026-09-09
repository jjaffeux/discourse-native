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
| close `top-2 right-2`, ghost `icon-sm`, Lucide X | Logical top/end 8px placement, 32px compact ghost surface, exact 16px two-stroke X artwork. Touch platforms retain DButton's larger invisible target and independent button semantics. |
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
and closes only when its original attachment is still mounted and open.
`showDDialog<T>` is the route-oriented helper and returns the typed close result.
Both APIs use the nearest Navigator unless `useRootNavigator` is explicitly set.

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

Input and Field own the future visual replacement of the temporary native fields
in examples and migrated forms. No substitute Field public owner is added
here.
