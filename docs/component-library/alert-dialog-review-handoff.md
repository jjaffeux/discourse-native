# Codex task handoff

Title: **Review and merge Alert Dialog**

Create exactly one new isolated Codex task from current local `main` with the
following prompt. Task creation was unavailable in implementation task
`01a085d9-7909-7fd0-b1b8-30914ac699b4`; this committed prompt is transport
only and does not transfer review ownership to the coordinator.

## Prompt

Review, fix, verify and merge the Alert Dialog component for discourse-native.
Read `/Users/joffreyjaffeux/Code/discourse-native/docs/component-library/review-and-merge.md`
and follow its independent reviewer protocol. Work in a new isolated worktree
on branch `codex/review-alert-dialog`. Merge the implementation branch
`codex/ui-alert-dialog`, preserving its commits. Exact implementation source
commit is `77a8933a9f58b275b44dc41ede4cf22e46ae9c9f`; the branch's later commits only
integrate accepted dependencies/current main and record progress and this
handoff. Review
`docs/component-library/alert-dialog.md`, the Alert Dialog row in
`docs/component-library/progress.json`, all source/migrations/tests and the
committed `tool/alert_dialog_review.dart` local-data harness.

Alert Dialog depends on Dialog. Dialog reviewer task
`01a08558-7ac2-79a3-bd49-1be6148f540c` accepted and merged it on local main at
`6a0aaa54d86aaa492681f5cc4dcd32b5e2feefe3`; the Alert Dialog branch then
integrated current main through `77ee9b047528d43fcbcd4a31d464182f9640b835`
in merge commit `ede650a0`. The accepted Dialog API/source required no Alert
Dialog correction and the combined focused suite passed. Reconcile against
the latest main again before acceptance and coordinate any route/focus/async
primitive correction with the Dialog owner. Attachment reviewer task
`01a085d4-9afd-7082-8081-f8b1f8f66287` and Command reviewer task
`01a085d3-21b9-75d0-a4f0-c739439ccb9d` use the same parent; avoid incompatible
primitive changes.

Review the frozen shadcn Base UI page, Markdown and base-nova registry against
the mapping. Frozen Markdown SHA-256 is
`ccc9147729b395b1d80ba6c9190ffbd5b556213571f958bb10c111a38b63c2da`.
Acceptance must cover complete Composition, Basic, Small, Media, Small with
Media, Destructive and RTL examples and the linked Base UI anatomy/API. Verify
the regular/small responsive widths, exact padding/gap/media/title/description/
footer/action metrics, palette/font/radius mapping, hover/press/focus/disabled/
loading/error states, no corner close, inert outside press, Escape cancellation,
cancel-first focus, containment/restoration, typed controlled/uncontrolled and
borrowed controller state, async success/failure/re-entry guards, live overlay
theme/font/radius/direction changes, narrow 200% layout, RTL, reduced motion,
touch/pointer/keyboard and native semantics.

Audit the production migrations and retain every existing domain guard:
forum removal, poll removal, draft deletion, notification dismissal,
diagnostics clear, bookmark destruction, Voice capture/recording, topic
delete/selected-post merge/delete and group-member removal. Confirm that
specialized phrase-entry forms and ordinary editors/pickers/sheets remain with
their correct owners. Fix implementation, examples, migrations or tests in the
review task wherever evidence requires it.

Reuse source-valid verification and rerun all affected checks after dependency
integration or fixes. The component/example suite passed 9 tests at seed
`3089443727`; after accepted Dialog/current-main integration, the
Dialog/component matrix passed 32 tests at seed `4155910622`; the primary migrated
consumer groups recorded 55 + 3 + 24 + 14 + 89 + 2 passing focused tests in
the progress evidence. Root and `profiles/full` analysis passed. A broad
parallel batch reproduced the known diagnostics resize-handle test flake and
was interrupted during an unrelated long topic test; do not misreport it as an
Alert Dialog pass or failure—use focused affected checks.

The unlaunched prepared bundle is
`/private/tmp/discourse-alert-dialog-review.uFQUBx/Alert Dialog Review.app`,
identifier `org.discourse.native.styleguide.alertdialog`, scheme
`discourse-alert-dialog-review`. Deep strict ad-hoc signature verification
passed with restricted debug entitlements. Its original/copied kernel SHA-256
is `a2724f22c8a502674b303547455467b94ba6df30da6cfec4ac365037cf86248d`.
The exact source hashes at build were: component
`8ad4aae893a91fc74dec3e79c4bb61d4b3b176bbdd900782e60d966b8df5ab99`,
examples `244cdb6401ddf3a59c9aa4e382f14039123b2a9e421d7b2e5c1a410f01e426f9`,
harness `34432dd7181d2f1adae42933dc0ec8ff886f104615b64424cd6d118bf6a992f5`.
Rebuild after any behavior/source change.

Acquire the shared desktop lease directly before the mandatory first official
browser/native rendered comparison. Inspect actual registered examples and
the local production-adapter fixtures across light/dark/custom palette,
regular/small/media/destructive, narrow/200%/RTL/reduced motion, mouse and
keyboard interaction. Record only checks actually performed. Release the lease
before blocking or ending a turn. No iOS/Linux claim without devices.

After acceptance, reconcile current main and update only Alert Dialog progress
and evidence, set the example implemented, then acquire the separate main
lease. From `/Users/joffreyjaffeux/Code/discourse-native` on `main`, perform
`git merge --no-ff codex/review-alert-dialog`. Record the merge SHA in a
follow-up local main commit, regenerate `progress.md`, release the lease and
notify coordinator task `01a0816f-d4e0-7f93-9d6b-baeaf6961181` and dependent
reviewers of the merge milestone. No coordinator approval, push, GitHub write,
App Store/release/account mutation, provisioning change or OS security change.
