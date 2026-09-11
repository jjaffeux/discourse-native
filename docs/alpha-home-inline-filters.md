# Alpha home inline filters

The aggregate home retains ForumTabsBar and its existing tab lifecycle. A quiet Discourse/alpha header replaces the decorative banner. The feed summary and modal Filters button are removed. Forum inclusion, tokenized queries, and per-forum Apply actions appear in a collapsible Native card above the topics, sharing their reading lane and scroll area. Topic rows use the existing DItem standard variant with separators.

The implementation composes DCard, DCollapsible, DCheckbox, DButton, DBadge, DSeparator and the existing TopicFilterInput(tokenized: true). No UI component implementation is changed. TopicListRow, an application adapter, passes through DItem's existing variant.

Collapsed state is saved in aggregate preferences, with older preferences defaulting to expanded. Per-tab drafts remain in the aggregate session in memory, including across the shell's responsive remounts. They do not affect the feed until Apply. Applying one forum preserves other forums' applied values and their pending drafts. Existing tab creation, rename, close, reopen and pull-to-refresh behavior are retained.

Validation on 2026-09-11:

- 53 tests passed across aggregate_view_test, aggregate_feed_controller_test, aggregate_shell_navigation_test and topic_list_view_lifecycle_test.
- Static analysis of changed source, tests and the offline fixture passed.
- Flutter 3.47.2 debug macOS build passed.
- Isolated offline native fixture: dark palette at wide and narrow window widths; native token entry, collapse/expand, and resize with a pending token. Native AX confirmed token and independent controls. The resize check caught and verified the fix for lost drafts. Light/default-palette widget tests and 390px overflow checks also passed; no iOS/Android device test was performed.

The reproducible offline entrypoint is tool/component_fixtures/alpha_home.dart; its dependencies and preferences are fake and never access account settings.
