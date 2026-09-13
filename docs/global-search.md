# Global search

The navbar search opens a large popover whose input replaces the navbar field
at the same coordinates. The editor retains its controller, focus and selection.
Escape closes the innermost menu first, then restores the navbar search. Clicking
outside closes search without moving focus back. Touch phone layouts use the
available screen with a Back button. The existing Cmd/Ctrl+F shortcut and topic
search context remain available.

On a narrow desktop, the results surface grows beyond the navbar field to use
the available width. The input, clear action and caret keep their original
coordinates inside that larger header. Short windows reduce the results area's
height instead of moving the input upward.

The approved interactive reference is [the mockup](mockups/global-search.html).
Recent searches are full-width text rows; Clear history uses the same row inset.
There are no leading clock icons or footer.

## Search capabilities

All combines accessible forum, user and group search with chat when enabled.
Topics & posts uses Discourse full search; Users and Groups use their directory
APIs, with aggregate-search fallbacks when a directory is disabled. Chat uses
its own search API and requires the installed feature, authentication and site
search permission. Server responses remain authoritative for accessible results.

The filter picker exposes each scope's supported conditions. Conditions combine
with AND; repeatable conditions support date/count bounds. Chips expose the
filter, operator, value and removal action. Scoped filters and ordering survive
switching between scopes. Plugin and permission-dependent conditions only appear
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
