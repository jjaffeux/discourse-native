# Component task contract

You are implementing exactly the catalogue component assigned by the coordinator.
Read `brief.md`, `conventions.md`, `catalogue.json`, `progress.json`, and the
current code. Your worktree starts from the latest local main. Keep this task
focused on its assigned component and necessary shared/downstream changes.

1. Create branch `codex/ui-<component>` (unless the coordinator supplied another
   branch). Read the assigned official reference page, documented variants,
   examples and API, and relevant dependency docs. Consult the frozen sections
   and prop values so every capability remains accounted for. Define concrete
   acceptance criteria and native adaptations in your progress row first.
2. Implement complete idiomatic Flutter behavior, composition and states using
   shared conventions. Adopt suitable existing primitives, not a new parallel
   rendering owner. Keep all networking and business state outside UI.
3. Cover keyboard, semantics, focus restoration, touch, text scaling, narrow
   layouts, live light/dark/site themes and open overlays, reduced motion,
   dismissal, scrolling and lifecycle races as applicable.
4. Add comprehensive runnable styleguide examples and accurate usage code.
   Use self-contained data and the public library. Mark the group implemented
   only after verification; document all intentional reference differences.
5. Search core and every bundled plugin for adoption opportunities. Migrate
   appropriate callers while retaining permissions, asynchronous ownership,
   state and accessibility. Remove obsolete implementations. Record each
   migration and any deliberately retained alternative with a reason.
6. Format, analyze, run focused meaningful tests for the component, migrations
   and affected shared code. Inspect the running styleguide and affected app
   screens at relevant widths and representative themes. Clearly distinguish
   tests, macOS inspection and unavailable iOS/Linux device checks. Fix failures
   introduced by your change; full-suite testing is not required.
7. Update your row in `progress.json` with acceptance, decisions, migrations,
   verification and limitations. Set status `review_ready`; leave mergeCommit
   null. Regenerate `progress.md`. Commit with the repository subject convention
   and a useful body. Return commit SHA, branch, files changed, exact checks,
   native inspection evidence and any open issue to the coordinator.

Do not create other implementation tasks, merge, push, publish or mark the
whole project complete. The coordinator reviews and merges from the main
checkout and records the merge SHA. The user now authorizes concurrent
independent component tasks (up to four), each based on latest main at dispatch
with dependencies already merged. The coordinator serializes reviews and merges.
Edit only your assigned progress row and preserve unrelated component work.

Builds and automated checks can run concurrently. Before native CUA inspection,
notify the coordinator that code/checks are ready and request the shared desktop
inspection slot. Wait for that slot while continuing independent work, then
report completion or any blocking permission request so the slot can be released.
This is task scheduling; it does not require routine user confirmation.
