# Attachment reference and adoption

## Frozen upstream

- Reference: `https://ui.shadcn.com/docs/components/base/attachment`
- Markdown: `https://ui.shadcn.com/docs/components/base/attachment.md`
- Frozen Markdown SHA256: `47350990437e1b9c623684cbee001101962dcd7fb9328b162ef07adb03774175`
- Verified on 2026-09-09: the downloaded 22,086-byte Markdown matches the frozen hash.
- Registry: `https://ui.shadcn.com/r/styles/base-nova/attachment.json`
- Registry SHA256 observed on 2026-09-09: `f6c6d376067d2734375a607256d59ce6c3ea4e486deda510b31844102033d353`.

Source preparation inspected the complete Markdown, rendered documentation text, and complete base-nova registry source. The independent review subsequently compared the official rendered light/dark overview, image, lifecycle, size, group, trigger, and accessibility sections and exercised the exact-source macOS fixture under the shared desktop lease.

## Acceptance and source mapping

| Base-nova behavior | Flutter mapping |
| --- | --- |
| `Attachment` state: idle/uploading/processing/error/done | `DAttachmentState`; caller owns lifecycle and data. Idle paints a 4px/3px dashed border, in-progress titles use the accepted lifecycle-aware shimmer, error uses destructive border/media/description plus required text, and done returns to the neutral card. |
| default/sm/xs | `DAttachmentSize.regular/small/extraSmall`; 14/17.5 then 12/15 title metrics, 12/16 metadata, 40/32/28 media, 8/10/6 gaps, and 8 / 6 / 4 root padding when media is present. Content-only cards use the source's 10×8 / 8×6 / 6×4 root padding. |
| horizontal/vertical | `DAttachmentOrientation`; horizontal has a 160px minimum, while vertical keeps the 96px reference outer width, applies the same root inset, and stacks content below with its additional 4px horizontal inset. Large text grows the row; truncation stays one line. |
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

`attachment_review_main.dart` mounts both the component examples and real `ComposerUploadQueue`/`ChatUploads` production widgets with local-only data and callbacks. Its toolbar exposes light/dark, a custom purple host palette with a 14px radius, LTR/RTL, 100%/200% text, standard/reduced motion, and wide/420px narrow review conditions.

The final reviewer candidate `c4806e82` built successfully as `/private/tmp/DiscourseAttachmentFinalReviewa5fc-c4806e82.app`, bundle ID `org.discourse.native.attachmentfinalreviewa5fc.rc4806e82`, URL scheme `discourse-attachment-final-review-a5fc`. The build and copied kernel agree at SHA256 `ce11a5206bc72ea07de42da753b86839b79d4cfbd3fe30f916d990cfb734f299`; restricted ad-hoc entitlement readback and deep strict verification passed. Exact final evidence is `evidence/attachment/final-review-build.json`.

## Independent acceptance

Dialog was accepted on local main at merge `6a0aaa54d86aaa492681f5cc4dcd32b5e2feefe3`. The final Attachment candidate was rebuilt from accepted-parent/current-main source; its Dialog files matched the accepted source, and the card trigger/dialog overlap passed the focused regression set and native AX interaction.

Independent source review found and fixed three acceptance issues: the migrated chat file link was shorter than its existing 44px keyboard target, horizontal multi-action cards reserved widths that did not match rendered `DButton` geometry, and the full-card trigger did not own/borrow focus robustly or fill the card's minimum interior. The accepted implementation keeps the 44px chat link contract, derives action reserve from actual targets, and gives `DAttachmentTrigger` explicit focus lifecycle and semantics without merging trigger and action nodes.

The accepted-parent regression run passed 104 Attachment, fixture, styleguide, Scroll Area, Dialog, composer, and chat tests with randomized seed `904748`; root and `profiles/full` analysis passed. After current main adopted Dialog's shared overlay route, the same affected run passed all 105 tests and both analysis targets again. Candidate `4112df91` rebuilt with matching kernels at SHA256 `758b369c9ca18ff0eb3f6c7a865d7ee7a96827b4a1fb52ef58ade9041c9c5c6d`; Attachment component, fixture, and adoption behavior were unchanged, so the completed native pass remains valid under the review protocol. Native macOS AX inspection exercised production progress/failure/retry/cancel/remove/complete behavior, chat-link semantics, image trigger/remove separation, lifecycle text, sizes, Dialog trigger/actions, theme/direction/text/motion/narrow modes, group pointer/trackpad/keyboard scrolling, focused-child visibility, and Tab+Return activation.

The native screenshot API continued to display the launch artwork instead of Flutter's live Metal layer even while AX content and callbacks updated, so no native pixel-fidelity claim is made. Space activation is covered by the focused Flutter widget test, not claimed through native CUA focus. No spoken VoiceOver, iOS, Linux, physical touch-device, or pixel-equality claim is made.
