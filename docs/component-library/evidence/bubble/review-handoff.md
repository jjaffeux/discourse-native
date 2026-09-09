# Create task: Review and merge Bubble

Create exactly one new Codex project task titled **Review and merge Bubble** in
an isolated worktree from latest local main. This is a transport handoff only;
the new task owns all review, fixes, verification and final local-main merge.

## Exact source

- Implementation task: `01a085d9-7909-7fd0-b1b8-30a76c6ab2af`
- Branch: `codex/ui-bubble`
- Exact source/evidence commit: `3fc2f85be46d9fac37b645e70871e621a2cdcf96`
- Component implementation commit: `78c60d0cd7cf87d34c46524fff95336b43e261cd`
- Prepared Popover merge: `db64a64a`, integrating exact unaccepted review pin
  `d99562f0f6973c9dc3f566eea02d9b00c6de4f7b`
- Source base/current main at handoff: `5a26e5713719988f69930a7f02b3373b530d050a`
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
- 84 focused Bubble, Bubble examples, complete styleguide-page, Collapsible,
  Tooltip and prepared Popover tests passed with seed `6863`.
- `flutter build macos --debug --no-pub -t lib/styleguide_main.dart` passed.
  Kernel SHA256:
  `f88587be60d68500ce239860fcc82d391e37739efe363537df9631fa65675799`.
  Deep strict signature verification passed. This was the ordinary existing
  development build, not an isolated bundle; it was not launched.
- `dart format` and `git diff --check` passed. No full suite was run or required.

## Reviewer-owned completion

1. Review and fix the complete public API, visuals, interaction, semantics,
   examples and app audit. Preserve all other component owners and progress
   rows. Bubble examples intentionally remain `ComponentStatus.planned` until
   rendered/native acceptance.
2. Popover reviewer is `01a08558-ae1e-7843-8cff-7221a399ea5c` on
   `codex/review-popover`. Bubble source preparation used its tested pin only.
   **Wait for Popover's accepted local-main merge**, integrate accepted current
   main, reconcile the API/overlap and rerun affected checks. Never allow the
   unaccepted parent to reach main through Bubble.
3. Toast reviewer is `01a08592-b1eb-7ad2-bebb-3ddea00f2702`. The frozen
   link/button and reaction demos use Sonner for action feedback. After accepted
   Toast lands, complete the final Bubble/DToast styleguide composition rather
   than retaining local feedback as the final reference or creating a notifier.
4. Attachment implementation is `01a085d4-9afd-7082-8081-f8b1f8f66287`.
   Preserve its separate media/upload/action boundary. Coordinate Message
   dependents after Bubble merges.
5. Under the shared desktop FIFO lease, compare the official rendered
   base-nova reference with the actual Flutter styleguide at matching width and
   state. Inspect every variant, content padding/radius/type, 80%/ghost widths,
   alignments, group gap, reaction geometry/top-bottom/start-end, static and
   interactive states, links/buttons, Collapsible, Tooltip and Popover. Verify
   light, dark, a custom palette/radius/font, 360px, 200% text, RTL and reduced
   motion. Exercise pointer, keyboard, focus restoration, disabled/busy/error/
   selected semantics and touch-target behavior. Build/use an exact-source,
   uniquely identified local-data macOS fixture if needed. Record only checks
   actually performed; no iOS/Linux/VoiceOver claim without evidence.
6. Re-audit `ChatMessageTile`, chat/topic `ReactionPill`, Voice room chat,
   quotes and post actions. Current evidence retains them because Message,
   Message Scroller, Attachment, CookedHtml, selection, virtualization,
   permissions and async reactor/domain ownership would be changed by a partial
   migration. Adopt only a genuinely safe surface and preserve all callbacks,
   guards and semantics; otherwise keep the specific retained reasons.
7. Integrate latest main in the review worktree and rerun checks proportional
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
