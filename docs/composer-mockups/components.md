# Quiet dock — supported composer features

The single HTML/CSS mockup covers **new topics, replies, whispers and post
edits** using the application's existing capabilities. No new generic Native
component or authoring feature is required.

Open [Quiet dock](index.html) or [the direct entry point](quiet-dock.html).
Both use the same `mockups.css` and `mockups.js`. They work from disk or the
local preview server, without dependencies or account access.

## Composition

| Mode | Controls and behavior |
| --- | --- |
| New topic | Title, category/tags, existing live editor, formatting, image upload, emoji, eligible plugin actions, Create topic |
| Reply | Reply/Whisper header menu when permitted, expandable reply context, same editor/tools, Reply |
| Whisper | Eye-slash icon and Whisper heading, same reply context/editor/tools, Whisper submit action |
| Reply to a whisper | Whisper is mandatory; no menu to turn it into a public reply |
| Edit | Post identifier in the header; a muted context surface with a small “Topic” label and emphasized topic title above the editor; same editor/tools, Save; close offers Cancel or Discard changes |

The design exposes the existing **bold, italic, inline code and link** actions
in a compact toolbar. Upload images, emoji and the existing plugin insert menu
remain in the footer. It does not introduce heading/list/quote formatting
buttons; source authoring and the existing quote pipeline continue to belong to
the native editor.

There is one live writing surface. The actual app uses `ComposerEditor` and its
hybrid source/projection machinery. No Write/Preview mode or renderer is needed.

## Whisper behavior

The mockup follows `ComposerHeader`, `ComposerController.setWhisper` and reply
creation in `ShellController`:

- Show the Reply/Whisper menu only for an expanded reply when the current user
  has `whisperer == true` and the target is not already a whisper. The app also
  disables mode changes while the editor is busy or loading the original body.
- A user without whisper permission sees an ordinary Reply heading and no
  whisper action.
- A reply to a whisper starts as a whisper and cannot be switched to public.
  The existing controller forces the flag to stay true for that target.
- New topics and edits do not expose a visibility conversion. An edit preserves
  the original post type; this study's edit fixture is an ordinary public post.
- Keep **Allowed groups only** as the Whisper option's description in the header menu.
  Do not assume that every whisper is limited to staff.
- Keep the eye-slash icon and Whisper label when minimized. Preserve the flag
  with the existing reply draft across resizing, docking, minimizing and draft
  restoration. Public/whisper selection keeps the current reply text.
- The existing backend permission and submit-admission checks remain the
  authority. The mockup's sample-user selector is not an application control.

The review controls below the window expose **User can whisper**, **User cannot
whisper**, and **Reply to a whisper**. Changing that scenario loads a fresh sample
reply, so one sample user's whisper text does not become another user's public
draft. The four flow buttons above the window are also mockup-only controls.

## Existing components and owners

Application UI imports `package:discourse_native/discourse_ui.dart`. Existing
application icon assets supply `DIcons.farEyeSlash`, reply, placement and tool
icons; they do not require a new component.

| Area | Existing Native components | Integration with existing behavior |
| --- | --- | --- |
| Dock and scrolling | `DResizablePanelGroup`, `DResizablePanel`, `DResizableHandle`, `DScrollArea` | Keep `ComposerPresentationController` and the keyed `ComposerPresentationHost` surfaces |
| Placement popup | `DPopover`, `DToggleGroup`, `DButton`, `DTooltip` | Left, bottom and right only; save/close and minimize remain header actions |
| Reply/Whisper menu | `DDropdownMenu`, `DButton`, `DTokens` | Replace the current raw menu with Native; preserve its permission and target gates, selected state, label and icon |
| Title | `DInput`, `DField`, `DFieldLabel`, `DFieldError` | Existing title controller, focus, site validation and submission rules |
| Category/tags | `DSelect`, `DCombobox`, `DBadge`, `DButton` | Existing category/tag pickers, lookup, restrictions and required-tag handling |
| Reply context | `DAvatar`, `DItem`, `DItemContent`, `DItemTitle`, `DItemDescription` | Recompose `ComposerReplyContext`, retaining cached excerpt availability and bounded scrolling |
| Edit topic context | `DItem`, `DItemContent`, `DItemTitle`, `DItemDescription` | Use the existing muted variant as a passive surface, with a small Topic label and stronger title; both come from existing context |
| Formatting and link | `DButtonGroup`, `DButton`, `DDialog`, `DInput` | Existing mark commands and `showComposerLinkDialog`; selection and text ownership stay in the hybrid editor |
| Image uploads | `DAttachment`, `DAttachmentMedia`, `DAttachmentContent`, `DAttachmentAction` | Existing image picker and `ComposerUploadQueue`; preserve upload, retry, cancel and remove behavior |
| Emoji | `DButton` plus the existing app emoji picker | Respect `siteConfig.emojiEnabled`; preserve the current autocomplete and picker logic |
| Plugin insert | `DDropdownMenu`, `DButton` plus existing plugin editors | Use actual registry contributions and their current site/account policies |
| Draft state | `DSpinner`, `DToast` and semantic status text | Derive status from existing `DraftStatus`; drafts are supported for topics and replies, including whispers |
| Edit close | `DAlertDialog`, `DButton` | Existing Cancel / Discard changes flow; no saved edit draft or keep-draft-and-close action |

`DAttachment` and its upload lifecycle are already used by the actual composer.
The sample attachment is an **image**, matching the existing `pickComposerImages`
filter. The mockup does not propose arbitrary document/PDF uploads.

The sample site explicitly has image uploads, emoji, poll creation and local
dates enabled. The insert menu demonstrates only **Add poll** and **Insert
date/time**, which already exist. Production must use the registry's actual
contributions, not hardcode this fixture list. Poll creation remains gated by
the current account's `canCreatePoll`, and local dates by the existing settings.
Plugin-owned header and footer contributions retain their current slots.

## Work to achieve the layout

1. Recompose the header and fields with Native components. Preserve the existing
   reply destination, whisper eligibility and docking menu behavior.
2. Expose the existing four formatting commands in the compact top toolbar.
   Keep image upload, emoji and eligible plugin actions in the footer.
3. Keep the existing live editor mounted. Preserve canonical Markdown, plugin
   atoms, selection, IME, undo history and quote behavior.
4. Recompose the reply-context disclosure and upload queue using their existing
   data and interaction owners.
5. Present existing draft state for new topics and replies only. Keep existing
   close/discard, pending-upload, loading and submission guards.

These are UI composition and migration tasks. The layout needs **no new
composer capability**, API field, generic component or component extension.

## Docking and mobile

- Keep the existing desktop default: right dock, 420 logical pixels; saved user
  placement and size preferences continue to take precedence.
- Retain left/bottom/right placement, a single shared divider, a 360px side
  composer minimum and a 320px reader minimum. A narrow window temporarily uses
  the bottom dock and restores the preferred side when space returns.
- Retain the current default bottom heights: 280px for replies and 380px for
  new topics. The HTML allows resizing to explore the proposed arrangement.
- Mobile uses bottom docking and hides placement controls. Bounded content can
  scroll while editor actions remain above the keyboard.
- Minimize/restore retains an in-progress edit in the existing editor session;
  it does not save that edit as a reusable draft.
- The rail and sidebar remain outside the docked content area at appropriate
  viewport widths. No floating or separate composer window is proposed.

## Supported-state boundaries

The mockup omits edit reasons, revision comparison, preview, a word counter,
extra formatting commands and saved edit drafts. Although the data-layer
`updatePost` API accepts an edit reason, the current composer does not expose or
persist it; it is therefore outside this design.

Draft-save failure uses the current local-save error text. It keeps the draft
open when save-and-close fails. Subsequent editing reschedules the existing
save path; the mockup does not add a manual draft-retry button. Real submission
still depends on the current admission controller, including site validation,
permissions, busy state and pending uploads.

Taxonomy-only and topic-metadata edits keep their existing modes and omit fields
that do not apply. Private messages and plugin-owned authoring flows are not
new features of this topic-composer mockup.

## Source evidence

- [Native conventions](../component-library/conventions.md),
  [catalogue](../component-library/catalogue.json),
  [styleguide](../component-library/styleguide-design.md), and
  [public UI barrel](../../lib/discourse_ui.dart).
- [Docking](../composer-docking.md),
  [hybrid editor ownership](../composer-hybrid.md), and
  [current composer panel, toolbar and upload queue](../../lib/src/shell/composer_panel.dart).
- [Whisper header and eligibility](../../lib/src/shell/composer_header.dart),
  [whisper flag and draft controller](../../lib/src/shell/composer_controller.dart),
  [reply/edit creation](../../lib/src/shell/shell_controller.dart), and
  [draft model](../../lib/src/models/composer_draft.dart).
- [Save/close and discard](../../lib/src/shell/composer_discard.dart),
  [image picker](../../lib/src/shell/composer_upload_picker.dart),
  [reply context](../../lib/src/shell/composer_reply_context.dart), and
  [link editor](../../lib/src/shell/composer_link.dart).
- [Existing poll action](../../lib/src/plugins/poll/poll_plugin.dart) and
  [existing local-date action](../../lib/src/plugins/local_dates/local_dates_plugin.dart).

## Prototype and verification

All posts, accounts and capabilities in the HTML are fixtures. Typing, permissions,
submissions, attachments and save feedback are local simulations. Nothing is
posted or uploaded. Reloading resets sample drafts; the query string records
only the chosen flow, scenario, viewport and dock.

The textarea is a lightweight stand-in for the existing native live editor, not
an implementation of its hybrid atoms or rich rendering. The small link/emoji
popups and sample plugin insertion demonstrate existing entry points; production
uses the existing full editors. The keyboard switch simulates occupied space,
not a native keyboard or device test.

Prototype validation covers JavaScript syntax, local asset/document links and
the whisper permission/state matrix. The Flutter implementation and its widget
and macOS verification are recorded in [the native review](native-review.md).
