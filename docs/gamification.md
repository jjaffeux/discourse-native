# Native Gamification

The bundled `discourse-gamification` module owns leaderboard requests, score records, administrator forms, state, and navigation. Core supplies generic metadata and directory-label contributions, account leases, transport, the existing user-card store, and route containers.

Members can open the default leaderboard or a linked leaderboard, choose its allowed rolling period, see their separate rank, load more members, and open user cards. Profile/card Cheers links to the default leaderboard's all-time result. These values can differ from the currently selected contest period. Directory score values continue through the existing generic directory implementation.

Administrators can create and configure boards, edit all group/date/category/period options and 15 score overrides, delete boards, edit all 18 global settings, inspect and create/edit score events, and request recalculation. Board configuration updates send the complete draft. Creation retains the new board ID if subsequent configuration fails. A confirmed event creation remains saved if refreshing the event list fails.

Scores, positions, eligibility, and scoring jobs are authoritative on the server. The client does not award points after posting, liking, or chatting. Zero and negative leaderboard scores are valid. User-card metadata hides zero for upstream parity. System creator IDs can be negative and the everyone group can have ID zero.

A member period is a rolling server-date interval intersected with configured contest dates. The administrator recalculation presets use UTC dates; upstream's All time preset starts on `2014-08-26`. Recalculation is queued by HTTP and observed through the existing scoped MessageBus channel. The server supplies no job ID, so the UI cannot identify a unique job or promise real-time completion. Disconnection or an expired confirmation wait leaves completion unknown.

The server has no public board catalogue or archive flag. Ended date-bounded boards remain readable by link and editable by administrators. Score-event results are limited to 100 with exact filters, without pagination or deletion. Compact rendering is available to plugin-owned callers; automatic theme-sidebar placement is not registered.

The focused suites are in `test/plugins/gamification/`. Run them by explicit file path. `gamification_host_test.dart` exercises the real application shell's period and scroll restoration. API/controller/lifecycle tests cover wire contracts, account retirement, disabled state, mutation races, and recalculation delivery. Administrator widget tests exercise the actual Native controls. Production-widget captures are opt-in through `NATIVE_UI_EVIDENCE_DIR`.

The generic contracts are `UserCardMetadataPlugin`, `UserProfileMetadataPlugin`, and `UserDirectoryColumnLabelPlugin`. The profile contribution currently serves the signed-in account's Native summary and reuses host-loaded `UserCard` data. It does not introduce an arbitrary-user Native profile. Identity decorations and profile actions proposed by other ports remain separate. Duplicate directory-label claims fail with both owners identified.

Upstream evidence was inspected at Discourse revision `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. Local tests use source-shaped boundary fixtures and actual production widgets. They do not replace deployment checks with real administrator credentials or server jobs.
