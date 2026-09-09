# Create task: Review and merge Bubble

Create exactly one new Codex project task titled **Review and merge Bubble** in
an isolated worktree from latest local main. This is a transport handoff only;
the new task owns all review, fixes, verification and final local-main merge.

## Exact source

- Implementation task: `01a085d9-7909-7fd0-b1b8-30a76c6ab2af`
- Branch: `codex/ui-bubble`
- Exact reconciled source/evidence commit: `0dc71a5b8d282410587e36387a27cd48b50567da`
- Component implementation commit: `78c60d0cd7cf87d34c46524fff95336b43e261cd`
- Current-main reconciliation merge: `0dc71a5b`, integrating main
  `9ad0e87ca7141c4f57ad8bb1d4cbb6101aaf0c1c`
- Accepted Popover merge: `dc6ab75fe99f2af8b401bae60285fdbe65e8012a`
- Accepted Toast merge: `d454c8f62fb4ab8718b3a32b2743556f2f78609d`
- Mapping/audit: `docs/component-library/bubble.md`
- Durable row/evidence: `docs/component-library/progress.json`

Merge `codex/ui-bubble` into the new review branch while preserving its commits.
Do not reset, duplicate or edit the implementation worktree. Read current
`docs/component-library/review-and-merge.md`, conventions, visual-fidelity and
the Bubble evidence before acting.

## Prepared verification

- Frozen Markdown SHA256 reproduced exactly:
  `6863ccd2854a6d590991fc58cb8b5ddcb82fe88d25185100b7bf111021267a82`.
- Inspected base-nova registry SHA256:
  `be11ab3fa78ec7bd4736f4ab98c16a2d5a230536206d5a4fd06259422b55cb14`.
- Root and `profiles/full` `flutter pub get --enforce-lockfile` passed without
  lockfile or dependency-pin changes.
- Root and `profiles/full` `flutter analyze --no-pub` passed with no issues.
- After current-main reconciliation, 94 focused Bubble, Bubble examples,
  complete styleguide-page, Collapsible, Tooltip, accepted Popover and Toast
  tests passed with seed `6864`. Final DPopover source has no diff from main.
- `flutter build macos --debug --no-pub -t lib/styleguide_main.dart` passed.
  Kernel SHA256:
  `eb6f2dbe1c0cb694eb50f16d69418b4d274a753033bab46628437d6d5ca3c207`.
  Deep strict signature verification passed. This was the ordinary existing
  development build, not an isolated bundle; it was not launched.
- `dart format` and `git diff --check` passed. No full suite was run or required.

## Reviewer-owned completion

1. Review and fix the complete public API, visuals, interaction, semantics,
   examples and app audit. Preserve all other component owners and progress
   rows. Bubble examples intentionally remain `ComponentStatus.planned` until
   rendered/native acceptance.
2. Popover and Toast are accepted on the reconciled main revision. Bubble's
   Popover source is byte-identical to accepted main, and its link/button and
   reaction examples now compose DToast for action/success/error feedback.
   Preserve those final shared owners; do not resurrect the prepared pins or a
   duplicate notifier.
3. Attachment implementation is `01a085d4-9afd-7082-8081-f8b1f8f66287`.
   Preserve its separate media/upload/action boundary. Coordinate Message
   dependents after Bubble merges.
4. Under the shared desktop FIFO lease, compare the official rendered
   base-nova reference with the actual Flutter styleguide at matching width and
   state. Inspect every variant, content padding/radius/type, 80%/ghost widths,
   alignments, group gap, reaction geometry/top-bottom/start-end, static and
   interactive states, links/buttons, Collapsible, Tooltip and Popover. Verify
   light, dark, a custom palette/radius/font, 360px, 200% text, RTL and reduced
   motion. Exercise pointer, keyboard, focus restoration, disabled/busy/error/
   selected semantics and touch-target behavior. Build/use an exact-source,
   uniquely identified local-data macOS fixture if needed. Record only checks
   actually performed; no iOS/Linux/VoiceOver claim without evidence.
5. Re-audit `ChatMessageTile`, chat/topic `ReactionPill`, Voice room chat,
   quotes and post actions. Current evidence retains them because Message,
   Message Scroller, Attachment, CookedHtml, selection, virtualization,
   permissions and async reactor/domain ownership would be changed by a partial
   migration. Adopt only a genuinely safe surface and preserve all callbacks,
   guards and semantics; otherwise keep the specific retained reasons.
6. Integrate latest main in the review worktree and rerun checks proportional
   to real changes. Set the Bubble styleguide status implemented only after
   acceptance. Update only Bubble and explicit dependency follow-ups in
   progress, commit, then acquire the separate `main` lease. Confirm the shared
   checkout is clean/on main and HEAD equals the integrated revision. From
   `/Users/joffreyjaffeux/Code/discourse-native`, merge the review branch with
   `git merge --no-ff`. Record the merge SHA/status in the required follow-up
   local-main commit, regenerate progress, release the lease and notify the
   coordinator `01a0816f-d4e0-7f93-9d6b-baeaf6961181` and dependents.

No push, GitHub write, account-data mutation, provisioning/OS-security change,
App Store Connect or release work is authorized.
