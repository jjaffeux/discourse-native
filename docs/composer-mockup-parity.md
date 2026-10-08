# Composer parity

Reference: the final native mockup snapshot `54ba01c`, including the composer
parts of `41d4082`, `03d7a28`, `8015f13`, and `c03c2c4`.

The existing continuous Native editor remains the source of truth. Its block
handles, structural reordering, undo/redo, logical navigation, paste, and slash
menu already provide the authoring behavior. The menu uses the app's actual
upload, emoji, GIF, date, poll, event, and other installed plugin capabilities;
availability follows the forum and account. Category hierarchy and multiple
tags use the live selectors, and a new topic retains its originating list's
category and tag defaults. Taxonomy now sits with the creation actions at the
foot of a new-topic composer.

The title shares the body's writing column and uses the topic heading style.
Enter from the title reaches the start of the body. Unmodified Backspace or Up
at the collapsed body-start caret returns to the title; selected text,
composition, embedded-editor commands, and normal body editing remain owned by
the mature editor.

Open topic and reply drafts have Native document tabs and an All drafts picker.
Switching a tab retains its editor, selection, history, and persistence session.
The editors share one retained stack, keeping their rendering and accessibility
ancestry stable during tab changes. Closing the selected tab reveals the next
neighbor, including a minimized draft; closing a background forum's draft leaves
the current forum's visibility alone. Resuming a retained minimized draft reveals
and focuses that same editor. All drafts reveals its reader page from full-screen
composition. Authorized reply visibility controls remain available beside the
tabs. Each session remains account scoped. Reopening a retained server draft
selects its existing editor instead of creating a second owner for its
persistence key.
Private-message replacement retains the existing protection for Discourse's
shared private-message draft key. Closing a tab saves and puts it away, and
closing the last tab closes the composer. Closing a written composer offers
Save draft first, Discard, and Cancel. Enter initially saves; Escape or outside
press keeps the editor. Existing checks for submission, uploads, restore,
failed storage, retries, and changed discard revisions remain in force.

The user approved the Native kit extension required by the position control.
`DPositionControl` unfolds leftward in place, uses the new opt-in sliding
indicator in `DToggleGroup`, and folds after selection. Outside press and Escape
fold it; reduced motion removes transitions. A narrow desktop offers bottom and
full screen. The phone retains its full-screen sheet and has a distinct
minimize action. The position and restore artwork use the desktop group's
approved shared Native layout glyph, with the window's live panel visibility.
The minimized composer is a compact card at the foot of the window, with its
destination/title, word count, and restore artwork. It retains
the editor and returns to the phone sheet or desktop's remembered placement.

Focused checks cover these behaviors, docking, close retry, draft safety,
background persistence, structural movement, slash commands, taxonomy and
submission, the existing toggle group, and localization. Real-font widget
captures were inspected at 1200px desktop and 390px phone widths, in light and
dark, with ordinary and 200% text. These are rendered fixtures, without a
physical-device deployment.
Localization generation succeeds. After search integration, the global UI-text
audit reports the existing `order:` search badge label on unchanged current
main as well; it reports no composer UI text.

The existing shell-based draft integration fixture has 86 failures on the
pre-composer main baseline because it targets older reply affordances. The
identical failures were reproduced before integration. Two other older assertions (a 16px footer inset
where the implementation uses 14px, and stripping a leading space after link
removal) are recorded separately against unchanged main. New composer
regressions and the directly affected docking, menu, and persistence checks
supply independent coverage of the changed behavior.
