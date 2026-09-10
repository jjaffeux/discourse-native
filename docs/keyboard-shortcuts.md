# Keyboard navigation

The topic list and reader have independent keyboard selections. `J/K` move
through posts when a topic is open and through the list when no topic is open.
`Shift+J/K` always address the visible topic list.

| Shortcut | Behavior |
| --- | --- |
| `G` then `J` / `G` then `K` | Open the next / previous topic from the source list, including while reading in a narrow layout. |
| `Shift+J` / `Shift+K` | Highlight the next / previous topic in the visible list. Leave the open reader unchanged. |
| `O` / `Enter` | Open the highlighted topic at its unread position. Both keys run the same command with the same focus rules. |
| `J` / `K` | Select and reveal the next / previous post in the open topic. When no topic is open, highlight the next / previous topic in the visible list. |
| `R` | Reply to the selected post. |
| `Shift+R` | Reply to the topic. |
| `C` | Create a topic. |
| `U` | Go back through the active tab's content history. |
| `Cmd+[` / `Cmd+]` (macOS), `Alt+Left` / `Alt+Right` (Windows/Linux) | Go back / forward through the active tab's content history, like the mouse side buttons. |
| `Cmd+R` (macOS), `F5` (Windows/Linux) | Refresh the current tab, keeping its history and composer. |
| `Cmd/Ctrl+Enter` | Submit the composer. |
| `Escape` | Close the composer through its existing draft-preserving flow, or dismiss a dialog. |
| `Cmd/Ctrl+F` | Search using the current forum, topic, or plugin context. |
| `?` | Show the shortcut reference. |

`Cmd` applies on macOS; other platforms use `Ctrl`. Cursor movement accepts
key repeats; opening, replying, back, and help do not.

## Selection and focus

A colored outline marks the topic-list cursor separately from the open
topic's background. Moving the cursor never loads a topic or marks it read.
`O` and `Enter` open that row with either reading pane focused. Opening another
topic in split view replaces the reader while keeping the source list in
history, so `U` returns to the list without stepping through every opened topic.

The list cursor is remembered by topic ID, scoped to the forum, account, tab,
and feed. Returning to the list restores it. Refreshes retain the selected
ID; if it disappears, movement resumes from its former position. At the last
loaded row, movement waits for the next page, including an already-running
prefetch. A context or focus change cancels the pending cursor move.

Posts have their own selection outline. `R` uses that post as the reply target
and opens the normal composer with the existing permission checks. Mouse or
touch scrolling clears the post selection so an offscreen post does not
remain an invisible reply target. `Shift+R` remains available for a topic reply.

The adjacent-topic arrows sit in a fixed bar below the source list. They and
`G` then `J/K` open topics at the unread position without adding reader history
entries. The list scrolls to reveal the opened topic and moves its cursor to that
row. When the open topic is absent from the source list, either direction
opens the first listed topic. Both directions stay disabled if the list is empty.
Next loads another page when needed. Sequences expire after one second
and reset on an unrelated key, focus change, pointer press, or route change.
Pending keyboard navigation is cancelled if its tab, topic, account, or focus
changes.

In narrow layouts, the list is hidden while reading. Its selection shortcuts
are idle until `U` returns to the list; `G` then `J/K` still opens adjacent topics
and `J/K` continue to address posts. Editors, form
controls, menus, and dialogs keep their local keys. Focused buttons keep
normal activation instead of opening an unrelated highlighted topic.

## Implementation

- `lib/src/app_shortcuts.dart` defines reading commands, labels, and bindings.
- `lib/src/shell/keyboard_navigation.dart` dispatches to visible content panes
  through Flutter's early focus handlers. Explicit pane ownership makes the
  target independent of keyboard focus. It also supplies the shared focus
  guard and selection outline.
- `TopicListView` stores its cursor in page storage and uses `ListController`
  to reveal virtualized rows. Selection is distinct from both the open topic
  and the persisted scroll position. The cursor itself is not saved to disk.
- `TopicView` uses the existing stream-index navigation and composer paths
  for post movement and replies.
- `lib/src/shell/keyboard_shortcuts_help.dart` builds the reading reference
  from the command definitions and includes existing composer/search keys.

Normal Tab traversal and the existing arrow, Home/End, forum-switching, and
tab-switching shortcuts remain available.

## Comparison with core web

Reviewed core checkout `2e9dc47bd88` on 2026-09-07. Core's definitions are in
`frontend/discourse/app/services/keyboard-shortcuts.js`, its reference is in
`frontend/discourse/app/components/modal/keyboard-shortcuts-help.gjs`, and
adjacent-topic loading lives in `frontend/discourse/app/lib/topic-list-tracker.js`.

Core uses `J/K` for the current topic list or post stream. Native uses `J/K`
for posts while a topic is open and for the topic list otherwise. `Shift+J/K`
always address the visible topic list; core uses that shifted pair for
sections. This resolves the ambiguity of showing both panes at once. Native
retains the familiar open, back, reply, and help keys.

Confirmed core’s `g j` / `g k` adjacent-topic bindings in the local core checkout
on 2026-09-10 and implemented them in Native.

Further web bindings can be added separately: other `g …` destination sequences,
quote/like/bookmark/edit, jump-to-post/unread, incoming-topic
refresh, and moderation. These are not advertised by the native reference.
Native keeps its existing `Cmd/Ctrl+F` search and modified-arrow tab switching.

## Verification

`test/keyboard_navigation_test.dart` exercises the complete select → open →
read → reply → submit → back → next-topic workflow using both opening keys
at split and narrow widths. It also covers independent pane selections,
virtualization, pagination, refresh/removal, per-tab cursors, pending requests,
editor/dialog focus, help, and clearing the reply target after manual scrolling.
