# Radio Group final compositions — 2026-09-09

Status: source, automated, official rendered-reference and native macOS review
accepted on 2026-09-09; merged locally as
`1f3b73293a842e65a5b7675e99496322c7595589`. Desktop lease released.

## Provenance

- Review task: `01a086cd-3f9c-75b0-bda3-7d80f6e4604d`.
- Candidate: `3169db0954aa8e387ec316d1414a5a0d0cb5a919`, built from current main
  `7b09b62dc83b4c56665794be0548a659e0ed8c32` plus the reviewed source history.
- Composition implementation `bf601efd`; review corrections `28418a2d`; merged
  semantics regression `c4faf8e0`. The subsequent evidence-harness change only
  bounds the opt-in export to compositions; it does not change the built app.
- Original accepted merge `62e7d25adeb8c125faca2a6476cbb800660a2025` and original
  implementation `99126e23b169f72ffde2975adb1da77fd5f966cb` are preserved.
- Accepted Field owner `5cd7f3694498e4e09e3c114639baca834b56705e`; Label owner
  `9bbc2806020646451fd1c283d347283fe4e45f67`.
- Frozen reference: https://ui.shadcn.com/docs/components/base/radio-group,
  Markdown SHA256 `e00939e01c108da6492bdf9a3d9ccf34bbb284e3dce26260dcf44dc4ef4219f6`.

`source-manifest.sha256` records tracked library, fixture, support, macOS,
assets and package inputs. These inputs equal candidate source at build time.
The isolated copy and build output both contain kernel SHA256
`393192a0a8c364720d81b4eba65bdba6216fb84ace89f7bd57e96d420931ad11`.

Bundle: `/private/tmp/discourse-radio-final-3169db09-ix1Kgb/Radio Group Final Compositions.app`.
Identifier and URL scheme are isolated (`org.discourse.radio-final-3169db09`,
`radio-final-3169db09`). Ad-hoc signing changed only the isolated copy. Strict
deep verification passed; read-back in `signed-entitlements.plist` retains the
debug sandbox/JIT/network capabilities and contains no application/team/APNs
identity. Main's build, the real application, OS security settings and remote
repositories are untouched.

## Reviewed changes and ownership

The six required final compositions use DField, DFieldControl, DFieldContent,
DFieldLabel/choice, DFieldTitle, DFieldDescription, DFieldSet and DFieldLegend as
appropriate. Default uses DLabel. Bare DRadioGroupItem remains the only radio
and focus owner. Field labels invoke its native ActivateIntent, so label/card
activation reaches Radio's Form path exactly once and selecting the active
item is a no-op. There are three uniquely named, merged radio semantics nodes
per composition; disabled items have no tap action and invalid items report
invalid semantics.

The accepted Field owner explicitly approved building fixed horizontal and
vertical fields without LayoutBuilder to permit intrinsic sizing. Responsive
fields retain their existing Flex subtree and breakpoint logic. DFieldGroup,
DFieldSet spacing and other Field APIs are unchanged. Radio's 2px header is a
DFieldContent composition. Frozen values/defaults now match each example.

All nine displayed code snippets are complete runnable apps generated from
their actual widget implementations. The generator's `--check` and source
equality regression prevent undefined sample helpers or divergent snippets.

Radio reset now retains its mounted initial baseline. Controlled changes and
reset never expose unaccepted proposals to synchronous Form save/validation
observers. Error appearance/clear retains the radio subtree and focus without
changing scrollable adopters' layout constraints. Error text is associated
with each radio's invalid semantics. Disabled/read-only/item override policy,
required announcements, borrowed focus, arrows, toggleable Poll votes and
touch bounds remain with Radio; no new public controller or surrogate owner
was introduced.

## Automated and font-loaded verification

- Root and full-profile `flutter pub get --enforce-lockfile`: pass; no lockfile
  changes.
- 239 affected widget/unit/ownership tests: pass, seed `9092026` (`tests.log`).
  Includes Radio, Field, Label, their examples, the real review fixture, Poll,
  flag editing, move/change-owner dialogs, keyboard navigation and Chat Drawer.
- Another 39 Drawer/example/styleguide navigation tests pass with the same seed
  (`styleguide-tests.log`): 278 distinct affected tests in total.
- Root/full `flutter analyze --no-pub`: no issues (`analyze-*.log`).
- `dart format`, generated snippet check and `git diff --check`: pass.
- `flutter build macos --debug --no-pub --target tool/radio_group_review_main.dart`:
  pass (`build.log`).
- Opt-in `tool/radio_group_composition_evidence_test.dart`: pass (`export.log`).
  It loads the installed SF/SF Arabic fonts and exports all seven frozen examples
  in light/dark, focused cards in both themes, and forest/plum cards at 360px,
  RTL, 200% and reduced motion. These are font-loaded widget renders, not native
  desktop screenshots or VoiceOver speech evidence.

| Composition | Native-font logical geometry | Rendered reference |
| --- | --- | --- |
| Default | 112.0094×64; 16px rows | 109.8594×64 |
| Description | 272.2539×142; 42px rows | 264.0859×142.75 |
| Choice Card | 384×65 per card; 211px group | 384×65; 211px group |
| Fieldset / Invalid | 320px width; choices 73px tall | 320×73.75 choices |
| Disabled | 81.4219×73; regular-weight labels | 80.0625×73.75 |
| RTL | 230.3018×142 | 232.0547×142.75 |

Rows remain separated by 8px. Field content has a 2px label/description gap;
descriptions use 21px leading; described indicators sit 1px below the row top.
Full measurements are in `measurements.json` and `reference-geometry.json`.
SF versus reference Geist glyph widths and Flutter's 19px versus CSS 19.25px
label leading remain documented platform typography adaptations. At the frozen
320px Fieldset width, the SF description wraps to two lines while Geist fits
one. The width is not enlarged to disguise that font difference. Live palette
alpha is multiplicative.

## Fresh browser and native acceptance

The approved browser rendered the official reference in light and dark themes:
all seven examples, checked/unchecked/disabled/invalid states, both exterior
focus rings and keyboard card selection. The 360px dark-page capture verifies
natural card-description wrapping. `reference-*.png` contains 17 screenshots;
the geometry JSON measures the visible reference DOM, not inferred source sizes.

The exact isolated native bundle above was inspected under the canonical
desktop lease acquired at `2026-09-09T16:39:11Z`. The 28 `native-*.png` captures
are actual macOS screenshots, distinct from the 18 font-loaded widget exports.

- All seven final examples passed light and dark inspection. Fieldset spacing,
  regular-weight disabled labels, invalid color/rings and logical Arabic layout
  match the mapped source within the typography adaptations above.
- Clicking a card's empty area selected Pro; Down selected Enterprise. Both
  card and radio focus rings remained visible. The disabled first item stayed
  inert; selecting Option 3 and pressing Down wrapped to Option 2.
- The required/read-only sample permitted its editable override, rejected its
  locked item, and displayed validation after the parent cleared selection.
  Controlled Form validation, Email selection/save and reset behaved correctly.
- Forest and Plum previews passed at 360px, 200% text, RTL and reduced motion.
  Pro selection survived the live theme change. The bounded card preview clips
  the third card below its viewport; the complete large-text layout is covered
  by the font-loaded exports. The Arabic native example fits its preview with
  wrapped descriptions and right-side indicators.
- The host's live blue/custom primary, focus and radius tokens are preserved;
  the neutral widget exports isolate reference geometry. This is not a claim of
  pixel-identical host colors or Geist typography. Native disabled opacity
  continues to apply to the whole associated row, an accepted adaptation.

`native-default-keyboard.png` records a focused unchecked Default radio while
Comfortable remains selected after accessibility activation. It is not used as
evidence of arrow selection; actual pointer-plus-arrow checks above cover that.
Native accessibility read-back exposes radio roles, names and exclusive values.
Detailed merged/error/required semantics are covered by tests, not a claimed
spoken VoiceOver session.

## Production audit and cleanup

Actual adopters are PollCard, PostFlagEditor, TopicMovePosts and TopicChangeOwner;
Field's choice sample and Drawer examples also consume Radio. Their application
source was not rewritten by this follow-up. The fresh local-only fixture showed
Morning select/deselect, Inappropriate selection retained through live dark,
RTL and 200% changes, and exclusive Alex-to-Sam / first-to-second destination
selection in the real dialogs. Search `review` returned in-memory fake results;
an unmatched search showed the empty state. Both dialogs were cancelled without
submission. The dialogs inherit their actual overlay theme/scale behavior; the
200%/RTL controls apply to the underlying fixture, not its navigator overlays.

The temporary reference tab was closed and its viewport override reset. The
desktop lease was released to the next queued reviewer. The isolated app's
quit shortcut was affected by the active AZERTY layout; the next lease holder
received its exact bundle/process identity for approved-CUA cleanup. The Card
reviewer confirmed native application-menu Quit and an absent bundle in CUA's
app inventory; a read-only process check also confirmed the executable stopped.
This was an input/cleanup incident, not a component crash or a production app mutation.
No VoiceOver speech, iOS device, Linux or cross-platform native claim is made.

## Latest-main integration

Candidate `eb8dc183724d8b36857568d03e653afb03ab3791` starts from local main
`1770316fcc06f665747d6598f43dde1d093f4420` and merges the complete reviewed
history, including native acceptance commit `24a0f84b`. No main-into-worktree
merge or history replacement was used. Progress reconciliation preserves all
64 component records and every unrelated workflow field.

Radio, Field, Label, the Radio examples and generated snippets, the real
Poll/flag/owner/move adopters, Radio keyboard/Chat ownership, Drawer examples,
the native fixture and both profiles' package/lock inputs byte-match inspected
source `3169db09`. New main changes concern Breadcrumb, Toggle Group and Toast
diagnostic tests, not the inspected Radio behavior. Their exports/registrations
and production changes are retained.

All 52 Radio/Field/real-fixture/styleguide-navigation tests pass again on this
candidate, seed `9092026` (`integration-tests.log`); these are a subset of the
278 distinct affected tests above, not 52 additional tests. Final root/full
analysis is clean (`integration-analyze-*.log`); generated snippets and diff
checks pass. No second native run is claimed or needed for unchanged behavior.
The final no-fast-forward merge was performed from the main checkout on `main`:
`1f3b73293a842e65a5b7675e99496322c7595589`, reviewed branch head
`bef32b012c34a5f2c05a8143543caee705a239fc`. Both separate final-composition
records are merged; only this task's active queue entries were removed. The
original component merge remains `62e7d25adeb8c125faca2a6476cbb800660a2025`.
No push or remote/release operation was performed.
