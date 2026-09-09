# Attachment reference and adoption

## Frozen upstream

- Reference: `https://ui.shadcn.com/docs/components/base/attachment`
- Markdown: `https://ui.shadcn.com/docs/components/base/attachment.md`
- Frozen Markdown SHA256: `47350990437e1b9c623684cbee001101962dcd7fb9328b162ef07adb03774175`
- Verified on 2026-09-09: the downloaded 22,086-byte Markdown matches the frozen hash.
- Registry: `https://ui.shadcn.com/r/styles/base-nova/attachment.json`
- Registry SHA256 observed on 2026-09-09: `f6c6d376067d2734375a607256d59ce6c3ea4e486deda510b31844102033d353`.

Source preparation inspected the complete Markdown, the rendered documentation text, and the complete base-nova registry source. No rendered browser comparison or native device pass is claimed here; those remain with the independent reviewer under the shared desktop lease.

## Acceptance and source mapping

| Base-nova behavior | Flutter mapping |
| --- | --- |
| `Attachment` state: idle/uploading/processing/error/done | `DAttachmentState`; caller owns lifecycle and data. Idle paints a 4px/3px dashed border, in-progress titles use the accepted lifecycle-aware shimmer, error uses destructive border/media/description plus required text, and done returns to the neutral card. |
| default/sm/xs | `DAttachmentSize.regular/small/extraSmall`; 14/20 then 12/16 text, 40/32/28 media, 8/10/6 gaps, 10×8 / 8×6 / 6×4 content padding. |
| horizontal/vertical | `DAttachmentOrientation`; horizontal has a 160px minimum, vertical keeps the 96px reference card/media width and stacks content below. Large text grows the row; truncation stays one line. |
| rounded-xl / xs rounded-lg | Host radius ×1.4 for default/sm and ×1 for xs; media uses host radius ×1 or ×0.8. |
| border, card, muted, destructive and ring variables | `DTokens.surface`, `border`, `muted`, `destructive`, and an outside-only 3px half-alpha focus-within ring. Live light/dark/custom theme changes are read during every build. |
| icon/image media | `DAttachmentMediaVariant.icon/image`; 16px icon, 14px xs icon, 24px vertical icon; images cover a square and use 60% opacity only for uploading/processing/error. Media is decorative unless explicitly labeled. |
| title/description | `DAttachmentTitle` and `DAttachmentDescription`; medium title, 2px metadata gap, one-line truncation, destructive error metadata. `DMarkerContent` is reused as the already tested shared shimmer owner. |
| actions | `DAttachmentActions` with `DAttachmentAction`, backed by the accepted ghost extra-small `DButton`. Every icon-only action requires a tooltip/semantic label, supports disabled/loading/focus, and borrows optional focus nodes. Touch gets a 48px target while desktop artwork stays 22px. |
| full-card trigger | `DAttachmentTrigger`, a real keyboard button or link with an explicit semantic label and borrowed focus node. It occupies the card behind `DAttachmentActions`; visual content ignores pointer input so the trigger and actions never trap one another. |
| group | `DAttachmentGroup` composes accepted `DScrollArea`: 12px gap, 4px vertical scroll padding, hidden scrollbar, horizontal edge fade, pointer/touch/trackpad drag, overscroll containment from the native viewport, configurable item snap extent, automatic scrolling to focused descendants, and optional focusable labeled presentational group with Left/Right/Home/End. Supplied controllers/focus nodes are borrowed; omitted resources are owned/disposed. |
| reduced motion / lifecycle | Title shimmer stops for reduced motion, disabled ticker, or inactive app through the accepted shared shimmer behavior. Snap and direct keyboard movement remain functional without decorative animation. |

The public anatomy is `DAttachment`, `DAttachmentMedia`, `DAttachmentContent`, `DAttachmentTitle`, `DAttachmentDescription`, `DAttachmentActions`, `DAttachmentAction`, `DAttachmentTrigger`, and `DAttachmentGroup`. Every part accepts widget children; file/network/upload/download/business objects are deliberately absent.

## Production audit and migrations

- `ComposerUploadQueue` is migrated to actual `DAttachment` rows. It preserves `ComposerController` as the owner of progress, retry, cancel, removal, submission blocking, abort triggers, thumbnails, upload ordering, and result insertion. Uploading and retrying show a spinner plus numeric description; failure keeps its reason and independently labeled retry/remove buttons; completion keeps the local authenticated thumbnail and remove callback.
- Non-image/non-video `ChatUploads` attachments are migrated to `DAttachment` with a link trigger. Existing absolute/subfolder/CDN URL resolution and `openLink` ownership remain unchanged, and filename/filesize stay in title/description.
- Chat image lightboxes and inline video are retained: they own authenticated images, aspect ratios, gallery navigation, GIF/video controls, hero/download data, and error reporting rather than representing the compact file-card composition.
- Composer projected images, image galleries, editing toolbars, drag/drop regions, picker buttons, Markdown document models, and upload networking are retained: they are selection/editing/drop/network owners, not attachment cards. Chat send/edit coordinators retain upload IDs and lifecycle ownership.
- No other core or bundled-plugin file/attachment chip renderer was found in the full `lib/src` and `packages` audit on 2026-09-09.

## Styleguide and native fixture

`attachment_examples.dart` provides the documented composition, image/vertical group, all five states, all three sizes, mixed scroll group, dialog trigger with independent actions, and RTL/large-text/narrow cases. Examples use public components and local state only. The bundled Discourse image keeps image examples deterministic and offline.

`attachment_review_main.dart` mounts both the component examples and real `ComposerUploadQueue`/`ChatUploads` production widgets with local-only data and callbacks. The independent reviewer owns building and inspecting its uniquely identified macOS bundle after integrating the accepted Dialog parent/current main.

## Prepared dependency gate

Source preparation merged exact Dialog review pin `8a80078316381a60f70b4e11adbc919814ca9fbc` from `codex/review-dialog`; parent reviewer task `01a08558-7ac2-79a3-bd49-1be6148f540c`. This is tested prepared source, not accepted main. Attachment's reviewer must wait for Dialog's accepted local-main merge, integrate current main, reconcile the accepted parent, verify overlapping trigger/dialog behavior, and ensure no unaccepted parent revision reaches main through Attachment.
