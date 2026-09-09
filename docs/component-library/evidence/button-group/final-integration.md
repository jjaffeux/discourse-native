# Button Group final integration

Date: 2026-09-09. Candidate: `8120a12c2b2f839bb642d2f6a87a75f99596a8f4`.
Base main: `4d79219df5ddc4c51e80defb02a0eb607dd6a3dd`.

The candidate was created from current main and then merged the accepted review
history (`4f420330`), preserving the original implementation and recovered
handoff. Main was not merged into a worktree. The merge was conflict-free;
public exports and the example registry add only Button Group. The complete
current-main progress record is preserved, except for the Button Group row
and explicitly owned Select/Input Group composition closeouts.

## Source-equivalence review

Against native-inspected `cff5dfc2`, `DButtonGroup`, `DButton`, `DInput`,
`DInputGroup`, `DSelect`, `DPopover`, the joined-control scope, production
`ContentNavigationControls`, Select examples and Input Group examples are
byte-identical. Button Group examples change only baseline to implemented;
the isolated harness changes only its page-heading theme context as disclosed
in [native-review.md](native-review.md).

Newer main changes `DField` to skip `LayoutBuilder` for explicit orientations
and extract the same Flex construction into `_layout`; responsive orientation
still uses the previous width/breakpoint calculation. The reviewed vertical
Field composition therefore keeps the same layout/metadata contract. The
Field and real Button Group composition regressions pass together below.
Other newly accepted components and production adoptions are preserved.

## Verification on the candidate

The following run passed all **169 tests**, randomization seed **826145**:

```sh
flutter test --no-pub \
  test/d_button_group_test.dart \
  test/d_button_test.dart \
  test/d_button_reference_test.dart \
  test/d_button_adoption_test.dart \
  test/d_input_test.dart \
  test/d_input_group_test.dart \
  test/d_select_test.dart \
  test/d_popover_test.dart \
  test/d_dropdown_menu_test.dart \
  test/ui/d_field_test.dart \
  test/styleguide/button_group_examples_test.dart \
  test/styleguide/input_group_examples_test.dart \
  test/content_navigation_controls_test.dart \
  --test-randomize-ordering-seed=826145 --reporter expanded
```

Root and `profiles/full` `flutter analyze --no-pub` both passed without
diagnostics. Touched Dart files were formatted; `git diff --check` passed.
No manifest, lockfile, native runner or provisioning change was introduced.
This targeted matrix supplements the recorded source-specific browser/native
acceptance and earlier focused runs; it is not a full-suite claim.
