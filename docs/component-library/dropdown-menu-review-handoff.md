# Dropdown Menu review handoff

Create a new Codex task titled `Review and merge Dropdown Menu` from latest
local main in an isolated worktree.

## Reviewer prompt

Review and merge the Dropdown Menu component for the Discourse Native shadcn
Flutter component library.

Implementation worktree:
`/Users/joffreyjaffeux/.codex/worktrees/bb70/discourse-native`

Implementation branch:
`codex/ui-dropdown-menu`

Implementation source commit:
`a78b3615`

This commit integrates current local main `6b8ec8f8` in the isolated worktree;
the subsequent evidence-only commit records the reviewer task ID.

Important dependency gate:

- Dropdown Menu source preparation replayed unaccepted Popover review commit
  `d99562f0f6973c9dc3f566eea02d9b00c6de4f7b` as local commit
  `746846022ad26d219cb8afc2a0176bdc4bb27167`.
- Do not merge Dropdown Menu to main until Popover is accepted and merged on
  current local main.
- Before final merge, integrate accepted Popover/current main into the review
  worktree, reconcile overlap, rerun affected checks, and verify affected
  behavior. The unaccepted Popover source must not reach main through Dropdown
  Menu.

Required review protocol:

- Follow `docs/component-library/review-and-merge.md`.
- Review source, styleguide coverage, application adoption, reference fidelity,
  native behavior and progress metadata.
- Acquire the desktop lease for native/browser inspection and the main lease
  for final local main mutation.
- Final merge must be `git merge --no-ff YOUR_REVIEW_BRANCH` from
  `/Users/joffreyjaffeux/Code/discourse-native` on `main`.
- Preserve unrelated changes and all other component owners.

Implemented surface:

- Public export: `package:discourse_native/discourse_ui.dart`.
- Component: `lib/src/ui/components/d_dropdown_menu.dart`.
- Reference evidence: `docs/component-library/dropdown-menu.md`.
- Styleguide examples:
  `lib/src/styleguide/examples/dropdown_menu_examples.dart`.
- Table temporary-menu migration:
  `lib/src/styleguide/examples/table_examples.dart`.
- Tests:
  `test/d_dropdown_menu_test.dart` and
  `test/styleguide/dropdown_menu_examples_test.dart`.

Reviewer must preserve these downstream coordination requirements:

- Button Group reviewer `01a0859e-170c-7821-b0fd-9ff24a9bfaac` needs final
  public split-menu/dropdown composition replacing its local handoff fixture.
  Preserve independent primary-button and menu-trigger actions, joined exterior
  geometry and focus/invalid rings, keyboard operability, RTL/scaling, overlay
  appearance and trigger focus restoration.
- Table accepted behavior must stay intact: actions use DDropdownMenu, first
  item receives focus when opened by keyboard, edit/duplicate/delete local row
  behavior remains, expanded row highlight follows menu state and trigger focus
  restores after selection/dismissal.
- Notify Button Group reviewer with the final accepted API/merge status after
  review.

Implementation verification already performed:

- `dart format lib/src/ui/components/d_dropdown_menu.dart lib/src/styleguide/examples/dropdown_menu_examples.dart lib/src/styleguide/examples/table_examples.dart lib/src/styleguide/component_examples.dart test/d_dropdown_menu_test.dart test/styleguide/dropdown_menu_examples_test.dart`
- `flutter test --no-pub test/d_dropdown_menu_test.dart test/styleguide/dropdown_menu_examples_test.dart test/d_table_test.dart test/d_popover_test.dart test/styleguide/popover_examples_test.dart --test-randomize-ordering-seed=826145`: 42 tests passed after current-main integration.
- Root and `profiles/full` `flutter analyze --no-pub`: passed.
- `flutter build macos --debug --no-pub -t lib/styleguide_main.dart`: passed; kernel SHA256 `5b8111208021b3a52ba1237e83017feeca049c96905d9809239dad0da18143d9`.
- `git diff --check`: passed.

Remaining reviewer checks:

- Official rendered reference comparison at matching width, text scale and
  state.
- Native macOS styleguide inspection, including hover, keyboard traversal,
  typeahead, submenu Escape ordering, outside dismissal, trigger focus
  restoration, dark/light/custom palette, large text and RTL.
- Any additional app menu adoption audit once accepted Popover is on main.

## Button Group reviewer notification text

Dropdown Menu source/API is committed on `codex/ui-dropdown-menu`.

Current-main-integrated source commit: `a78b3615`.

Public API:

- `DDropdownMenu(child:, content:, controller:, open:, defaultOpen:, onOpenChange:, onOpenChangeComplete:, restoreFocus:)`
- `DDropdownMenuTrigger(builder:, focusNode:)`
- `DDropdownMenuContent(children:, semanticLabel:, side:, align:, sideOffset:, alignOffset:, sideCollision:, alignCollision:, collisionPadding:, collisionBoundary:, width:, constraints:, isSubmenu:, autofocus:)`
- `DDropdownMenuGroup`, `DDropdownMenuLabel`, `DDropdownMenuSeparator`
- `DDropdownMenuItem(onPressed:, leading:, trailing:, inset:, variant:, closeOnSelect:, semanticLabel:, focusNode:)`
- `DDropdownMenuShortcut`
- `DDropdownMenuCheckboxItem`
- `DDropdownMenuRadioGroup<T>` / `DDropdownMenuRadioItem<T>`
- `DDropdownMenuSub(trigger:, children:, leading:, inset:, enabled:, semanticLabel:, width:)`

Split-button composition is demonstrated in the Dropdown Menu styleguide and
uses a primary `DButton` plus a separate `DDropdownMenuTrigger` button. Preserve
independent action callbacks and joined exterior geometry in Button Group.

Final merge remains gated on accepted Popover being merged to current main. The
Dropdown Menu reviewer must integrate accepted Popover/current main before
merge and then notify Button Group with accepted API status. No coordinator gate
is required.
