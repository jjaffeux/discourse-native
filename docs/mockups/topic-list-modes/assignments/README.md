# Assignments inside compact topic rows

A follow-up to the selected calendar-stamp design. The dedicated assignment
column wastes width when most topics are unassigned and truncates names when
multiple assignments or post targets are present.

The proposal places assignment metadata under the title, after the tags. It
shows only on assigned topics. Keep the avatar/group icon, full name, optional
post number, and +N disclosure. Category, Replies, and Activity retain their
columns at desktop widths. At narrow widths, category moves into the same
metadata area and assignments wrap naturally.

Open `/assignments/?placement=inline&theme=dark` on the topic-list mockup server
(port 8769), or open `index.html` directly. Switch Current/Proposed to compare
the same 11 topics, of which four are assigned. The preview has light/dark and
390px controls. Topics and +N open sample assignment details; event lines open
sample schedules. All fixture data is illustrative. No external requests,
assets, dependencies, or forum writes are used.

Reviewed in the browser at the normal desktop width and a 390px pane, in both
palettes. The narrow layout has no page or row overflow; the proposal exposes
four assignment summaries and zero empty-assignment placeholders. Verified +N
reveals all assignees and post targets, Escape closes the dialog, and focus
returns to the originating button. JavaScript syntax checked with `node --check`.

The approved proposal is implemented in Flutter. `CompactTopicListMetadataPlugin`
provides optional metadata beside tags without reserving table columns. The Assign
plugin contributes its existing avatar, a wrapping full name, post target, and
Native `DButton` for +N. +N uses the list's normal topic navigation. Unassigned
rows render no assignment content. Card metadata and calendar stamps keep their
existing behavior.

Native review covered wide light/dark Compact lists, a 390px pane, 200% text, RTL,
long group names, post targets, and seven unassigned topics among nine fixtures.
The offline review entrypoint is `tool/topic_list_modes_review_main.dart`.

Validation: 16 compact-list tests and 142 assignment, plugin, event, lifecycle,
read-removal, and control-adoption regression tests pass. Focused static analysis
with fatal infos is clean, and the macOS debug fixture builds. Tests cover tag
alignment, absence of the assignment column/placeholders, full-name wrapping,
assignment addition/removal, +N navigation, keyboard navigation, and switching
list modes without losing the viewport. The installed Flutter 3.47.4 SDK was used;
the project's 3.47.2 pin is unchanged.
