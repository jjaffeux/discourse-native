# Composer slash commands

Typing `/` at a word boundary opens a Native command menu in topic and chat
composers. An empty query displays **Type to search** next to the caret.
Continue typing to filter, use Up/Down and Return to choose, or Escape/outside
click to dismiss. An unmatched query displays an empty state; Return cannot
accidentally send chat while that menu is open. Escape and **Close menu** remove
an unused `/`, while preserving `/query` when text has been typed. Space closes
the menu and preserves the slash, query and space as literal draft text.
URLs, paths, selections, IME composition and Markdown code do not open commands.

Topic composers also show an **Add block** (+) button before each block handle.
It opens these same commands on the hovered or selected empty line. For a
populated block, it inserts a new paragraph after the complete block and focuses
its slash query, preserving surrounding content. This insertion is one undoable
edit. In Arrange mode, + returns to the editor and opens the commands there.
The controls respect text scaling, RTL and the existing editing/composition
guards; insertion after an unclosed code fence is disabled.

The shared editor supplies Bold, Italic, Inline code, Link and Heading 1–4. Headings show their Markdown markers
and can be found with `/heading` or `/h1`–`/h4`; choosing one formats the
current line, preserving its text and replacing any existing heading level. Topic insertion
includes Table, Details, enabled uploads and emoji, plus applicable plugin
contributions (GIFs, polls, dates, events and diagrams). Chat supplies its upload,
emoji and GIF handlers and applicable plugin contributions. Availability comes
from the current composer and site settings. `reaction` is an alias for Emoji;
this inserts an emoji in the draft and does not react to another message.
Chat GIF selection retains the existing picker behavior of sending a separate
GIF message.

The adapter refreshes plugin callbacks after removing the slash query, so
callbacks that capture document positions receive current offsets. Menu
appearance, filtering, highlighting, scrolling and keyboard navigation belong
to the Native components. The only component extension is external-editor key
routing on `DCommandController`.

## Verification

- Focused command, slash menu, autocomplete and Command styleguide tests pass.
- Production Chat integration covers actions, settings and preventing send on
  selection or empty results. A plugin callback regression checks refreshed
  document offsets.
- Native macOS topic composer inspected in light and dark with an isolated,
  offline production fixture: inline hint, filtered menu, retained typing focus,
  Return and arrow selection. Native chat was inspected in dark/wide and
  light/narrow layouts, including opening and cancelling date/time, menu
  collision above the editor and Escape dismissal. The repeatable
  offline chat fixture is `tool/composer_slash_review_main.dart`. 200% layout
  is covered by widget tests.
- Five existing failures reproduced on unchanged main `fbcd8fb38`: four chat
  selection-toolbar overflow cases and keyboard-selected table cell focus.
  The installed Flutter is 3.47.4; the repository pin remains 3.47.2.

The block insertion fixture is `tool/composer_block_add_review_main.dart`.
Its production editor was inspected on macOS in dark/wide and light/360px
layouts, including insertion below populated blocks, keyboard heading selection,
Escape and reopening on the same empty line. Widget coverage additionally
checks undo, whitespace-only lines, hover targeting, CRLF, images, code blocks,
adjacent headings, RTL, 200% text, composition guards and 320px iOS-themed
Arrange mode. These themed widget checks are not device testing.
