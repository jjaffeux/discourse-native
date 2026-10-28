# Topic head parity

Reference: `discourse-native-mockups` at `847614e` (branch
`test-mobile-layout`), look A. The rules come from `f493c51` and `83cee2f`:
`toolChip`, `toolGroup`, `headPathThatFits`, `headTagsThatFit`,
`TopicActionsButton` and `TopicView`'s head in `App.tsx`, and the `--tool-*`
tokens, `.topic-head-compact` and the card rules under
`[data-variant="a"][data-touch]` in `app.css`.
`test/topic_head_mockup_parity_test.dart` pins every value below.

## One line

The category path, the tags and the tools share one line. The tools keep
their place at its end. The path and tags take what the tools leave.
`fitTopicHead` in `topic_header_tags.dart` is the reference's arithmetic.
Each chip is counted with the 8px gap after it.

| Rule | Value |
| --- | --- |
| Path | Whole while the path and a `+N` count of every tag fit. Otherwise only the topic's own category shows. That category may shrink, its name ending in an ellipsis. |
| Tags | As many as fit before a `+k` count of the rest. There is no cap on their number or width. |
| Count | `+k` with no fill, in `mutedForeground`. Pressing it shows every tag inline. The run then wraps, and the tools stay at the end of its last line. The path stays as it was fitted. The opened state is kept for the topic in `PageStorage`. |
| Tools at large text | When the tools would leave less than three control heights of the line, they go below the path and tags, at the line's end. The reference has no rule for this case. |

The native head keeps the actions that the reference does not draw. Tags are
edited by a long press on a tag, by a tap on a phone, or with the pencil that
ends the opened run on a desktop. An editable topic without tags shows Add
tag. A topic that could take a subcategory offers one after its own category,
and that offer goes first when the line is short.

## Pill chips

`DButtonVariant.tool` is the reference's `toolChip`. `DButtonGroup.tool` is
its `toolGroup`.

| Part | Value |
| --- | --- |
| Chip | Pill radius, a fill of `foreground` at 5%, a transparent 1px edge, 12.5px regular text, 30 tall (`DControlSize.filter`), 9px padding inside the edge. Hover is `foreground` at 8%. |
| Joined chips | One 5% pill behind both. Each child after the first has a 1px rule of `foreground` at 12% on its leading edge, inset 1px at the top and bottom, as the reference's transparent border insets it. |
| Tag | The tool chip, with `#` in `mutedForeground` and a 6px gap before the name. |
| Category | A pill with a transparent edge. The topic's own category has its category fill. A parent category has no fill and `mutedForeground` text. |

A phone scales all text by its 17/14 baseline (`AppTextScaleRegion`), so the
chips are 34 tall there. They are 30 tall at the unscaled baseline, as every
other control is.

## The phone's actions sheet

On a phone the head has one ⋯ (`TopicActionsButton`) in place of the
assignment button, the ⋯ and the wrench. Its sheet holds a group each,
separated by rules:

1. What the topic's plugins offer: `TopicPropertySection.actions`. Assign
   offers Assign topic, or Reassign topic and Unassign *name* from topic. A
   section with no actions keeps its own button in the head. Assign keeps its
   button while a post is assigned, because those assignments are read in its
   details.
2. Share topic, Flag topic and Mark unread.
3. Select posts.
4. Close, Pin, Archive and Unlist.
5. Delete or Recover.

Each command shows only when the topic allows it. A desktop keeps its ⋯ and
its wrench. The wrench uses groups 3 to 5, in the same order. The sheet's
geometry and elevation belong to the shared sheet work.

## The page card and the condensed head

| Part | Value |
| --- | --- |
| Page card (`ForumMobileSurface`) and topic sheet (`DSheetVariant.page`) | Top corners 31 (`DMobileDockGeometry.capsuleRadius`), as round as the bar. Bottom corners stay 22. |
| Condensed head | A band of `wellFill` with 31px corners throughout its motion. Both header states keep the band's box so the morph keeps its state. |
| Card under the band | Its top corners stay at 31px, including while the band rests at the top. The shared sheet clips the page and head to this outline. |
| Previous page | The live page or captured history frame has the same rounded outline while it recedes behind the sheet. |
| Grabber | Drawn under the band while the band still covers its foot, 12 below the sheet's top. |
| Card's depth | None while the head is drawn in, wherever the band is: the band runs on up into the screen's head, so the card has no rim, catch of light or shadow along its top. The panel depth returns with the full head. |

The outer `ForumMobileSurface` stays square and transparent while a page
sheet covers it. The sheet owns the visible corners. Plain preset backgrounds
use `wellFill` on phones too, so the head's upper curves blend into the canvas
while attached to the top. Pulling the sheet reveals the same rounded shape.

`DPageSurface.scrollable(compactHeaderBand: true)` reports its compact state
and how much of it is shown to the enclosing page sheet through
`DSheetPageBand`. These reports control the grabber and depth, leaving the
corners rounded. The sheet applies each report outside the frame's build. A
head that has withdrawn is not heard from again, even if one of its reports
was still waiting for the frame.

## Validation

`test/topic_head_mockup_parity_test.dart` covers the arithmetic as pure cases.
At 390 and 1000 wide on iOS and Android it covers the line, the path
collapsing, the opened run, the chip colours, corners, heights and split, the
sheet's groups and order, Assign opening its drawer from the sheet, the card
corners, and the band hiding the grabber while retaining its rounded outline.
A full-shell pixel check on a distinct canvas verifies both top curves during
a pull. `test/ui/d_sheet_page_motion_test.dart` checks rounded live and captured
backgrounds during entrance and dismissal. `test/forum_mobile_surface_test.dart`
checks the plain preset canvas fill in light and dark.
`test/support/topic_head_review_main.dart` runs the production head
on a simulator with a fixture. It opens the topic, draws the head in, opens
the sheet and opens every tag, printing `TOPIC_HEAD_REVIEW` before each stage.
