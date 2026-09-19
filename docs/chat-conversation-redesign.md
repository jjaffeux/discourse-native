# Chat conversation redesign

Reference inspected on September 19, 2026: the running mockup at
http://localhost:5183/, Chat → general and the flourpower DM, plus the supplied
General and WhatsApp screenshots. The mockup's message data varies; the design
and interactions, rather than its sample text, define the target.

## Required changes

1. Unify public channel, individual DM, group DM and thread message presentation.
   Incoming messages align to the start; the current user's messages align to
   the end. Resolve ownership against the message's site account.
2. Put content in rounded bubbles: neutral raised incoming surfaces and muted
   accent outgoing surfaces with readable palette-derived text. Keep rich HTML,
   links, selection, emoji, uploads and delivery state functional.
3. Show a 28px avatar and muted sender/time line at the first message in each
   sender group, on the matching side. Reserve the avatar column on subsequent
   messages. Retain status, staff/bot identity and avatar flair.
4. Use compact gaps inside a group and larger gaps between groups. Bubble width
   follows content until the responsive maximum, approximately 76% of the row.
5. Put the More chevron in the top trailing corner of the bubble. Keep its slot
   stable so hover/focus does not move text or change message height. Use the
   existing Native dropdown and buttons, accessible by pointer, keyboard and
   touch. Keep only supported, permission-aware actions: Reply, React, Bookmark,
   Pin/Unpin, Copy link/text, Edit, Flag, Restore, Rebuild HTML, Delete and Select.
6. Put a separate React button beside the bubble, toward the middle of the
   conversation: right of incoming messages and left of outgoing messages.
   Existing reaction pills stay below the matching bubble, with their current
   toggle and reactor-list behavior. Prevent duplicate reaction launchers.
7. Replace the detached reply indicator with an inset quote above the body:
   subtly recessed surface, accent rule on the leading edge, author attribution
   and a two-line excerpt. Clicking it jumps to the original message. Keep it
   visible on every reply, including consecutive replies from one author.
8. Replace the large thread summary card with a compact row below its message:
   chevron, overlapping participant avatars, truncated latest-reply excerpt and
   emphasized reply count. Preserve unread/accessibility context. Activating
   the row continues to open the existing separate thread panel.
9. Always cap the transcript at 825 logical pixels and center it in its current
   panel, independently of the forum content-width setting and text scale.
   Apply the lane consistently to messages, dates, unread/deleted/loading rows
   and jump controls; preserve the full-width scroll hit area and virtualization.
10. Update Native examples and regression coverage for both channel kinds,
    incoming/outgoing groups, quote navigation, menu permissions, React,
    thread navigation, narrow/RTL/scaled layouts and light/dark palettes.

## Native kit additions

The existing Message and Bubble APIs cover basic alignment and interaction but
lack an inset quote, a top-corner action slot, the reference accent treatment,
and optional end-aligned sender metadata. Project AGENTS.md requires user
direction before adding these options. The user explicitly authorized extending
the kit before these component APIs were changed.

Implemented in the shared kit:

- `DBubbleVariant.neutral` and `accent` provide the chat surfaces without changing
  the original variants.
- `DBubbleContent.trailingAction` and `quote` reserve independent controls and
  source context. At narrow widths or large text scales, the corner action gets
  its own line so rich content has room to wrap.
- `DBubbleQuote` provides the inset accent rule and keyboard-accessible link.
- `DMessage.footer` keeps reactions and thread previews from moving the avatar
  below the bubble; `DMessageHeader.followMessageAlignment` aligns metadata.

The chat adapter owns identity, permissions, navigation, cooking and mutation
callbacks. It uses one renderer and one permission-aware Native dropdown for
all channel kinds. The popup owner sits outside the message's semantic grouping,
while its trigger stays in the corner. This preserves the menu's native
accessibility nodes. Menus also open by right-click, Shift+F10, the context-menu
key and touch long press; long press on selectable text retains selection.

Code-block headers now omit their decorative icon when there is insufficient
space beside the existing controls. The language remains available to assistive
technology, and copy/full-screen actions stay accessible in narrow bubbles.

## Verification

Native macOS review used an isolated offline build of the actual
`ChatMessageTile` through `tool/message_native_review_main.dart`, plus the new
Message styleguide example. Reviewed public channels, group and individual DMs,
incoming/outgoing messages, grouping, attachments, failure state, quotes,
light/dark palettes, and 360px/200%/RTL layouts. Verified the menu through its
macOS accessibility nodes, Reply activation, quote jump, thread-preview callback,
and the standalone reaction picker. The offline fixture has no emoji catalogue;
actual reaction selection and persistence are covered by integration tests.
No live server data was changed during native review.

Regression coverage includes the Bubble and Message component suites and
examples, the native review fixture, both chat tile suites, channel lifecycle,
reading lanes, split thread workspace, reactors, retained animations, the chat
shell, code blocks, and scrolling performance. The scroll tests exercise rich
HTML, images, oneboxes, nested quotes, code blocks, edits, resize, virtualization,
and both channel kinds. Scroll-only passes retained zero message-widget rebuilds.

Validation includes `dart analyze` and a debug macOS build. Touch behavior is
covered by Flutter widget tests; no physical iOS or Android device was used.

The integration candidate based on main `997ea3731` passed all 411 selected
component, example and integration tests. The final typography cleanup passed
113 targeted tests, including the typography adoption guard; the four control
adoption checks passed separately. Root static analysis is clean. The macOS
debug build succeeds with existing dependency warnings.

Final reconciliation includes main `03f2913b2` and its tooltip updates. All 154
affected tooltip, message and typography checks passed, followed by clean root
analysis, a successful macOS build, and a final native check of light/dark
surfaces, quote navigation, the accessible message menu and Reply activation.
The inspected source candidate was `594d4b71`; the final documentation commit
does not change that application source.

The merge candidate was subsequently based on main `45f977281` to retain the
concurrent PM inbox archive change. Chat, Bubble, Message, code-block and tooltip
source is identical to the native-reviewed candidate. All 93 channel lifecycle,
thread workspace, archive-controller and model-boundary checks passed on this
combined state, and root analysis remained clean.
