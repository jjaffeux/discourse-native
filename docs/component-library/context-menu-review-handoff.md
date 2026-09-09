# Context Menu review handoff

Independent reviewer task: `01a0861f-38ca-7122-b18f-5f286ab90ccb`

- Implementation task: `01a08606-5dce-7b91-9ee6-7713872f1fa7`
- Implementation branch: `codex/ui-context-menu`
- Implementation source commit:
  `d1c954fefb5d461be217d443f5bf51330b7f24e7`
- Review branch: `codex/review-context-menu`
- Review worktree:
  `/Users/joffreyjaffeux/.codex/worktrees/8c70/discourse-native`

The reviewer owns all remaining fixes, accepted-parent reconciliation, official
rendered browser comparison, isolated native macOS inspection, final
compositions, progress integration and the authorized local main merge under
`docs/component-library/review-and-merge.md`.

## Required dependency gate

Context Menu prepared against source-equivalent Dropdown Menu candidate
`d273c27e788bb3991c773c7432e0b8c927715651` on
`codex/review-dropdown-menu-candidate`, reviewed by task
`01a085cf-f401-7813-80da-7c687de8a5d5`. The copied
`d_dropdown_menu.dart` differs only by current Dart formatting. It is not an
accepted parent and must not reach main through this branch.

Wait for Dropdown Menu's accepted local-main merge. Create a candidate from
that latest main, bring the Context Menu implementation into it, reconcile the
accepted parent/API plus shared exports/examples/progress, and rerun affected
checks. Coordinate directly with the Dropdown Menu reviewer.

## Prepared evidence

- Frozen Markdown SHA256 reproduced exactly:
  `ec20bd0ef47abb75872c1294d1563f0f279d3da5861177d8f2c588d8eb5f6895`.
- Registry SHA256 observed 2026-09-09:
  `57bfdd236a7f4cb83625edf4c33265ce009738947666d00311034a88f6868756`.
- Ten Context Menu tests passed with randomized seed `826145`.
- Fifty-three Dropdown/Popover/styleguide/InstanceActions/modal lifecycle
  regressions passed with seed `826145`.
- Root and `profiles/full` analysis passed without diagnostics.
- Styleguide macOS debug build passed; kernel SHA256:
  `6fa392ded08bd8c73b78794d38c04606daee7d42f2ae60acf01e336c32f2b699`.
- Formatting, progress JSON/render and diff checks passed.

`docs/component-library/context-menu.md` contains the complete source mapping,
acceptance criteria, application audit and retained alternatives. The
styleguide entry intentionally remains baseline until the reviewer completes
actual official/native acceptance. No iOS/Linux device run, spoken VoiceOver
pass or pixel-diff equality is claimed.
