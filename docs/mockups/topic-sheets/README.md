# Topic sheet navigation study

Open `docs/topic-sheet-layouts.html` in a browser to compare three interactive
HTML/CSS explorations. Design C has been selected and implemented in the desktop
application. A later revision moves left/bottom/right composer docking to the
app level: the workspace shrinks and the sheet fits inside it. These HTML files
preserve the original design study with internal sheet docking. See
`docs/component-library/sheet.md` for the Native adaptation and verification.

- **A — Right-anchored:** a sheet covers the right part of the topic list.
  The default composer sits at its bottom. This leaves the most list context
  visible while writing.
- **B — Centered:** one floating surface owns the reader and composer, with
  margins around it and a stronger backdrop. This puts more emphasis on the
  current conversation.
- **C — Expands for reply:** a narrower sheet opens for reading and grows
  toward the left when replying. Minimize or close the composer to restore
  the reading width. This gives a side composer more room without making
  every reading session occupy the same space.

In all three, opening a topic overlays the existing list without resizing it.
Close or Escape returns to that list. Reply, left/bottom/right docking,
minimize/restore, previous/next topic, and draft recovery are interactive.
The preferred side dock falls back to bottom below the existing 681px
reader/composer threshold. Drafts are local in-memory samples and survive
closing the sheet and switching topics, but not reloading the page.

## Decisions to refine

1. Whether the sheet attaches to an edge, floats, or expands for composing.
2. How much of the list should remain visible, and whether the visible
   background should be interactive. This study dismisses on outside click;
   visible navigation is inactive while the sheet is open.
3. Whether closing with a draft should keep it quietly, minimize the entire
   conversation, or ask before closing. This study keeps the draft quietly.
4. Whether opening a link to another topic should replace this sheet or add
   sheet-local history. Previous/next here moves through the sample list.

## Native UI boundary

The mockups approximate existing Native controls: regular 28px buttons with
8px corners, contextual action tints, outline tags, avatars, and compact menus.
Production work must use `package:discourse_native/discourse_ui.dart`.
Existing `DSheet` / `DDialog` and `DResizablePanelGroup` are the starting points,
but these drawings do not establish that every proposed presentation is
supported. Centered geometry and animated expansion need an API check before
implementation; any missing UI kit behavior requires the user's direction
under `AGENTS.md`. The user approved the inset and animated-width extension for
design C; it is implemented by Native `DSheet`, with a styleguide example.

Formatting icons are illustrative. Typing, reply preview, and likes only affect
the mockup. The gallery supports light and dark appearance and narrow layouts.
