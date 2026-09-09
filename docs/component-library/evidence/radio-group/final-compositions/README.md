# Radio Group final compositions — 2026-09-09

Status: automated/source review complete; native/reference desktop acceptance
awaiting the canonical FIFO lease. No follow-up merge is claimed yet.

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
- Root/full `flutter analyze --no-pub`: no issues (`analyze-*.log`).
- `dart format`, generated snippet check and `git diff --check`: pass.
- `flutter build macos --debug --no-pub --target tool/radio_group_review_main.dart`:
  pass (`build.log`).
- Opt-in `tool/radio_group_composition_evidence_test.dart`: pass (`export.log`).
  It loads the installed SF/SF Arabic fonts and exports all seven frozen examples
  in light/dark, focused cards in both themes, and forest/plum cards at 360px,
  RTL, 200% and reduced motion. These are font-loaded widget renders, not native
  desktop screenshots or VoiceOver speech evidence.

| Composition | Current native-font logical geometry |
| --- | --- |
| Default | 112.0094×64; 16px rows |
| Description | 272.2539×142; 42px rows |
| Choice Card | 384×65; 16px indicator, 8px dot, both 3px exterior focus rings |
| Fieldset / Invalid | 320px width; choices 73px tall; header gap 2px |
| Disabled | 81.4219×73; regular-weight labels |
| RTL | 230.3018×142 |

Rows remain separated by 8px. Field content has a 2px label/description gap;
descriptions use 21px leading; described indicators sit 1px below the row top.
Full measurements are in `measurements.json`. SF versus reference Geist glyph
widths and Flutter's 19px versus CSS 19.25px label leading remain documented
platform typography adaptations. Live palette alpha is multiplicative.

## Production audit and remaining acceptance

Actual adopters are PollCard, PostFlagEditor, TopicMovePosts and TopicChangeOwner;
Field's choice sample and Drawer examples also consume Radio. Their application
source was not rewritten by this follow-up. The current real-surface tests pass;
the original native evidence remains historical, not relabelled as a fresh run.

Native acceptance will use the existing local-only fixture with in-memory fakes
and the real styleguide/adopters. Desktop browser/native inspection, lease
release, final source reconciliation and local main merge are still pending.
No VoiceOver speech, iOS device, Linux or cross-platform native claim is made.
