# Message reference and implementation

Frozen on 2026-09-08 from `https://ui.shadcn.com/docs/components/base/message.md`.

- Markdown SHA256: `39047b5f5cef3654f98cd34f60dbdee75f585a03af3ddf35839e113b8e649782` (verified 2026-09-09).
- Base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/message.json`.
- Registry SHA256: `6a484395f7ed32d3b254619cc542aeed6ce77a5628d1e9a04d4b5baaf7de0c41`.
- Reference package: `lucide-react`; Flutter actions use the shared Button owner with caller-supplied artwork.

## Source mapping

| Reference | Flutter | Exact mapping |
| --- | --- | --- |
| `Message` | `DMessage` | Full-width logical row, 8px gap, 14px/20px text, start/end ordering. |
| `MessageGroup` | `DMessageGroup` | Vertical consecutive-sender stack with 8px gap. |
| `MessageAvatar` | `DMessageAvatar` | 32px minimum slot, circular content supplied by `DAvatar`, bottom anchored, fixed 32px upward shift when a footer is present. Empty slot preserves grouped alignment. |
| `MessageContent` | `DMessageContent` | Full remaining width, minimum width zero by flex construction, vertical 10px gap, arbitrary rich children and logical surface alignment. |
| `MessageHeader` | `DMessageHeader` | Wrapping logical-start metadata with 12px horizontal inset; 12px/16px medium muted text. |
| `MessageFooter` | `DMessageFooter` | Wrapping metadata/actions with the same metrics and inset; follows the Message side. |
| descendant ghost Bubble | automatic metadata flush | A direct ghost `DBubble`, or one in `DBubbleGroup`, removes the 12px metadata inset. |
| icon actions | `DButton.iconOnly` | Shared Button owns keyboard, focus, tooltip, semantic label, disabled state and 24px compact desktop / 48px touch hit target. |
| attachment | `DAttachment` parts | Shared Attachment owns media/card/action rendering. Message only positions it. |
| typing/in-progress status | live `DMarker` | Shared Marker owns status-role semantics and optional shimmer/spinner composition. |

CSS pixels map to Flutter logical pixels at 100% with the captured 16px root. Typography keeps the host family while using explicit reference size, leading, weight and zero tracking. Colors come from live `DTokens`; Message itself paints no surface. It therefore updates immediately for light, dark, custom palette, font and radius changes through its composed owners.

`DMessage` is deliberately presentational. It does not assign a chat/article role or merge descendants. Callers may add a semantic label or whole-row live region only when that accurately describes the entire changing row. `DMessageStatus` supplies localizable pending, delivered, read, failed and deleted presentation; delivery and retry work remain caller-owned.

Bubble owns its own maximum width and internal alignment in Flutter. Callers use matching `DMessageAlign.end` and `DBubbleAlign.end`; this preserves a clear dependency boundary instead of Message reconstructing Bubble. `DMessageContent` automatically aligns other content-sized children. `flushMetadata`, content spacing/alignment, avatar alignment, minimum extent and footer shift are narrow application-adapter extensions. Their defaults exactly follow base-nova.

## Accessibility and native adaptation

- Ordinary Message composition adds no semantic boundary, preserving arbitrary rich-content and independent descendant controls. Optional row/status semantics are explicit.
- `DMessageHeader` and `DMessageFooter` use `Wrap`, so sender metadata and actions reflow at narrow widths and large text rather than clipping.
- Logical ordering, alignment and directional padding follow RTL. The ambient Flutter text scaler is the sole scaling owner.
- Icon-only actions must provide Button/Attachment tooltip labels. Each remains independently focusable and actionable; footer semantics do not merge them.
- Desktop keeps compact reference artwork. Button and Attachment retain their already-reviewed 48px invisible touch targets on iOS/Android.
- Message has no animation. Reduced motion is inherited by composed Marker/Bubble/Attachment owners.
- `DMessageAvatarAlignment.top` and zero spacing/minimum extent are explicit compatibility options for the existing Discourse Chat adapter; reference examples use bottom/8px/32px defaults.

## Application audit and adoption

`lib/src/plugins/chat/chat_message_tile.dart` is the suitable production adoption. Its `_Tile` now composes `DMessage`, `DMessageAvatar` and `DMessageContent`, while the adapter retains:

- controller lookup, optimistic/canonical CookedHtml and projected previews;
- speaker chaining, exact 42px gutter, top-anchored 28px authenticated avatar, existing row padding and minimum heights;
- user-card behavior, status/flair/staff/bot/time metadata;
- selection, uploads, edited/pinned/bookmark/delivery state, reactions, thread preview and reply jump;
- hover/long-press actions, permissions, async mutations and virtualization keys.

Category channels retain the established compact Discourse presentation. Direct
messages now use the complete Message/Bubble composition described below. The app
adapter preserves product-specific behavior in both layouts. `ChatUploads`
composes the accepted Attachment owner for file cards.

`tool/message_native_review_main.dart` mounts these exact production widgets
against local in-memory Chat records for native acceptance. It covers ordinary
and chained rows, CookedHtml, selection ownership, an upload, reactions, a
thread preview, a direct reply, edited/pinned state, failed delivery and deleted
presentation without reading or mutating a real account.

Retained alternatives:

- `chat_transcript.dart` remains a quoted-transcript `QuotePanel` with nested CookedHtml and source/channel links, not a live conversation row.
- message inbox/topic rows summarize private-message topics rather than render conversation messages.
- empty/error notices remain `DEmpty` or `DAlert`; SnackBars remain transient feedback.
- Voice room list rows, notification summaries, post streams and composer previews keep their domain-specific owners.
- Message Scroller task `01a08606-ce86-7be2-b92f-59676b40cb40` owns stable item IDs, anchoring, pagination viewport and scroll lifecycle. It composes keyed Message children without inspecting them.

## Accepted dependency provenance

- Bubble: accepted local merge `c3d6ae97af486134b32067aecc29f7191b05367d`, reviewer `01a08639-b066-7882-85f5-a759c5fdab6f`.
- Attachment: accepted local merge `99cea2172e9ddb5da775bff7b81e82c24ad72870`, reviewer `01a085f6-d243-7d73-8a4a-c1a1225d3a8f`.
- Avatar and Marker: accepted local merges `5c78eb9d5c9db5f37ac7eaf8deab2233944dcbd0` and `fc92f4e69042191eff5d39d52c1355a6d6a87da7`.

Message candidate `35ac776c` was created from accepted-parent main
`b2f42554`; all accepted parent source wins over prepared snapshots. Their
Message-facing APIs are unchanged. The reconciled 193-test component,
composition and Chat lifecycle run passed.

## Independent review

Review fixes preserve intrinsic direct-child widths and order, use the exact
zero default header gap, inherit medium-weight status typography and lock the
14/20 and 12/16 metrics with live font tests. The styleguide now has seven
complete example groups, including the separate multiline Avatar composition.
Copy, like, dislike, retry and download callbacks expose real local results.

The production-fixture regression exposed reaction-pill and thread-metadata
overflows at 360px and 200% text. Reaction artwork/fallback and count now wrap
within their existing target; the thread header uses an overflow-aware layout
for author and participant/reply metadata. Normal-width alignment, semantics,
permissions and callbacks stay with the existing adapters. All 212 affected
Message, Chat and reaction tests pass with seed 39059, including the final-main
test-only correction to the legacy Reply semantics assertion. Root and
full-profile analysis are clean on candidate `5f419da1`.

Exact-source build provenance, completed browser/native observations and
explicit platform limits are tracked in
`docs/component-library/evidence/message/native-review.json`. The production
fixture's visible thread/reply/jump/edit result belongs only to that local
review harness. Generic Message and the production adapter expose no new
network or scroll responsibilities.

## Acceptance result

Official rendered Overview, Avatar, Group, Header/Footer, Actions and Attachment
compositions were compared in light and dark. All seven native examples were
inspected in normal light/dark and Plum at 360px, 200% text, RTL and reduced
motion. Copy, like, dislike, retry, download and status changes produced visible
local results. The corrected footer and scaled production reaction/thread
metadata passed the final native inspection on source `5f419da1`.

The actual local-data production tiles retained independent profile, upload,
reaction, thread, jump and action nodes. Thread/jump/reply callbacks, pointer
hover, visible Tab focus, Return menu activation, Escape dismissal/focus return
and rich-text selection were exercised. The profile target correctly reached
the offline fixture's error surface rather than real account data. Broader
bookmark, mutation, permission and touch/long-press variants are covered by the
passing widget suites, not claimed as native device runs.

No spoken VoiceOver, iOS/Linux device, physical touch, modifier shortcut, real
file transfer or delivery-network acceptance is claimed. The image attachment
uses deterministic local artwork, and host font/palette/radius tokens remain
live; cross-host bitmap identity is not claimed. The exact isolated app was
quit, its absence verified, the owned reference tab closed, and the desktop
lease released before final integration.

Final integration candidate `a5296738` starts from main `5ca267b5`. All 244
focused Message, Chat, reaction, Button and styleguide-page checks passed with
seed 39060, and root/full-profile analysis passed. Message, production layout
and native fixture source remain identical to the inspected `5f419da1`;
acceptance labels/notes/snippet text do not change those rendered compositions.
The latest Button Group optional joined-control scope is absent from these
fixtures and preserves ordinary button behavior. All unrelated main progress,
exports and registrations were retained.

The final candidate `5c7c10f7` additionally incorporates accepted Dropdown Menu
follow-up main `d6474006`. All 36 targeted Dropdown Menu, Message fixture and
styleguide-page checks passed with seed 39061; root/full analysis passed again.
Message's production action menu uses `MenuAnchor`, not `DDropdownMenu`, so the
inspected Message behavior remains unchanged. Other progress data is preserved.

Accepted local main merge: `bf86d92e26feee925739f3d7ee90f26ee05721d7`.
The final candidate also preserves accepted Menubar main `ec8bfabe`; all 25
Message/Menubar examples and styleguide-page checks passed with seed 39062,
along with root/full analysis. Only adjacent registrations/exports required
reconciliation, retaining both owners. No Message runtime behavior changed.
No push was performed.


## Direct-message presentation (2026-09-11)

Both one-to-one and group DM tiles use the complete kit composition. The tile
observes its source channel; unknown channels retain the compact layout until
classified. Ownership uses the current account on the message's site. The same
rule applies to conversation, search, deleted-message expansions and thread
consumers, without new routing or network responsibilities.

Outgoing messages use end-aligned primary bubbles and incoming messages use
start-aligned muted bubbles. One-to-one DMs omit sender headers and avatar slots,
so message content uses the space previously reserved for identity. Group DMs
keep incoming sender metadata in Message Header and avatars at the end of each
sender run. Timestamps, edited/pin/bookmark indicators and pending/failed status
use Message Footer. Consecutive DM bubbles share a timestamp on the last row,
with the kit's 8px group spacing. Group DMs retain empty avatar slots on preceding rows.
Group DM sender metadata appears on the first row. Edited state, reactions,
pin/bookmark indicators and send errors remain attached to their own messages.
No successful-delivery or read receipt is inferred.

Canonical HTML and provisional text inherit Bubble typography and foreground.
`CookedHtml.linkStyle` optionally overrides link color and underline decoration;
DM outgoing links use the bubble foreground with underlining. Its default keeps
other consumers unchanged. `ChatUploads.alignment` defaults to logical start and
allows outgoing attachment collections to align at logical end. Attachment-only
messages, including empty projected sending previews, do not render empty bubbles.
Reaction controls retain their existing permissions, async toggles and reactor
views within wrapping Message footers. Reply and thread previews compose
interactive outline bubbles with existing navigation callbacks.

Verification uses the dedicated DM widget tests plus the existing Message,
Chat tile, rich-text, preview, uploads, search, channel lifecycle, thread workspace
and local review-fixture suites. The isolated macOS fixture was inspected beside
the Message styleguide in light/dark and Plum, including 360px width, 200% text
and RTL. Reaction toggling changed 3 to 4; reply navigation reported DM 201;
secondary-click actions opened and Reply reported DM 206. Native accessibility
retained independent profile, link, reaction, attachment and status nodes. The
unchanged compact channel fixture was also inspected. The isolated app was
quit and its process absence checked before releasing the desktop lease.

Touch long-press and keyboard menu behavior were exercised by widget tests;
no physical touch device or spoken VoiceOver acceptance is claimed. Fixtures
use in-memory accounts and local fake responses, with fallback emoji artwork.


Checks completed for this adoption:

- 298 focused regression tests passed across the DM, Message, Chat, rich-text,
  preview, uploads, search, lifecycle, workspace, styleguide and fixture suites.
- After adding the empty pending-attachment edge case, all 24 DM/fixture tests
  passed again (22 DM tests and two fixture tests).
- `flutter analyze --no-pub`, touched-file formatting, and `git diff --check` passed.
- `flutter build macos --debug --no-pub -t tool/message_native_review_main.dart`
  passed on the final source. The native inspection above preceded only the
  pending-attachment empty-body guard; the inspected fixture compositions are
  unchanged by that guard.


### Consecutive DM groups (2026-09-11)

The conversation stream supplies `ChatMessageTile.endsGroup` from its existing
sender-chain projection. This gives consecutive bubbles the kit's grouped
presentation while keeping one virtualized row per message for jumps, read
tracking, actions and selection. Sender changes, chain time limits, day/unread
dividers and deleted rows retain the existing group boundaries. Standalone
tiles show their own timestamp and, in group DMs, avatar; channels retain their
compact presentation.

The production fixture includes a five-bubble outgoing run, reactions, rich
links, an incoming attachment and pending/failed messages. Regression coverage
checks 8px spacing, shared metadata moving on live arrivals, separate message
selection, prepended history, deletion, group boundaries and per-message status.

Verification for the grouping follow-up: 183 focused DM, lifecycle, stream,
thread, search, message-action and fixture tests passed. Static analysis,
touched-file formatting, `git diff --check` and the macOS fixture build passed.
The isolated macOS app launched (confirmed by its process and sampled Flutter
threads), but the desktop inspection tool repeatedly returned
`timeoutReached` when attaching by path or bundle ID, including after resetting
the tool session. That attempt did not complete a native visual inspection.
The subsequent one-to-one identity review below also inspected the grouped
layout successfully. The isolated process was stopped and the desktop lease released. Narrow,
200% text, RTL and palette regression coverage ran as widget tests.


### One-to-one DM identity (2026-09-11)

Only group DMs render `DMessageAvatar` and the incoming sender header. One-to-one
DMs omit both children, removing the avatar gutter without changing the kit.
The existing observable channel's `isGroup` flag controls this presentation;
late channel metadata and changes to group membership refresh the tile.
Reply quotes and message controls retain their existing content and behavior.
The local production fixture now switches between group and one-to-one DMs.

132 focused DM, lifecycle, message-action, search and fixture checks passed.
Coverage includes both senders in LTR/RTL, the removed gutter, late metadata,
group identity retention and one-to-one narrow/200% text/palette compositions.

Static analysis, formatting, `git diff --check` and the macOS fixture build
passed. Native inspection succeeded in a new isolated bundle: the Message
styleguide, grouped bubbles with shared identity, and one-to-one bubbles without
headers or avatar gutters were inspected. The one-to-one layout was also checked
in dark Plum at 360px, 200% text and RTL, including reactions, attachments and
pending/failed footers. A reaction changed from 3 to 4, and Reply on a middle
bubble reported DM 204. Independent link, reaction, attachment and status AX
nodes remained available. The isolated app was quit, its process absence verified,
and the desktop lease released. No physical touch device or spoken VoiceOver
review was performed.
