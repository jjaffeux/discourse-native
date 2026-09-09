# Create task: Review and merge Date Picker

Created as task `01a086a1-dd61-77d1-ae4f-a09fa87ff595` on branch
`codex/review-date-picker` in worktree
`/Users/joffreyjaffeux/.codex/worktrees/11aa/discourse-native`.

Create exactly one new Codex task titled **Review and merge Date Picker** from
latest local main in an isolated worktree and use this prompt verbatim:

> Independently review, fix, accept, and merge the Date Picker implementation
> from branch `codex/ui-date-picker`. Read current main's
> `docs/component-library/brief.md`, `conventions.md`, `visual-fidelity.md`,
> `date-picker.md`, `progress.json`, and `review-and-merge.md`. Preserve the
> implementation commits and reconcile a candidate from latest main; never
> merge main into the worktree. The frozen official Base UI Date Picker Markdown
> SHA256 is `cedb8c5a45c2cc2cede23b564b55c7a7a3c506e5d14f6b413d7758c03a0550c6`;
> primary example hashes are recorded in `date-picker.md`. Review all eight
> actual catalogue examples: Composition, Basic, Range Picker, Date of Birth,
> Input, Time Picker, Natural Language Picker, and RTL. Verify controlled,
> uncontrolled and Form behavior; strict locale/ISO/leap-invalid text;
> deterministic natural input with an explicit clock; range/bounds/disabled
> dates; typed wall-clock values without timezone ownership; Arrow Down,
> close/focus restoration, outside/Escape dismissal, semantics, touch targets,
> IME/controller ownership, live themes, narrow/200% text, RTL and reduced
> motion. Inspect the Local Date composer migration and preserve its ISO draft,
> timezone, recurrence, preview and validation logic; verify the documented
> retained alternatives for Events, Bookmark and User Status. Use
> `tool/date_picker_review_main.dart` for the exact-source native fixture and
> complete official browser comparison plus native macOS acceptance. The
> implementation integrated Calendar source
> `50b83b642a816e83382d4d14b588a12c4cd2533c` from `codex/ui-calendar`, whose
> reviewer is `01a08631-7574-70b0-a98f-4e7217e03209`, and prepared Input Group
> fixes through `c48643dc` from `codex/review-input-group`, reviewer
> `01a085d3-1acf-7361-9dc8-fc4a99de7c45`. Neither prepared dependency may
> transit to main through Date Picker: wait for each accepted merge, integrate
> its final main revision, reconcile API/behavior differences, and rerun
> affected checks. Set Date Picker styleguide status to implemented only after
> acceptance. Then follow `review-and-merge.md`: prepare from latest main,
> acquire the main lock, merge the review branch from
> `/Users/joffreyjaffeux/Code/discourse-native` on `main`, update only the Date
> Picker progress/review row with the merge SHA, regenerate `progress.md`,
> release the lock, and notify dependents. Do not push or mutate remote systems.

After creation, record the real reviewer task ID and review branch in the Date
Picker progress row and send the reviewer the final `codex/ui-date-picker` head.
