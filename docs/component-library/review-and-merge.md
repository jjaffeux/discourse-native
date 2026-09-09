# Independent component review and local merge

The user's 2026-09-09 instruction supersedes the original coordinator review
and merge gate: every implementation hands off to a **new Codex review task**.
That reviewer owns source review, necessary fixes, remaining reference/native
verification, integration, and the final local main merge. Do not return work
to the coordinator for routine approval. The coordinator tracks the catalogue
and starts eligible implementations; it is not a merge gate.

The existing 17 unmerged implementations each have a separate reviewer. Keep
the original implementation task and branch in `progress.json`; add
`reviewTaskId`, `reviewBranch`, `reviewStatus`, and the review evidence. Resolve
dependencies directly with their reviewer (look up its ID in main's progress).
Reuse valid source-specific tests, builds and captured evidence. Re-run checks
when code changes, conflicts, failures or uncovered behavior require them.
Never label unperformed native/browser checks as completed or silently drop
required documented compositions to clear the queue.

## Shared access without coordinator permission

All worktrees use the same Git common directory. The helper below uses atomic
directory creation there. Only the lease holder may mutate the main checkout
or use shared UI, respectively. Builds and read-only source/evidence review in
your own worktree do not need these leases.

```sh
python3 /Users/joffreyjaffeux/Code/discourse-native/tool/component_review_lock.py acquire desktop --owner YOUR_TASK_ID --component COMPONENT --repo /Users/joffreyjaffeux/Code/discourse-native
python3 /Users/joffreyjaffeux/Code/discourse-native/tool/component_review_lock.py status desktop --repo /Users/joffreyjaffeux/Code/discourse-native
python3 /Users/joffreyjaffeux/Code/discourse-native/tool/component_review_lock.py release desktop --owner YOUR_TASK_ID --token RETURNED_TOKEN --repo /Users/joffreyjaffeux/Code/discourse-native
```

Use `main` instead of `desktop` for any main-checkout mutation, including
progress updates. Desktop requests are first-come, first-served: a busy
`acquire desktop` automatically joins the waiting queue and returns exit 75,
the holder, your queue position and the next waiting task. Retrying preserves
your position. `status desktop` shows the live queue. The next waiting task
acquires directly when the holder releases; nobody can jump ahead by polling
faster. Main-checkout access remains a simple exclusive lease.

Continue independent work, or wait up to 45 seconds between attempts. If you
are no longer ready for desktop review or are ending your turn while queued,
withdraw your own waiting request with:

```sh
python3 /Users/joffreyjaffeux/Code/discourse-native/tool/component_review_lock.py cancel desktop --owner YOUR_TASK_ID --repo /Users/joffreyjaffeux/Code/discourse-native
```

Cancellation only removes a waiting request; it never releases a held lease.
Read owner status or message that task directly when useful. Do not ask the
coordinator to grant access. Leases never expire automatically: do not delete
another task's lease or treat elapsed time as permission to take it. Arrange
release with the owner; if a task is terminated, establish that it has stopped
using the resource before repairing an abandoned lease and record the reason.
Never hold one lease while waiting for the other, UI permission, a dependency,
or a user response. Release a held lease before ending a turn or on a genuine UI blocker; cancel
your waiting desktop request if you have not acquired it. Waiting requests do
not expire automatically. Verify a task is terminal or explicitly withdrew
before repairing an abandoned waiting request, and record the reason.

The desktop lease covers native app and browser actions together. Switch's
implementation task initially holds it while finishing its in-flight native
review; its new reviewer receives the evidence and released access directly.
Quit only your own isolated review app and close only your own browser tabs.
The recorded host uses AZERTY: earlier native CUA `super+a` input quit an
isolated app (the `a` key produced `q`). Use documented literal text/pointer
editing or native Edit actions as appropriate and verify the actual field
state. Do not classify a shortcut/tool-input incident as a component crash
without evidence. See the Typography and Skeleton records in progress.
Use the approved CUA surface. The prior browser denial concerned verification
of an admin-enforced security policy. The Mac was subsequently unlocked;
attempt the approved surface only, and stop if that denial persists. No
alternate route, policy bypass, OS security or provisioning changes.

## Reviewer procedure

1. Work in your new task's isolated worktree on its own `codex/` review branch.
   Read main's current conventions, this file and your component's evidence.
   Merge the existing implementation branch into your review branch, preserving
   its commits. Do not duplicate or reset its worktree. Bring in current local
   main and resolve actual code conflicts in your own worktree. Preserve all
   other component owners, exports, examples and production migrations.
2. Complete the source, app adoption, official rendered reference and native
   review. Use the existing exact-source isolated bundle when applicable;
   rebuild for source changes that affect it. Record meaningful focused tests
   and root/full-profile analysis as appropriate to the actual changes. The
   user does not require the full suite. Finish fixes in this review task.
3. Reconcile with the latest main in your worktree, preserving its complete
   progress record and changing only your component row and explicitly owned
   dependency follow-ups. Shared progress files in an older implementation are
   historical: never replace current main's other rows or workflow with them.
   Set the example's implemented status only after acceptance. Commit.
4. Acquire `main`, then recheck that main is on `main`, no merge is in progress,
   and its HEAD still matches the main revision you integrated. If it moved,
   release, integrate the new commits in your worktree, verify the affected
   overlap and retry. Inspect and preserve unrelated working changes. Do not
   stash, reset, commit or overwrite another task's or the user's changes.
5. From **`/Users/joffreyjaffeux/Code/discourse-native` on main**, perform the
   authorized `git merge --no-ff YOUR_REVIEW_BRANCH`. Final merges must happen
   there. Resolve preparation/conflicts in your worktree, not in shared main.
   Verify the merge and record its SHA in your row in a follow-up local commit;
   set status `merged`, `reviewStatus` `merged`, remove only your queue entries,
   and regenerate `progress.md` with `dart --disable-dart-dev
   tool/render_component_progress.dart` (direct execution avoids implicit pub
   resolution). Keep the lock until these main mutations are complete.
6. Release `main`, report the merge SHA and actual verification, and notify
   dependent reviewer tasks directly. No coordinator approval is required.
   Never push, write to GitHub, or change App Store Connect/release settings.

## Future implementations

After implementing a component, create a new project Codex task titled
`Review and merge <Component>` from latest local main, using an isolated
worktree. Its prompt must include the component branch, exact source/evidence,
remaining checks and dependencies, and this protocol. Record the returned
reviewer ID in the implementation handoff and progress row, then send it the
final commit. Creation can first return a `clientThreadId` while its worktree
is being prepared; do not pass that setup ID to tools requiring a real task ID.
Use the task tools to resolve the new task. If the app list omits a worktree
that has already started, identify its review branch with `git worktree list`,
read its `codex-thread.json` in the Git directory reported by
`git -C REVIEW_WORKTREE rev-parse --absolute-git-dir`, and verify that
`ownerThreadId` with `read_thread` (matching title and worktree). This is a
read-only lookup, not a reason to create another reviewer. The reviewer
finishes and merges directly. Do not send an
implementation back to the coordinator as its required next step.

The overall goal remains incomplete until all 64 components and the separate
final library audit have passed their required verification and merged locally.
