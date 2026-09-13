# Global search

The navbar search opens a large popover whose input replaces the navbar field
at the same coordinates. The editor retains its controller, focus and selection.
Escape closes the innermost menu first, then restores the navbar search. Clicking
outside closes search without moving focus back. Touch phone layouts use the
available screen with a Back button. Cmd/Ctrl+F opens unfiltered global search
with All selected. Cmd/Ctrl+Shift+F opens contextual search. Both shortcuts
also switch an already open search while keeping its query, editor and caret.

Contextual search on a topic selects Topics & posts and adds that topic's filter.
Opening it from a topic list selects Topics & posts and clears the previous
topic filter. Clicking the navbar applies these defaults once per opening;
users can remove the topic filter or switch scopes while search is open.
Cmd/Ctrl+Shift+F reapplies the current context. The separate topic-list search
field has been removed, and `/` opens contextual search from topic pages and
topic lists when an editor or other form control does not own the keyboard.
Saved topic-list routes drop the old field's search parameter on restoration,
so a removed control cannot leave the list invisibly filtered. Other filters
and tab-history anchors are retained.

Contextual search from a chat channel or thread selects Chat and adds the parent
channel's filter. An expanded chat drawer supplies this context ahead of the
forum page behind it. Channel filters use stable IDs, including direct messages,
and display the channel's title. Closing the drawer or returning to a forum page
clears that opening context the next time search opens. The header search icons
and inline channel search bar, result counter, and previous/next controls are
removed. Cmd/Ctrl+F searches across the forum even when Chat is open.

Chat results retain their channel, thread, and message targets and use the
existing in-app navigation: an open drawer receives the result; otherwise Chat
uses the saved display preference, falling back to full page on compact layouts.
Escape dismisses search before the drawer, including from filter controls.

On a narrow desktop, the results surface grows beyond the navbar field to use
the available width. The input, clear action and caret keep their original
coordinates inside that larger header. Short windows reduce the results area's
height instead of moving the input upward.

The approved interactive reference is [the mockup](mockups/global-search.html).
Recent searches are full-width text rows; Clear history uses the same row inset.
There are no leading clock icons. A fixed footer displays the global and
contextual search shortcuts using Native keycaps, wrapping on narrow layouts.

## Search capabilities

All combines accessible forum, user and group search with chat when enabled.
Topics & posts uses Discourse full search; Users and Groups use their directory
APIs, with aggregate-search fallbacks when a directory is disabled. Chat uses
its own search API and requires the installed feature, authentication and site
search permission. Server responses remain authoritative for accessible results.

The filter picker exposes each scope's supported conditions. Conditions combine
with AND; repeatable conditions support date/count bounds. Chips expose the
filter, operator, value and removal action. Scoped filters and ordering survive
switching between scopes. Closing search clears filters from every scope while
retaining the query. Reopening applies the current topic or chat context again.
Closing a nested filter or display menu leaves search filters in place.
Plugin and permission-dependent conditions only appear
when the site exposes them. Sorting and display properties use their own menu.

Category lookups use category IDs, including when subcategories share a slug;
the UI retains their readable parent/name labels. Tag filters use canonical tag
names. Chat reply links retain their thread and message IDs. Replaying a recent
search restores its conditions instead of accumulating the previous search's
filters.

## Implementation

`GlobalSearchController` owns query state, per-scope conditions, requests and
pagination. `GlobalSearchApi` uses the existing transport and credential reader;
site leases and request revisions reject stale completions. The application
continues to use `ShellSearchController` for its existing shortcut, topic-context
and recent-search integration.

`ForumSearch` composes Native `DPopover`, `DPopoverAnchor` and `DInputGroup`.
Popover's placement resolver aligns the replacement header with the existing
input and retains collision/lifecycle ownership. Input Group's optional
`borderless` presentation lets the popover own the shared surface while keeping
editor and addon geometry intact. Filter editors, condition buttons, ordering,
results and feedback use existing Native components.

## Review

`tool/global_search_review_main.dart` mounts the production surface with local
wire-shaped fixtures, without account or network changes. Focused verification
covers endpoint mapping, filters, stale requests, input placement, caret
preservation, keyboard navigation, nested dismissal and narrow layouts.

Protocol details were checked against Discourse core source, including search,
category/tag lookups and chat routing (local source revision
`438ea4dea8ccc4d5f7bc8460b46fc16d29bff65a`). Verification uses wire-shaped local
responses; it does not claim a live-server or physical iOS/Android device pass.

Acceptance on 2026-09-13:

- Root and `profiles/full` analysis passed; all 19 touched Dart files were
  formatted and `git diff --check` passed.
- 172 focused cases passed across the search controller, panel, presentation,
  clear-action accessibility, content navigation, forum tabs, legacy search,
  Input Group, Popover, styleguide examples and control-adoption tests.
- Actual macOS review covered the navbar/popover transition, recent searches,
  combined results, filter lookup/editor/application, readable compact category
  chips, ordering/display menu, dark/light palettes, narrow panes, larger text,
  chat-disabled forum switching, and the new Input Group shared-surface example.
  The existing navbar still constrains editor width at extreme narrow/200% text
  settings; the search results surface uses the available pane width.
- The final offline macOS build launched successfully with an isolated ad-hoc
  bundle and verified debug entitlements. No account data was changed.
- The HTML mockup's inline JavaScript passed `node --check`. Browser rendering
  was unavailable under the browser access policy; native review is recorded
  separately above.

### Contextual opening follow-up

The contextual opening change passed 16 presentation cases covering mouse and
keyboard opening, changing topics, returning to lists, manual scope changes,
and Escape focus restoration. Native macOS review covered the removed list
field in dark/wide and light/narrow layouts, the topic condition, returning to
the list, and dismissal after changing scope. The offline fixture does not
provide topic bodies; opening context was verified from its route and request.

After incorporating the concurrently merged compact control sizing, the 95
focused presentation, accessibility, navigation and restored-route cases
passed, with the inherited size assertions updated to the shared control scale.
Root and `profiles/full` analysis passed. Four unrelated keyboard-navigation
failures also reproduced identically on the unchanged `71c94832` baseline
(selected-row borders, split-view scrolling, and resuming J/K after dialogs).

### Slow forum search follow-up

The reported partial failure on 2026-09-13 came from the ordinary 10-second
request deadline: forum search was cancelled after 10.004 seconds while chat
returned successfully in 0.519 seconds. A later forum retry succeeded in 5.830
seconds. The response format and search endpoint were valid.

Forum search now has a separately configurable 30-second deadline for both
aggregate and full search, including the legacy search caller. Ordinary reads
keep their existing timeout. Requests still abort at their deadline, and
coalescing keeps different deadlines and credentials separate. Search feedback
identifies timeouts, busy forums and rate limits while retaining successful
sections and the existing Retry action.

Verification covers delayed responses, bounded cancellation, independent
timeout configuration, credentials and subfolder URLs, request coalescing,
partial results and retry recovery. The focused transport, search controller,
search API and panel suites passed. Root and `profiles/full` analysis, formatting
and `git diff --check` passed. A public Discourse response was also replayed
successfully through the parser and aggregate-search adapter. This follow-up
does not claim a new authenticated live-server or native UI review.

### Contextual chat search follow-up

The chat change passed 286 focused cases covering channel and direct-message
scope from clicks and shortcuts, drawer precedence over the underlying topic,
filter removal and reopening, delayed capability discovery, saved display
preferences, exact message navigation, Escape, and existing chat consumers.
Root and `profiles/full` analysis passed. Native macOS inspection used the
offline fixture to check the removed controls, channel chips, result selection
and message highlighting in drawer and full-page modes, dark/light palettes,
and a narrow viewport. Keyboard refocusing and Escape refinements were verified
with widget tests; no authenticated server or physical mobile device was used.

### Search shortcuts follow-up

Cmd/Ctrl+F now selects All and clears retained conditions. Cmd/Ctrl+Shift+F
applies the current topic, list or chat context, including drawer precedence,
even while search is open. Clicks preserve manual scope and filter edits while
the panel remains open. The search footer and keyboard-shortcuts help display
both bindings from the same platform-aware shortcut definitions.

Focused verification covers global/contextual switching on macOS and Linux
target-platform overrides, retained text and caret, topic/list/channel context,
chat drawers and direct messages, dismissal, scrolling to results, and footer
keycaps. Native macOS inspection used the offline fixture in dark/wide and
light/390px layouts, including 200% text. The footer wrapped without clipping.
Native automation sent F without modifier flags, confirmed with a temporary
key-event diagnostic; the shortcut combinations were verified by widget tests.
No authenticated server or physical mobile device was used.

The integrated change passed all 315 focused search, shell navigation,
accessibility and chat cases, root/full-profile analysis, formatting and
`git diff --check` against main's updated search-scope checkmarks and HTML
renderer dependency.
