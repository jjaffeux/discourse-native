# Component library progress

Generated from [progress.json](progress.json). Read the [brief](brief.md), [conventions](conventions.md), [catalogue](catalogue.json) and [inventory](inventory.md).

Coordinator task: `01a0816f-d4e0-7f93-9d6b-baeaf6961181`. Reference: 2026-09-08.

Foundation: **merged** on `codex/component-library-foundation`. Merge: 1b130d3323f9b7619bdead025fd76a57be402a97.

## Current review queue

**46 of 64 components are merged locally.** 18 existing components are in progress; 0 are planned.

Each component has an independent review task that owns fixes, remaining verification and the local main merge. See the [review and merge procedure](review-and-merge.md).

Branch preparation does not mark a component merged or visually verified.

| Component | Current stage | Branch head | Reviewer task |
| --- | --- | --- | --- |
| toggle-group | independent review | 7f4de6a8 | 01a085e6-4bb7-7e13-9e2a-98992292b4b3 |
| alert-dialog | Implementation and checks | — | — |
| sheet | independent review | 88e3e8c2 | 01a0862f-b27f-76d2-a441-8a77594aedc8 |
| drawer | independent review | 8377cebe | 01a08643-3074-72e1-8b18-a2266dd724e6 |
| button-group | independent review | 97554ada | 01a085f4-2a6b-7c82-9dc3-c9b14d76b355 |
| combobox | independent review | 55dcf257 | 01a08628-7889-7dd2-a93c-c854fcdf1e9a |
| context-menu | independent review | e9b29538 | 01a0861f-38ca-7122-b18f-5f286ab90ccb |
| menubar | independent review | 10b63f75 | 01a08628-7042-7173-a37d-7f1f04eade66 |
| navigation-menu | independent review | 57ee8393 | 01a08621-0e86-7a62-82b9-6a8eca71227f |
| breadcrumb | independent review | cd9c542d | 01a08623-9d6e-7393-b3e8-fb4c402b8c71 |
| pagination | independent review | 2167c871 | 01a08629-4841-73d0-a5a6-c723f253b4b0 |
| calendar | independent review | 4b86c11a | 01a08631-7574-70b0-a98f-4e7217e03209 |
| date-picker | Implementation and checks | — | — |
| attachment | independent review | 7c465bd1 | 01a085f6-d243-7d73-8a4a-c1a1225d3a8f |
| message | independent review | 93729c14 | 01a08627-8995-7b43-9c06-8a219d472681 |
| message-scroller | independent review | 1e49e130 | 01a08639-b066-7882-85f5-a7729bfd111b |
| data-table | independent review | 679db98d | 01a0863a-ff5a-7fe1-bc5c-5f0809bfd69a |
| input-otp | Implementation and checks | — | — |

## Component implementation

| # | Component | Status | Task | Branch | Dependencies | Merge |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | direction | merged | 01a0818b-e20a-77d0-bb99-77691899dad7 | codex/ui-direction | — | e69458861e83f3989e2f06dd177805c572740a5a |
| 2 | typography | merged | 01a081e5-0bef-70a1-9ae3-7717028403e0 | codex/ui-typography | direction | 20f42345002e9b0946d1690acd6de6f83b7aa681 |
| 3 | spinner | merged | 01a08213-9960-79f1-8d90-9626f24a4b5a | codex/ui-spinner | — | 07a085c175c57c3e6b4868fd700885f8bfe5212c |
| 4 | kbd | merged | 01a0821b-27cc-7013-affb-99cae203b2a8 | codex/ui-kbd | typography | 8d0936ff13346650682f3b04e55b612074bd3f66 |
| 5 | tooltip | merged | 01a0829c-ba0d-7282-a010-7e26f190dd4f | codex/ui-tooltip | kbd | f0aee9adc5f0d64adfd9aa5e285830e2a143a1e7 |
| 6 | button | merged | 01a083ac-5fd5-78b1-9263-7e3218a878b6 | codex/ui-button | spinner, tooltip | eb6d8ea0d9417f0edc830c5ce715b52436f12c94 |
| 7 | separator | merged | 01a08213-a2e5-7692-a127-f09d2a03094b | codex/ui-separator | — | 855f131dc0bdaadaf5aea034a9cd78dbbe06b7b1 |
| 8 | label | merged | 01a0825a-9fe1-7700-878c-f448801c0851 | codex/ui-label | typography | 9bbc2806020646451fd1c283d347283fe4e45f67 |
| 9 | badge | merged | 01a083ac-c98c-7fe0-878d-54ee3bcbebb9 | codex/ui-badge | spinner | 916580e72e11de6a6b7872c41d5c4d92e27e9635 |
| 10 | input | merged | 01a083ad-3168-7c01-b35a-7271f9fe6326 | codex/ui-input | label, button | 7df72ef294826616e8ba24c31c6129d8e9041fec |
| 11 | textarea | merged | 01a08437-208f-7332-b373-192eaada5844 | codex/ui-textarea | label | 6fbecbcefe1cac3fcbe15f8b9af20fa0569682d3 |
| 12 | checkbox | merged | 01a083ad-91cf-7e91-9083-a861d5c4fa28 | codex/ui-checkbox | label | 13466a062d19c247905ccc65adc615c8d0d6273d |
| 13 | radio-group | merged | 01a083ce-313b-7da0-aa51-3687fd556604 | codex/ui-radio-group | label | 62e7d25adeb8c125faca2a6476cbb800660a2025 |
| 14 | switch | merged | 01a083ce-319b-7bc3-a5c9-371087710718 | codex/ui-switch | label | e2d7743cdeaed5be8ad8adbb896e2de8f655ca6d |
| 15 | toggle | merged | 01a08567-ac29-7dd0-ba78-1717a5235bd0 | codex/ui-toggle | button | a492253dc0abaed3f424df1b59c5a11b266d5b60 |
| 16 | toggle-group | review_ready | 01a085ce-ca89-7af3-8375-946721be90c6 | codex/ui-toggle-group | toggle | — |
| 17 | slider | merged | 01a083ce-313a-7362-ada6-57dc14221509 | codex/ui-slider | label | e646022a0fd5524daab612e3bbfa9fe3de6db7a5 |
| 18 | progress | merged | 01a083ce-313e-7f70-a1a8-e645f31235c8 | codex/ui-progress | label | 15da313eb259c51c6bbed5974895b6616c32c84c |
| 19 | skeleton | merged | 01a08213-b4ca-77e1-a2aa-8a490808243e | codex/ui-skeleton | — | fc43a2bdb09ba15b703c0a84863941cde7b009d5 |
| 20 | aspect-ratio | merged | 01a082a9-b9d4-79f0-8a0d-cc48e700cc67 | codex/ui-aspect-ratio | — | 60a3c432c8ba92b9676125b9527776b2d55c5a13 |
| 21 | avatar | merged | 01a082d2-4434-73b1-8ab4-88c9b2ba9b66 | codex/ui-avatar | — | 5c78eb9d5c9db5f37ac7eaf8deab2233944dcbd0 |
| 22 | card | merged | 01a082d9-6c59-7443-8e64-f76105fd5e56 | codex/ui-card | typography | a73f465ac86105fdda35f5b56f8b491da4b3936d |
| 23 | empty | merged | 01a0843e-76da-7911-ac98-49bd6dba8384 | codex/ui-empty | typography, avatar, kbd | fb790fcd2356a9acc7cd488ca587eaafb4d91ccb |
| 24 | item | merged | 01a084bf-dd8a-7c13-86dd-63f2e60d20cd | codex/ui-item | separator, avatar, button, dropdown-menu | 6df0ab4469e4a3f9619518c56bd6e8db847e6b2c |
| 25 | table | merged | 01a0844a-0669-7780-92e8-33cc4314f64a | codex/ui-table | typography | 082fcc55ab85d3bd4012c6bd24c647c1febd7d2a |
| 26 | scroll-area | merged | 01a083e1-420b-7711-b8e8-f268576dcc3b | codex/ui-scroll-area | separator | 655be577246f1f247e1e71199d32add8366deffc |
| 27 | collapsible | merged | 01a08445-7647-7a83-a366-e06252405043 | codex/ui-collapsible | — | 985b4efdf4dd5e4502c98d4c2c0332df8e344982 |
| 28 | accordion | merged | 01a0859b-73ff-7190-8c59-b71fe74d2b2f | codex/ui-accordion | collapsible | f3aa5074a848a6f8ee793de7323cf9de766be1d4 |
| 29 | tabs | merged | 01a08560-5018-7e52-aa73-14ff2ce6cc28 | codex/ui-tabs | button | 7e6bf1234fcd55aced4037c7e36946d017fe5c79 |
| 30 | resizable | merged | 01a083e2-4063-7c30-89ea-fa664ff9c943 | codex/ui-resizable | — | eff4770f10b73dd6fb1e5eed17b374d68b68bfed |
| 31 | popover | merged | 01a084fb-b319-7053-8265-8cdfd4e2c2bd | codex/ui-popover | button | dc6ab75fe99f2af8b401bae60285fdbe65e8012a |
| 32 | hover-card | merged | 01a085fd-5d84-7e40-bce5-c4ed49e7f2d8 | codex/ui-hover-card | popover, avatar | de39686f2a5d75651ef37268edb44adb6376cd7c |
| 33 | dialog | merged | 01a084fb-b319-7053-8265-8cb4db577932 | codex/ui-dialog | button | 6a0aaa54d86aaa492681f5cc4dcd32b5e2feefe3 |
| 34 | alert-dialog | in_progress | 01a085d9-7909-7fd0-b1b8-30914ac699b4 | codex/ui-alert-dialog | dialog | — |
| 35 | sheet | in_progress | 01a08606-5dcc-7381-bbbb-719367c8f574 | codex/ui-sheet | dialog | — |
| 36 | drawer | in_progress | 01a08606-5dd1-75a2-9dbb-a652188d7bd5 | codex/ui-drawer | dialog | — |
| 37 | select | merged | 01a085bb-1d11-7f52-a7bd-667348469087 | codex/ui-select | popover, scroll-area | 57bbeb94368649a4665483180e4f5c84b5f33856 |
| 38 | native-select | merged | 01a083f3-9a01-7c71-9931-3674b85e81b3 | codex/ui-native-select | label | 0cdec859288cb2fa0369f64e1a9c1c022dc033e4 |
| 39 | field | merged | 01a084bf-dd8a-7c13-86dd-63d635b7bf97 | codex/ui-field | label, separator | 5cd7f3694498e4e09e3c114639baca834b56705e |
| 40 | input-group | merged | 01a085af-d606-7281-ac25-34c83adc855e | codex/ui-input-group | input, textarea, button, kbd, spinner, field, dropdown-menu, popover | d1de717b1e2d1eeaf06d86dafe1452662d05e368 |
| 41 | button-group | in_progress | 01a08581-831f-7751-b714-096b5aebf86a | codex/ui-button-group | button, separator | — |
| 42 | command | merged | 01a085bc-5eda-7712-9863-190bf6846bcc | codex/ui-command | input, dialog, scroll-area | 090d4f5448c2d8f87183d62092c6a5393ce90bd6 |
| 43 | combobox | in_progress | 01a085fd-5d83-79c3-b598-bd49a5152023 | codex/ui-combobox | input, popover, command | — |
| 44 | dropdown-menu | merged | 01a085b3-05fc-79f1-bde2-dc6936b2bcd4 | codex/ui-dropdown-menu | popover, checkbox, radio-group | 5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787 |
| 45 | context-menu | in_progress | 01a08606-5dce-7b91-9ee6-7713872f1fa7 | codex/ui-context-menu | dropdown-menu | — |
| 46 | menubar | in_progress | 01a08606-5dd4-7b80-b330-d7ebfff967f9 | codex/ui-menubar | dropdown-menu | — |
| 47 | navigation-menu | in_progress | 01a08606-5dd7-73d2-b6f5-15b1bfbc34e7 | codex/ui-navigation-menu | popover | — |
| 48 | breadcrumb | in_progress | 01a08606-c290-7772-8b90-e5358efa6752 | codex/ui-breadcrumb | button, dropdown-menu | — |
| 49 | pagination | in_progress | 01a08606-c9d5-7741-bfe0-e4ff531ff9b7 | codex/ui-pagination | button, select | — |
| 50 | calendar | in_progress | 01a085fd-5d83-79c3-b598-bd3ffc5b366e | codex/ui-calendar | button, select | — |
| 51 | date-picker | in_progress | 01a08606-ca30-7bc1-8e27-69575273d443 | codex/ui-date-picker | calendar, popover, input | — |
| 52 | carousel | merged | 01a08567-ac29-7dd0-ba78-16f423c97dd9 | codex/ui-carousel | button | 3ec0c089d273029ff901d9155eba93e17c4d3a23 |
| 53 | toast | merged | 01a0857a-fcd6-7880-90c0-501e72f034df | codex/ui-toast | button | d454c8f62fb4ab8718b3a32b2743556f2f78609d |
| 54 | alert | merged | 01a08454-55a6-7681-8da9-bec8b23899a4 | codex/ui-alert | typography | a07ab617436f24f2e8116762f58b0b28e5d36918 |
| 55 | attachment | in_progress | 01a085d4-9afd-7082-8081-f8b1f8f66287 | codex/ui-attachment | dialog, spinner | — |
| 56 | marker | merged | 01a0842f-af4f-7341-95c2-06a97f4ff0c4 | codex/ui-marker | spinner | fc92f4e69042191eff5d39d52c1355a6d6a87da7 |
| 57 | bubble | merged | 01a085d9-7909-7fd0-b1b8-30a76c6ab2af | codex/ui-bubble | button, collapsible, popover, tooltip | c3d6ae97af486134b32067aecc29f7191b05367d |
| 58 | message | in_progress | 01a08606-ca30-7bc1-8e27-693690217969 | codex/ui-message | attachment, avatar, bubble, marker | — |
| 59 | message-scroller | in_progress | 01a08606-ce86-7be2-b92f-59676b40cb40 | codex/ui-message-scroller | message, scroll-area | — |
| 60 | chart | merged | 01a08400-ced8-7f22-a1aa-4955c7d28383 | codex/ui-chart | tooltip | ff57007163df986741ce422e4674d267012c8093 |
| 61 | data-table | in_progress | 01a08606-ca45-73b1-9be1-7486d4e3fe1d | codex/ui-data-table | table, pagination, checkbox, input, dropdown-menu | — |
| 62 | sidebar | merged | 01a08352-7665-7f90-a637-75478a83ea53 | codex/ui-sidebar | tooltip, separator, skeleton | 93bfcf65f64868c92340f9aec8236d77585c3cd8 |
| 63 | input-otp | in_progress | 01a08606-ca44-78f3-98f2-d147200278ef | codex/ui-input-otp | input, field | — |
| 64 | questionnaire | merged | 01a08606-ca34-7a13-b7ec-79b90b5ebd8f | codex/ui-questionnaire | field, button, progress, card, dialog, native-select | 4217ffe98a37c61510d464f21cfef87c563e82f1 |

## Decisions and evidence

### Foundation

Status: merged. Task: 01a0816f-d4e0-7f93-9d6b-baeaf6961181. Branch: codex/component-library-foundation.

**acceptanceCriteria**

- Freeze every current All Components catalogue entry with reference URLs, documented sections/variants, dependency facts and hashes.
- Provide searchable catalogue and runnable baseline examples with usage, theme, viewport, text-scale, direction, motion and reset controls.
- Expose the styleguide from the bottom-left app rail, including before site load; preserve the mounted workspace on return.
- Verify the theme mapping, interaction and access behavior before the foundation merge.

**decisions**

- Keep D-prefixed public widgets in discourse_ui.dart; host maps palette into DTokens.
- Existing Button, Tooltip and Select are baseline examples until their sequential tasks replace them.
- Use native Flutter styleguide route and independent preview Navigator; no networking or credentials in examples.
- Coordinator follow-up: the styleguide Reset action now uses public DButton. The ordinary-action adoption guard retains explicit per-file exceptions for the native Direction menu and Typography rich-text focus examples, including their displayed usage snippets; no general app-action exemption was added.

**migrations**

- Bottom-left InstanceRail footer opens the styleguide; root workspace remains mounted.

**verification**

- Flutter 3.47.2 / Dart 3.13.2; flutter pub get --enforce-lockfile passed without lockfile changes.
- dart format --output=none --set-exit-if-changed on all foundation Dart files passed.
- flutter analyze --no-pub passed with no diagnostics.
- flutter test test/styleguide test/app_theme_test.dart test/app_settings_page_test.dart test/site_theme_app_test.dart --test-randomize-ordering-seed=random: 50 tests passed, seed 905880268.
- Tests cover catalogue/order accounting, search by documented capability, no-match state, local example state across theme/width changes, reset, 200% text at 320px and 1200px, Escape, bottom-left semantic label and hit target, entry before loading/with no sites, retained draft on return, default/custom tokens, reduced motion and live overlay theme.
- Built and ran macOS standalone styleguide. Fixed native launch-screen dismissal and Material selection/ink ownership discovered during runtime inspection.
- Inspected macOS dark/current and light previews, keyboard selection of Forest site palette, 360px viewport and 200% preview text; exercised example action and visible focus. Used isolated temporary app identity org.discourse.native.styleguide to avoid competing with normal Discourse navigation.
- Observed the styleguide palette button in the actual app rail; route entry/exit and retained workspace were verified through the real InstanceRail in widget tests.
- git diff --check passed.
- After Spinner exposed the stale baseline guard, coordinator ran flutter test --no-pub test/d_button_adoption_test.dart test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=random: 9 passed, seed 1006078620, including actual Direction/Typography state preservation and reset. Touched files are formatted, flutter analyze --no-pub and git diff --check pass. Logs: /private/tmp/component-button-adoption-fix.log and /private/tmp/component-button-adoption-fix-analysis.log.
- Coordinator rebuilt the real repository-root macOS app after Label and Aspect Ratio integration: flutter build macos --debug --no-pub succeeded at main 4b5bd8b7d6fecb5a11d01732e8fe7ff7bbba0b98 with all seven currently merged catalogue components. Artifact: /Users/joffreyjaffeux/Code/discourse-native/build/macos/Build/Products/Debug/Discourse.app. Log: /private/tmp/discourse-main-label-aspect-build.log. The real account app was not launched; this verifies compilation and bundling, and does not diagnose the user-reported startup problem.
- Coordinator built the real repository-root macOS app after Spinner, Tooltip and Avatar integration: flutter build macos --debug --no-pub succeeded at main 6976336acc1cf7dd1a44da5bfa4ba7dbdf3dd799 (ten merged catalogue components). Artifact: /Users/joffreyjaffeux/Code/discourse-native/build/macos/Build/Products/Debug/Discourse.app; log /private/tmp/discourse-main-avatar-tooltip-spinner-build.log. Full-profile flutter pub get --enforce-lockfile and flutter analyze --no-pub also passed, with no lockfile/pin changes and analysis clean in 2.4s. This is compilation/bundling verification only; the real account app was not launched and the user-reported startup issue remains unverified.
- Final four-component batch checkpoint: the real repository-root macOS app built successfully with flutter build macos --debug --no-pub at main ea58497479e75efce7a86ebe95c784cd3c974846, containing all eleven merged catalogue components. Artifact: /Users/joffreyjaffeux/Code/discourse-native/build/macos/Build/Products/Debug/Discourse.app; log /private/tmp/discourse-main-four-component-batch-build.log. Coordinator verified all four reviewed branch heads are ancestors of main, their merge commits have two parents, public components/examples are present and marked implemented, and the native inspection owner/queue are empty. All requested batch work is complete; work is paused for user review. This build does not diagnose the user-reported startup issue; the real account app was not launched.
- After final Button, Badge and Input integration, the real repository-root macOS app builds successfully with flutter build macos --debug --no-pub at main e5bee6d59479627082aaa2c95015df0282738383 (15 merged components). Artifact: /Users/joffreyjaffeux/Code/discourse-native/build/macos/Build/Products/Debug/Discourse.app; log /private/tmp/discourse-main-input-badge-build.log. Compilation/bundling verified only; the account app was not launched and the user-reported startup issue remains unverified.
- Real macOS app rebuilt successfully after final Radio Group and Checkbox integration at source main1532aaa2 (17 merged components). Artifact /Users/joffreyjaffeux/Code/discourse-native/build/macos/Build/Products/Debug/Discourse.app; log /private/tmp/discourse-main-checkbox-radio-build.log. Only progress metadata changed during the build. This verifies compilation and bundling; the account app was not launched.

**limitations**

- iOS and Linux devices were not run during the foundation phase. No new native platform dependency was introduced.
- Select remains a baseline catalogue implementation awaiting its task. Button and Tooltip are implemented, adopted, verified and merged.

### shadcn visual fidelity correction

Status: merged. Task: 01a0816f-d4e0-7f93-9d6b-baeaf6961181. Branch: codex/ui-shadcn-fidelity.

**acceptanceCriteria**

- Match reference geometry, explicit typography metrics, semantic colors, relative radii, borders, artwork, states and motion; idiomatic Flutter interaction owners do not justify a different visual design.
- Recheck merged Direction, Typography and Separator; correct unjustified differences and inspect actual rendered examples before merging corrections.
- Require official registry/source mappings and rendered visual comparison in every current and future component task.

**decisions**

- Direction owns no intrinsic visual styling. Separator source confirms a one-pixel square-ended border-colored horizontal/vertical rule, matching the implementation.
- Typography corrections restore 800-weight h1, tight heading tracking, 28px paragraph leading, 14px Small leading, reference inline-code padding, list indentation, base text in lists/quotes/tables and heading-specific article gaps.
- Kbd, Spinner, Skeleton and Label tasks received the clarified design specification before merge. Native desktop inspections remain serialized.

**verification**

- Official frozen Typography Markdown preserved verbatim with original SHA256; Separator registry source captured and hashed with upstream MIT license.
- Initial focused typography, four-palette examples, nonlinear text scaling and adoption checks: 17 passed. Static analysis passed without diagnostics.
- Final impact run covered Typography, all styleguide groups, scaling boundary, adoption guard, Settings, Add-a-site and Poll: 73 passed, one existing styleguide navigation test needed its outer scroll position targeted explicitly after note/preview geometry changed (seed 446229861). The repaired Typography preview test passed (seed 3779910838); no production scrolling behavior changed.
- The final run includes the new original-text specimen and balanced-heading layout check. flutter analyze --no-pub passed with no diagnostics.
- Isolated macOS build completed at /private/tmp/discourse-shadcn-fidelity.4xigijr8/app/build/macos/Build/Products/Debug/Shadcn Fidelity Review.app using real Settings, EmptyState and Poll fixtures with in-memory stores. Native visual inspection is pending the shared desktop slot.
- Compared the native original-text specimen at 768px Light and 360px Dark with a browser reconstruction of the exact frozen CSS utilities using corresponding app colors and a system font. This was a local reconstruction because the original Typography HTML now redirects; no claim of pixel-identical live-site rendering is made.
- Inspected the real EmptyState at 200%, actual Settings heading/layout with visible Tab focus, and real Poll dialog in Plum at 200%. Escape dismissed the dialogs; all stores and data were isolated in-memory fixtures.
- Native visual review prompted exact CSS border-box spacing (1px h2 border in addition to 8px padding; 2px quote border in addition to 24px inset) and a guard against balancing that introduces additional breaks within words at 200%. Rebuilt and re-inspected the final source at 360px/200% with RTL/reduced motion, including the corrected heading and directional quote.
- Final component and all eight Typography examples passed 14 focused tests after the border correction, then 14 after the native large-text refinement. Final flutter analyze --no-pub passed. The native build source was byte-compared with the reviewed source.
- Native application Info.plist and ad-hoc signature verified: Shadcn Fidelity Review, org.discourse.shadcn-fidelity, isolated discourse-shadcn-fidelity URL scheme. All runner/signing/fixture adjustments were confined to /private/tmp. Native app quit and comparison tab closed after inspection.
- Coordinator reviewed final branch aee3b24c113b2c5cc1793fbff9973d77ffca5c4c and reconciled only progress/contract metadata against main. All reviewed Dart code, tests and preserved reference source match the native-inspected branch exactly.

**limitations**

- The app keeps its configured fonts, palettes and radius. Native font shaping and soft line breaks can differ from browser rendering. Plain h1 uses a conservative compact measure; rich headings retain native span layout so selection/copy remains intact.
- The original Typography live HTML redirects to Typeset; comparison used the preserved original source and an explicitly identified local CSS reconstruction. No automated pixel-exact cross-renderer comparison is claimed.
- iOS/Linux devices and VoiceOver speech were not inspected for this follow-up. Normal Flutter semantics and selection behavior remain covered by the focused tests; the styleguide AX tree exposed fewer nodes than the initial app fixtures.

### Documentation layout and Sidebar adoption

Status: merged. Task: 01a0816f-d4e0-7f93-9d6b-baeaf6961181. Branch: codex/styleguide-shadcn-layout.

**acceptanceCriteria**

- Use the actual DSidebar library component for documentation navigation on desktop and mobile.
- Match measured shadcn documentation density: 30px navigation visuals, 30/36px page titles, a 640px article and restrained preview/code panels.
- Keep app palette previews and sample state independent of documentation theme, code visibility, navigation resizing and preview settings.
- Preserve searchable frozen capabilities, keyboard navigation, mobile dismissal, text scaling, example reset and the mounted app workspace.

**decisions**

- The user authorized Sidebar ahead of the paused catalogue specifically because the styleguide needs it. Other components and the final audit remain paused.
- Documentation uses a local neutral light/dark DTokens theme and the host font. Example themes continue to resolve from the original host theme; no app setting is changed.
- Short page introductions replace engineering notes at the top. Baseline components remain labelled; full notes and reference coverage stay available in a disclosure.
- Reference measurements and native review are recorded in docs/component-library/styleguide-design.md.
- Explicit viewport presets retain their actual logical widths and scroll within the 640px article. A visible scrollbar supports mouse dragging.
- Compact Sidebar examples use a 500px breakpoint and a 500px-tall preview; the public component default remains 768px.

**migrations**

- ComponentStyleguidePage adopts DSidebarProvider, DSidebar, content/groups/menus/buttons/header and trigger.

**retainedAlternatives**

- Documentation-only compact toolbar controls retain native Flutter interaction owners until their owning Button/Select catalogue work. They are private to the styleguide and do not replace public components.

**verification**

- 160 affected tests passed at f19ded8b: flutter test --no-pub test/styleguide test/d_sidebar_test.dart test/d_button_adoption_test.dart --test-randomize-ordering-seed=2847364191. Log: /private/tmp/styleguide-review-final-tests.log.
- After the final explicit-scrollbar change, all 14 styleguide-page tests passed with seed 1283551953, including mouse dragging a 1024px preview, returning to 360px, retained sample state, and real DSidebar desktop/mobile composition. Log: /private/tmp/styleguide-preview-scroll-tests.log.
- Root and full-profile flutter analyze --no-pub are clean; formatting and git diff --check pass. Full-profile locked pub get passed without changing any lockfile or SDK pin.
- Final standalone macOS build passes at 6d8c63edcbcd8372408a4a5ec8ccc9d8479e5bbb. Its isolated kernel matches the workspace build: SHA256 90f5d1b5d4689ca2a660441be25859071c9f9c9f15bf3dc10817147efc373342. Deep strict signature verification passes.
- Native dark/light documentation, independent preview theme, code/state retention, 360px/200% swatches, centered Card, actual narrow-window Sidebar search/selection, Escape/focus return, and compact desktop Sidebar demo were inspected. Exact source checkpoints, evidence and limits: docs/component-library/styleguide-design.md.
- Real application flutter build macos --debug --no-pub passed from 07539c2c57533835094f70b02e07cfbbba92896a in the isolated coordinator checkout. Its complete Git tree f288c94ea575d48a3585b1ca6355e4d35ce0ddf3 exactly matches merged main 0eb34a59ab5de86a1c28c6ebbf08ccb746dab9a5. The running app in the main checkout build directory was preserved. Log: /private/tmp/styleguide-real-app-final-build.log.
- Coordinator exported and visually inspected Light/Dark Foundations at 1270×847 logical pixels / 2× output with the Flutter widget-test renderer and explicitly loaded SFNS/Material fonts. Source c5d37bd1 has identical styleguide/Sidebar code to final 6d8c63ed. Export harness completed successfully; /private/tmp/styleguide-b104-render.log. PNGs/provenance: /Users/joffreyjaffeux/.codex/visualizations/2026/09/08/01a0816f-d4e0-7f93-9d6b-baeaf6961181/styleguide-current-{dark,light}.png and styleguide-preview-provenance.json. This is a test-renderer preview, not native desktop verification.
- Coordinator inspected the live official Button documentation in CUA Chrome at a matched 1270×847 viewport after discovering browser control remains available independently of the Mac lock. The live h1 measures 30px / 36px, weight 600 and -0.75px tracking, matching the documentation shell specification. Compared live dark reference canvas/panel/navigation with the current Flutter test export. Temporary browser viewport was reset and the created tab closed before granting Button the browser-only comparison slot. This still does not verify native application interactions.

**limitations**

- The Mac locked before the final explicit-scrollbar screenshot. Its appearance and native drag remain unverified; the mouse-drag widget test passes.
- Native synthetic Cmd/Ctrl+K and horizontal-scroll attempts produced no visible response. Keyboard bindings pass widget tests. Some native AX trees were sparse; no spoken VoiceOver, iOS/Linux device or pixel-diff claim is made.
- The docs shell is the first Sidebar adoption. Forum and Chat retain their domain-specific adapters. Button, Select, Input, Sheet and other remaining catalogue entries are still unfinished.

### direction

Status: merged. Task: 01a0818b-e20a-77d0-bb99-77691899dad7. Branch: codex/ui-direction.

**acceptanceCriteria**

- Expose DDirection through discourse_ui.dart with explicit LTR/RTL, inherited direction, nearest-scope lookup and optional lookup, all using Flutter Directionality as the only provider.
- Update dependent layout and lookup consumers on live direction changes; preserve child state, text editing, focus, native reading-order keyboard traversal and directional semantics across nested overrides.
- Keep host light/dark/custom themes, text scaling and reduced-motion preferences intact; demonstrate directional layout and fixed LTR content boundaries without introducing rendering or focus ownership.
- Provide runnable public-API styleguide examples and usage covering installation, explicit direction, inherited lookup (useDirection adaptation), nested overrides, live changes, editable content and a live overlay.
- Audit core and all bundled plugins/packages for direction usages, migrate appropriate UI providers/lookups, and record retained native/markup alternatives and removed obsolete ownership.
- Pass touched-code formatting, static analysis and focused component/styleguide/downstream tests; inspect isolated macOS examples in representative themes and widths; record device limitations before review_ready.

**decisions**

- D-prefixed DDirection wraps Flutter Directionality; TextDirection is the public value type. A null textDirection inherits the nearest Flutter/provider scope. DDirection.of and maybeOf are idiomatic equivalents of useDirection; of requires a direction ancestor and maybeOf returns null when absent.
- Keep an identical Directionality child structure when explicit/inherited direction changes so state and borrowed resources remain mounted. Direction has no colors, animation, input state, overlay, controller or focus node of its own.
- The frozen link/outline button variants and email/password/submit types belong to the reference demonstration, not Direction properties; demonstrate real native input/action composition without implementing those separate catalogue components.
- Installation is the existing public Dart barrel import; no package, Flutter-pin or lockfile change. Direction owns no hover/pressed/disabled/loading/error state, focus traversal, theme, animation or overlay lifecycle; composed native controls own those behaviors.
- Three real examples cover live inherited/explicit direction with retained local editing, nested RTL/LTR URL boundaries and nearest lookup, and a MenuAnchor whose overlay observes the native scope. Native buttons/menu items remain sample composition, not completed catalogue Button/Menu components.
- All acceptance criteria pass for implementation, focused widget/regression checks and the native scenarios recorded below; iOS/Linux devices and live authenticated app screens remain explicitly unverified.

**migrations**

- styleguide_page.dart: replace the preview Navigator Directionality provider with DDirection; the existing Right to left control updates all mounted examples.
- Core: migrate 9 direction lookups in main_content.dart, resizable_pane.dart, users_page.dart, composer_panel.dart, topic_list_navigation.dart, topic_header_tags.dart and forum_tabs_bar.dart to DDirection.of through discourse_ui.dart, preserving reading-lane physical alignment, resize signs, toolbar arrows and text measurement.
- Chat plugin: migrate 3 chat_drawer.dart lookups for composer overlap geometry, resize delta and resize cursor to DDirection.of without changing plugin state, permissions or callbacks.
- Audited lib, every lib/src/plugins module, packages (including vendored Dart sources), and profiles for Directionality/TextDirection/direction boundaries. There was no obsolete custom Direction implementation to delete; the one direct app provider and all 12 direct app lookups were replaced.

**retainedAlternatives**

- Flutter WidgetsApp/MaterialApp remains the host locale-direction owner. DDirection reads that native provider; generic components do not impose a new global LTR default.
- event_calendar_data.dart retains the TextDirection supplied by kalender to its frame generator. ShapeBorder paint/path overrides and TextPainter/TextDirection values retain the native API types; these are caller-supplied rendering contracts, not competing providers.
- Cooked HTML/Markdown, code and URL rendering are unchanged; content direction remains owned by their renderer/markup. The nested example explicitly fixes its URL island to LTR. There were no custom code/URL Directionality wrappers to replace.
- Existing baseline Button/Tooltip/Select owners remain for their later catalogue tasks; native MenuAnchor owns the demonstration overlay.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 confirmed. flutter pub get --enforce-lockfile passed with no lockfile changes.
- dart format --output=none --set-exit-if-changed lib/discourse_ui.dart lib/src/plugins/chat/chat_drawer.dart lib/src/shell/composer_panel.dart lib/src/shell/forum_tabs_bar.dart lib/src/shell/main_content.dart lib/src/shell/resizable_pane.dart lib/src/shell/topic_header_tags.dart lib/src/shell/topic_list_navigation.dart lib/src/shell/users_page.dart lib/src/styleguide/component_examples.dart lib/src/styleguide/examples/direction_examples.dart lib/src/styleguide/styleguide_page.dart lib/src/ui/components/d_direction.dart test/resizable_pane_test.dart test/styleguide/direction_examples_test.dart test/styleguide/styleguide_page_test.dart test/ui/d_direction_test.dart: all 17 files already formatted.
- flutter analyze --no-pub passed with no diagnostics, including the new tests and all core/plugin imports.
- flutter test --no-pub test/ui/d_direction_test.dart test/styleguide/direction_examples_test.dart --test-randomize-ordering-seed=random: 20 passed, seed 3516659226. Covers missing/inherited/explicit/nested providers, native interoperability, retained editing selection/state/focus, directional geometry and semantics, Tab/Shift+Tab/Enter, live open-menu direction/theme, menu selection/Escape/outside dismissal/restoration/removal, and all three examples in light/dark/Forest/Plum with narrow 320/360px layouts and 200% text/reduced motion.
- flutter test --no-pub test/styleguide/styleguide_page_test.dart --plain-name "Direction examples": passed after correcting the test to scroll the lazy detail list back to its preview control.
- Coordinator independently ran flutter test --no-pub test/ui/d_direction_test.dart test/styleguide test/resizable_pane_test.dart test/chat_drawer_test.dart test/users_page_test.dart test/composer_toolbar_test.dart test/topic_header_tags_test.dart test/topic_list_navigation_test.dart test/forum_tabs_bar_test.dart test/app_settings_page_test.dart --test-randomize-ordering-seed=random: all 186 passed, seed 4165766908; inspected /tmp/direction-coordinator-regression-tests.log. Includes real styleguide navigation/controls and live RTL resize focus/sign regression. No unchanged passing suite was repeated.
- Built and ran flutter run -d macos -t lib/styleguide_main.dart --no-pub with a PTY from /private/tmp/discourse-native-direction.F27Xzr. Temporary PRODUCT_NAME DiscourseDirectionStyleguide, bundle org.discourse.native.styleguide.direction, and disabled development signing isolate it from the normal app; none of those runner changes are in this branch.
- CUA inspected the running macOS Direction editor in the 1280x860 logical window: typed a local draft, saved via Tab/Enter, switched inherited LTR to RTL, and confirmed draft/saved value and directional arrow/field/action geometry. Inspected current dark and light previews, Forest palette at 360px and 200% text, and scrolling to the saved value without overflow.
- CUA inspected the nested example at 360px/200% Forest: Arabic RTL outer section, wrapping fixed LTR URL, inherited LTR lookup, and resumed RTL sibling. In Plum at 360px/100%, inspected the RTL native menu, visible arrow-key focus, Enter selection, restored trigger focus, and Escape dismissal while keeping the styleguide open.
- git diff --check passed; catalogue snapshot, native runners, pubspecs and lockfiles are unchanged.
- Rebuilt the final committed native examples and confirmed Direction is marked implemented and its live editor renders in the running catalogue.
- Coordinator final review of branch HEAD 1642d8d7bb6c8b5786ed9b5ba348d9bf9e6fbe40 accepted the provider API, three examples, one preview provider plus 12 app lookups, focused regression evidence and completed macOS inspection. No remaining implementation issue was identified. Merge reconciliation affects only progress metadata.
- After merging from the repository main checkout, git diff confirmed all non-progress files exactly match reviewed branch HEAD 1642d8d7bb6c8b5786ed9b5ba348d9bf9e6fbe40; the main worktree is clean. The merge preserves both parents and adds no code change beyond the verified component branch.

**limitations**

- Native device inspection was macOS only. iOS/Linux device behavior and VoiceOver speech were not run; screen-reader direction semantics and native keyboard behavior are covered by widget tests.
- Authenticated core and Chat screens were not exercised in a live signed-in session. Their migrated geometry, resizing, toolbar, measurement and state behaviors were verified by the focused downstream tests listed above.
- Live direction and custom-theme changes while a menu is already open were verified in widget tests. Manual native preview-setting clicks follow normal outside-click dismissal, so the native menu was inspected after selecting its palette/direction.
- The initial isolated build needed temporary signing adjustments; a long CUA approval wait and synthesized command-key attempts required app relaunch/reselection before successful native checks. Those tooling interruptions did not require production code changes.

### typography

Status: merged. Task: 01a081e5-0bef-70a1-9ae3-7717028403e0. Branch: codex/ui-typography.

**acceptanceCriteria**

- Expose reusable DText plain/rich semantic variants for h1, h2, h3, h4, paragraph, lead, large, small, muted and inline code, plus directional blockquote/list composition through discourse_ui.dart; account for all 14 frozen sections.
- Keep DiscourseTypography as the single numeric size owner; reproduce the frozen shadcn weights, leading and tracking while preserving app fonts, semantic colors and the inherited nonlinear platform/app TextScaler.
- Use native Text/InlineSpan selection under the caller's SelectionArea, heading/list semantics, intrinsic wrapping and directional geometry; demonstrate keyboard-focusable composed actions without adding typography-owned interaction or overlay state.
- Cover the frozen table composition with native Flutter Table, semantic headings, column alignment, wrapping and themed borders/striping; leave general table behavior to the later Table catalogue entry.
- Provide runnable public-API examples for every frozen section plus article/rich-code/interactive content, nested lists, empty/long text, RTL, live light/dark/site themes and 200% narrow layouts; keep usage code accurate.
- Audit all core and bundled plugin UI; migrate meaningful existing headings and secondary prose while preserving roles, permissions, state and accessibility; document retained authored HTML/Markdown/composer and control-specific typography.
- Pass formatting, static analysis and focused component/example/migration/theme/text-scale regression tests; inspect an isolated macOS styleguide and available affected screens, record evidence/device limitations, then mark review_ready and commit without merging.

**decisions**

- Frozen Markdown SHA256 verified as 3ff202e83d6c90b2521ec471af07cab3c59314028c51ef8d040b3218ec9a9541. The live HTML now redirects to Typeset; the captured original examples define scope, not Typeset.
- The initial adaptation to generic TextTheme metrics was superseded by the user clarification to copy shadcn. The coordinator follow-up restores the exact frozen typography metrics, reference body text and spacing; TextTheme supplies live font families and DTokens supplies semantic colors.
- Use native Text and Text.rich plus caller-owned SelectionArea; inline code spans can fragment and remain selectable with a rectangular text background, while standalone code can use token radius/padding. Use the existing bundled JetBrains Mono for code only; all other families come from TextTheme.
- Block/list spacing belongs to explicit Flutter composition instead of CSS sibling selectors and scroll margins. Directional quote borders and list markers follow DDirection/Directionality. Typography introduces no animations, overlays, focus nodes or network/business state; composed native controls retain their interaction ownership.
- Table is a documented native Table composition in the examples, not a second public table engine. Existing authored markup and composer renderers continue to own their formatting, source offsets, specialized selection and heading mappings.
- DText.headingLevel separates document hierarchy from visual role (1-6, with 0 opting out). DProse supplies explicit reading flow; DBlockquote supplies a directional italic quote boundary; DTextList supplies wrapping native list/item semantics with optional ordered continuation. Empty flows/lists occupy zero height.
- DText.styleOf resolves live, unscaled TextTheme roles for rich spans. Native Text still owns shaping, wrapping and selection. Standalone code backgrounds fit the text even in a full-width prose flow; caller alignment and current token radius remain effective.
- Seven runnable examples cover every frozen section, full and RTL articles, rich actions, nested/ordered/empty lists, long and empty text, explicit truncation, and native table alignment. Table/article usage includes the complete self-contained sample table class. Marked implemented only after the checks and native inspection below.
- No global type scale, AppTheme, AppTextScaleRegion, source renderer, native runner, dependency, Flutter pin or lockfile was changed. No separate typography implementation existed to remove; migrated callers now delegate their semantic text rendering through the public library.
- The coordinator visual-fidelity follow-up adds an original-text specimen (eight total examples), plain-heading balance with native wrapping limits, and exact border-box insets. See the dedicated visualFidelity record for source mapping, checks and remaining platform differences.

**migrations**

- Core: EmptyState title and secondary introduction; Settings title/section headings/help text; shared ShellSheet and desktop add-site title; group management form/Logs headings. Visual roles are preserved while semantic heading levels now match page/dialog hierarchy.
- Bundled plugins: Chat channel title/description (including its medium emphasis), Poll and Local Dates composer dialog titles, GIF picker title, Voice room-chat title, and Events cooked fallback heading. Existing controllers, callbacks, permissions, localization/markup data and asynchronous ownership stay in the app/plugin.
- Scaling fixes justified by the migrated surfaces: Settings header has a minimum rather than fixed 52px height; its percentage has an intrinsic width with a 64px minimum; Voice room-chat heading uses Expanded beside Close. Normal-size geometry remains covered by the existing tests.
- Audited 120 core text-consumer files and all bundled plugin directories: Assign, Chat, Discourse AI, Events, GitHub, Lazy Videos, GIFs, Local Dates, Poll, Prometheus Alert Receiver, Reactions and Voice. Also inspected package API/Voice and full-profile sources; these contain no additional native presentation owner requiring migration. Removed redundant legacy Button/Select imports from migrated public-barrel consumers.

**retainedAlternatives**

- DiscourseTypography remains the only numeric size/leading owner; AppTheme maps Material/Cupertino and site themes; AppTextScaleRegion composes nonlinear platform scaling and the app preference unchanged.
- Cooked HTML/Markdown, rich composer/markdown highlighting, quote/code blocks, oneboxes, emoji and user-content links retain their distinct rendering/selection/source-offset contracts and authored h1-h6 mapping. Generic prose is not a parser or replacement for those systems.
- Native control labels, form fields, menus, tabs, dense metadata, notification snippets, topic titles with emoji/unread spans, and specialized alert/event/onebox tables retain explicit semantic roles or renderer-owned styles. Their composition, interaction and domain semantics differ from document prose; the Button/Table/etc. catalogue tasks retain ownership of those component APIs.
- Assign/AI/Reactions and other sheets already delegate titles to the migrated shared ShellSheet or native AlertDialog theme; do not insert redundant text owners. Package bridge/transport and compatibility runners contain no additional Typography UI to migrate.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 confirmed; flutter pub get --enforce-lockfile passed with no lockfile changes. Frozen Typography Markdown hash verified, and official new-york-v4 Typography demo source inspected alongside the captured examples.
- flutter analyze --no-pub: passed with no diagnostics after the final component/layout/test fixes (log /private/tmp/typography-analysis.log).
- flutter test --no-pub test/ui/d_typography_test.dart test/styleguide/typography_examples_test.dart --test-randomize-ordering-seed=random: 13 passed, seed 3875140872. Tests cover all theme roles/native families/caller emphasis, nonlinear scale, heading levels/opt-out/labels, quote/list direction and semantics, nesting/empty lists, wrapping/truncation, code selection/copy using macOS and Linux target-platform overrides, native action focus/Enter/Space/Shift+Tab, live tokens and table header/cell semantics.
- flutter test --no-pub test/styleguide test/typography_boundary_test.dart test/app_text_scale_test.dart test/app_theme_test.dart test/site_theme_app_test.dart test/discourse_typography_adoption_test.dart test/app_settings_page_test.dart test/add_instance_sheet_test.dart test/add_instance_lifecycle_test.dart test/group_page_test.dart test/chat_channel_info_view_test.dart test/gif_picker_test.dart test/voice_room_view_test.dart test/event_card_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/plugins/local_dates/local_date_composer_component_test.dart --test-randomize-ordering-seed=random: 226 passed, seed 1788584063; /private/tmp/typography-regression-tests.log. This includes the actual migrated owners, all eight app zooms, authored cooked content, live site themes, and source scale ownership.
- After the native layout refinements: flutter test --no-pub test/ui/d_typography_test.dart test/styleguide/typography_examples_test.dart test/app_settings_page_test.dart --test-randomize-ordering-seed=random: 18 passed, seed 959805661; /private/tmp/typography-final-component-tests.log. Explicit regressions verify fitted code backgrounds, unbroken code wrapping, the taller settings heading and a single-line zoom readout.
- flutter test --no-pub test/styleguide/styleguide_page_test.dart --plain-name "Typography preview controls": passed; /private/tmp/typography-preview-final-test.log. The real searchable styleguide preserves rich-action state through Plum/360px/200%/RTL and resets it through the preview Navigator. Test waits for native Navigator reconstruction rather than assuming a single frame.
- Every example was rendered at 320px and 960px, 200% text, both directions, reduced motion, and Light/Dark/Forest/Plum in widget tests without overflow or unexpected truncation. Intentional one-line ellipsis is asserted separately.
- Built and ran flutter run -d macos -t lib/styleguide_main.dart --no-pub from isolated /private/tmp/discourse-native-typography.lr3l_nr8. Temporary PRODUCT_NAME DiscourseTypographyStyleguide, bundle org.discourse.native.styleguide.typography and disabled development signing stayed only in that copy. Selected that exact .app path with CUA and raised it before interaction.
- CUA native styleguide inspection: current dark and Light headings; 360px/200% Forest quote/attribution, nested ordered lists, table wrapping/borders/striping/alignment; Plum wrapping code; fitted code backgrounds after refinement; mouse selection through a rich code span; visible Tab/Shift+Tab focus and Enter/Space activation; retained details after Plum-to-Light theme change; Arabic RTL headings, right-side quote rule/list markers, mirrored table columns and fixed LTR code island at 360px/200%. Final hot restart loaded implemented status and the completed usage examples.
- CUA inspected actual EmptyState at 360px and 100/200%, Add-a-site dialog at 200%, Poll dialog in Plum at 200%, and Settings in its deliberately neutral dark theme at 200%, including the final single-line 200% readout and growing heading. A temporary lib/styleguide_main.dart harness used the repository's in-memory fake stores/API and actual widgets; it was never added to this worktree. Open/close and preview changes made no real account or settings writes.
- Focused tests caught a duplicated table semantic wrapper (Flutter already supplies table/rows) and zero heading-level handling; native layout inspection led to fitted standalone code backgrounds and an intrinsic-width settings percentage. All were corrected and covered by focused checks. An early automated Select All chord quit the isolated process because the machine uses AZERTY (CUA key a visibly types q); no native copy-shortcut success is claimed from that attempt.
- dart format --output=none --set-exit-if-changed on all 22 changed/new Dart files passed with zero changes. git diff --check passed. Only Typography's progress row changes, with progress.md regenerated by dart run tool/render_component_progress.dart; native runners, dependencies, lockfile, Flutter pin and global typography/scaling owners are unchanged.
- Coordinator reviewed committed branch HEAD c1b6e1f513b47287101155fdaabfb585b458533f, the complete public component, all seven runnable examples and usage, core/plugin migrations, semantic/scaling/selection tests, and exact passing regression/analysis logs. Native inspection evidence and device limitations were reviewed. No remaining implementation issue was found; merge conflicts were confined to progress metadata, reconciled while preserving the concurrent workflow and other task rows.
- Post-merge comparison confirmed lib/, test/ and docs/typography.md exactly match the reviewed component branch. Only previously committed workflow/progress documents differ; all three concurrent component task rows are preserved.

**limitations**

- iOS and Linux devices were not run. Platform overrides in widget tests validate Flutter keyboard/scaling behavior but are not device testing.
- Authenticated live app/plugin sessions were not opened. Native app-screen inspection used actual widgets with in-memory fixtures; other migrated views were verified by focused owner tests.
- Native mouse selection and composed keyboard actions were inspected. Copy/Select All shortcuts were verified in widget tests for macOS/Linux, not conclusively through CUA on this AZERTY machine; the native Cocoa Edit menu is not the Flutter SelectionArea context menu.
- Table is fully accounted for as the frozen typography composition; general Table component behavior belongs to its later catalogue task. No implementation issue remains known after the focused checks.

### spinner

Status: merged. Task: 01a08213-9960-79f1-8d90-9626f24a4b5a. Branch: codex/ui-spinner.

**acceptanceCriteria**

- Provide public DSpinner with a 16 logical-pixel default, arbitrary positive sizing, live inherited/explicit color, stroke width and custom rotating artwork; keep async/business state in callers.
- Reproduce the official shadcn/Lucide Loader2 SVG artwork on every platform with a 24-unit view box, rounded 2-unit scalable stroke, 16px default geometry and 1s linear clockwise rotation; expose one customizable native loading status with a decorative opt-out, no focus or interaction interception.
- Stop motion for reduced-motion preferences, inactive applications and disabled ticker subtrees; handle live updates, removal and restoration without leaked animation work.
- Demonstrate all frozen sections with interactive customization, four reference sizes (12/16/24/32), loading buttons, badge/input/empty compositions, start/end placement, cancellation/retry, RTL, narrow layouts and 200% text.
- Audit core and every bundled plugin, migrate circular indeterminate indicators including DButton and remove AdaptiveActivityIndicator ownership; preserve determinate progress and document retained linear/typing alternatives.
- Format/analyze and run focused component, styleguide and migrated-consumer regressions, then inspect an isolated macOS styleguide using the coordinator inspection slot.
- Inspect official registry/source in addition to frozen docs, record a concise reference-to-Flutter visual mapping, correct unjustified visual differences and inspect the final rendered examples before review_ready.

**decisions**

- Frozen spinner.md SHA256 verified as 9c7185da74c70d9b9bb7c3b894e14bb62e2a07c264bed76a786ab7f38325d654; catalogue variant/size=sm/align values belong to demonstration Button/Badge/Item/Input Group/Empty controls, not Spinner props.
- The clarified shadcn fidelity requirement supersedes the initial platform-artwork choice. DSpinner now renders the exact default Lucide Loader2/loader-circle SVG path through the existing flutter_svg dependency on all platforms; the custom example uses the exact LoaderIcon SVG. No new package or catalogue entry.
- Composition uses ordinary children and directional Flutter layout. Spinner owns no Button/Badge/Input Group/Empty APIs and no loading completion, errors or cancellation state.
- DSpinner defaults to 16 logical pixels, follows inherited IconTheme color and uses DTokens.foreground as fallback; explicit color and SVG view-box strokeWidth are supported. Stroke scales with size. Whole-panel callers retain 24px boxes and constrained inline callers retain their existing dimensions; DButton now uses the 16px default.
- Use a native loadingSpinner semantics role and a single caller-localizable live label, with semanticLabel=null for decorative artwork. DButton retains its existing name, Loading value, disabled state, tooltip and async ownership.
- Reduced motion pauses the reference SVG rotation at its current position while keeping indeterminate busy semantics. Default and custom motion stops for inactive apps and disabled ticker subtrees and resumes without disposing borrowed state. DMotion.spin matches Tailwind’s 1s linear infinite animation.
- No networking, completion callbacks, error state, focus nodes or overlay ownership were added to DSpinner. Example completion/validation/cancellation controls use local sample state.
- Visual mapping in docs/component-library/spinner-reference.md records exact SVG path/view box/stroke/cycle and companion Button/Badge/Input Group/Empty/Item source geometry. App theme colors, surface radius and font family remain native integration points; large text can wrap instead of clipping status text.
- Implementation, reference mapping, consumer regressions and final native correction checks are complete. Spinner is review_ready for the coordinator; only this component row and its generated evidence are updated. Device/VoiceOver gaps and the unassigned native keyboard incident remain explicit limitations.

**migrations**

- Replaced 97 direct indeterminate circular/adaptive usages in 57 core/plugin source files and migrated DButton loading to DSpinner (98 busy-indicator constructions total). All app callers use the public discourse_ui.dart barrel; DButton imports the component internally.
- Removed shell/adaptive_activity_indicator.dart and migrated its callers in aggregate_view, draft_list, instance_rail, lightbox and topic_list_view. Updated adaptive Apple tests to exercise DSpinner.
- Core adoption covers app loading, account menus/presence, forum/sidebar loading, badges/categories/tags/groups and member/activity views, topic lists/actions/taxonomy/ownership/move-post dialogs, composer image workflows, bookmarks/reactions/likes, emoji/search/pickers, preferences, update installation and video/photo loading.
- Bundled plugin audit: migrated direct circular usages in Assign, Chat (channel/thread/search/message actions/composer), AI summary, GIFs and Voice. Reactions uses the migrated shared reaction presenter. Poll, Events, GitHub, Lazy Videos, Local Dates and Prometheus Alert Receiver have no additional direct circular spinners; existing DButton consumers inherit the new rendering.
- Updated emoji-picker, reaction-list and user-presence regression assertions to the public DSpinner instead of the Material implementation, preserving loading/error/permission/async tests on macOS.
- Added a dedicated spinner_examples.dart with six runnable examples for all frozen documented sections: customizable sizes/artwork, Button, Badge, Input Group, Empty and RTL. Installation/usage are documented through the public barrel.
- Fidelity follow-up updates 16 additional consumer test files and the shared activityIndicators test finder to the public DSpinner, so loading assertions continue exercising the new artwork on Linux as well as Apple platforms. Numeric progress remains separate.

**retainedAlternatives**

- instance_rail.dart retains the CircularProgressIndicator with value: updates.progress because update-download percentage is meaningful. update_sheet.dart and composer_panel.dart retain numeric LinearProgressIndicator values for update downloads and composer uploads.
- Horizontal indeterminate bars in badges/categories/tags, bookmark actions, revision history, user-directory empty/loading status, Assign searches/group refresh, Events cards/directory/participants and Chat pinned refresh retain their linear layout for the separate Progress catalogue entry; they do not duplicate circular spinner ownership.
- loading_skeleton.dart and content placeholders remain owned by the concurrent Skeleton task. Vendored video-player example loading bars are upstream sample UI outside the app component migration.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 verified. Root and profiles/full flutter pub get --enforce-lockfile passed with no lockfile or pin changes.
- dart format --output=none --set-exit-if-changed on all 69 touched/new Dart files passed (0 changes). Final root flutter analyze --no-pub passed (no issues, 2.6s); profiles/full flutter analyze --no-pub passed (no issues, 1.6s). git diff --check passed; no lockfile, Flutter-pin or repository platform-runner changes.
- flutter test --no-pub test/d_spinner_test.dart test/adaptive_apple_widgets_test.dart test/d_button_test.dart test/styleguide test/emoji_picker_test.dart test/reactions_row_accessibility_test.dart test/user_presence_widget_test.dart --test-randomize-ordering-seed=random --reporter expanded: 86 passed, seed 4000949775.
- flutter test --no-pub test/d_spinner_test.dart --plain-name 'an open dialog receives live palette changes without replacing its spinner' --reporter expanded: 1 passed. An already-open dialog retains Spinner state, receives a site-palette update and dismisses via Escape.
- Component tests cover identical reference artwork under iOS/macOS/Linux target-platform overrides (not device execution), default and custom motion pause/resume/removal, app inactivity, TickerMode, reduced motion with unchanged busy semantics/no numeric value, decorative semantics/input/focus exclusion, 12/16/24/32 sizing and tight constraints, live light/dark/Forest/Plum colors, all 11 DButton variant colors and disabled named-action semantics.
- Example tests exercise all six examples at 280px with 200% text and RTL, state retention across palette changes, customization, inline start/end placement, button failure/completion, disabled validation with preserved text, rejection/retry/send, empty-state cancel/fail/retry/complete, and styleguide search/registration.
- Broader migration command: flutter test --no-pub test/add_instance_sheet_test.dart test/aggregate_view_test.dart test/anchored_picker_test.dart test/assigned_group_view_test.dart test/badges_page_test.dart test/categories_page_test.dart test/chat_browse_channels_view_test.dart test/chat_channel_info_view_test.dart test/chat_channel_view_lifecycle_test.dart test/chat_composer_test.dart test/chat_header_button_accessibility_test.dart test/composer_image_gallery_test.dart test/composer_image_test.dart test/d_button_adoption_test.dart test/do_not_disturb_dialog_test.dart test/draft_list_test.dart test/emoji_picker_test.dart test/gif_picker_test.dart test/group_page_test.dart test/groups_page_test.dart test/inline_video_test.dart test/lightbox_test.dart test/plugin_dependency_boundary_test.dart test/post_revision_history_test.dart test/preferences_page_test.dart test/reaction_presentation_test.dart test/reactions_row_accessibility_test.dart test/styleguide test/tags_page_test.dart test/topic_create_button_accessibility_test.dart test/topic_header_tags_test.dart test/topic_list_view_lifecycle_test.dart test/topic_taxonomy_fields_test.dart test/user_presence_widget_test.dart test/voice_room_view_test.dart --test-randomize-ordering-seed=random --reporter expanded. Seed 4125606634: 578 passed / 5 failed initially. Four introduced test expectations/navigation issues were corrected and all passed in the final 86-test run; the remaining pre-existing adoption-allowlist failure is recorded under limitations.
- Isolated macOS build: flutter build macos --debug --no-pub --target lib/styleguide_main.dart passed in /private/tmp/discourse-ui-spinner-native, producing Spinner Styleguide.app with bundle ID org.discourse.native.styleguide.spinner. Ad-hoc signing and removal of the unused push entitlement stayed only in the temporary copy; repository runners unchanged.
- Final custom-artwork review: explicitly oversized child icons are fitted into the requested diameter. flutter test --no-pub test/d_spinner_test.dart test/styleguide/spinner_examples_test.dart --test-randomize-ordering-seed=random --reporter expanded: 27 passed, seed 33603198, including the open-dialog and oversized-artwork regressions. The isolated macOS build was refreshed successfully after this change.
- Native macOS slot used and explicitly released. Verified 12/16/24/32 sizes, custom artwork/accent/32px selection and pause, live current-dark to Light palette with retained sample state, DButton loading followed by visible Tab focus and Return completion, and Forest 360px/200%/RTL/reduced-motion payment status with wrapping and directional placement.
- Temporary-only Migration fixtures mounted real UserMenuMessage and GifPicker with local gated data, no actual account requests. In Plum 360px/200%/RTL/reduced motion, both actual loading surfaces completed failure/retry/loading/completion or empty-state transitions. The initial artificial 310px GIF fixture height overflowed at 200%; using the native picker maximum height of 540px eliminated that fixture-only overflow. Normal semantics lifecycle remained stable.
- Official base-nova registry, rendered Spinner page, Lucide loader-circle/loader SVGs and Tailwind spin source inspected. The independent SVG fixture raster comparison passes exactly with the existing flutter_svg renderer. Source mapping: docs/component-library/spinner-reference.md; third-party attribution: licenses/lucide.txt.
- Fidelity follow-up: flutter test --no-pub test/assigned_group_view_test.dart test/chat_channel_info_view_test.dart test/preferences_page_test.dart test/voice_room_view_test.dart test/invite_list_test.dart test/topic_filter_test.dart test/users_page_test.dart test/chat_composer_test.dart test/chat_channel_view_lifecycle_test.dart test/chat_browse_channels_view_test.dart test/topic_list_view_lifecycle_test.dart test/topic_view_lifecycle_test.dart test/native_inline_video_playback_test.dart test/inline_video_test.dart test/chat_message_tile_thread_preview_test.dart test/topic_progress_lifecycle_test.dart test/d_spinner_test.dart test/adaptive_apple_widgets_test.dart test/d_button_test.dart test/styleguide test/emoji_picker_test.dart test/reactions_row_accessibility_test.dart test/user_presence_widget_test.dart test/post_likes_account_generation_test.dart test/user_card_account_lifecycle_test.dart --test-randomize-ordering-seed=random --reporter expanded: 583 passed, seed 2556737142. Updated loading-state assertions retain native editing, disabled/busy semantics, account/lifecycle isolation and asynchronous consumer coverage.
- Fidelity follow-up: dart --suppress-analytics format --output=none --set-exit-if-changed on 24 changed Dart files passed with 0 changes; final root flutter analyze --no-pub passed in 3.1s and profiles/full in 1.6s, no issues. git diff --check passed. No SDK/pin/lockfile or repository runner edits.
- Refreshed isolated macOS build passed at /private/tmp/discourse-ui-spinner-fidelity/build/macos/Build/Products/Debug/Spinner Fidelity.app, bundle org.discourse.native.styleguide.spinner.fidelity. Its DSpinner, examples and DButton sources match the final worktree bytes. Spinner Baseline.app was preserved for the bounded forced-semantics comparison recorded below. All native inspection followed the coordinator slot grants.
- Follow-up native comparison completed: exact base 5fd6658b UserMenuMessage/GifPicker/DButton and bare native-indicator shim repeated the forced-semantics SIGSEGV at 0x48 with the same AccessibilityBridge::CreateRemoveReparentedNodesUpdate / CommitUpdates frames. Baseline report SHA-256 109d039d154e65ce4cc92f8a8cad45fa2e6cc9467d0b7e8b0af4691ddc6e2a17. New DSpinner is not necessary for that diagnostic crash; underlying framework/fixture cause remains unresolved.
- Final SVG native app inspected with normal semantics lifecycle: all six reference sections across current dark/Light/Forest/Plum; custom size/color/pause and live-theme state retention; reference Button states and real DButton Tab/Return completion; badge leading/trailing/completion; input editing/validation/rejection/retry/send; empty cancel/fail/retry/complete; Forest 360px/200%/RTL/reduced-motion payment status. Actual UserMenuMessage and GifPicker loading/error/retry/completion fixtures passed under Plum 360px/200%/RTL/reduced motion with no crash or overflow. Precise app identities and observations: docs/component-library/spinner-native.md.
- Native-found example corrections: keep input error rings outside their filled interior, use intrinsic amount width at the payment row end with a large-text cap, and replace stale waiting instructions after completion. flutter test --no-pub test/styleguide/spinner_examples_test.dart --test-randomize-ordering-seed=random --reporter expanded: 13 passed, seed 2614942230. Root flutter analyze --no-pub clean in 2.6s; formatting/diff checks pass; refreshed isolated native build succeeds with matching source bytes.
- Final bounded native reinspection passed on the already rebuilt source-matched Spinner Fidelity.app using pointer-only navigation: Light input rejection kept the interior white inside the red error ring; both cancelled and completed Empty states showed the nonbusy description; Light payment amount reached the inline end at Fit/100%/LTR and 360px/200%/RTL with the full normal title and wrapping Arabic large text. No overflow, crash or unresponsive episode occurred in this pass. Prior full examples and real core/GIF fixture checks were not repeated.
- After the final correction pass, only the isolated Spinner app was quit through its own native menu. A subsequent global cua.getState snapshot confirmed all three Spinner bundle identifiers absent. Desktop slot released to the coordinator for Avatar. No further native actions or follow-on component work are planned.
- Coordinator reviewed stable clean Spinner HEAD 3c0192067f2b5543afe33ce71ce5e9deb9f469cf, its exact Lucide path and motion/lifecycle semantics, six complete example sections, app-wide adoption, final native corrections and explicit diagnostic limitations. Reconciled shared exports, imports and registrations against the seven previously merged components; retained the existing adoption guard correction, Skeleton replacements and Aspect Ratio media contracts.
- Coordinator combined-main verification: 738 focused component, styleguide, Button-adoption and affected loading/account/media/Chat/Voice consumer tests passed, seed 1778345709. The exact command and output are in /private/tmp/component-spinner-integration-tests.log. All 87 touched Dart files were formatted; merge-introduced duplicate imports and directive ordering were corrected. Final flutter analyze --no-pub is clean (7.7s), git diff --check passes, and generic Spinner/example source remains byte-identical to the reviewed native-inspected branch. The existing f5549d51 adoption guard was preserved and passed in the combined run.

**limitations**

- iOS and Linux devices were not run; target-platform widget tests do not substitute for device testing. flutter devices listed macOS 26.6.2 (darwin-arm64), Chrome and a wireless iPhone on iOS 26.6; no Linux device was available. The wireless phone was not used or modified. VoiceOver spoken output and authenticated app screens have not been inspected. The final SVG app’s six examples, actual core/GIF fixtures and three final example corrections were inspected on macOS.
- Forced-semantics diagnostic crash reproduces with pre-migration native consumers. The new DSpinner is not necessary to trigger it, but its framework/fixture root cause is unresolved. Reports and exact reproduction are retained in docs/component-library/spinner-native.md and ignored local artifacts; no forced-semantics instrumentation is committed.
- On the first relaunch for the three final example corrections, the native Theme menu stopped responding after typed search. Verified Spinner Fidelity PID 13780 was at 97.6% CPU, with no crash report; a one-second passive sample showed repeated FlutterKeyboardManager/FlutterChannelKeyResponder/FlutterEmbedderKeyResponder message processing. Cause remains unassigned. Sample SHA-256 7fc2c30a768983cea7dd552c4f042f98fae0b80c8c4d6fcd0e2a0020ef8887fd. The app quit normally through its native menu. Final correction inspection subsequently passed using pointer-only navigation under a new slot grant; that success does not establish a cause or fix for the keyboard event loop.

### kbd

Status: merged. Task: 01a0821b-27cc-7013-affb-99cae203b2a8. Branch: codex/ui-kbd.

**acceptanceCriteria**

- Public DKbd and DKbdGroup cover text, custom icon/child, grouped and inline hints, button, tooltip, input-addon and RTL composition. Kbd className maps to typed Flutter styling/composition; outline and inline-end are demo-control props, not Kbd variants.
- Match base-nova default geometry, type, spacing and semantic color roles: 20 px keycaps, 4 px padding/gaps, 12/16 px sans medium text, no border, small relative radius and tooltip tint. Preserve intrinsic height, wrapping at 200% and narrow widths, live light/dark/site palettes and reduced motion.
- DShortcut and DShortcutKeycaps preserve existing bindings and sequential highlight feedback without handling actions, format platform modifiers and named keys with spoken labels, and clear stale feedback on lifecycle/visibility changes.
- Search core and all bundled plugins; migrate tooltip ownership, shortcut help, search hints and suitable plugin shortcut hints while preserving dispatch, permissions, focus, state and overlay ownership. Record retained alternatives.
- Runnable public-library examples demonstrate every frozen section plus logical shortcuts, static/highlighted/icon states, scaling, direction and live compositions using available native controls. Focused rendering/semantics/theme/layout/keyboard/lifecycle and caller tests pass, analysis is clean, and macOS is inspected in the serialized desktop slot.

**decisions**

- Reference scope remains the frozen Kbd page (SHA256 3dd0b0dacf86f4b701ae35df3efe453ba1e9995a542e0a4a004a252f5bdd7978). Inspected actual official base-nova registry source (SHA256 4cfe2ba8e19f4d19d090eb039e3f1c041c9cfb379ce948237a9b5018203f7a6c) and rendered light/dark reference. The detailed source-to-Flutter measurements and narrow adaptations are in docs/component-library/kbd-visual-mapping.md; catalogue scope is unchanged.
- Existing app Actions/Shortcuts and app_shortcuts.dart remain binding owners. The Kbd library owns presentation and optional non-consuming hardware feedback only; Button, Tooltip and Input Group remain their separately scheduled catalogue entries.
- Native APIs are DKbd(label) / DKbd.child with required spoken label, DKbdGroup(children) with wrapping/direction/spacing/semantic label, DKbdTheme for ancestor tooltip colors, and retained typed DShortcut/DShortcutKeycaps APIs. No CSS prop string or parallel action registry is introduced.
- Default keycaps use explicit DiscourseTypography.xs (12 px), 16 px leading, weight 500 and zero tracking with the host sans-serif family. Live DTokens supply muted colors and small radius (site base × 0.6). Surfaces are borderless with 20 px minima and 4 px horizontal padding; icons default to 12 px. Intrinsic growth and wrapping preserve native text scaling. Tooltip tint follows its actual foreground at 20% light / 10% dark for contrast on the existing surface. Apple and Linux notation describe unchanged app bindings.
- Optional non-consuming shortcut feedback preserves sequence progression, is disabled for static hints, uses logical activator equality through theme rebuilds, and clears on visibility, app lifecycle and view focus changes. The group has spoken English defaults with caller semanticLabel overrides; sequences visibly say then.
- Seven public-library examples cover the two reference key groups before additional text/symbol/custom-icon states, groups/sequences/inline typography, platform formatting, working button/tooltip, focusable search input, RTL/LTR islands and narrow/large-text/empty groups. Existing Button/Tooltip and native input composition remain visibly identified as separate catalogue work.

**migrations**

- Moved DKbd, DShortcut and DShortcutKeycaps out of theme/d_tooltip.dart into the public Kbd component owner; DTooltip now composes it and announces shortcut labels. Updated core tooltip/hint imports to discourse_ui.dart and baseline DButton to the shared owner.
- Keyboard help now renders CharacterActivator hints through DKbd and wraps key groups beside wrapping labels; its sheet/scroll/focus/dispatch owners are retained.
- ForumSearch replaces plain platform string plus redundant Tooltip with static DShortcutKeycaps sourced from the existing primaryShortcutForPlatform binding; supplementary hints hide below 280 logical pixels of field width while input and clear/advanced controls retain ownership.
- Rail callout uses the shared group with bounded Flexible layout and contextual keycap foreground/tint; the obsolete intrinsic-height wrapper was removed. Existing rail/tab/sidebar/navigation/new-topic/reply/draft shortcut hints now resolve to the shared public implementation.
- Bundled Local Dates replaces embedded modifier text in its Insert menu label with an optional typed MenuSerializableShortcut on ComposerToolbarContribution; composer menu passes it to its existing MenuItemButton formatter. Site gating, editing availability, callbacks and both quick-insert shortcut bindings remain unchanged.

**retainedAlternatives**

- Flutter MenuItemButton retains native menu shortcut presentation for composer formatting and Local Dates; it aligns accelerator columns and participates in the existing menu semantics. Keycap boxes would duplicate that native rendering owner.
- Help instructions and docs remain prose; emoji keycap names are content identifiers, not keyboard hints. Search hints are intentionally omitted when the field is too narrow. No additional standalone hint owner was found in the other bundled plugins or compatibility wrappers.
- DTooltip/rail overlay positioning, gestures and native menu/sheet ownership remain with their scheduled Tooltip/menu/sheet components; this task changes only their Kbd presentation and necessary wrapping/semantics.

**verification**

- Official frozen page and base-nova registry source read. Hidden-browser light/dark renders and computed styles confirmed 20 px height, 4 px padding/group gap, 12/16 px medium type, no border and the relative small radius. Read the coordinator’s updated visual-fidelity contract; documented mapping in docs/component-library/kbd-visual-mapping.md.
- flutter pub get --enforce-lockfile passed in root and profiles/full without lockfile or Flutter pin changes.
- flutter analyze --no-pub passed with no issues in root and profiles/full after the final explicit typography metrics. All touched Dart files were formatted; git diff --check passed.
- flutter test --no-pub test/ui/d_kbd_test.dart test/styleguide/kbd_examples_test.dart test/keyboard_shortcuts_help_test.dart test/d_button_test.dart test/d_tooltip_test.dart test/forum_tabs_integration_test.dart: 70 passed after the geometry/color corrections, covering reference dimensions and palettes, live tooltip tint, semantics, keyboard actions, lifecycle cleanup, help wheel scrolling/Escape and rail/tab integrations.
- flutter test --no-pub test/ui/d_kbd_test.dart test/styleguide/kbd_examples_test.dart: 21 passed after explicit 12/16 typography metrics and the reference-first example arrangement. Custom Material role metrics cannot override the reference; host font family remains live. Matrix covers light/dark/forest/plum, 240/360/900 px, both directions and 200% text; component long-label cases also include 80 px.
- flutter test --no-pub test/forum_tabs_integration_test.dart test/content_navigation_controls_test.dart test/draft_list_test.dart test/keyboard_navigation_test.dart test/styleguide/styleguide_page_test.dart: 91 passed during migration. Rail number-shortcut test rerun after removing the obsolete intrinsic-height wrapper passed.
- flutter test --no-pub test/forum_search_clear_accessibility_test.dart test/poll_composer_panel_test.dart test/ui/d_kbd_test.dart: 43 passed during migration, covering search-hint scaling, preserved clear-focus/query state, typed Local Dates menu hints, permissions and dispatch.
- Isolated macOS styleguide and local-data harness built with flutter build macos --debug --no-pub. Product Discourse Kbd Review at /private/tmp/discourse-kbd-native-4bea uses verified bundle/signature org.discourse.kbd.review4bea. Runner, signing, diagnostics and fake-data fixtures remain outside the repository; the primary app was not launched or modified.
- Native CUA inspected corrected Kbd rendering in Light, Dark and Plum, including 360 px / 200% input and tooltip compositions, RTL input, focus/typing, pointer activation and F6 (counter 0→2). Actual ForumSearch accepted a query and omitted the supplementary hint when narrow. Actual shortcut help wheel-scrolled to its final Search row at 200% text and Escape dismissed it. Native AX exported meaningful chord/key labels through the normal semantics lifecycle.
- The final explicit metric guard preserves the values used by the palettes just inspected natively. The first example was subsequently arranged into the two centered reference groups with default 4 px gaps; the final arrangement is covered by the widget matrix. The isolated native app was quit and confirmed absent from cua.listApps; the serialized desktop slot was released.
- Coordinator reviewed the full API and migrations, exact Base Nova source mapping, corrected compact keycap metrics, native inspection and documented modifier-injection limitation. Reconciled Separator imports and example registration while retaining the newer shadcn Typography styles; combined checks follow.
- Coordinator integration: 176 selected tests passed (seed 2125845405) covering Kbd, the whole styleguide, Button/Tooltip, keyboard help, search, forum tabs and composer/Local Dates menu dispatch. That command also requested a nonexistent local_date_shortcut_test.dart; it was a test-path error, not a failing case. The two actual Local Dates component/lifecycle test files then passed all 6 cases. After resolving alphabetical import ordering, flutter analyze --no-pub passed with no issues. Reviewed final import deduplication, format and git diff --check.

**limitations**

- Native Command+K remains unverified: CUA super+k and Meta_L+k reached the passive Flutter diagnostic as Key K with Meta false. Logical macOS/iOS/Linux focus-shortcut tests pass. No VoiceOver speech check is claimed; native AX inspection and widget semantics checks are distinct.
- iOS and Linux were not inspected on devices during this task; a wireless iPhone is detected on the host. Widget target-platform overrides are not device tests.
- Default spoken key names and sequence separator are English; callers can override spoken labels and compose localized DKbdGroup content.

### tooltip

Status: merged. Task: 01a0829c-ba0d-7282-a010-7e26f190dd4f. Branch: codex/ui-tooltip.

**acceptanceCriteria**

- Reproduce frozen shadcn base-nova Usage, Composition, four physical and two logical sides, RTL, disabled Button wrapper and shortcut examples using DKbd; record frozen Markdown and official registry hashes plus measured visual mapping.
- Provide generic public DTooltip with child/content composition, controlled open state, imperative controller, provider delay/skip coordination, per-trigger delay, alignment and offsets, keyboard focus, hoverable content, pointer dismissal, Escape and native long press without stealing control actions or shortcut bindings.
- Use nearest live overlay with foreground/background tokens, 12/16 regular text, 12px horizontal and 6px vertical padding, 6px content gap, 320px maximum width, relative rounded-md radius, no border or shadow, and 10px rotated rounded arrow; support collision flip/shift, clipped viewports, scrolling/removal and reduced motion.
- Preserve semantics, disabled-trigger composition, focus ownership and hidden-pane suppression; test large text, narrow overlays, live light/dark/site palette changes while open and lifecycle/controller races.
- Replace the obsolete theme Tooltip owner, migrate appropriate core and every bundled-plugin tooltip with existing permissions/actions intact, audit richer rail hints and retained framework alternatives, and verify affected DButton, Kbd, rail and app consumers.
- Add comprehensive runnable public-library styleguide examples with accurate code; format/analyze, run focused component/migration/downstream tests, then compare native macOS styleguide and actual app-widget fixtures to source/reference during the granted desktop slot. Record platform limits and stable implementation SHA before review_ready.

**decisions**

- Implementation starts from c00aa3ee5aa057887b73603ff94571f02e609ba6. Button outline/icon-sm in the docs describe the composed Button, not Tooltip variants.
- Native long press is retained as a documented app extension to Base UI touch-disabled tooltips. Tooltips remain supplementary labels; action and keyboard shortcut ownership stays in callers.
- Frozen Tooltip page and official base-nova registry are archived with SHA256 hashes. docs/component-library/tooltip-visual-mapping.md records computed browser measurements, source mapping, native adaptations and comparison conditions; catalogue scope is unchanged.
- DTooltip owns one OverlayPortal with native Focus, pointer routing and gesture recognizers. Its RawTooltip subtype preserves Flutter find.byTooltip inspection compatibility without instantiating another RawTooltip. The public barrel exports the new owner; no app service enters the generic component.
- Typed API covers physical/logical sides, alignment/offsets, arrow, collision padding/flip/shift, controlled/defaultOpen, change reasons/completion, borrowed controller and trigger IDs, provider timing, cursor tracking, focusable disabled wrappers, hoverable popups and native touch modes. Dart content/trigger composition replaces web portal/payload/render functions.
- The body uses inverted live DTokens, host sans 12/16 regular type, 12x6 insets, 6px content gap, 320px maximum width, radius x0.8, no border/shadow and a 10px rounded rotated arrow. Entry fades/scales/slides over 150ms; exit fades/scales. Reduced motion is instant. DKbd presentation uses the existing shared component and bindings remain caller-owned.
- A small clipped trigger does not constrain its popup: ancestor clips only determine anchor visibility, while the nearest overlay defines collisions. This fixes a reproduced zero-width rail/avatar popup. Pointerdown inside rich content permits scrolling; Escape dismisses the hint without dismissing its parent route.
- Borrowed-controller replacement synchronizes an already-open trigger after the frame. Detachment/removal notifies listening widgets after the locked build/disposal phase; the component never disposes its borrowed handle.
- Eleven public-library examples cover every frozen composition first, then alignment, provider timing, controlled live hints, imperative multiple triggers, rich/narrow content, cursor tracking and disabled hints. Save uses the official Lucide artwork with its ISC notice; Arabic labels match the reference. Button stays explicitly baseline until its own task.
- Native inspection completed in the exclusive coordinator slot. It exposed and corrected a controlled-demo hover/click pinning race and a rail fallback-monogram clipping regression at 200%; both were rechecked natively. The styleguide group is now implemented, with its composed Button still explicitly baseline.

**migrations**

- See docs/component-library/tooltip-migrations.md for the per-file audit and all 105 original native tooltip message expressions. Replaced direct Tooltip constructors across core and bundled plugins and routed every owned IconButton/PopupMenuButton tooltip through DTooltip while retaining native controls, callbacks, state, keys, permissions and menus.
- Removed lib/src/theme/d_tooltip.dart and updated the public barrel and DButton dependency to lib/src/ui/components/d_tooltip.dart. Existing DButton/action tooltip callers automatically use the new owner without changing their API or dispatch.
- Replaced InstanceRail private RawTooltip renderer, transition, custom shape, hard-coded swatches and shadow with a thin DTooltip content adapter preserving app avatar/title, logical side, timing and primary shortcuts.
- Migrated account access, forum/tab/topic/status hints, search/filter clears, composer and gallery controls, diagnostics/media/lightbox, and sheet/choice controls; bundled Chat, Voice, Assign, Events, AI, GIFs, Local Dates, Poll, Reactions and alert tables use the shared component.
- Native control wrappers use labelTrigger to merge the accessible name with the original control action/state. Removed redundant lightbox icon naming and updated focused tests to inspect the actual retained control rather than Material Tooltip internals.

**retainedAlternatives**

- Framework-private text-selection/picker hints retain their native owner. AppTheme TooltipTheme fallback uses the same inverted palette/basic geometry; every exposed nonempty app IconButton/PopupMenuButton property was migrated.
- Vendored video-player and WebRTC example apps are third-party package demonstrations, not core/bundled-plugin application UI, and remain unmodified.
- Existing DButton and action-adapter tooltip parameters already compose shared DTooltip. Essential instructions remain inline, and app networking/permission/avatar data remains outside generic UI.

**verification**

- Flutter 3.47.2 / Dart 3.13.2. flutter pub get --enforce-lockfile passed; pubspec, lockfile and Flutter pin are unchanged.
- Hidden-browser official light/dark renders at 1280x720 CSS px / DPR2 / 100% text: Add to library body 97.492x28px, 12/16 type, 12x6 padding, 4px trigger gap, radius 8px, no border/shadow; Save Changes S body 122.547x32px with 20px keycap, 6px gap and 6px trailing inset. Host palette/font/radius supply corresponding theme variables.
- flutter test --no-pub test/ui_tooltip_test.dart test/d_tooltip_test.dart test/d_button_test.dart test/styleguide test/app_theme_test.dart test/forum_tabs_integration_test.dart test/site_theme_app_test.dart test/composer_selection_toolbar_accessibility_test.dart test/voice_call_widget_test.dart test/d_button_adoption_test.dart --test-randomize-ordering-seed=random: 185 passed, seed 338221338 (build/tooltip-focused-final.log).
- A focused 22-file app/plugin migration run passed 333 with three accessible-name expectation failures; gallery/search expectations were corrected and duplicate lightbox icon naming removed. flutter test --no-pub test/composer_upload_panel_test.dart test/forum_search_clear_accessibility_test.dart test/lightbox_test.dart --test-randomize-ordering-seed=random then passed all 82, seed 3282548594 (build/tooltip-migration-followup.log). The other migration files passed in build/tooltip-migration-tests.log, seed 901138905.
- flutter test --no-pub test/ui_tooltip_test.dart test/shell_navigation_integration_test.dart test/chat_navigation_test.dart test/content_navigation_controls_test.dart test/forum_tabs_bar_test.dart test/native_inline_video_playback_test.dart --test-randomize-ordering-seed=random: 226 passed, seed 98425898 (build/tooltip-final-owners.log).
- The coordinator controller-swap issue was reproduced by a failing focused regression (build/tooltip-controller-swap-repro.log). After fixing it, flutter test --no-pub test/ui_tooltip_test.dart test/styleguide/tooltip_examples_test.dart test/d_tooltip_test.dart --test-randomize-ordering-seed=random passed 42, including uncontrolled replacement/listener/removal and controlled already-open attachment (build/tooltip-controller-final.log), seed 1354908790.
- Component and styleguide matrices cover exact metrics, physical/logical placement, directional alignment, focus/action/longpress/tap behavior, semantics, group warm timing, popup travel and scrolling, hidden panes, controller lifecycle, nested clipped anchors, live light/dark/Forest/Plum, 240/360/900px previews, both directions, 200% text and reduced motion.
- flutter analyze --no-pub reports no issues after the final controller fix. Touched Dart files are formatted and git diff --check passes. Read-only migration audit finds no direct Tooltip/RawTooltip constructors and no nonempty native IconButton/PopupMenuButton tooltip values in lib; old theme/d_tooltip imports are absent. The full compatibility profile also passed flutter pub get --enforce-lockfile and flutter analyze --no-pub; root/full lockfiles are unchanged (build/tooltip-full-profile.log).
- Isolated macOS app Tooltip Fidelity Review, bundle org.discourse.native.styleguide.tooltip.review, built with flutter build macos --debug --no-pub --target=lib/tooltip_inspection_main.dart under /private/tmp/discourse-tooltip-review/app. Component/examples/actual-fixture widget source bytes were verified against the worktree; runner/signing/fakes remain outside the branch.
- Native CUA inspected all eleven examples at 900/360 logical preview widths, 100/200% text, LTR/RTL and motion/reduced motion. All four sides/arrow attachments, start offsets, disabled-wrapper Tab access, S action/keycap/SVG, provider wait and neighbor change, imperative selection/close, cursor tracking and disabled-hint action passed. The pinned popup stayed open through live Light/Dark/Forest/Plum, wrapped/flipped inside the narrow preview, and accepted Escape.
- The native controlled-demo race was fixed by leaving pin/unpin to the button; onOpenChange handles Escape/lifecycle/disabled dismissal. flutter test --no-pub test/styleguide/tooltip_examples_test.dart passed all 7 including actual mouse hover/click/double-toggle sequencing (build/tooltip-native-demo-fix.log), then native pin/theme/Escape were rechecked.
- Actual InstanceRail, UserMenuButton, TopicProgressButton and VoiceCallWidget were inspected with in-memory services. Sign-in/topic/mute hints used their original controls; topic action incremented the local counter. Rail popup escaped its clipped trigger and rendered avatar/title/Command shortcut. Restored the fallback monogram FittedBox after a native 200% clipping observation; focused rail tooltip regression passed and final 360px/200% Light/Dark recheck showed both TR letters (build/tooltip-native-rail-fix.log).
- The real InstanceRail opened the actual ComponentStyleguidePage. Its live Tooltip preview, usage, scoped overlay, Escape and offscreen dismissal while outer-scrolling were inspected; route close preserved accepted local actions. Rich popup content accepted pointer/wheel access without dismissing. The fixture viewport metadata mismatch was corrected; compact account controls also passed through actual native window resizing.
- Quit only the isolated Tooltip app, then confirmed tooltipReviewRunning:false in global CUA inventory. Released the desktop slot to the coordinator before docs/commits. No app-specific query reopened it; no real account action, media session, SDK or system accessibility setting was changed.
- Final post-native run: flutter test --no-pub test/ui_tooltip_test.dart test/d_tooltip_test.dart test/styleguide test/d_button_adoption_test.dart --test-randomize-ordering-seed=random passed all 95, seed 108318862 (build/tooltip-post-native-final.log). Final flutter analyze --no-pub is clean, all 95 touched Dart files pass dart format --output=none --set-exit-if-changed, and git diff --check passes.
- Coordinator reviewed clean final Tooltip HEAD 786b6ef7177ac08374ef0822e0e3556f3c8e19d7, exact reference source mapping, controller replacement and overlay lifecycle fixes, eleven complete examples, all 105 implicit hint adoptions and native evidence. Reconciled each conflicting loading control individually: preserved all 14 Spinner owners, three InlineVideo Aspect Ratio owners and three Chat Skeleton owners in those five overlapping files while adding every reviewed Tooltip wrapper. Preserved prior library components, Label forms and the rail monogram fitting correction.
- Coordinator combined-main verification: the focused component/styleguide/theme, shell, media, composer, Chat, Voice, Poll, Local Dates and Events run passed 866 cases with one stale shell-test finder (seed 2401219401). That test incorrectly searched for an indeterminate Spinner to reopen the retained determinate update-progress control; it now uses its named Tooltip control. All 103 shell-navigation cases then passed, seed 1648058206. Logs: /private/tmp/component-tooltip-integration-tests.log and /private/tmp/component-tooltip-shell-followup-tests.log. All 95 touched Dart files are formatted; final root analysis is clean (5.5s); git diff --check passes. Auditing all changed source files found no loss of previous Spinner, Skeleton, Aspect Ratio or Label owners. Generic Tooltip and its example source are byte-identical to the native-inspected branch.

**limitations**

- iOS/Linux devices and VoiceOver speech were not run. Automated platform overrides and widget semantics assertions do not constitute device/speech testing.
- CUA AX transiently classified the actual styleguide preview Hover/Added nodes as checkboxes after outer scrolling. The visible UI and component semantics assertions were correct; the native/CUA classification cause was not diagnosed and no forced-semantics instrumentation was used. Recorded for coordinator review rather than claimed native speech parity.
- Authenticated app/plugin sessions were not opened. Native inspection used actual widgets with in-memory services; other migrations and Voice action wiring are covered by focused owner tests. The fake Voice port does not display a native mute-state change.
- Native rich-content pointer/wheel access and outer-scroll dismissal were inspected; deliberately overflowing popup-content scrolling and long press/touch gestures were verified in widget tests, not on touch hardware.
- The configured host font/palette/radius intentionally supply the reference theme variables, so glyph widths/colors can differ from Geist/neutral defaults. The composed DButton visual treatment remains its separate baseline catalogue task.

### button

Status: merged. Task: 01a083ac-5fd5-78b1-9263-7e3218a878b6. Branch: codex/ui-button.

**acceptanceCriteria**

- Match base-nova default, outline, secondary, ghost, destructive and link surfaces and all four text/icon sizes, directional icons, rounded and spinner compositions.
- Preserve compatibility variants, rich labels, tooltip shortcuts, loading names, caller-owned async operations, disabled activation, borrowed focus nodes and accessible touch targets.
- Adopt public owner in core/plugins and appropriate native-button exceptions; exercise actual components in interactive examples without changing Sidebar shell.
- Verify root/full-profile analysis and focused component/adoption/downstream tests; compare official and isolated native light/dark/custom/RTL/200% states before review_ready.

**decisions**

- Sole public renderer moved to ui/components/d_button.dart; keep compatibility theme/variants and native shell inset targets.
- Implement base-nova variants and all four text/icon sizes; directional composition, invalid/expanded/popup states and link-only navigation semantics.
- Preserve caller-owned loading/Futures, rich semantic names, borrowed focus nodes and shared Tooltip/Spinner.
- Reference sources and hashes, native adaptations and pending rendered comparison recorded in docs/component-library/button.md.
- Coordinator touch-target correction: small legacy inset surfaces keep 32px paint/40px desktop targets but clamp iOS/Android targets to 48px independently.
- Browser/export comparison corrected Small leading to22.4px, dark input-token alpha multiplication, leading loading padding, and responsive Size composition; added exact Arabic reference composition.
- Radius follow-up: xs/icon-xs=min(.8×base,10px), sm/icon-sm=min(.8×base,12px), regular/large=base per official theming scale; preserves caller radius overrides.
- Restore existing disabledOpacity scoped override with .5 default; preserve disabled/loading activation guards. No Input changes.
- Users search height follows touch targets; reorder arrows are outside CheckboxListTile semantics/height constraints, with authored40px pointer and48px touch targets.
- Native AX correction: icon-only tooltip becomes default spoken label; UserSummary count label moves onto DButton to eliminate duplicate nested buttons.

**migrations**

- All existing direct Button imports migrated to discourse_ui.dart; obsolete theme/d_button.dart removed.
- PollCard cast-votes, vote-on-web and connect-account buttons adopt DButton; existing ownership/permission/deadline behavior retained.
- StyleguideAction uses actual DButton ghost/outline controls without changing DSidebar shell ownership.
- UserSummary numeric count actions use DButtonVariant.link and retain destination callbacks/names.

**retainedAlternatives**

- Adoption guard records remaining calendar, selection-strip, composer, option-grid, topic and shell-account controls; their specific geometry/composition belongs to upcoming owners.
- CupertinoDialogAction remains inside native Cupertino alert composition pending Dialog/Alert Dialog.
- Button Group/Dropdown Menu are separate pending catalogue entries; joined Button example demonstrates compatible radius composition only.

**verification**

- Frozen Button Markdown SHA256 exactly matches catalogue; official base-nova registry and reference SVG artwork captured with hashes.
- Root and full-profile locked pub resolution passed without lockfile or SDK changes.
- 222 focused impact tests passed: Button/adoption/PollCard/styleguide/affected creation, Chat, upload, account-menu and post-action accessibility. Log /private/tmp/button-final-impact.log.
- 35 final focused Button/reference/examples/UserSummary tests passed. Log /private/tmp/button-last-tests.log.
- Root and full-profile flutter analyze --no-pub passed without diagnostics.
- Final real PollCard review-fixture macOS debug build passed. Bundle /private/tmp/DiscourseButtonReview-3a88.app has unique org.discourse.native.button-review.3a88 identity and URL scheme; deep strict ad-hoc signature passes. Source files byte-verified against pre-build manifest; kernel SHA256 4eb63551ff6daaaf3f3d15c58f2ebb2f5c0f3f4fb01e559a666cdffff4309f4e.
- All seven Button examples also passed the 260px/200%/RTL/reduced-motion layout test in Light, Dark, Forest and Plum. Example async and navigation tests pass.
- Reproduced 40px small inset touch-target defect, then passed 27 Button/Chat-header/topic-creation tests including flat/flatClose/explicit inset semantic bounds and edge activation on macOS/iOS/Android profiles. Root and full-profile analysis clean. Logs /private/tmp/button-inset-*.log.
- Corrected source byte-verified and rebuilt in /private/tmp/DiscourseButtonReview-3a88-v2.app (unique org.discourse.native.button-review.3a88.v2 ID/scheme); deep strict signature passes. Kernel SHA256 b229b90dee48bcda90cefc31e8a9f4ee398673f7400a8da4b9f3566ede5fbc26. V2 supersedes the earlier unlaunched review bundle.
- Actual CUA Chrome reference comparison completed at1270x847 and360x700 against exact current Flutter widget-test exports, including six variants, all sizes/icons/loading, settled hover/focus and Arabic RTL. Evidence/metrics/harness in docs/component-library/evidence/button; detailed findings in button-rendered-comparison.md. Browser viewport reset, original dark theme restored and tab closed.
- After rendered-comparison fixes,218 Button/styleguide/adoption/PollCard/UserSummary tests passed;11 final focused tests passed after Arabic example; root/full-profile analysis and font-loaded export harness pass.
- Compared implementation 6db474b8c16529a28d77a168d9ac9dc4fb885647 rebuilt and source-byte-verified in unlaunched /private/tmp/DiscourseButtonReview-3a88-v3.app; unique V3 ID/scheme and deep strict signature pass. Kernel SHA256 9e8e0376cc234c8be9299212620d118ca2a27b7b7ce3737b432318d8eb20ba9d. V3 supersedes earlier native review bundles.
- Radius regression reproduced 2px vs3.2px at4px base, then passed0/4/10/14/20 base radii for both constructors with live theme rebuilds. All28 affected tests and root/full analysis pass. Refreshed exact exports and inspected Light4/Forest14/Plum20 specimens without browser/native actions.
- Radius-corrected source 4483071a2b1e4a147fb9627a8b5de9713a2138b8 byte-verified and rebuilt in unlaunched /private/tmp/DiscourseButtonReview-3a88-v4.app, unique V4 identity/scheme; deep strict signature passes. Kernel SHA256 f3c167b9494e8e49c3f9f1894ff453eeffb27e0e4da57053cbb7db9102be2396. V4 supersedes V3.
- All29 affected Button/reference/example tests and root/full analysis pass after opacity override correction. V5 bundle source-byte-verified/deep-strict signed; signed entitlements omit APS/team/application identifiers while retaining local sandbox/JIT/permissions. Unlaunched /private/tmp/DiscourseButtonReview-3a88-v5.app supersedesV4; kernel0b4bdc1f7e6292fb2eb3ff8a1803c5057abd8d85b73551d6aea25552344b0e12.
- Actual V6/V8 macOS CUA inspection completed: light/dark/custom, sizes/icons,360px/200%/RTL, loading/disabled/repeat/keyboard/link behavior and real Poll/Users/UserSummary integrations. Evidence and provenance in button-native-review.md; native/browser slots explicitly RELEASED.
- Final40 focused tests pass;48 Users tests pass with only two unrelated Avatar assertions already fixed on coordinator main. Root/full analysis clean. Final source-exact V8 kernel f1d36a8fc4850705bb5fcc310bef9d27677695a3c96499f5a45fd05e95843f8c.
- Coordinator reviewed source, native V6/V8 evidence and actual application migrations; merged root search/Sidebar AX correction passed native desktop/mobile verification before Button promotion. Main merge reconciliation retains existing Avatar assertions and named independent controls.
- Coordinator main integration: 274 affected tests passed initially; Chat and Like assertions were updated from tooltip to accessible label to reflect the native icon-name fix, retaining focus/tap/keyboard checks. All 12 final affected accessibility tests pass. Root/full-profile analysis clean; source/SDK/lock pins unchanged. Logs /private/tmp/button-main-integration-tests.log and /private/tmp/button-main-accessibility-tests-final.log.

**limitations**

- Coordinator owns baseline root styleguide AX correction and final combined review. Preserve main Avatar assertions when merging. Catalogue baseline status remains for coordinator promotion after merged root AX recheck.
- No iOS/Linux native device, spoken VoiceOver or automated cross-renderer pixel-diff claim.

### separator

Status: merged. Task: 01a08213-a2e5-7692-a127-f09d2a03094b. Branch: codex/ui-separator.

**acceptanceCriteria**

- Expose DSeparator through discourse_ui.dart with horizontal/default and vertical Axis orientation, themed line, explicit length for unbounded axes, centered cross-axis space, thickness, directional indent/endIndent, and ordinary Flutter composition.
- Support bounded, intrinsic-height row, narrow, scrolling and explicitly sized unbounded layouts without overflow; retain RTL geometry and host text-scaling ownership.
- Exclude decorative separators from semantics and keyboard focus; expose caller-localized non-interactive labels for meaningful separators without inventing a resizer role or stealing adjacent controls focus/touch input.
- Read shared tokens on every build for live light/dark/site-palette changes; retain special application separator colors and spacing. No animation, controller, networking, business state or overlay ownership belongs in this widget.
- Provide interactive public-API styleguide examples and accurate usage for Usage, Vertical, Menu, List and RTL, including configurable geometry/semantics, responsive menu actions, list scrolling and empty state.
- Audit core and all bundled plugins/packages, migrate genuine Divider/VerticalDivider and equivalent separator uses, and document retained framework, border, resize and content-rendering ownership.
- Pass formatting, static analysis and focused component/styleguide/migration regressions; inspect an isolated macOS styleguide in representative widths/themes after coordinator grants the native slot, and record actual evidence plus unavailable device/VoiceOver/authenticated-screen coverage.

**decisions**

- Frozen 2026-09-08 source hash verified as b0c3b29e2b3852570144159da0ee5681074c1ddb1727d2f720a7b211f1259120; documented component prop is orientation. React className/style/render adapt to typed geometry/color properties and normal Flutter composition, with no additional package.
- DSeparator uses Flutter Divider/VerticalDivider as its rendering owner, with explicit library defaults and live DTokens.border. Default cross-axis space is the line thickness; migrations preserve previous native spacing explicitly.
- A separator fills bounded available length. A Row in unbounded height can use IntrinsicHeight with stretched children or supply length; a separator with no finite parent length and no length naturally collapses along that axis rather than inventing a dimension.
- Decorative is the default. Meaningful separators require a non-empty caller-localized semanticLabel; Flutter has no separator SemanticsRole, so they expose a static labeled semantics boundary with no actions or keyboard focus. Labels on decorative separators are rejected to avoid silently inaccessible intent.
- Hover, pressed, selected, disabled, loading, error, keyboard activation, controllers, overlays and animation are not Separator states. The sample menu/list actions retain native control focus/touch behavior; the host owns text scaling and reduced-motion preferences.
- Five real examples cover configurable horizontal semantics/insets/emphasis, horizontally scrolling intrinsic-height navigation, responsive menu descriptions/actions, a mutable separated list with empty state, and Arabic RTL plus explicitly sized unbounded composition. Narrow menus retain every destination and switch separator orientation rather than hiding Help.
- All 73 authored native Divider/VerticalDivider call sites were migrated. DSeparator delegates painting/intrinsic sizing to Flutter with explicit default thickness/space/insets/radius, excludes decorative semantics and ignores pointer input, so only the public component owns application dividing rules. Existing AppTheme DividerTheme mapping remains necessary for framework-internal controls.
- Coordinator advance review requested the public DButton owner for ordinary example actions. Vertical navigation, responsive menu actions and list controls now use DButtonVariant.flat with label composition; all three vertical usage snippets match. A fresh DefaultTextStyle inside menu labels deliberately removes DButton's compact single-line default so descriptions wrap without silent truncation. No adoption-guard exception was added.
- Native macOS inspection covered all five examples and real migrated widgets in temporary local fixtures. The day, picker and sheet adapters remain application-owned; their fixture registration and signing adjustments are outside the repository. Final example text uses singular 1 item and the list snippet matches the rendered subtitle layout.
- Acceptance criteria are satisfied for the implemented API, migrations, automated checks and recorded macOS scenarios. Separator is implemented in the styleguide and review_ready for coordinator review; uninspected platform/screen-reader/authenticated flows remain explicitly limited below.

**migrations**

- 53 Divider/VerticalDivider usages in core shell files now use public DSeparator: list rows and loading-list boundaries, user/preferences/group panes, sheets, pickers and native-menu compositions, topic/date streams, diagnostics, drafts, badges, bookmarks, search, uploads and the instance rail. Horizontal height and vertical width become orientation-independent space; prior 17/24 spacing and specialized colors are preserved.
- 19 dividing rules migrated in Assign, Chat, Discourse Events, GIFs, Local Dates, Poll and Voice plugins. Existing permission checks, list lazy construction, async ownership and callbacks are unchanged; Chat unread marker keeps its error color and visible New label, Assign keeps its ledger color.
- The styleguide pane separator uses DSeparator. Public barrel export and dedicated separator_examples.dart registration added. Existing barrel imports were extended and redundant baseline control imports removed where a new complete barrel import already supplies them.
- Three equivalent container rules migrated: forum tab gaps retain 1×18 geometry and hover/selected visibility, MessageInboxTitle retains its 18px line and 10px margins through space: 21, and instance sidebar section boundaries retain their sliver insets and spacing.
- Updated the existing anchored picker, topic day separator, group list geometry and forum tab tests to assert public DSeparator boundaries while preserving their behavior assertions. Audited all lib/src/plugins modules, packages (including vendored Dart libraries) and profiles; no additional authored package/profile separators were found.

**retainedAlternatives**

- Flutter Divider and VerticalDivider remain the sole paint/intrinsic-layout owners inside DSeparator. Framework-internal menu/control separators and AppTheme DividerTheme remain native. No authored PopupMenuDivider call sites existed; a future PopupMenuEntry separator must retain that framework entry contract.
- Container/ShapeBorder/BoxDecoration borders on pane edges, cards, tab selection indicators, pickers and controls remain part of their surface/layout ownership. Prometheus alert tables retain TableBorder for coordinated table grid painting; these are not independent content separator widgets.
- ResizablePaneHandle and the Chat thread split retain adjustable handle rendering and their hit/focus/drag geometry; they belong to Resizable, not the non-interactive Separator.
- Cooked HTML hr rules remain in the HTML renderer/CSS adapter to preserve markup, margins and content-selection ownership. StreamDaySeparator keeps date semantics, floating behavior and callbacks while its visual rule uses DSeparator.
- LoadingSkeleton and indeterminate activity indicators remain owned by the concurrent Skeleton and Spinner tasks. Only rules between loading rows changed on this branch; their placeholder content and business state are untouched.

**verification**

- Flutter 3.47.2 / Dart 3.13.2 verified. flutter pub get --enforce-lockfile passed without dependency, pin or lockfile changes.
- flutter analyze --no-pub passed with no diagnostics after migration imports and tests were corrected.
- flutter test --no-pub test/ui/d_separator_test.dart test/styleguide/separator_examples_test.dart --test-randomize-ordering-seed=random: all 21 passed, seed 3679188485. Covers bounded/unbounded/intrinsic sizing, parent constraints, RTL insets, decorative/meaningful static semantics, pointer pass-through and Tab/Enter, live token/fallback/override colors, native MenuAnchor intrinsic sizing and open-menu theme updates/focus restoration, real example actions/list scrolling/empty state and catalogue navigation. Every example also renders at 320/760px, 200% text and RTL with reduced motion in light/dark/Forest/Plum.
- flutter test --no-pub test/anchored_picker_test.dart test/topic_day_separator_test.dart test/group_page_test.dart test/group_member_menu_ownership_test.dart test/preferences_page_test.dart test/forum_tabs_bar_test.dart test/aggregate_view_test.dart test/chat_drawer_test.dart test/user_menu_button_accessibility_test.dart test/user_menu_message_accessibility_test.dart test/user_menu_site_identity_test.dart test/draft_list_test.dart test/instance_actions_accessibility_test.dart test/forum_search_clear_accessibility_test.dart test/topic_create_button_accessibility_test.dart test/topic_actions_menu_test.dart test/topic_list_filter_menu_ownership_test.dart test/emoji_picker_test.dart test/bookmark_ui_test.dart test/diagnostics_panel_test.dart test/badges_page_test.dart test/users_page_test.dart test/composer_toolbar_test.dart test/assign_plugin_test.dart test/assigned_group_view_test.dart test/chat_channel_info_view_test.dart test/chat_transcript_test.dart test/chat_search_test.dart test/event_card_test.dart test/gif_picker_test.dart test/voice_diagnostics_view_test.dart test/voice_room_view_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_widget_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=random: all 548 passed, seed 3396198342. Covers 36 affected core/plugin/styleguide test files, including actual list geometry, permission and menu/sheet lifecycle regressions.
- Built flutter build macos --debug --no-pub -t lib/styleguide_main.dart successfully from isolated temporary copy /var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/discourse-native-separator.3ka532q1. PRODUCT_NAME DiscourseSeparatorStyleguide, bundle org.discourse.native.styleguide.separator, and signing changes exist only in that temporary copy.
- git diff --check passed. Production native runners, dependency lockfiles, Flutter pin and frozen catalogue are unchanged.
- dart format --output=none --set-exit-if-changed on all 61 touched Dart files passed (0 changes). Only the assigned Separator progress row differs from the dispatch base.
- flutter test --no-pub test/message_inbox_page_test.dart test/sidebar_width_test.dart test/event_sidebar_boundary_test.dart --test-randomize-ordering-seed=random: all 19 passed, seed 3080551253. These additional final-audit checks cover the migrated inbox-title and sidebar container rules, constrained inbox navigation and sidebar layout/lifecycle.
- After the DButton review fix: flutter test --no-pub test/styleguide/separator_examples_test.dart --test-randomize-ordering-seed=random passed all 10 examples tests, seed 2524191817. The responsive menu interaction test now runs at 320/760px with 200% text and asserts RenderParagraph.didExceedMaxLines is false for all three descriptions; list tests assert DButton disabled/enabled behavior after clear/add.
- CUA selected /var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/discourse-native-separator.3ka532q1/build/macos/Build/Products/Debug/DiscourseSeparatorStyleguide.app with cua.getApp and used the window Raise action after the coordinator granted the native slot. All interactions used this distinct product/bundle and lib/styleguide_main.dart. No production runner changed.
- Native macOS: searched the catalogue and inspected horizontal Separator in Light and Dark. Toggled Meaningful boundary, Asymmetric insets and Emphasize boundary; visually confirmed line thickness/insets and retained switch state after a live Dark/RTL change. Decorative versus meaningful semantics were tested through Flutter semantics, not claimed from VoiceOver speech.
- Native macOS: inspected Dark vertical navigation, visible DButton keyboard focus, and successive Tab/Return activation of Docs and Source across the rules. Inspected the wide responsive menu, selected Help, then switched to Forest site, 360px preview, 200% text and reduced motion; descriptions stayed readable, separators changed to horizontal and inner scrolling revealed retained Selected: Help.
- Native macOS: inspected Arabic RTL and asymmetric horizontal insets in Forest/Plum at 360px and 200%, including the fixed-length vertical rule beside wrapping text and the explicit horizontal length in an unbounded row. Inspected the Plum list, selected Item 2, scrolled through Item 12 while preserving selection, cleared to an empty list with no rules, and added a first item with no trailing rule.
- Native migrated fixtures: instantiated actual StreamDaySeparator, AnchoredPickerContent and showShellSheet with local callbacks in temporary separator_native_fixtures.dart. At Plum/360px/200%, clicking the date then the rule produced exactly one date activation. Picker selection, typing Alpha to filter, the selection marker and header/footer rules worked. Switching the mounted picker to Light retained its query and Alpha selection. Real sheet header/footer rules rendered in Plum and Light; footer close and Escape dismissal returned to the retained picker. The sheet uses its existing root Navigator and inherited root text scale; it is not claimed as a 200% dialog check.
- Native inspection completed and the shared desktop slot was explicitly released to coordinator before final documentation/checks. No approval block or native component failure occurred. No further CUA or focus actions were performed after release.
- Final flutter test --no-pub test/styleguide/separator_examples_test.dart --test-randomize-ordering-seed=random passed all 10 after the native-observed singular-item text correction, seed 1551245093. flutter analyze --no-pub passed with no issues (4.4s). dart format of the two changed example/test files reported 0 changes. The unchanged 588-test component/migration result was not repeated.
- Final refreshed isolated flutter build macos --debug --no-pub -t lib/styleguide_main.dart passed with the DButton examples, implemented status and final usage/count text. This build occurred after releasing the desktop slot, with no app focus or CUA action.
- Coordinator accepted the completed native inspection, reviewed the component, migrations, DButton cleanup and wrapping regression, and reported no remaining implementation issue before final commits. The corrected DButton adoption guard on combined main is owned by coordinator review; no local guard exception or unmerged component code was introduced.
- Coordinator reviewed the full DSeparator API, sizing and semantics tests, core/plugin migrations, final DButton examples and wrapping regression, and recorded macOS evidence. Reconciled shared exports, example registration and duplicate public imports with merged Typography while preserving every other progress row and the native inspection queue.
- Coordinator combined-main verification: 132 tests passed, seed 970432551, covering DSeparator, all merged styleguide examples, the corrected DButton adoption guard, anchored pickers, date separators, tabs, inbox/sidebar layout, Chat drawer and Poll/Local Dates sheets. An import accidentally removed during conflict cleanup was restored before this successful run. flutter analyze --no-pub passed with no issues; 61 changed Dart files were already formatted and git diff --check passed. Logs: /private/tmp/separator-coordinator-tests-final.log and /private/tmp/separator-coordinator-analysis-final.log. The final worker tip changed only its implementation SHA record; the verified Dart files were preserved byte-for-byte while including that final metadata commit.

**limitations**

- Native device inspection was macOS 26.6.2 on darwin-arm64. Linux device inspection is unavailable on this host. Flutter devices detected a wireless iPhone running iOS 26.6, but it was not launched or controlled; iOS device behavior is unverified.
- VoiceOver speech was not run. Static boundary labels/actions/direction are covered by widget semantics tests. CUA exposed limited AX content outside native popup/dialog surfaces, so pointer locations came from observed screenshots where necessary.
- Authenticated core/plugin screens were not inspected in a signed-in session. Native migration evidence uses the actual date/picker/sheet widgets with local temporary fixtures, while the broader app/plugin migrations are covered by the 567 focused regression tests already listed.
- Live theme changes in an already-open native MenuAnchor are verified by widget tests. Native palette settings normally dismiss menus on outside interaction, so manual overlay evidence covers rendering after selecting the palette, plus dismissal and preserved local state.
- The native inspection preceded final styleguide implemented metadata and a singular-item/usage-text correction. Those non-behavioral text changes were verified by the final focused example test run and refreshed isolated build without reacquiring desktop focus.

### label

Status: merged. Task: 01a0825a-9fe1-7700-878c-f448801c0851. Branch: codex/ui-label.

**acceptanceCriteria**

- Account for the frozen Installation, Usage, Label in Field, RTL and API Reference sections, with hash 7263b641bac78acd5ec6cfbffefeddda484eaedb1d32b8a73a675b53da0644c2. Export DLabel through discourse_ui.dart without external runtime dependencies.
- Match the official registry Label metrics: text-sm=14 logical pixels, font-medium=weight 500, leading-none=line height 1, gap-2=8 pixels in composed rows, zero outer padding/border/radius, select-none and disabled opacity 0.5. Preserve host font family, live DTokens foreground, inherited text scaling/direction and unconstrained wrapping.
- Use the title/label slots of native Flutter controls for association, full-row touch activation, one accessible control name/state, one keyboard focus target, visible focus, and disabled/busy guards. Keep native InputDecoration and Form validation ownership and do not add an HTML ID registry or a second form/focus system.
- Demonstrate basic checkbox labeling, disabled states, rich wrapping content, native form labels/descriptions/errors and submission/reset, Arabic/Hebrew RTL, and lifecycle/state retention with runnable public widgets and accurate snippets.
- Audit core and every bundled plugin; migrate appropriate checkbox/switch label titles, preserve native field labels and non-control metadata, and document retained alternatives.
- Format and analyze, pass focused component/example/migration/downstream tests, build and verify an isolated macOS app identity, then inspect styleguide and real migrated production surfaces only after coordinator grants the shared desktop slot.

**decisions**

- The official base-nova registry source renders a styled native HTML label with ordinary element props. The catalogue outline variant, horizontal orientation, and button/submit types belong to neighboring controls in the Field demo, not Label variants.
- DLabel accepts child composition, optional TextStyle emphasis and enabled state. It derives the host font family from DText small and reuses DiscourseTypography.sm for the unscaled 14px metric, then applies shadcn weight 500, line height 1 and zero letter spacing. Existing native control slots own association, activation and semantics as temporary composition while Checkbox/Switch/Input/Field are pending. Their tasks must port shadcn visuals while preserving native behavior.
- The linked Base UI Label API and .md endpoint return HTTP 404 on 2026-09-08; inspected the frozen Markdown and official shadcn base-nova registry source instead. No missing API is inferred.
- The label creates no focus target, gesture handler, overlay, animation, controller, networking or business state. Native owners retain lifecycle and interaction; disabled content uses full-subtree opacity 0.5, a forbidden pointer cursor, disabled semantics, IgnorePointer and ExcludeFocus. Callers must also disable the native control callback.
- Visual fidelity mapping: HTML label -> DLabel content in an existing native label slot; flex items-center/gap-2 -> centered Row with 8 logical pixels for icons/spans; text-sm/font-medium/leading-none -> 14 px/500/1; select-none -> SelectionContainer.disabled; disabled opacity-50 -> Opacity(0.5); peer-disabled cursor/pointer rules -> forbidden cursor and interaction suppression. The component has no default outer padding, border, radius or background. Native control hit areas and control visuals belong to their respective controls, which are not implemented by this task.
- docs/component-library/label-visual-mapping.md records the official registry URL, raw registry SHA256 89b01e14fd39dceece9fa421e71e78ea83286bd43a2ca1c2f55d2e8d3958fff2 and UTF-8 label.tsx content SHA256 b3b7b21d2877838fc73713df48a47248392de04a3b3fafa8961369f33ab14530, with the exact visual mapping and FieldDemo handoff.

**migrations**

- Core: AppSettingsModal GIF switch, Preferences linked-post notifications, InviteEditor send-email option, PostFlagEditor legal confirmation, TopicMovePosts chronological order, UserStatusEditor pause notifications, and GroupPage membership/read-state/SMTP/unknown-sender options now use DLabel. Existing permission, busy, validation and callback ownership remains unchanged.
- Bundled plugins: Poll public-voter/automatic-close settings; Local Dates end/countdown/time options; Events all-day and dynamic boolean fields; Voice privacy acknowledgment, room options, push-to-talk and auto-status settings use DLabel.
- VoiceDiagnosticsView replaces its unassociated caption-plus-switch Row with a native SwitchListTile using DLabel and one combined semantic control. Tapping the recording caption now enters the existing consent flow; busy/start/stop callbacks are retained. Its old DecoratedBox surface becomes Material with the same color/border/radius so native focus and ink remain visible.

**retainedAlternatives**

- Native InputDecoration.labelText is temporarily retained in existing core/plugin fields to preserve accessible naming, focus/error behavior, descriptions and validation. Input and Field own its future shadcn visual port; floating native appearance is not a blanket final exception. The Label page's larger payment/billing FieldDemo, FieldLabel, descriptions, errors and field-set composition belong to the scheduled Field task.
- Core user/group/topic result lists, image selection, aggregate/feed/post selection, topic property metadata, revision section captions, badges, menu labels and action text retain their existing list/typography owners. They are selection content or descriptions rather than standalone control labels.
- Every bundled plugin was searched: Assign and Chat use native field labels and selection/message content; Discourse AI, GitHub, Lazy Videos, GIFs, Prometheus Alert Receiver and Reactions contain no standalone input label needing replacement. GitHub issue labels are domain badges. Poll/Local Dates/Events/Voice migrations are listed above. packages/discourse_voice is a native bridge; profiles/full shares this same bundled UI and has no separate label renderer.

**verification**

- Frozen Label Markdown SHA256 verified as 7263b641bac78acd5ec6cfbffefeddda484eaedb1d32b8a73a675b53da0644c2; inspected https://ui.shadcn.com/docs/components/base/label and https://ui.shadcn.com/r/styles/base-nova/label.json. Linked Base UI Label HTML/.md endpoints returned HTTP 404.
- flutter pub get --enforce-lockfile passed on Flutter 3.47.2 / Dart 3.13.2 without lockfile changes.
- flutter analyze --no-pub passed with no issues. All touched Dart files formatted; git diff --check passed.
- flutter test --no-pub test/ui/d_label_test.dart test/styleguide/label_examples_test.dart test/voice_diagnostics_view_test.dart test/app_settings_page_test.dart test/preferences_page_test.dart test/user_status_editor_test.dart test/invite_list_test.dart test/post_flag_editor_test.dart test/post_flag_editor_ownership_test.dart test/topic_move_posts_ownership_test.dart test/group_page_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/event_composer_test.dart test/voice_room_view_test.dart test/voice_diagnostics_panel_test.dart test/styleguide/styleguide_page_test.dart test/d_button_adoption_test.dart test/ui/d_typography_test.dart --test-randomize-ordering-seed=random: 267 passed, seed 1867985777. Log: /private/tmp/ui-label-regression-tests.log.
- After final centered rich-content mapping and test cleanup, flutter test --no-pub test/ui/d_label_test.dart test/styleguide/label_examples_test.dart --test-randomize-ordering-seed=random: 19 passed, seed 1609358833. Log: /private/tmp/ui-label-final-component-tests.log. Component checks cover native label/row and semantic activation, checked/disabled semantics, one Tab stop/Space/Shift-Tab, removal during activation, disabled descendants, non-selectability, exact text metrics, live light/dark/Forest/Plum/default themes, RTL and 200% text at 216px and 720px. Example checks cover required input naming/focus/error/save/reset, rich-label wrapping and independent terms action, RTL interactions, theme/width/scale/direction/motion state retention and Reset.
- Built the temporary in-memory fixture target build/label-inspection/main.dart with flutter build macos --debug --no-pub -t build/label-inspection/main.dart. Final app: build/macos/Build/Products/Debug/Discourse Label.app. Actual Info.plist verified CFBundleName/Executable=Discourse Label, CFBundleIdentifier=org.discourse.native.label-review, URL scheme=discourse-label-review. Temporary Xcode/Info overrides were restored. Fixture mounts the real PostFlagEditor, VoiceMeshPrivacyDialog and VoiceDiagnosticsView as well as ComponentStyleguidePage. Ad-hoc signature verified with codesign --verify --deep --strict. The app was launched only after the coordinator granted the desktop slot.
- Coordinator prereview follow-up: added label-visual-mapping.md with raw registry and source-content hashes, reused DiscourseTypography.sm, and clarified that native control visuals are temporary and the full FieldDemo belongs to Field. flutter analyze --no-pub passed; flutter test --no-pub test/ui/d_label_test.dart test/styleguide/label_examples_test.dart --test-randomize-ordering-seed=random: 19 passed, seed 4088727084. Logs: /private/tmp/ui-label-prereview-analysis.log and /private/tmp/ui-label-prereview-tests.log.
- macOS CUA on 2026-09-08: styleguide label-text clicks, Tab/Space activation with visible native control focus, disabled pointer guards and live Light/Dark themes passed. Forest rich content plus its independent terms action wrapped at 360px/200%. Plum Arabic/Hebrew RTL leading controls and label clicks passed at 360px/200%. The Plum native form at 360px/200% showed the empty validation error, focused from its email label, accepted literal reader@example.test input, saved locally, and reset field/checkbox/result/error. Screenshots: build/label-inspection/screenshots/{light-disabled,dark-enabled,forest-rich-360-200,plum-rtl-360-200,plum-form-error-360-200,plum-form-saved-360-200}.png.
- macOS actual production widgets in local fixtures: PostFlagEditor in Dark preserved explanation and checked legal confirmation through busy-disabled state and a retained local error, then returned successfully on retry. VoiceMeshPrivacyDialog in Forest at 200% text fit without clipping, toggled from its label and cancelled. VoiceDiagnosticsView in Forest opened the existing consent flow from Recording Off; Cancel kept it off, confirm updated the local fixture to Recording On, and caption activation stopped it. No account data, network calls, room join or actual recording was involved. Screenshots: build/label-inspection/screenshots/{post-flag-busy,post-flag-retained-error,voice-privacy-forest-200,voice-diagnostics-consent,voice-diagnostics-on,voice-diagnostics-off}.png.
- Native macOS AX snapshots exposed the named legal and privacy checkboxes with checked value, and one named Recording Off/On switch with the corresponding off/on state. Snapshot excerpts: build/label-inspection/{post-flag-busy,voice-privacy,voice-diagnostics-on,voice-diagnostics-off}-ax.txt. Widget semantics checks additionally verify required input naming, combined controls, disabled state and semantic activation.
- Quit only Discourse Label.app through its native menu. A subsequent global CUA getState confirmed org.discourse.native.label-review was absent; released the desktop slot to the coordinator. docs/component-library/label-visual-mapping.md records the inspection evidence. Example group marked implemented only after this verification; mergeCommit remains null.
- Coordinator reviewed the generic API, all control-label migrations and focused regression coverage at stable HEAD 1c8348cf85aa76001d701837545e123eff06eafc. Reviewed native Light disabled, Plum RTL at 360px/200%, and actual PostFlagEditor retained-error screenshots; checked native consent/busy/retry evidence and explicit Input/Field handoffs. Reconciled the public barrel, example registrations and progress metadata while preserving newer Kbd, Skeleton and Typography work.
- Coordinator combined integration check on main: flutter test --no-pub test/ui test/styleguide plus Voice diagnostics, Settings, Preferences, User Status, Invites, Post Flag, Topic Move, Groups, Poll, Local Dates, Events, Voice room/panel and DButton adoption regressions passed all 374 tests, seed 4174198982. flutter analyze --no-pub passed with no diagnostics in 10.3s; all 22 touched Dart files passed format checking, and git diff --check passed. Logs: /private/tmp/component-label-integration-tests.log and /private/tmp/component-label-integration-analysis.log. Generic Label, its examples and their focused tests are byte-identical to the inspected worker source.

**limitations**

- iOS and Linux are uninspected on devices. A wireless iPhone was detected but has not been run. No new native platform dependency is introduced.
- The macOS styleguide route exposed only its native search field through the CUA accessibility snapshot. Preview semantics are verified by widget tests; production dialog/view snapshots exposed the named control states. VoiceOver speech was not run.
- Checkbox/Switch/TextFormField and baseline DButton visuals in Label examples are temporary until their catalogue tasks implement the reference controls. This task completes Label only and does not exempt those components or FieldDemo from shadcn fidelity.

### badge

Status: merged. Task: 01a083ac-c98c-7fe0-878d-54ee3bcbebb9. Branch: codex/ui-badge.

**acceptanceCriteria**

- Reproduce base-nova default, secondary, destructive, outline, ghost and link variants with 20px visual height, 12/16px medium type, 12px icon slots, directional insets, pill shape and exact token-based states.
- Provide static and actionable/link compositions with keyboard focus and activation, disabled and invalid semantics, borrowed focus node safety, accessible touch targets, wrapping large labels, RTL and live palettes.
- Demonstrate every frozen section using DBadge and DSpinner, audit core and plugins and migrate justified status/counter owners without changing business state.
- Pass root/full-profile analysis and focused component/example/migration tests; compare reference and isolated native styleguide plus real migrated fixtures under a coordinator-granted desktop slot before review_ready.

**decisions**

- Frozen Badge Markdown matches the catalogue hash; captured official base-nova registry, examples and Lucide artwork with exact hashes and source-to-Flutter mapping in docs/component-library/badge.md.
- Public DBadge supports six treatments, static/action/link composition, decorative leading/trailing widgets, custom live colors, disabled callbacks, invalid/name/value/live semantics and owned-or-borrowed focus. Pointer activation transfers keyboard focus; links use Enter and actions use Enter/Space.
- Preserve 20px default visuals, 12/16px medium type, 12px artwork and 4px gaps. Large labels grow/wrap, touch actions reserve 48px, and rounded-4xl maps to 2.6× configured radius (10.4px at host default 4; reference 26px at 10), using the live website globals override, not rounded-full.
- Spinner remains the only implementation dependency. Button is baseline only for example controls; Badge imports no unfinished Button code. Six full styleguide sections retain the redesigned documentation shell.
- Native/browser comparison completed under the granted exclusive slot; Badge is review_ready for coordinator review. Slot released, task tab closed and isolated app quit.
- Ring uses animated exterior-only rounded-rectangle difference, preventing tint in transparent/translucent interiors. Frozen registry and compiled CSS require only a destructive border for idle invalid; 3px ring width applies on focus-visible.

**migrations**

- Core: TopicUnreadBadge exact count and tooltip; user-menu capped count with full accessible value; user-card staff/suspension labels and earned badge count; GroupsPage membership and GroupPage member-owner labels.
- Plugin: Chat drawer numeric urgent counts use DBadge with preserved domain calculations and 99+ visual cap/full accessible count. At minimum width with large text, metadata moves below preview to preserve title/lock space.
- Spinner styleguide temporary badge renderer removed in favor of DBadge and DSpinner; sample busy/direction controls retained.
- Self-contained native-review fixtures mount real GroupsPage, TopicUnreadBadge, staff UserCardTarget and ChatDrawerChannelsView backed by in-memory stores/API.
- Native narrow Groups footer overflow corrected: member count wraps in flexible width beside Member/Owner badge. Final native reinspection and narrow RTL regression pass.

**retainedAlternatives**

- Anchored avatar/header/rail counters and flair retain overlay geometry and parent-owned semantics; unread dots remain dots.
- Composer Mention/Hashtag/Poll/Local Dates/Link pills retain editing/serialization/baseline behavior; reaction/like/taxonomy controls retain separate interaction owners.
- Voice recording privacy banner, award artwork/tier text, image counter overlays, decorative aggregate artwork, GitHub diff counts and plugin banners remain distinct. Full core/plugin audit is documented in badge.md.

**verification**

- Flutter 3.47.2 / Dart 3.13.2. Root and full-profile locked pub get passed without SDK/pin/lockfile churn.
- 254 focused component/example/real-fixture/core/Chat tests passed with seed 792026; command/output /private/tmp/badge-final-tests.log. Narrow large-text Chat overflow fixed and regression strengthened.
- Root flutter analyze --no-pub and profiles/full flutter analyze --no-pub pass without diagnostics. Touched Dart formatted; git diff --check passes.
- Isolated macOS debug build succeeded; bundle org.discourse.native.badge.bebb9 / Badge Review BEBB9. Deep strict ad-hoc signature verification passes. Complete relevant Dart source matches the checkout; kernel and source-manifest hashes recorded in badge-native.md.
- Coordinator-granted browser-only comparison completed; theme restored, own tab closed and slot released. No native app launched while Mac locked. Evidence and exact export harness in evidence/badge/.
- Exact final test command: flutter test --no-pub test/d_badge_test.dart test/badge_migrations_test.dart test/styleguide/badge_examples_test.dart test/styleguide/spinner_examples_test.dart test/groups_page_test.dart test/group_page_test.dart test/user_card_test.dart test/user_card_target_accessibility_test.dart test/user_card_account_lifecycle_test.dart test/user_menu_message_accessibility_test.dart test/plugin_user_menu_widget_test.dart test/chat_drawer_test.dart test/chat_shell_integration_test.dart test/topic_list_view_lifecycle_test.dart --test-randomize-ordering-seed=792026 --reporter expanded. All 254 pass.
- Browser corrections pass 39 focused tests, seed 792027, and widget-renderer export test. Radius source scale and bundled SVG paths verified against live computed styles.
- Exterior ring followup: six light/dark pixel regressions reproduced tint before correction; 46 affected tests including renderer export pass seed 792028. Root/full analysis clean; isolated source-matching bundle rebuilt, deep strict signature verified, restricted entitlement omission confirmed by signed read-back. No UI accessed.
- Final native review: 59 affected permanent tests pass seed792030 plus updated renderer export; root/full analysis clean. Actual 200% root profile staff/count, compact states, exterior rings, 360px/200% RTL custom palettes, topic counts, Groups and Chat inspected. Final source-matching unique signed bundle and entitlement read-back in evidence/badge/native/build-identity.json. Exclusive native/browser slot released.
- Coordinator reviewed source/migration changes and native variants, exterior ring, actual200% profile and wrapped Groups/Chat screenshots. Shared imports/exports reconcile with final merged Button without changing the Badge renderer.
- Coordinator integration with final Button: initial impact run passed272 checks and exposed5 Groups/Chat layout regressions. Desktop/touch Group action heights, touch search height and symmetric Sidebar switch padding were reconciled without changing Badge. Final37 Group checks and1 switcher regression pass; root/full analysis and diff checks clean. Logs: /private/tmp/badge-main-integration-tests.log, /private/tmp/badge-button-groups-integration-final.log, /private/tmp/badge-button-switcher-integration.log, /private/tmp/badge-main-integration-analysis-final.log and /private/tmp/badge-main-integration-analysis-full-final.log. Native Badge source/evidence remains unchanged; these bounded Button app-adapter changes were verified with affected widget tests.

**limitations**

- No iOS/Linux device, spoken VoiceOver or authenticated production-flow testing. Native AX text and automated semantics checked; representative assigned macOS scenarios complete.
- Geist/SF metrics, underline offset and clipped sRGB custom colors differ from wide-gamut CSS. At 200% the existing profile name/action text ellipsizes; its staff/count Badge labels remain visible. Invalid browser states use a clearly identified fixture built from frozen classes and the official compiled stylesheet.

### input

Status: merged. Task: 01a083ad-3168-7c01-b35a-7271f9fe6326. Branch: codex/ui-input.

**acceptanceCriteria**

- Match official base-nova Input geometry, typography, border, placeholder, focus, disabled and invalid states with recorded source hashes and actual native comparison.
- Implement single-line native editing with owned/borrowed controller and focus lifecycle, initial and controlled updates, Form validation/save/reset, secure entry, keyboard configuration, read-only, disabled, selection and IME preservation.
- Audit core and plugin fields; migrate appropriate single-line inputs and Sidebar adapter while preserving app behavior, documenting retained Textarea/Field/Input Group owners and shared-file conflicts.
- Provide actual component examples for documented Input capabilities and compositions, forms, independent state, RTL/long text, live palettes and 200 percent/narrow layouts.
- Format touched source; pass root/full-profile analysis and focused editing, lifecycle, example and migration regressions; inspect isolated exact-source native review build only after coordinator desktop authorization.

**decisions**

- Official Input Markdown matches frozen SHA256; base-nova source and concrete state/geometry mapping are preserved in docs/component-library/input-reference.md.
- One DInput FormField/TextField owner handles native editing and lifecycle. Controller/value/initialValue modes are exclusive; reset preserves the mount snapshot like pinned TextFormField and synchronizes visible text/Form state.
- Desktop uses 14/20px typography; touch uses 16/24px and a transparent 48px target. File selection composes a 24px Button visual in a 32px input and host-owned asynchronous picker callback.
- Simple prefix/suffix slots support app search/status controls; no new shared primitive or full Field/Input Group/Textarea/OTP renderer is introduced.
- File selector foreground and compact surface are laid out separately: desktop field remains 32px, touch Button keeps an unclipped 48px target. Explicit 14/20 medium file label and zero padding survive Button integration; coordinator must select the completed extraSmall enum after Button merges.
- Bounded source/render correction: input role uses colors.outlineVariant; source opacity modifiers multiply existing alpha. Interpolating exterior-only 3px annulus replaces spread shadows to avoid fill tint.
- DFileInput owns one half-opacity layer around surface/content. Existing Button remains truly disabled, with its baseline disabledOpacity locally neutralized through the actual theme API; final Button merge must reconcile 24px size/import and disabled-theme compatibility.

**migrations**

- Migrated Add a Site, InviteEditor single-line validators, change-owner/move-post searches and title, link dialog, permanent-delete confirmation and message title.
- Migrated Chat channel name/slug/thread title, GIF query, Poll title/options/range/close, Local Dates format/timezone/date/time, Events single-line attributes, Voice room metadata.
- DSidebarInput now delegates to DInput and its duplicate InputDecoration was removed. The documentation search now uses DInput while preserving the shared Sidebar shell, shortcuts, clear and mobile state.

**retainedAlternatives**

- Multiline/rich composers and descriptions remain with Textarea/Input Group owners; inline tab/composer titles retain borderless inline geometry.
- Command/Combobox/token/member-picker and schema-driven Field compositions retain their existing renderers pending their complete owner migration. Remaining directory/search and earlier component-example opportunities are listed explicitly in input-reference.md.

**verification**

- flutter pub get --enforce-lockfile passed at root and profiles/full without lockfile/SDK changes.
- Root and profiles/full flutter analyze --no-pub are clean; touched files are formatted and git diff --check passes.
- Focused impact run (19 suites, seed 928374611): 357 passed, one new semantics assertion needed a frame pump. After the test-only correction, all 12 Input tests plus the Button adoption guard passed (13 total) with the same seed. Logs: /tmp/input-final-focused.log and /tmp/input-final-unit.log.
- Coverage includes all seven actual examples at 320px/200% RTL in Light/Dark/Forest/Plum, editing/IME/controller/reset/form/file regressions, real app async ownership and validation, Sidebar/navigation, Voice and Chat/link editing.
- flutter build macos --debug --no-pub -t tool/input_review_main.dart passed. Fixture mounts real Add a Site and Poll editor against local fake data plus actual Input samples and the full styleguide.
- Isolated native bundle /private/tmp/DiscourseInputReview-01a083ad.app built from implementation source ae4aa4a8. CFBundleIdentifier org.discourse.native.input.01a083ad and unique discourse-input-review-01a083ad scheme; codesign --verify --deep --strict passes. Source-build and isolated-copy kernels both SHA256 f9d9ddb13dba95a076d165d84db1eafcbfd3215232bb161782ad53b17e647089. Bundle is prepared but has not been launched.
- Final file-target and responsive-form refinements: all 20 Input/component-example tests passed with seed 928374611; root/full-profile analysis and isolated macOS rebuild passed. Live grid-to-stack/palette changes preserve field identity, edited text and reset baseline. Logs: /tmp/input-final-refinements.log, /tmp/input-refinements-analysis.log, /tmp/input-refinements-full-analysis.log, /tmp/input-refinements-native-build.log.
- Refreshed isolated bundle from final implementation source 4e1eb3b3fe499868e4ee70f86cb48a987c4040e8. Source/copy kernels both SHA256 400b22d515a8be38b71865ddbf53b4c56da175574bbc96ef0d4473b83e959506; unique identifier/scheme restored and deep strict ad-hoc signature verification passed. It remains unlaunched pending the serialized desktop slot.
- Correction passes all 363 focused component/example/migration tests (seed 928374611). Root/full analysis, formatting/diff checks and isolated macOS fixture rebuild pass. Logs are recorded in input-reference.md.
- Eight font-loaded Flutter exports plus pixel tests verify .15*.3 dark fill, role separation, no interior focus/invalid tint, exterior ring bounds, disabled fill and equal half-opacity file trigger/filename with disabled Button semantics. Hashed exports: docs/component-library/evidence/input/correction/. No CUA or browser/app launch.
- Correction native checkpoint 3800505aacce361f92bc71ff18332f58bf3cb07e: refreshed /private/tmp/DiscourseInputReview-01a083ad.app, unique org.discourse.native.input.01a083ad identity and discourse-input-review-01a083ad scheme. Source/copy kernel SHA256 both 661a1bb69eaf830e8c84de3f2931d1f2df5b760ea3dc4e86980c386cd243939a; deep strict ad-hoc signature passes. Remains unlaunched, in_progress/awaiting_slot.
- Official browser computed-style/crop comparison corrected file gap to 4px and Field label/description leading to 19.25/21px. Sixteen font-loaded Flutter exports cover all registered examples in both app palettes and real Add Site/Invite editors. All 366 focused tests (seed 928374611), root/full analysis and exact-source native build pass. Browser slot explicitly released; prior tab absent after interruption, restoration not verifiable. Evidence and logs: input-reference.md.
- Latest source a1020b6745954e54d72183729bc2f86049a949e6: unique signed /private/tmp/DiscourseInputReview-01a083ad.app refreshed, deep strict signature passes, source/copy kernel SHA256 b034361de32ad1e22d036fc1d4e0334f262b4ce1bc5eeee287751ad748211ba3. Remains unlaunched and awaiting_slot.
- Semantics correction source 0464e555817ef8dae4fe63b1e8dd48548a2c3bed: editor container prevents editable role from merging into its page; Sidebar adoption inherits it and File Button remains separate. Three boundary regressions plus affected suites pass (369 tests, seed 928374611), root/full analysis clean. Exact-source unique /private/tmp/DiscourseInputReview-01a083ad.app rebuilt and deep strict ad-hoc signed with empty entitlements (no restricted entitlements); source/copy kernel SHA256 53eaa15f083810cdf1e97449df3abd24386bd355754e74795493797a5c13b34b. Unlaunched, awaiting_slot; no UI interaction.
- Final Button integration source 3201d96b51f86abbb638218eee8d0178ef168938 merges pinned main9d7a49e; all non-Input progress rows and merged Button/Avatar owners preserved. File trigger uses sibling Button extraSmall24px and scoped disabledOpacity1; pixel checks use actual independent label rectangles. Desktop/mobile styleguide test verifies bounded descendant editor and independent functioning Clear search. All371 affected tests (seed928374611), root/full analysis, three pixel and three export tests pass. Unique signed review bundle refreshed with empty entitlements, deep strict verification and matching source/copy kernel SHA256 ffd5c6d2683dcadd2bc3a93c85fd3256bbcaa2d11b50285b067d3553fb222b2f. Unlaunched awaiting_slot; no CUA.
- Native macOS review completed on integrated3201d96b kernelffd5c6d2683dcadd2bc3a93c85fd3256bbcaa2d11b50285b067d3553fb222b2f: editing/Tab/theme retention, desktop/mobile independent search/Clear search/navigation, actual AddSite/Poll editing, file picker open/cancel, validation/save/reset and secure controlled editing, narrow/200%RTL/Plum rendering. Evidence/input/native contains hashed screenshots/AX. Unique app quit and absent in inventory; desktop slot explicitly released. Example status marked implemented after gate; no behavioral correction required.
- Post-native status-only source 460c0f21d2afabdc45fb69765c719435a52c3336: seven example tests and rebuild pass; unique bundle refreshed and deep strict signed with empty entitlements. Source/copy kernel 66925e1943f9e996c4162e03d4378fa3de71d32df6cbe6325769e008c499f734; not relaunched after slot release. Native-reviewed behavioral implementation remains unchanged.
- Coordinator reviewed native real Add Site/Poll editing, independent desktop/mobile search Clear action, file Button and narrow200% RTL form evidence. Merge into main required only regenerated progress Markdown; final Badge/Button exports and app alignment changes were preserved. All146 focused integration checks pass seed909623, including Input/pixel/examples, Sidebar/styleguide, Add Site, Poll, Group layout, Button adoption and Badge migrations. Root/full analysis clean; git diff --check passes. Logs: /private/tmp/input-main-integration-tests.log, /private/tmp/input-main-integration-analysis.log, /private/tmp/input-main-integration-analysis-full.log.

**limitations**

- macOS native inspection complete; no physical iOS/Linux or spoken VoiceOver verification. Native file chooser cancellation verified; no file upload or network submission performed.

### textarea

Status: merged. Task: 01a08437-208f-7332-b373-192eaada5844. Branch: codex/ui-textarea.

**acceptanceCriteria**

- Match frozen base-nova Textarea source: minimum height, content growth, insets, typography, proportional radius, input role, disabled alpha and exterior focus/invalid rings; preserve hashed primary source and mapping.
- Implement native multiline editing with controller/value/initialValue, mount-time Form reset, validation/save, IME/selection and borrowed lifecycle ownership, keyboard, focus, semantics and real extension needs.
- Demonstrate Field composition using DLabel/native Form, Disabled, Invalid, Button composition using existing StyleguideAction and RTL, plus bounded growth, read-only, live themes, narrow/large-text and reduced-motion behavior.
- Audit all core/plugin multiline fields, migrate appropriate ordinary fields while preserving domain callbacks and async behavior, and record specific specialized retained alternatives.
- Pass touched formatting, root/full-profile analysis and focused component/migration tests; prepare exact-source isolated signed native fixture bundle. Remain in_progress awaiting_slot until reference and native inspection.

**decisions**

- Frozen docs match SHA256; primary registry/example/Field sources and CSS-to-Flutter mapping preserved in textarea.md and reference/textarea/.
- DTextarea is a standalone FormField/native TextField owner; same-string updates preserve selection/composition and reset restores mount text. No unmerged Input/Field/Button dependency.
- Match 64px content-growing surface, 11x9px border-box text insets, explicit 14/20 desktop and 16/24 touch metrics, host radius, outlineVariant input role, multiplied alpha and exterior-only 3px rings.
- Seven actual examples cover all frozen compositions plus native Form/reset, controlled ownership and bounded read-only editing. Field uses DLabel/native composition; Button composition uses existing StyleguideAction until pending owners merge.
- Merged pinned main e612ad7b in d286e118; final owners and all non-Textarea progress rows preserved. Textarea examples now compose final DButton; adjacent DInput adapters reconciled without changing rich composer boundaries.
- Independent review accepted the component, migrations, ownership boundaries and base-nova mapping. The only acceptance correction promotes the completed styleguide entry from its stale baseline/pending label to implemented after browser and native inspection.

**migrations**

- 14 ordinary multiline core/plugin call sites migrated: invitations/group request/template/bio, post flag/notice/fast edit, Assign note, Chat description, Events description, Voice description/flag/simple room chat.
- Domain controllers, focus, max length/counter, line bounds, permissions, async callbacks and persistence remain app-owned. Downstream tests target the new public field.

**retainedAlternatives**

- Rich composer_panel.dart and composer_surface.dart keep specialized lossless Markdown projection/IME/selection/cursor/keyboard/lifecycle owners shared by post/chat composers.
- Spinner Input Group multiline example retains its borderless native field inside a shared addon surface pending Input Group; remaining single-line controls belong to adjacent Input/Field/Combobox owners.

**verification**

- Root/full-profile enforced-lockfile pub resolution and static analysis pass; Flutter 3.47.2 and lockfiles unchanged.
- 215 focused tests pass with seed 928374611 across Textarea/component examples/geometry/semantics, Assign, Events, Groups, Invites, post flag/notice ownership, fast edit, Chat and Voice. Logs and coverage recorded in textarea.md.
- Eight Arial-loaded light/dark Flutter renders and pixel checks verify input alpha multiplication, exact exterior rings and unchanged interior pixels. All seven examples pass 216px/200% RTL in Light/Dark/Forest/Plum.
- Local-data native fixture mounts actual InviteEditor and EventComposerSheet plus Textarea examples/full styleguide; macOS debug build passed from clean committed source 118fa0f10a4d838f50117c0aa0b0b7edc2cfd44b.
- Final pointer-state refinement: all 12 component/visual/example tests and root/full-profile analysis pass.
- Isolated /private/tmp/DiscourseTextareaReview-01a08437.app has unique org.discourse.native.textarea.01a08437 identifier and discourse-textarea-review-01a08437 scheme. Source/copy kernel SHA256 both add8ac7965e911c3e129d7ed80b33913983d13f7e161f9257a83232effc23650; deep strict ad-hoc signature verification passes. Bundle remains unlaunched awaiting_slot.
- AX correction c2d7026f isolates editor Semantics container; reproduced oversized unadorned editor before fix. Exact bounds and independent actions/heading tests pass for single/Column/Row with required/invalid/error metadata. 60 focused checks and final 12 component tests pass; root/full analysis clean.
- Refreshed unlaunched /private/tmp/DiscourseTextareaReview-01a08437-AX.app from c2d7026f production source. Source/copy kernel SHA256 be9603f36ffc05f2b2a1f7473cf99eec79f07852c369e93ae0ccf140df37e3fa. Unique .ax identifier/scheme; restricted APS/team/application entitlements absent by readback; deep strict ad-hoc signature passes. Awaiting serialized UI slot.
- Pinned-main integration: 221 focused tests pass, root/full-profile analysis and enforced-lockfile resolution pass; no SDK/lockfile changes.
- Unlaunched source-exact /private/tmp/DiscourseTextareaReview-d286e118.app from d286e1188bc57c2f2b1a26c3439c69d636606d9b, unique identity/scheme. Source/copied kernel SHA256 2b33e2ae6338e5aa17e889731b44b50e459cdc497d37216643f6aa1f45093faf; deep strict signature and signed entitlement readback pass with debug/JIT allowed and APS/team/application identities absent.
- Independent review reran 163 focused component, visual, styleguide and migrated production tests with randomized seed 1079605986; all passed. After the status correction, 16 component/visual/styleguide tests passed with seed 933940314. After latest-main integration, the 163-test set passed again with seed 1478152398. Root and profiles/full flutter analyze --no-pub, touched formatting and git diff --check passed.
- Official browser inspection covered light/dark default, focus and invalid compositions. Native macOS inspection of exact d286e118 source covered multiline growth, label focus, independent semantics, invalid/form save/reset, controlled/read-only editing, live palette, 320px/200%/RTL layout, and actual InviteEditor/EventComposerSheet success, failure and pending paths.
- Post-review source 35a7959e rebuild produced /private/tmp/textarea-final.rvUv9Z/DiscourseTextareaReview-final-35a7959e.app with identifier org.discourse.native.textarea.review35a7959e; kernel SHA256 c12e0e3007dc8baaeb0ff917bbd9fef78258a87d1eb49e64523b26ffb59e988f and deep strict ad-hoc signature verification pass. DTextarea, foundations and inspected Invite/Event fixture sources are unchanged from native-reviewed d286e118; the only runtime delta is styleguide baseline-to-implemented acceptance metadata, so the coordinator explicitly waived a redundant relaunch.
- Final integration of main 7d29f531 preserved accepted Table, Alert, Empty and Chart owners. The 163 affected Textarea/adoption tests passed again with seed 1934955355; root/full analysis and git diff --check passed.

**limitations**

- No iOS/Linux device or spoken VoiceOver verification; widget tests, native macOS inspection and exported renders do not claim cross-platform device/pixel parity.
- Browser Geist and native host font rasterization differ, so no pixel-equality claim is made; geometry, palette, focus/invalid states, interaction and semantics were compared directly.

### checkbox

Status: merged. Task: 01a083ad-91cf-7e91-9083-a861d5c4fa28. Branch: codex/ui-checkbox.

**acceptanceCriteria**

- Match frozen Checkbox sections and base-nova 16px control, check/mixed artwork, borders, radius, focus and invalid states; record source hashes and rendered comparison.
- Provide controlled/default state, native Focus/Space/semantics and FormField validation/save/reset with borrowed focus lifecycle, RTL, scaling, reduced motion and live palettes.
- Migrate matching core/plugin checkboxes and multi-selection owners preserving permission, tri-state, callbacks and labels; document retained alternatives.
- Provide actual interactive styleguide variants, group/table/form/error and narrow/200%/RTL/theme examples, preserving Sidebar shell.
- Pass formatting, root/full-profile analysis and focused component/form/semantics/migration tests; inspect isolated native fixtures only in coordinator desktop slot before review_ready.

**decisions**

- Frozen Checkbox Markdown hash matches catalogue; base-nova Checkbox/Field and Base UI CheckboxRoot sources captured with hashes in checkbox.md.
- Native FocusableActionDetector/Actions/Shortcuts/Semantics own interaction; pointer activation takes focus, mixed activates to checked without three-step cycling, and readOnly remains focusable without mutation. Borrowed focus nodes are not disposed.
- DCheckbox controlled/default constructors and DCheckboxFormField controlled/default integration cover save/reset, validation and external-value ownership. DLabel composes titles with 8px gap; secondary interactive content retains independent focus/semantics.
- Fixed 16px paint, 14px Lucide Check, 4px radius, token colors and explicit rings. Mixed uses a documented Minus extension pending visual review; pointer/touch targets reserve 40x32/48x48 native space.
- Six actual-component styleguide examples cover basic, states, group, table, form recovery and RTL/long labels; Label examples migrated. Shared Sidebar shell remains unchanged.
- Controlled-form follow-up: mutation paths retain the current prop synchronously. Native effective reset baseline is the controlled prop; separately captured reset proposal preserves onChanged and Form notification ordering, while errors and interaction flags clear normally. Parent acceptance syncs in didUpdateWidget without artificial interaction.
- Visual correction: outlineVariant input token with multiplicative alpha; focus/invalid rings paint outside; intrinsic pointer label rows, source group/table typography and outer choice-card focus. Font-loaded exports and official browser evidence are preserved in evidence/checkbox.
- Coordinator accepts the native Minus mixed-state extension after reviewing the partial-selection table and all/none transition evidence. Completed examples are promoted from baseline without changing their behavior.

**migrations**

- Core User Status, Invites, Post Flag, Topic Move, Users column visibility/reorder, Composer gallery, Group member selection, Topic post selection and Aggregate included forums.
- Plugins Local Dates, Events, Voice privacy, Chat message selection and Poll multiple-choice rows. Bare selection controls gain accessible names; native shortcut guards recognize DCheckbox.
- All application Checkbox/ListTile and manual check_box rendering migrated; imports/callbacks/permissions preserved. Poll button regions reserved for concurrent Button task.

**retainedAlternatives**

- Poll single-choice radio rows, switches/radios/segmented controls, menu checkmarks/status icons/reactions retain their distinct owners. Native Checkbox keyboard guards remain for third-party controls.

**verification**

- 392 focused tests passed with seed 734129, including two temporary stale Avatar-test cast corrections; those Avatar-only corrections were reverted for coordinator ownership, leaving the two known base Users test failures. No checkbox migration failures remain.
- Root and full-profile flutter analyze --no-pub clean; both locked pub get runs succeeded without dependency changes.
- Final Checkbox/Label focused tests: 34 passed (seed 927315), including readOnly, pointer focus transfer, mixed activation and caller-declined controlled-form updates. Bordered notification composition then passed all seven Checkbox example tests.
- Final macOS debug build passed from clean source commit 0df1b03ca000166c1901825b001dbad750b04ce6. Copied unique bundle /private/tmp/DiscourseCheckbox132a-0df1b03c.app (org.discourse.native.checkbox.132a, discourse-checkbox-132a scheme) has matching source/copied kernel SHA256 50658162f62e4a78954bfc3470df11c70cf72e04f308efa777562b3646d9894b; deep strict ad-hoc signature verification passes. No CUA or app launch performed.
- Additional Topic Inbox run: 98 passed, one compact-title Escape failure. Exact failing case reproduced on pristine base 2e894b5e in a temporary detached worktree; logs /tmp/checkbox-baseline-topic.log and /tmp/checkbox-topic-retry.log. Baseline worktree removed.
- Final root/full-profile flutter analyze --no-pub passed after all source changes. Source, tree and native bundle provenance are recorded in checkbox-native-provenance.json.
- Controlled follow-up: all 36 Checkbox/Label component and example tests pass (seed 927315), covering synchronous save/validate in caller/Form callbacks during declined toggles/resets, native reset error/interaction clearing, and later acceptance. Formatting/diff checks pass.
- Controlled consistency source 7519fc61670d995a80dc027e902f6545105715a2: root/full-profile analysis clean; 36 focused tests pass. Refreshed bundle /private/tmp/DiscourseCheckbox132a-7519fc61.app, identifier org.discourse.native.checkbox.132a.sync and unique discourse-checkbox-132a-sync URL scheme. Source/copied kernel SHA256 e379f6048e80056a2d98aa976da8e850b6191b8a34b3bae299d705e0dcb35940 matches; deep strict ad-hoc signature verification passes. This supersedes the earlier 0df1b03c inspection bundle. No CUA or launch performed.
- Visual follow-up: 38 focused Checkbox/Label/paint tests and 118 migration tests passed; three font-loaded export/pixel tests passed. Root/full analysis clean after removing two redundant test imports. Browser-only slot released after restoring original theme/viewport and closing the temporary tab.
- Visual source a1d2737243099e8e6565c8fad268a102aa70a843: clean-source macOS debug build passed. Refreshed signed bundle /private/tmp/DiscourseCheckbox132a-a1d27372.app, identifier org.discourse.native.checkbox.132a.visual, scheme discourse-checkbox-132a-visual. Source/copied kernel SHA256 52687198c964426357053f2039af167ad2294598607a589b091aa9d7735ce715 matches; deep strict signature verification passes. No app launch; native inspection awaiting_slot.
- Exclusive native slot: reviewed exact signed a1d27372 app, all six actual registered examples, light/dark states, mixed table 1→4→0, keyboard/pointer focus, disabled/readOnly, outer Plum card ring, form invalid→saved→reset, Forest360px200%RTL Arabic/Hebrew wrapping and activation. Actual legal explanation editing and checked/unchecked submission gating verified; actual Voice privacy checked values and focus verified at Plum200%RTL. Screenshots and AX in evidence/checkbox/native-*. No new source issue found. App quit through native menu; process absence verified; browser/native slot explicitly released before evidence commit. No browser used this slot.
- Coordinator reviewed native mixed table, legal confirmation and large-text multilingual evidence. Merge preserves final Radio Group single-choice Polls, uses Checkbox for multiselect and removes the obsolete row renderer; Users column reorder Buttons remain independent. Initial integration passed406 checks and exposed3 inherited Button/Badge Topic Inbox assumptions. Reserved32px for the tags overflow beside compressed categories and updated touch-target/combined-label assertions. All66 Topic Inbox checks now pass, including macOS/iOS assignment interaction; root/full analysis and diff checks clean. Logs: /private/tmp/checkbox-main-integration-tests.log, /private/tmp/checkbox-main-topic-final.log, /private/tmp/checkbox-main-integration-analysis-final.log, /private/tmp/checkbox-main-integration-analysis-full-final.log. The generic Checkbox renderer matches inspected source; bounded app-adapter reconciliation is covered by affected widget tests.

**limitations**

- No spoken VoiceOver or iOS/Linux device execution. Native Checkbox used the pre-Input styleguide shell; its AX search limitation was separately fixed and natively verified in merged Input. Real legal and Voice fixtures exposed checked values and focus. The status-only example promotion does not change inspected behavior.

### radio-group

Status: merged. Task: 01a083ce-313b-7da0-aa51-3687fd556604. Branch: codex/ui-radio-group.

**acceptanceCriteria**

- Reproduce base-nova 16px radio and focus/invalid/disabled states with live tokens.
- Controlled and initial selection, native roving arrows/Space, RTL, item labels/descriptions/cards and Form validation/reset.
- Migrate real single-choice controls preserving domain callbacks; focused tests and isolated macOS fixture build; native comparison pending slot.
- ReadOnly group/item inheritance and overrides preserve focus/navigation while blocking all selection channels; required semantics pair with caller Form validation.

**decisions**

- Label is merged; Field is not an implementation dependency: expose label/description slots, do not implement DField.
- Button baseline is used for examples; concurrent Checkbox/Input/Button ownership preserved.
- DRadioGroup uses native RawRadio/RadioGroup focus owners and FormField; controlled rejection/reset preserves the accepted form value.
- Source metrics, hashes, native hit-target adaptation and API contract documented in docs/component-library/radio-group.md.
- Poll explicitly opts into toggleable items to preserve withdrawal; normal radio groups do not deselect.
- Current Base UI Radio API captured; readOnly guards native selection callbacks, required flags announce semantics while caller Form validator enforces requirements and localization.
- Field composition source correction: input uses outlineVariant and alpha modifiers multiply existing alpha; choice cards use captured FieldLabel/Field 10px padding, base-radius lg, selected alpha, hover/focus and 8px/2px content geometry. No DField implementation.
- Live browser correction: both card/radio focus rings, 20px card title, reference widths/selections and invalid-label colors. Outside foreground rings preserve translucent fills; evidence documents host font, focus token, hit target and disabled-opacity adaptations.
- Removed discretionary desktop minimum: intrinsic labeled rows now match Default64px, Description142px and Fieldset73px with8px gaps; touch alone retains48px. Measurements document fractional SF line-height and width differences from browser.

**migrations**

- lib/src/shell/topic_move_posts.dart destination radios
- lib/src/shell/topic_change_owner.dart user radios
- lib/src/shell/post_flag_editor.dart reason rows
- lib/src/plugins/poll/poll_card.dart single-choice/number radios
- RawRadio focus-owner recognition in shell/keyboard_navigation.dart and plugins/chat/chat_drawer.dart

**retainedAlternatives**

- Poll multiselect belongs to Checkbox; Poll actions to Button; change-owner search fields to Input.
- Ranked-choice Poll web workflow and menu-item radio semantics remain appropriate domain/menu controls.

**verification**

- 157 focused component, Poll, flag, move/owner ownership, shell keyboard and Chat drawer tests passed with seed 9092026.
- Local production review fixture search/select check passes for owner and move dialogs.
- Root and full-profile locked pub get passed without lockfile changes; root and full static analysis clean.
- Final committed-source macOS fixture build passed at 767e3d49b9d0c2807b42a28a19bafc9f2483d5b8; isolated bundle /private/tmp/discourse-radio-review-35591zqt/Radio Group Review.app; kernel SHA256 623a8ae4684b35c11408691b1c4d3eb88858123527091811845a267ef0bf6cda; source equality (725 files), matching kernels and deep strict ad-hoc signature verified. See docs/component-library/radio-group.md.
- Final Poll semantics-wrapper refinement and production fixture passed 35 tests with seed 9092026; final root/full static analysis clean. No native app launched.
- ReadOnly/required follow-up: 162 focused component, migration, ownership, keyboard, Chat and fixture tests pass seed 9092026. Final 15 component tests also pass after semantic-action binding cleanup and extra keyboard override coverage. Root/full analyses clean.
- ReadOnly replacement bundle /private/tmp/discourse-radio-readonly-review-l6gbqvk1/Radio Group Readonly Review.app built from 88400eed4c5d4c2215b2df534e7b419c0258b9b1; kernel c8399e45e0d59311d1bcebfc6fbef08400b7d3e29fab55ad1d36f95ef5416af9, 725 source files equal commit, matching copied kernel and deep strict ad-hoc signature verified. No native launch; awaiting_slot.
- Visual-source correction: 163 focused tests passed seed 9092026, including translucent input/card color roles, light/dark modifier alpha, geometry and hover. Root/full static analysis clean; exact source captures and mapping updated.
- Latest source-corrected fixture /private/tmp/discourse-radio-field-review-a2j2_677/Radio Group Field Review.app from 9ece5376b01fad2157af34ca2dd7914ba833e880; kernel 16336ff6c32757e9362121e5d6763a2e35e65d98df43ae4fed546aaf055e15b6; 725 source files byte-match, original/copied kernels equal, deep strict signature passes. No launch; native awaiting_slot.
- Serialized official light/dark browser comparison completed and slot released; 22 font-loaded widget/production fixture PNGs and reproduction harness preserved in evidence/radio-group. Export plus component run passed 18 tests.
- Final desktop geometry correction:165 focused tests pass seed9092026, including18 component tests and retained touch bounds; measured font-loaded export run passes.
- Latest browser-corrected bundle /private/tmp/discourse-radio-browser-review-zpdismeb/Radio Group Browser Review.app from 99126e23b169f72ffde2975adb1da77fd5f966cb; kernel 2f72ac9df88df5dd329edafa55d2dced9a1c5e8961564768713b00484914ad11; 725 source files byte-match, kernels equal and deep strict signature passes. Root/full analyses clean. Native not launched, awaiting_slot.
- Native review completed on source99126e23: all9 registered examples, Poll/flag and real owner/move dialogs; keyboard/disabled/readOnly/validation/save/reset, dual focus light/dark, Forest/Plum360pxRTL200%.18 screenshots and AX evidence in native-review.md. No component defect. Isolated copy local-only re-sign verified; app quit and desktop slot RELEASED.
- Coordinator reviewed controlled/read-only/disabled group source and actual Poll, owner/move, flag and dark choice-card native evidence. Integration preserves final Button, Badge, Input, Sidebar/search and Chat keyboard ownership; only documentation and example registration conflicts needed reconciliation. All202 focused Radio/Poll/flag/owner/move/keyboard/Chat/fixture/Input/styleguide tests pass seed909624; root/full analysis and diff checks clean. Logs: /private/tmp/radio-main-integration-tests.log, /private/tmp/radio-main-integration-analysis.log and /private/tmp/radio-main-integration-analysis-full.log. No generic component or migrated behavior change was needed after native inspection.

**limitations**

- No spoken VoiceOver or iOS/Linux device verification. Native review used the pre-Input styleguide shell; its search AX limitation was separately corrected and natively verified by the merged Input work, with current integrated styleguide checks passing. Native production fixtures expose Radio roles, labels and values.

### switch

Status: merged. Task: 01a083ce-319b-7bc3-a5c9-371087710718. Branch: codex/ui-switch.

**acceptanceCriteria**

- Match base-nova 32×18.4/16 and 24×14/12 track/thumb geometry, 1px inset, directional 14/10px travel, semantic colors, focus/error rings, disabled opacity and 150ms motion.
- Provide controlled and uncontrolled switch, read-only and disabled behavior, focus/keyboard/touch/semantics, FormField validation/save/reset and live controlled updates.
- Reproduce default, description, choice-card, disabled, invalid, sizes and RTL examples without implementing pending Field.
- Migrate core and bundled plugin switches preserving async, permission and persistence owners; cover real local-data fixtures and focused regressions.
- Run focused tests and root/full analysis, build isolated signed review bundle; remain in_progress until actual reference/native inspection.

**decisions**

- Label is merged. Baseline DButton is used for actions; no dependency on unmerged Button/Checkbox/Input/Field.
- DSwitch owns Flutter focus/actions/semantics with shadcn artwork; DSwitchTile composes switch with arbitrary wrapping title/subtitle and a single row activation owner.
- Native accessible hit targets grow transparently to 48px; reference visual bounds remain compact.
- Official source URLs, SHA256 values, complete metric mapping and native adaptations recorded in docs/component-library/switch.md; frozen Switch Markdown hash matches.
- Controlled Form edits and reset requests wait for parent acceptance. Rejected/deferred reset retains consistent field value, semantics, validation and save.
- Choice cards use source 10px inset + 1px border, 8px horizontal/2px description/20px group gaps, selected/hover treatment and the observed wrapper/track focus rings.
- Native transparent 48px targets; borrowed focus node ownership; reference 150ms cubic(.4,0,.2,1) motion with reduced-motion zero duration.
- 2026-09-09 coordinator fidelity correction: rounded-lg now equals base radius; input maps to colors.outlineVariant separately from border. Every Switch opacity modifier multiplies token alpha, including card selected/hover and focus/invalid states. Controlled Form/reset and app callbacks unchanged.
- Browser correction: FieldTitle uses 14/20px leading (86px choice card at 384px); invalid descriptions stay muted. Added explicit source-faithful Invalid example and centered Size rows with associated labels. Live CSS shows both wrapper and track focus rings, now preserved.
- Exterior ring correction: animated 3px outside-only strokes preserve dual card/control rings without tinting translucent interiors. Desktop rows are intrinsic; Android/iOS/Fuchsia retain 48px minimum. Size composition has 20px gap. Poll/Group adapters add 8px vertical padding after fixture inspection exposed adjacent-field crowding.

**migrations**

- lib/src/plugins/chat/chat_channel_info_view.dart
- lib/src/plugins/chat/chat_drawer.dart
- lib/src/plugins/discourse_ai/ai_proofreading_plugin.dart
- lib/src/plugins/local_dates/local_date_composer_sheet.dart
- lib/src/plugins/poll/poll_composer_sheet.dart
- lib/src/plugins/voice/voice_diagnostics_view.dart
- lib/src/plugins/voice/voice_room_editor.dart
- lib/src/plugins/voice/voice_room_view.dart
- lib/src/shell/app_settings_page.dart
- lib/src/shell/group/group_manage_view.dart
- lib/src/shell/keyboard_navigation.dart
- lib/src/shell/preferences_page.dart
- lib/src/styleguide/examples/label_examples.dart
- lib/src/styleguide/examples/spinner_examples.dart
- lib/src/styleguide/examples/separator_examples.dart

**retainedAlternatives**

- Stock Switch/SwitchListTile keyboard guard type checks retain compatibility for external callers; no production stock switch renderers remain. DLabel native association test intentionally retains native control coverage.
- AI proofreading retains the outer existing InkWell/semantic owner; DSwitch small artwork excludes nested focus/pointer/semantics.
- Unmerged Button/Checkbox/Input/Radio Group/Slider controls and Field are not implemented here.

**verification**

- Locked root and profiles/full dependency resolution passed without SDK/dependency/lockfile changes.
- Root and profiles/full flutter analyze --no-pub passed with no issues.
- 327 focused app, component and styleguide tests passed with seed 824192; log /private/tmp/switch-impact-final-tests.log. The whole suite was not run.
- 17 final Switch tests passed after reference example centering; geometry/travel, pointer/Space/Enter/semantics, disabled/readOnly, controlled state, reset rejection/deferred acceptance, Form save/validation, live palettes, wrapper hover/focus and narrow 200% RTL examples. Log /private/tmp/switch-examples-final-tests.log.
- Two real-widget local fixture tests passed; Settings persists in memory; actual Preferences, Chat settings, Poll, Local date, Group manage and Voice diagnostics mount without credentials/network. Log /private/tmp/switch-fixture-tests.log.
- Routed Chat staff threading regression passed: flutter test --no-pub test/chat_shell_integration_test.dart --plain-name "staff toggle threading from routed channel settings"; /private/tmp/switch-chat-tests.log.
- Formatting of touched Dart files and git diff --check passed.
- Isolated macOS debug build passed from 404a1748bc0a11faa01f425ee74f920cc8bddb5e: flutter build macos --debug --no-pub -t tool/switch_review_main.dart. The main checkout/running app was untouched.
- Review bundle /private/tmp/discourse-switch-review-404a1748/Discourse Switch Review.app; bundle ID org.discourse.switch-review; URL scheme discourse-switch-review. Ad-hoc deep strict codesign verification passed. Only the isolated copy removes APS entitlement.
- Kernel SHA256 3b08262090a788c933ea6f36ecd28644a5998f25aad3b4d9968b2b4347395ee1 matches source build and isolated copy. Tracked lib/test/tool source equality to implementation commit passed. Complete trace: docs/component-library/switch-review-build.json; signature log /private/tmp/discourse-switch-review-404a1748/codesign.log.
- Final profiles/full flutter analyze --no-pub passed; /private/tmp/switch-full-final-analyze.log.
- Fidelity correction: 21 component/production fixture tests passed (19 Switch + 2 fixture), including distinct translucent input/border and live custom-radius/light-dark selected-hover-focus checks. /private/tmp/switch-fidelity-correction-tests.log.
- Prepared 16 font-loaded Flutter widget exports with component/example/image hashes under docs/component-library/evidence/switch; export test passed. Browser/native comparison remains pending; no CUA used.
- Exclusive browser-only Chrome comparison completed: official light/dark variants, description/cards/size/RTL/invalid, small Space +10px/Enter reset and RTL Space -14px. Corrected final widget exports inspected in neutral and Forest/Plum at 360px/200% RTL with radius0/18. Evidence/hashes: docs/component-library/evidence/switch.
- Final correction verification: 63 focused tests passed with seed 782311 (21 Switch, 2 production fixture, 39 affected Settings/Preferences/AI tests, 1 font export). /private/tmp/switch-fidelity-final-tests.log.
- Restored website dark theme, no viewport override used, closed sole comparison tab and explicitly released browser slot before build. No native app launched.
- Final browser-corrected root and profiles/full flutter analyze --no-pub passed; touched Dart format and git diff --check clean. Logs /private/tmp/switch-browser-final-analyze.log and /private/tmp/switch-browser-final-full-analyze.log.
- Refreshed browser-corrected macOS debug review bundle: /private/tmp/discourse-switch-review-9ab5a887/Discourse Switch Review.app. Source 9ab5a887cbf71b021022454f91cbdcd8f6041a4b; kernel SHA256 4545ebfacea1b7417d4f2e5820a2fa1a2be8c2714f208b015b608b5ff0df7d59 matches original build; tracked lib/test/tool equality and deep strict ad-hoc signature verification passed. Trace docs/component-library/switch-review-build.json. Native inspection remains awaiting_slot; bundle not launched.
- Exterior ring and desktop geometry regressions passed in 221 affected tests seed 782312; final Size/Poll/Group changes passed 59 component/fixture/export/consumer checks. Inspected refreshed 20 component and 14 app-fixture font-loaded exports against committed primary references. No CUA/browser/native launch. Logs /private/tmp/switch-exterior-final-tests.log and /private/tmp/switch-exterior-adapter-tests.log.
- Exterior correction root/full analysis clean; exact-source macOS debug build passed. Isolated bundle /private/tmp/discourse-switch-review-41ac9023/Discourse Switch Review 41ac9023.app; unique identifier org.discourse.switch-review-41ac9023 and scheme discourse-switch-review-41ac9023. Deep strict ad-hoc signature and source/copy kernel equality passed: f38fcf8e1c62d6f708ae2fae2d5e8af18ecbe869964cb49beed17931d2fde589. Trace docs/component-library/switch-review-build.json. No launch; native awaiting_slot.
- Pinned-main 7df72ef2 integrated preserving final Button/Input and all non-Switch rows. 267 focused integration tests passed seed782313; root/full analysis clean. Exact-source isolated signed bundle /private/tmp/discourse-switch-review-c637efb3/Discourse Switch Review c637efb3.app; kernel d4dfbbf790b2cbabee6780474a496f94dcb6ea3f938a4c103bbb5c741bb21fe5. Signature and entitlement read-back verified with restricted APS/team/application identifiers absent. No desktop access; awaiting_slot.
- Integrated pinned Radio/Checkbox main e612ad7b preserving all final owners and non-Switch rows. 90 focused integration tests passed seed 782314; root/full analysis clean. Unique exact-source bundle /private/tmp/discourse-switch-review-3243a88c/Discourse Switch Review 3243a88c.app; kernel 9af57c435d269a4f97355921a29131f3f232007988984017e3db2f2413655917. Explicit restricted-free debug/JIT entitlements read back exactly; strict deep signature verified. Runner identities/pins/locks unchanged. No UI access; native review pending.
- Native acceptance completed on exact source3243a88c/kernel9af57c435d269a4f97355921a29131f3f232007988984017e3db2f2413655917. All nine registered examples and actual Settings/Preferences/Chat/Poll/LocalDate/Group/Voice fixtures inspected; valid Poll applied after ordinary scroll revealed actions. Evidence/limits in evidence/switch/native-3243a88c. App quit verified; slot RELEASED. Only behavior-neutral example status/notes promoted afterward.
- Independent reviewer inspected the implementation, official-source mapping, browser/native artifacts and all production migrations; no functional defect found. Reviewer reran 70 focused component, fixture, Settings, Preferences and AI checks with seed 782315 plus the routed Chat threading regression; root and profiles/full flutter analyze --no-pub passed. Full suite and new device runs were not performed.

**limitations**

- No iOS/Linux device run or spoken VoiceOver claim. Native text wrapping adapts CSS text balancing.
- Review launcher covers representative migrated production surfaces. Voice room/editor and AI composer are covered by actual-widget regressions rather than the native fixture.
- Browser Geist/Noto Arabic and native SF/SF Arabic shaping/canvas pixels differ; no pixel-equality claim. Shared DTokens.focusRing aliases host primary while reference neutral uses independent gray. Desktop rows are intrinsic; touch platforms retain 48px targets.
- Native rejected/deferred controlled Form reset remains widget-test coverage; native fixture verified external controlled update and ordinary Form reset. Voice confirmation dismissed without recording. Inspected bundle retains baseline badge; status-only promotion does not alter controls.

### toggle

Status: merged. Task: 01a08567-ac29-7dd0-ba78-1717a5235bd0. Branch: codex/ui-toggle.

**acceptanceCriteria**

- Match frozen base-nova default and outline variants, icon/text and icon-only compositions, 28/32/36px small/default/large artwork, disabled and Arabic RTL examples.
- Provide genuine controlled pressed state and internally owned uncontrolled default state with change callbacks, borrowed focus-node lifecycle, pointer/touch/keyboard/semantic activation and disabled guards.
- Match live palette/font/radius tokens, muted selected/hover/press surfaces, input-token outline, visible exterior focus/invalid rings, 48px touch targets, text scaling, narrow layout and reduced motion without resetting state.
- Audit independent app on/off controls and migrate appropriate voice toolbar toggles while retaining async/domain ownership; retain momentary commands, navigation, tabs and mutually exclusive selection controls with specific reasons.
- Register exhaustive interactive styleguide examples and verify focused component/styleguide/consumer tests plus root and full-profile static analysis before direct reviewer handoff.

**decisions**

- Frozen Markdown SHA-256 df0f3e67987ad00fc40be86458c43a330126f3babfd31134644c7fc0284ec7cc verified on 2026-09-09; base-nova registry and Base UI behavior API inspected directly.
- CSS pixels map one-to-one to Flutter logical pixels at 100% text scale: h/min-w 28,32,36; horizontal padding 10; icon gap 4; icons 14 small and16 otherwise; font 12.8 small and14 otherwise; small radius min(.8x host radius,12), regular/large host radius.
- DToggle exposes controlled pressed/onPressedChanged and internally owned initialPressed state. Borrowed FocusNode is never disposed; internally created focus state is owned by the widget.
- The generic control uses native FocusableActionDetector/Actions/Shortcuts and Semantics(toggled:) ownership rather than Material or Cupertino artwork. Focus and invalid rings paint outside the transparent surface.
- SelectedIcon supports the reference pressed bookmark fill while ordinary icon/child composition remains reusable by later Toggle Group without implementing group selection here.
- The Button dependency is merged. Frozen examples cover default/outline, icon and text composition, default/sm/lg sizes, disabled and RTL plus public API behavior. Implement native pressed-toggle semantics and genuine controlled/uncontrolled toggling with keyboard/hover/press/focus and disabled state, matching measured reference artwork. Audit independent on/off formatting/view controls and plugin toolbar controls where appropriate; do not recast momentary actions, tab/navigation items or mutually exclusive selection as independent Toggle. Keep rich editor/IME/domain command ownership with app adapters. Toggle Group is a later catalogue component; build reusable Toggle suitable for composition without duplicating Toggle Group. Notify root when the final reviewer is created and after Toggle merges so Toggle Group can start.
- Implementation uses the direct reviewer workflow; root is not an approval gate.
- Independent review kept symmetric 10px horizontal padding: the live documented Lucide examples do not carry the registry's optional data-icon annotation, and their rendered geometry measures 10px on both edges. The temporary source-only icon-edge interpretation was reverted before acceptance.

**migrations**

- Voice room mute, deafen, camera, screen-share, raise-hand and recording controls use controlled DToggle while VoiceController retains async media, permissions, confirmation and error ownership.
- The persistent global Voice call mute control uses controlled DToggle and continues dispatching VoiceCallAction.toggleMuted through its existing port.

**retainedAlternatives**

- Composer bold/italic selection actions remain momentary domain commands: they transform the selected text, restore editor focus and do not expose an independent persistent pressed value.
- Composer gallery grid/carousel buttons remain mutually exclusive selection pending Toggle Group; tabs, navigation, dialog launchers and other one-shot toolbar actions remain their existing button owners.
- Presence and AI proofreading retain their associated row/DSwitch composition because they are full setting rows rather than compact pressed buttons.

**verification**

- Frozen Markdown SHA-256 matches catalogue exactly; base-nova registry and current Base UI Toggle API inspected directly and mapped in docs/component-library/toggle.md.
- 7 focused Toggle component/example tests passed with randomized seed 9052026, covering controlled/uncontrolled ownership, pointer/Space/Enter/semantic activation, disabled guards, exact artwork and touch targets, state surfaces/rings, live theme/RTL/200%/reduced-motion retention and all frozen examples.
- 258 Toggle, Voice adoption, retained composer toolbar and full styleguide tests passed with randomized seed 9052027.
- Root and profiles/full flutter analyze --no-pub passed without diagnostics; root and full locked dependency resolution passed without dependency changes. Touched Dart formatting and git diff --check passed.
- Unlaunched ordinary macOS styleguide debug build passed from source commit 271c1bddbd8332741e185d9924be7690e5628646 and was refreshed after latest-main/evidence reconciliation at 564051345421a6d603504046daeb8455583821dd. Toggle source SHA-256 966db63c7d1c41da694fd605f0970e692124beda4a2ac58324f122df50126176; refreshed kernel SHA-256 14d093ab5748a9c23a36c9b7c1480fa8ca642f2e58a06e003dab753978e306f5. This is build evidence only, not an isolated review bundle.
- Independent reviewer reran 81 focused Toggle, Voice and exact-fixture tests with randomized seed 9052032 after latest-main integration; root and profiles/full flutter analyze --no-pub, locked dependency resolution and git diff --check passed.
- Official live Base UI examples were inspected in light and dark, including 28/32/36px sizes, 14/16px icons, 4px gaps, 10px symmetric documented-example padding, 8px radius, outline/muted surfaces, disabled opacity, pressed state and RTL logical ordering.
- Exact-source isolated macOS bundle /private/tmp/discourse-toggle-review-d39eb0f3/Discourse Toggle Review d39eb0f3.app was launched. Real Voice mute, deafen, camera, sharing, hand and recording adapters changed state/action labels in both directions while Media settings remained momentary. Default/outline/text/size/disabled/RTL/controlled/uncontrolled/icon-only/invalid examples passed across Light, Dark, Forest, Plum, RTL and 200% text; Space and Return activated focused toggles.
- The isolated bundle uses ID org.discourse.toggle-review-d39eb0f3 and scheme discourse-toggle-review-d39eb0f3. Built and copied kernel SHA-256 values both equal 3eea3bb75a19aeab195e3ced4e91c3d6b2d01fe5fc46aad6fb9dc49d75334529; deep strict ad-hoc signature and restricted entitlement readback passed.
- Final reconciliation integrated local main 6b8ec8f85ce2270d56321a57f9a41abe05355e0f while preserving every non-Toggle progress row and all component registrations. Main's Voice changes were confined to Empty/Textarea consumers outside VoiceToolbarControl. All 71 Toggle, Voice and fixture tests passed with seed 9052033; root and profiles/full analysis and branch-relative diff checks passed.

**limitations**

- No physical iOS/Linux device run or spoken VoiceOver verification was performed.
- Browser and native font rasterizers differ; review establishes measured geometry, palette mapping and behavior rather than pixel equality. The final native bundle is source-specific to d39eb0f3; the subsequent latest-main merge did not touch Toggle, its tokens/theme, Voice adapter or review fixture.

### toggle-group

Status: review_ready. Task: 01a085ce-ca89-7af3-8375-946721be90c6. Branch: codex/ui-toggle-group.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Toggle Group API and Composition, Outline, Size, Spacing, Vertical, Disabled, Custom and RTL examples, including the documented default-spacing change and exact primary-source mapping.
- Compose accepted DToggle with clear single/multiple controlled/local/controller selection ownership, documented deselection, dynamic items, orientation/roving navigation, disabled state and native pressed semantics; preserve measured Toggle artwork and independent action boundaries.
- Support live palette/font/radius, keyboard and touch, visible focus, narrow/scaled/RTL layouts and reduced motion without resetting state; coordinate shared joined-edge needs and final Field composition with their owners.
- Audit and migrate appropriate core/plugin pressed selection groups, including the pending composer gallery grid/carousel selector, preserving domain callbacks and editor/gallery state; document all retained alternatives.
- Pass meaningful focused component/consumer tests and root/full-profile analysis, prepare exact-source fixtures and create a new independent reviewer for required rendered/native acceptance, final compositions, fixes and local main merge.

**decisions**

- Started from accepted current main after Toggle merge a492253d and Carousel merge 3ec0c089. Two completed reviewer tasks freed capacity for a fifth independent source implementation; the implementer creates its own new review/merge task.
- Independent reviewer 01a085e6-4bb7-7e13-9e2a-98992292b4b3 owns remaining review, fixes, required final compositions, rendered/native acceptance and the final local main merge directly. The implementation handoff 7f4de6a88f41983a20ec757dd606153bca067500 is source evidence, not acceptance.

### slider

Status: merged. Task: 01a083ce-313a-7362-ada6-57dc14221509. Branch: codex/ui-slider.

**acceptanceCriteria**

- Match base-nova 4px track, 12px thumb, borders, focus and disabled styling using live tokens; record source hashes and native comparison.
- Single/range/multiple controlled sliders, vertical/RTL, pointer capture and track jumps, overlap selection, keyboard arrows/Home/End/Page and per-thumb semantics.
- Validate min/max/step and thumb ordering; Form save/reset/validation; safe cancellation, removal and controlled updates.
- Migrate video seeking, topic position, Voice volume and Skeleton/AspectRatio controls; preserve domain callbacks and keyboard ownership.
- Focused component and migration tests, root/full analysis, isolated traceable macOS bundle and offline production-widget fixture; native inspection awaits coordinator slot.
- API follow-up: push/swap/none collision policies, accepted swap focus and semantic identity through RTL/vertical/spacing and parent rejection/clamping; absolute default largeStep=10; explicit native completion callback distinction.

**decisions**

- Label is merged; compose baseline DButton for example actions. No dependency on pending Button/Input/Checkbox.
- Slider owns interactive video seek and volume controls; noninteractive buffered progress remains part of the seek track, not a standalone Progress component.
- Reference registry SHA256 646bcd7913417b786bbf7578484f851bf89c81a62f70ef9c4f3522e2af80a951; official examples pinned to 3ba91b1cc83e1bbe4ab35a422ff2a694849c5048. Full source URLs/hashes and metric mapping in docs/component-library/slider.md and references/slider/sources.json.
- Public DSlider scalar, DMultiSlider ordered range/multiple input and matching Form fields. Parent controlled values own paint, semantics and save/reset; commits report accepted values after parent frame.
- Reference pointer push collisions plus optional stop; keyboard preserves neighbour bounds and thumb tab order. Primary-pointer capture cancels on configuration changes/removal. 12px thumb and 4px track retain 48px transparent targets.
- Coordinator API follow-up implemented swap and none (stop alias), absolute 10-unit largeStep default, explicit sorted traversal and accepted-swap focus reconciliation; native onChangeEnd intentionally also completes unchanged accepted interactions.
- Video seek values are milliseconds, so the application explicitly opts into largeStep=duration/10; generic largeStep remains 10 units. Production Page Up seek from 60s to 72s on a 120s clip is regression-tested.
- Integrated pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7, preserving every non-Slider progress row and final component/app owners. Fields freeze their mounted reset baseline, notify onChanged with reset proposals, and retain controlled accepted values until parent rebuild.

**migrations**

- lib/src/shell/inline_video.dart: live buffered seek track, duration-zero disabling and unchanged session seek callback.
- lib/src/shell/topic_progress.dart: TopicPositionSlider preserves integer post selection and editor route/lifecycle/busy ownership.
- lib/src/plugins/voice/voice_room_view.dart: only participant volume block and VoiceParticipantVolumeSlider adapter; preserve local persistence/media calls and 0.1 steps. Coordinate adjacent Switch hunks.
- Skeleton and Aspect Ratio example sliders preserve geometry semantics and step sizes.
- Reading and Chat keyboard guards recognize DMultiSlider input.

**retainedAlternatives**

- Read-only progress and resizable/viewport semantics belong to other catalogue components. Material slider type guards retained for external consumers. No concrete Material Slider controls remain in core/bundled plugin app source.

**verification**

- Flutter 3.47.2 unchanged. Root and profiles/full flutter pub get --enforce-lockfile pass; lockfiles unchanged.
- Root and profiles/full flutter analyze --no-pub: no issues. Touched Dart format and git diff --check pass.
- 217 focused tests passed with seed 4982 across test/d_slider_test.dart, test/d_slider_controlled_test.dart, test/slider_migrations_test.dart, test/styleguide/slider_examples_test.dart, test/inline_video_test.dart, test/topic_progress_test.dart, test/topic_progress_lifecycle_test.dart, test/voice_room_view_test.dart, test/keyboard_navigation_test.dart, test/chat_drawer_test.dart, and Skeleton/AspectRatio example suites. Final accepted-commit frame safeguard rechecked with all 14 slider interaction/controlled tests passing.
- tool/slider_review_main.dart mounts real production TopicPositionSlider, VoiceParticipantVolumeSlider and InlineVideoPlaybackSurface with local playback session; native app not launched.
- Initial source commit 3813f11df01e4a1db8d7b45fe0457d8f904f4d49 built via flutter build macos --debug --no-pub -t tool/slider_review_main.dart; root/full analysis remain clean. Source equality git diff check passed for lib/tool/macos/manifests/locks.
- Isolated review bundle /private/tmp/DiscourseSliderReview-01a083ce.app; bundle ID org.discourse.native.slider.01a083ce; URL scheme discourse-slider-review-01a083ce. Source and copied kernels match SHA256 1aae7dca646a7e21939f7c334e1fc16d29412d9a8869651b977b61baa0dbd6a0. codesign --verify --deep --strict passes. Credits stamps source 3813f11df01e, unmodified. Evidence: docs/component-library/evidence/slider/native-preparation-r1.json. Bundle has not been launched.
- API follow-up: 100 affected component/controlled/swap/production-fixture/example/reading-keyboard/Chat regressions passed; all 9 final swap-focused tests passed, including multi-thumb RTL/vertical borrowed focus, parent reject/clamp/external update, spacing, Form save/reset, absolute largeStep and unchanged native completion. Root/full static analysis and touched formatting pass.
- Media large-step adaptation: all 36 production slider-fixture and inline-video tests pass.
- API follow-up bundle /private/tmp/DiscourseSliderReview-01a083ce-r2.app built from be5f02ff2df29fc42b97ecb36fee30ef6df24d1c; ID org.discourse.native.slider.01a083ce.r2; scheme discourse-slider-review-01a083ce-r2. Source/copy kernel SHA256 6349ee6787314d4f9383576ac85d65e68435eb3d440bbef9762e2a7cec40988c; clean source equality and Credits stamp; codesign --verify --deep --strict passes. Current evidence docs/component-library/evidence/slider/native-preparation.json. Never launched.
- Reset/integration pass: 31 focused field, component, controlled, swap, production fixture and styleguide tests pass.
- Pinned-main reset pass: 31 focused tests and root/full analysis pass. Exact source 6792e34b950b780fbeb93a4aea82c57bd537f2b0, bundle /private/tmp/DiscourseSliderReview-6792e34b.app, ID org.discourse.native.slider.6792e34b, scheme discourse-slider-6792e34b, matching kernel SHA256 b37dbe5b00805e4e9cfb90f15ecf2ed5d59303b365afb296a83617ad847ad8b7. Ad-hoc strict deep signature passes; signed sandbox, allow-jit, get-task-allow and network entitlements verified; no restricted developer entitlements. Runner identities/pin/locks unchanged; every non-Slider progress row equals pinned main. No native/browser/CUA launch.
- Independent reviewer reran 230 focused Slider, Form, collision, styleguide, production migration, media, Voice, topic, Chat and keyboard tests with seed 4982; root and profiles/full flutter analyze --no-pub passed with no issues. Locked dependency resolution and git diff --check were clean.
- Latest-main reconciliation integrated reviewed Switch and Scroll Area through 41b74494 while preserving their exports, examples, migrations and progress rows. The same 230 focused checks passed with seed 4983; root and profiles/full analysis and git diff --check remained clean.
- Official Base UI browser comparison completed in light and dark across default, range, multiple-thumb, vertical, controlled, disabled and RTL examples. The exact-source macOS bundle was launched and its real topic, participant-volume and inline-video controls inspected in light/dark, RTL, 2x text, disabled, removal/restoration and external playback states. Native styleguide default/range/multiple/vertical/controlled/Plum/buffered examples passed; LTR/RTL keyboard direction and independent slider accessibility nodes were verified. No functional source defect was found.

**limitations**

- No iOS/Linux device run or spoken VoiceOver verification was performed.
- Browser and native font rasterizers differ; the review establishes measured geometry, styling and behavior rather than pixel equality.

### progress

Status: merged. Task: 01a083ce-313e-7f70-a1a8-e645f31235c8. Branch: codex/ui-progress.

**acceptanceCriteria**

- Export DProgress with track/indicator/label/value composition matching base-nova 4px geometry and reference typography.
- Clamp finite determinate min/max values, represent unknown progress without a fabricated percentage, and update accessible values without adjustable actions.
- Demonstrate basic/composed/controlled/RTL plus indeterminate, narrow, scaled, reduced-motion and live theme behavior.
- Audit core and bundled plugins; preserve async ownership while migrating appropriate linear indicators and prepare real local-data fixtures.
- Pass focused regressions, root/full analysis and isolated traceable macOS build; require exclusive rendered/native review before review_ready.

**decisions**

- Label is merged. Slider is demonstrative and not an implementation dependency; controlled progress uses DButton actions while Slider remains independently owned.
- Five public Progress parts reproduce base-nova geometry and inherited theme; exact source hashes, API, metrics and justified indeterminate/native semantics adaptations are recorded in docs/component-library/evidence/progress/implementation.md.
- Range is 0–100 by default, min/max clamping handles finite extremes, null/non-finite is unknown; read-only API composes caller state. Track-only layout preserves external 2px constraints.
- Six real-component examples cover reference basic timer, label/value, controlled DButton actions, RTL, async/range edges and explicit parts; independent rendered/native acceptance promoted the styleguide entry to implemented.
- Pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7 integrated; final Button/Badge/Input/Radio/Checkbox and shared application fixes preserved. DButton example actions now use merged Button.

**migrations**

- 15 linear indicator sites across 14 core/Chat/Assign/Events files; retain fractional upload/update max:1, thin strip geometry, domain colors and async ownership. See implementation.md for exact audit.
- Extracted real read-only UpdateDownloadProgress for update sheet and offline fixture; fixture also mounts ComposerUploadQueue with in-memory uploader, EventUnavailableCard and BadgesPage.

**retainedAlternatives**

- DSpinner, group/skeleton activity, poll result bars, topic progress and media timelines retain different semantics; other bundled plugins contain no matching linear indicator.
- Vendored video_player_avfoundation example source unchanged. Slider integration pending its separate task; Button/Input/Badge overlapping edits require coordinator reconciliation.

**verification**

- Root/full locked pub get and root/full analyze --no-pub pass; no lockfile/pin/dependency/runner source changes.
- 302 focused tests passed, seed 9092026; after timing/typography/example refinements 10 component/example/fixture cases passed again. Commands and logs recorded in implementation.md.
- Isolated macOS debug build succeeded; /tmp/DiscourseProgressc8.app (org.discourse.native.progressc8, discourse-progressc8) copied payload/source equality and strict ad-hoc signature checks pass. Kernel SHA256 2d7c551c75496b96ea3407a6ba187689116f64f8c11574d2e950433cbb033034.
- Pinned-main integration: 142 focused tests pass seed9092026; root/full analysis clean. Refreshed /tmp/DiscourseProgressc8r2.app matches source a2984ddb589533370262b77270dab688e8b0a4bc and all built Flutter assets. Kernel d7ec6e8f4046cdc6db93fb6546d22ac5c64d69faa2325b95082db0623e85808b. Deep strict ad-hoc signature and exact restricted-free entitlement readback pass; details in native-manifest.json.
- Independent review: 26 focused component/example/fixture/update/Assign tests passed; a broader run had 115 passing cases and only an explicitly mistyped nonexistent test path, then the clean focused rerun passed. Root and profiles/full analysis passed with no issues; nine component/styleguide tests passed after the acceptance-only status update.
- Official Base UI browser light/dark comparison measured 4px tracks, 384x36 composed geometry and the 150ms standard transition. Isolated macOS review passed light/dark/Forest, 360px/200%/RTL, reduced motion, keyboard activation, native AX boundaries and real upload/download/event/badge transitions. Exact-source /tmp/DiscourseProgressReview6adbb135.app has matching kernel SHA256 38e072176e4ed4538d3edea674b6044d6ad7eb7127dc7570edb9a5fb81318d7c, strict deep signature and restricted-free debug entitlements.

**limitations**

- Offline native fixtures cover actual upload queue, read-only update download, Event fallback and Badge directory; other migrated surfaces have focused regression tests only.
- No iOS/Linux device run or spoken VoiceOver verification was performed; browser and native font rasterizers differ, so review establishes measured geometry, behavior and palette mapping rather than pixel equality.

### skeleton

Status: merged. Task: 01a08213-b4ca-77e1-a2aa-8a490808243e. Branch: codex/ui-skeleton.

**acceptanceCriteria**

- Provide public DSkeleton rectangular/circular geometry with configurable dimensions and directional radius; compose fractional widths and aspect ratios with native layout widgets.
- Support standalone pulsing and synchronized DSkeletonRegion composition, explicit static placeholders, live reduced-motion and TickerMode changes, safe disposal and live light/dark/site token updates.
- Expose one caller-supplied loading label per region; exclude placeholder descendants from semantics, pointer interaction and keyboard focus. Preserve caller-owned loading/error/ready state and scroll geometry.
- Demonstrate interactive geometry, avatar, card, text, form, table and RTL compositions at narrow widths and 200% text, with accurate public API usage and local loading/ready/error controls.
- Audit core and all bundled plugins; migrate the existing LoadingSkeleton/LoadingSkeletonBlock owner and every caller while preserving labels, loading conditions and reading-lane geometry. Keep Spinner migrations separate.
- Format and analyze touched code, run focused component/styleguide/migrated-screen regression tests, and inspect an isolated macOS styleguide after coordinator slot approval; report actual device and accessibility evidence.
- Treat official base-nova registry styling as the design specification; preserve frozen example geometry, map muted/radius/pulse exactly, document concrete native conflicts, and inspect corrected examples plus real migrated surfaces before review_ready.

**decisions**

- Frozen Skeleton Markdown hash matches cab955b03db8fe7a9f4e5bc71be4f72054782d29476b19fb2029f569a880df16; documented props are empty. Web className geometry maps to Flutter dimensions, BorderRadiusGeometry, FractionallySizedBox and AspectRatio; RTL language controls are demo state, not Skeleton props.
- Move and extend the existing shell rendering owner while matching the official source: muted fill, medium radius (site base × 0.8), and a 2-second 1 → 0.5 → 1 pulse using Cubic(0.4,0,0.6,1). This supersedes the earlier legacy 675ms/0.62 timing decision.
- DSkeletonRegion is presentational loading composition, not a request/state owner. Explicit expand:true preserves existing bounded application loading panels; default intrinsic region sizing supports inline library compositions.
- Render the frozen Card frame explicitly from registry measurements (16px padding, 4px header gap, 16px section gap, foreground/10 outer ring, xl radius). Remove generic framed panels elsewhere. Local demonstration state controls sit outside reference compositions; no Material Card/Skeleton styling is substituted.
- DSkeletonRegion adds keyboard-focus exclusion to the preserved pointer/semantics exclusions. DSkeleton.animate=false opts a shape out; region animate=false, reduced motion and TickerMode disable the shared pulse.
- Public API, frozen scope mapping, native adaptations and the complete adoption audit are documented in docs/component-library/skeleton.md.
- Supersedes the earlier derived-fill decision: the initial Light defect was surfaceContainerHighest #FFFFFF on floating #FFFFFF, while actual muted is #F1F3F5. Removed DTokens.skeleton, its 16% foreground blend and unjustified decorative contrast threshold. DSkeleton now reads DTokens.muted directly; only sidebar callers override color to tokens.background because their backdrop equals muted.
- Inspected official Skeleton/Card registry JSON, theme radius scale and Tailwind pulse documentation on 2026-09-08. Current aggregate registry examples differ from the frozen document; retained frozen 16:9 Card, 32px form controls and five table rows. Reference-to-Flutter mapping and measured palettes are in docs/component-library/skeleton.md; frozen catalogue unchanged.

**migrations**

- Removed shell/loading_skeleton.dart; migrated all ten regions and their shapes to DSkeletonRegion/DSkeleton through discourse_ui.dart.
- Migrated topic_list_view (topics/messages/filters), topic_view (initial/recommendations/earlier/later), draft_list, user_activity, user_summary and instance_sidebar; explicit expand:true retains bounded viewport geometry and existing caller-owned labels/loading guards.
- Migrated bundled Chat initial-channel and bidirectional pagination skeletons. Preserved minimum message heights, request ownership and loaded/error behavior; made placeholder gutter/alignment directional.
- Migrated skeleton assertions in topic and Chat lifecycle tests and moved/extended the old owner tests under test/ui/d_skeleton_test.dart; added interactive styleguide tests and all seven registered examples.
- The navigation sidebar uses the public optional color override on its shapes. Core content and Chat keep the default muted fill. All other loading ownership and geometry migrations remain as recorded.

**retainedAlternatives**

- Audited all 12 bundled modules plus packages/discourse_voice/lib and profiles/full/lib. Only Chat had additional shape skeleton owners; Assign, AI, Events, GitHub, Lazy Videos, GIFs, Local Dates, Poll, Prometheus Alert Receiver, Reactions and Voice had none.
- Indeterminate busy indicators remain in the concurrent Spinner scope; no Spinner migration is claimed.
- Avatar/emoji identity and inline-size fallbacks, SiteImage authenticated loading/error builders, Chat dominant-color image surfaces and unavailable-image error placeholders retain their media behavior and existing owners.
- Unsupported-route placeholders and composer/inline PlaceholderAlignment atoms are navigation or text-layout representations, not content loading skeletons.

**verification**

- Frozen Markdown SHA256 verified with shasum -a 256; official Skeleton reference inspected on 2026-09-08.
- Flutter 3.47.2 / Dart 3.13.2; flutter pub get --enforce-lockfile passed without lockfile changes.
- flutter analyze --no-pub passed with no diagnostics.
- flutter test test/topic_list_view_lifecycle_test.dart test/topic_view_lifecycle_test.dart test/chat_channel_view_lifecycle_test.dart test/draft_list_test.dart test/user_summary_test.dart test/coherent_initial_render_test.dart test/connection_session_integration_test.dart --no-pub --test-randomize-ordering-seed=random: 206 passed, seed 3315690589.
- flutter test test/ui/d_skeleton_test.dart test/styleguide test/activity_section_lifecycle_test.dart --no-pub --test-randomize-ordering-seed=random: 81 passed, seed 1795106859.
- Component checks cover standalone/synchronized pulse, static opt-out, live motion/TickerMode changes, disposal, accessible label replacement, pointer and Tab exclusion, intrinsic/expanded/unbounded dimensions, fractional/aspect-ratio geometry, circle/directional/default radius and live light/dark/site/fallback themes.
- Styleguide checks cover search/registration, all seven examples at 320px/200%/RTL/Plum and 1024px/100%/LTR/Forest, loading/ready/error/retry transitions, keyboard slider adjustment, form validation/saving/theme retention, card actions and horizontal table scrolling. Existing styleguide access/Direction/tokens tests passed.
- Built isolated temporary macOS styleguide with flutter build macos --debug -t lib/styleguide_main.dart --no-pub at /private/tmp/discourse-native-skeleton.alyOd3/build/macos/Build/Products/Debug/Skeleton Styleguide.app; distinct product/bundle identity and all signing adjustments are outside the repository.
- Source audit found no remaining old LoadingSkeleton/LoadingSkeletonBlock imports or usages. git diff --check passed.
- Historical, before the shadcn fidelity correction: After the native palette fix: flutter test test/ui/d_skeleton_test.dart test/styleguide/component_tokens_test.dart test/styleguide/skeleton_examples_test.dart --no-pub --test-randomize-ordering-seed=random: 35 passed, seed 465275359. That former derived-fill/contrast regression was subsequently removed by the source-fidelity correction; it is not a current design criterion.
- Formatted all 16 touched Dart files with dart format; final dart format --output=none --set-exit-if-changed and git diff --check passed.
- Historical, before the shadcn fidelity correction: macOS 26.6.2 arm64 CUA: selected exact isolated app path and raised it under the coordinator-granted slot. Visually inspected all seven example groups. Geometry: circle/diameter pointer changes, Tab focus with visible halo, arrow keys changed diameter 56 to 64, pulse pause/static companion.
- Historical, before the shadcn fidelity correction: Native Light: caught the old white-on-white fill, rebuilt the derived token fix and confirmed visible avatar/lines. Exercised Loading → Ready → Error → Retry. Native Forest: 360px preview, 200% text, RTL and reduced motion together; inspected avatar/card/text/form placeholders and ready form rendering.
- Historical, before the shadcn fidelity correction: Native Plum: inspected pulsing table rows; dragged the horizontal scrollbar to reveal later columns and verified Ready retained the position. Inspected explicit RTL avatar placement and mirrored asymmetric corners. Reported completion to release the inspection slot.
- flutter devices reported macOS, Chrome and a wireless iPhone; native interaction was performed only on macOS.
- Coordinator review: migrated Use site radius, Retry, Follow and form Save example actions to public DButton.flat. flutter test test/styleguide/skeleton_examples_test.dart --no-pub --test-randomize-ordering-seed=random passed 18 tests, seed 3352427373; final analysis and isolated native build passed. This cleanup followed the recorded styleguide native inspection.
- The real-widget native fixture exposed an over-traversing Chat public-barrel import. Corrected it in 71e2d595 after primary implementation 941f6e37. flutter analyze --no-pub passed; flutter test test/chat_channel_view_lifecycle_test.dart --no-pub --test-randomize-ordering-seed=random passed 41 tests, seed 2088169370.
- Temporary-only offline fixture smoke check: flutter analyze --no-pub lib/styleguide_main.dart and flutter test test/native_skeleton_fixture_test.dart --no-pub passed (1 test). The fixture mounts actual TopicListView, ChatChannelView and ChatMessageStream with existing gated API fakes and an in-memory image client; HttpOverrides rejects unexpected real HTTP clients. Initial and both pagination regions render without widget exceptions and dispose cleanly.
- Source-fidelity checks: flutter analyze --no-pub passed. flutter test test/ui/d_skeleton_test.dart test/styleguide/skeleton_examples_test.dart test/coherent_initial_render_test.dart --no-pub --test-randomize-ordering-seed=random: 38 passed, seed 2017906744. Tests now measure rendered Avatar/Card/Text/Form/Table/RTL sizes and gaps, the exact full pulse cycle, and sidebar fill override. The final rendered DecoratedBox assertion passed a follow-up run of the five coherent-initial-render tests with the same seed.
- Temporary live palette probe: Light muted/content/highest #F1F3F5/#FFFFFF/#FFFFFF; Dark #1A1C20/#212429/#272B32; Forest #EEF6F0/#F8FCF9/#CBDDD0; Plum #2B2030/#211725/#49354F. Muted equals sidebar background in all four. Half-opacity muted/content contrast was 1.054, 1.049, 1.031, 1.053: intentionally subtle decorative treatment, not a text-contrast requirement.
- Final temporary offline fixture: flutter analyze --no-pub lib/styleguide_main.dart, flutter test test/native_skeleton_fixture_test.dart --no-pub (1 test), and flutter build macos --debug -t lib/styleguide_main.dart --no-pub passed. The smoke test mounts actual TopicListView, ChatChannelView, ChatMessageStream and InstanceSidebar, completes local fake API gates, verifies all loading regions disappear and the ready topic/message render, and disposes without exceptions. Fixture toolbar, fake data, signing adjustments and test remain outside the repository.
- Final source-fidelity macOS 26.6.2 arm64 CUA inspection under the exclusive coordinator-granted slot: inspected the exact rebuilt isolated Skeleton Styleguide.app using normal semantics. Visually inspected all seven example groups: 48px reference demo and 100x20 pill, 40px Avatar composition, Card padding/header gap/16:9 cover/outer ring, three-line Text, Form labels/inputs/group gaps, five-row three-column Table, and mirrored RTL avatar/lines. No added generic frames remained.
- Final native palette/constraint evidence: Light geometry/Avatar/Card/Table; Dark topic list at 360px, 200% text, RTL and reduced motion; Forest Chat first load and Text/Form at 360px, 200% text, RTL and reduced motion; Plum Form/Table/RTL examples; actual Plum Chat pagination at 360px, 200% text and RTL. Reduced-motion changes stopped the visible pulse. No overflow was observed in these combinations. Light and Dark actual sidebar placeholders remained distinct from their muted backdrop using the local background override.
- Final native real-widget transitions: TopicListView exposed Loading topics and rendered rows; ChatChannelView exposed Loading chat channel with the real composer separate; ChatMessageStream displayed a real local message between Loading older messages and Loading newer messages; InstanceSidebar exposed Loading navigation alongside real navigation items. Show local data completed the fixture gates: Loaded local topic and the local chat message appeared, both pagination loading labels disappeared, and sidebar loading was replaced by its ready categories/navigation. No authenticated account or real HTTP request was used.
- Final native demonstration actions: Avatar Loading -> Ready -> Error rendered; Card Follow changed to Following; Form literal text input changed Ada to AdaGrace and public Save visibly displayed Saved: AdaGrace. These final source-matched checks supersede the earlier ready-form-only limitation. Empty-name validation and the corrected table horizontal scroll below 256px remain covered by widget tests rather than final native interaction.
- Native input incident triage: a batch of field click, super+a, typeText(Grace), and scroll lost the targeted window on the AZERTY host. No new Skeleton/Discourse/Flutter diagnostic crash report was found. The cause is unconfirmed; no application crash or production defect is claimed. Retrying with the native Edit menu and literal input succeeded in editing/saving, although Select All did not select the existing text and the CUA key names backspace/delete were unsupported. No source change was made for this tool/input incident.
- Final native cleanup: quit only the isolated Skeleton app through its native app menu. A subsequent app-specific AX query reopened the fixture, so quit again and used cua.getState() to confirm Skeleton absent from running apps. Released the desktop slot to the coordinator before final documentation work.
- Official Skeleton/Card base-nova registry response bytes and decoded UTF-8 TSX content SHA256 values were verified on 2026-09-08 and recorded beside their exact source URLs in docs/component-library/skeleton.md. Both sources still match the documented muted/radius/pulse and Card frame mapping.
- Coordinator reviewed all generic code and app migrations, source measurements/hashes, motion and semantics tests, and final normal-semantics macOS evidence on real topic/Chat/sidebar loading-to-ready fixtures. Reconciled shared barrel/example registrations and imports with Kbd, Separator and corrected Typography; no component or migration defect found. Combined integration checks follow.
- Coordinator integration: flutter test --no-pub test/ui/d_skeleton_test.dart test/styleguide test/topic_list_view_lifecycle_test.dart test/topic_view_lifecycle_test.dart test/chat_channel_view_lifecycle_test.dart test/draft_list_test.dart test/user_summary_test.dart test/coherent_initial_render_test.dart test/connection_session_integration_test.dart test/activity_section_lifecycle_test.dart --test-randomize-ordering-seed=random passed 312 cases, seed 2377581763. The catalogue accounting case initially read progress.json before its merge conflict was resolved; after reconciliation its isolated rerun passed (1 case, same seed). Final flutter analyze --no-pub passed with no issues after removing two duplicate public imports. Touched merge files formatted; git diff --check passed. No production behavior fix was required during reconciliation.

**limitations**

- No iOS or Linux runtime/device inspection. A wireless iPhone was discovered, but no iOS CUA session or device deployment was performed; no Linux device was available.
- VoiceOver speech was not inspected. Normal native AX exposed the actual topic/chat/pagination/sidebar loading labels and ready-state replacements; styleguide AX remained sparse apart from native menus/text inputs. Single-label semantics, hidden descendants, live-region opt-out and focus/pointer exclusion passed widget tests. No forced global semantics diagnostic was used.
- Final native form editing and saving passed. Empty-name validation, palette-retained form draft state and the source-corrected table scroll below 256px passed automated interaction tests but were not completed in the final native session. The earlier window-loss incident and unsuccessful native Select All/unsupported key names are recorded precisely in verification; no application crash is inferred.
- Authenticated live accounts were not opened. Actual migrated TopicListView, ChatChannelView, ChatMessageStream and InstanceSidebar were inspected natively with gated local fake data, including loading completion. Remaining migrated screens and broader loading/error/pagination/session behavior were covered by the focused core/Chat regression suites.
- Shared overlaps for coordinator reconciliation: discourse_ui.dart, component_examples.dart, tokens.dart, own progress row and app/test imports in topic_view.dart, topic_list_view.dart, draft_list.dart, instance_sidebar.dart, user_activity.dart, user_summary.dart and Chat. No other component branch was imported or merged.

### aspect-ratio

Status: merged. Task: 01a082a9-b9d4-79f0-8a0d-cc48e700cc67. Branch: codex/ui-aspect-ratio.

**acceptanceCriteria**

- Export public DAspectRatio with required arbitrary finite positive ratio and ordinary child composition; use Flutter ratio layout, document tight/bounded/unbounded constraints and keep clipping, imagery, colors and loading caller-owned.
- Match frozen 16:9 (max 384px), square (max 192px), portrait 9:16 (max 160px) and RTL figure examples, using rounded-lg/muted/cover/grayscale/dark 20% brightness with live palette, font and radius tokens and an 8px caption gap.
- Preserve descendant state, semantics, pointer and keyboard input, focus, and caller-owned media/controller lifetimes across ratio, theme and direction updates; respect native text scaling and scrolling.
- Audit all core and bundled plugins, migrate appropriate ratio presentation including inline video, oneboxes, lightbox and Chat, preserve normalization/fit/clipping/loading/lifecycles, and record retained metadata, grid and playback APIs.
- Add comprehensive offline public-library examples for reference compositions, arbitrary ratio changes, constraint behavior, interaction/state retention, large text and RTL with Light/Dark/Forest/Plum previews and DButton actions.
- Format/analyze and pass focused component/example/migration/downstream checks without changing Flutter pin or lockfiles; inspect actual rendered reference examples and representative real migrated widgets in an isolated local-data macOS app after the coordinator grants the native slot; record exact evidence and limitations.

**decisions**

- Public DAspectRatio accepts every finite positive ratio and mounts Flutter RenderAspectRatio directly, with debug assertions and release mount/update validation. Parent constraints take precedence; at least one axis must be bounded. Child composition owns paint, clipping, semantics, focus, input, state and controllers.
- Preserved frozen Markdown and registry JSON under docs/component-library/reference; exact URLs, raw/source-content hashes, CSS measurements, native mapping and adoption exceptions are documented in docs/component-library/aspect-ratio.md. The linked Base UI API currently returns HTTP 404; registry uses a plain CSS ratio div and needs no Base UI dependency.
- Frozen examples retain 384x216 widescreen, 192px square, 160x284.444 portrait, live base radius/muted/cover/grayscale and 20% dark brightness, plus an 8px-gap 14px/20px RTL caption. Local bundled Discourse imagery substitutes for the remote reference avatar.
- An explicit packages/discourse_native/src/styleguide/assets/discourse.png asset declaration and key works in both the root application and the compatibility profile; no runtime network or asset-fallback owner is introduced.

**migrations**

- Core inline_video now uses DAspectRatio for outer capped geometry and inline/fullscreen playback. Removed competing manual ratio sizing while retaining finite-width fallback, actual-size poster decoding, clipping, taps, async sessions, disposal and scrolling.
- Generic/topic onebox thumbnails and lightbox reserved-image slots use DAspectRatio, preserving metadata normalization, widths, cover/contain fit, clipping, loading/error, links and gallery ownership.
- Bundled Chat upload images and optimistic GIF previews use DAspectRatio; preserve no-upscale/caps, contain fit, dominant fill, loading/error, semantics, playback toggles and gallery behavior.
- Skeleton card placeholder/ready compositions and public snippets now use DAspectRatio; updated relative-sizing API docs.

**retainedAlternatives**

- Media model aspectRatio values, image-decode normalization and native playback requests are metadata/transport, not widget layout owners.
- YouTube keeps its 200px minimum-height native overlay sizing; ComposerImagePreview retains authored scale, no-upscale, fixed selection/measurement bounds; image mosaic equalized heights and fixed carousel track are deliberate layout policies.
- Voice/GIF sliver grid childAspectRatio stays with Flutter grid layout; upstream video_player_avfoundation and vendored WebRTC example apps do not depend on this application library.

**verification**

- Acceptance criteria recorded before implementation. Frozen Markdown hash verified; official registry raw and source-content hashes recorded. Other component rows and workflow metadata compared with base and preserved.
- Format check passed for 15 touched Dart files; flutter analyze --no-pub passed without diagnostics.
- Focused component/examples/media/Chat/Skeleton/adoption command recorded in aspect-ratio.md: 305 passed, randomized seed 2654739856. Includes ratio/session retention, pointer/keyboard/focus/semantics, normalization/size caps, offscreen disposal and async race/decode checks.
- After shared asset correction, 32 example tests passed from root (seed 443369763), and 32 passed from profiles/full (seed 1858729558) after enforced-lockfile pub get. Neither Flutter pin nor any lockfile changed.
- Browser inspection of official examples confirmed 384x216, 192x192, 160x284.4375 CSS-pixel boxes; native reference rounded-lg is 10px before app token substitution. Verified object-cover, grayscale, dark brightness(0.2), and RTL caption at 8px gap / 14px font / 20px line-height. Light and Dark reference renders inspected.
- Isolated Aspect Ratio Review macOS app built and inspected at /private/tmp/discourse-aspect-ratio-review-01a082a9/app/build/macos/Build/Products/Debug/Aspect Ratio Review.app. Bundle ID org.discourse.aspect-ratio-review, separate URL scheme, package asset, ad-hoc signature and byte-identical production lib source verified before launch. Only the example implemented-status declaration changed afterward.
- Native reference comparison: widescreen Light/Dark, square Dark, portrait Forest, RTL figure Plum at 360px/200%; image crop/dimming/radii/caption matched recorded geometry and token mapping. Arbitrary ratio 1.37 to 2.72, contain/corner toggles, all constraint examples and outer scrolling inspected.
- Native interactive example: edited local draft, visible Tab focus, Enter increment, retained draft/counter/focus across ratio and live theme/direction changes; inner scroll preserved access to 200% text.
- Actual production OneboxCard, DiscourseTopicOnebox, LightboxThumbnail, ChatUploads, ChatPreviewBody and InlineVideo inspected using bundled image bytes on a temporary loopback-only fixture. Verified cover/contain/caps, ready/loading/error slots, GIF pause-to-play, gallery open/Escape, video lazy activation/pause/0:07 position retention/resizing/fullscreen/Escape. No real account data or video codec playback used.
- Full native styleguide search and registered Aspect Ratio preview inspected. After quitting only the isolated app, a subsequent global CUA app inventory returned no org.discourse.aspect-ratio-review entry; desktop slot released to coordinator. No real runner, SDK or system accessibility setting changed.
- Final component tests passed (5 tests, seed 1837891262) after ensuring semantics handles are disposed on assertion-failure paths as well as success.
- After marking the verified example group implemented, final shared styleguide page plus Aspect Ratio examples passed: 40 tests, seed 29227221. Final flutter analyze --no-pub and touched-file formatting passed; git diff --check was clean.
- Coordinator reviewed the arbitrary-ratio API and native RenderAspectRatio ownership, all media and Skeleton migrations, constraint/session regressions, exact source mapping and recorded native reference/media checks at stable HEAD bb218f825349d7df407f5cb6827bc955954de447. The package asset correction was verified in root and profiles/full. Preserved newer Label and all main workflow metadata while importing only this component row; the isolated app and its in-process loopback fixture server are closed.
- Coordinator integration check on main passed all 313 focused Aspect Ratio, actual media, Chat, Skeleton, styleguide and adoption tests (seed 837280413). All 32 Aspect Ratio examples also passed from profiles/full using the shared asset bundle (seed 1032379873). Root and profiles/full flutter analyze --no-pub passed without diagnostics; root/full flutter pub get --enforce-lockfile left pins and lockfiles unchanged. All 15 touched Dart files passed format checking and git diff --check passed. The generic component, examples and all migrated media/Skeleton source files are byte-identical to the native-inspected worker source. Logs: /private/tmp/component-aspect-ratio-integration-{tests,analysis}.log and /private/tmp/component-aspect-ratio-full-{tests,analysis}.log.

**limitations**

- The offline Discourse image intentionally replaces the remote Vercel avatar; app palette/font/radius variables and native glyph shaping differ from web defaults. Browser portrait height quantization is 284.4375px versus exact Flutter arithmetic 284.4444px. No unintended layout/style difference remained and no pixel-identical cross-renderer claim is made.
- No iOS/Linux device, VoiceOver speech or physical codec-playback check. The native media fixture mounted real widgets with a fake session; platform-override widget tests are not device checks.
- The full styleguide exposes fewer native AX nodes than the temporary harness, so its search/navigation used visible pointer targets; component child semantics and keyboard/focus behavior were inspected in the native harness and automated tests.

### avatar

Status: merged. Task: 01a082d2-4434-73b1-8ab4-88c9b2ba9b66. Branch: codex/ui-avatar.

**acceptanceCriteria**

- Public DAvatar, DAvatarImage, DAvatarFallback, DAvatarBadge, DAvatarGroup and DAvatarGroupCount reproduce base-nova metrics at sm/default/lg and accept ordinary Flutter composition.
- Image absence/loading/error/ready and source replacement preserve fallback and accessible identity without stale image flashes; optional fallback delay and status callback have lifecycle tests.
- Dot/icon/count badges and overlapping groups support RTL, narrow constraints, 200% text, live light/dark/site palettes and decorative semantics without taking interaction focus.
- All frozen documentation sections have self-contained runnable examples and correct public API snippets; Button/Dropdown ownership stays explicit and state survives preview changes.
- Audit core and every bundled plugin; migrate appropriate avatar visual owners while retaining MediaPipeline, AvatarLoader, stale guards, raster/SVG decode reporting and domain flair/presence ownership.
- Focused seeded component, styleguide, adapter and downstream regressions plus analysis pass; isolated macOS app compares reference and real migrated fixtures after exclusive desktop grant.

**decisions**

- Reference hashes, exact CSS-to-Flutter metrics, native adaptations and complete adoption audit are recorded in docs/component-library/evidence/avatar/implementation.md.
- Six public generic components retain app-independent presentation. ImageProvider stream ownership handles loading/error/ready and stale frames; AvatarImage remains the application networking/decoding adapter.
- Default groups preserve per-avatar sizes/dimensions and infer count size; explicit group size propagates badge/fallback metrics consistently. Standalone counts retain intrinsic 32px geometry.
- Above-100% text scaling reserves larger enum-sized boxes to fit initials and avoid ready/fallback geometry shifts; fixed app frames and explicit dimensions retain layout contracts. Narrow groups wrap.
- Exact Lucide plus SVG and full ISC/Feather MIT license recorded. Explicit badge icon slot hides arbitrary SVG/widget icons at sm; standalone GroupCount owns its 2px background ring.

**migrations**

- Core topic/post/group/user/composer/quote/reaction/search identities; Chat, Voice, Assign and Events avatar owners now use DAvatar.frame. Four CircleAvatar fallbacks removed.
- Rounded forum/rail/sidebar/directory/GitHub identity clips use public presentation with preserved domain radius. Topic poster overlap uses DAvatarGroup.
- AvatarImage reserves requested dimensions for every loading/ready/error state; cache, asynchronous pipeline guards, SVG/raster decode and reporting remain app-owned.

**retainedAlternatives**

- Domain online rings, flair, unread/count/recording indicators and UserStatus emoji retain their distinct meaning and geometry; underlying identities migrate.
- Video/camera/media/onebox thumbnails, shell/card clips and category swatches are not avatars. Adjacent 20px inbox posters retain their non-overlapping layout.
- Existing fallback text, custom colors and DiscourseAvatarTheme radius values remain application presentation inputs; Button/Dropdown temporary controls remain their pending owners.

**verification**

- flutter pub get --enforce-lockfile passed on root with no lock changes.
- flutter analyze --no-pub passed (no issues).
- 250 focused tests passed with --no-pub --test-randomize-ordering-seed=9082026 across 17 Avatar/example/decode/chat/group/rail/search/media/Voice/Assign/Events/accessibility suites. Exact commands recorded in native-review.md at completion.
- profiles/full locked pub get and flutter analyze --no-pub passed; no lock/pin/runner changes.
- After exact SVG icon-slot and standalone ring correction: 15 focused component/example tests passed again with seed 9082026; root analysis passed again.
- Isolated source-matched macOS 26.6.2 arm64 native inspection completed under exclusive slot; exact conditions, reference comparison, screenshot evidence and commands recorded in docs/component-library/evidence/avatar/native-review.md.
- Native production loading/error/ready and local forum action; light/dark/site/360px/200%/RTL/reduced-motion compositions; generic error selection preserved across Forest to Plum; dropdown Settings, Return reopen, Escape and visible focus restoration verified.
- Quit only isolated Avatar app and confirmed its identity absent from subsequent global CUA inventory before releasing desktop slot.
- Final implemented registration: 12 Avatar/styleguide-page tests passed with seed 9082026; touched-file format check, git diff --check and unrelated-row preservation check passed.
- Coordinator reviewed final clean Avatar HEAD c5da5fd6ee548d415c496be27052c314d391f39b, generic image stream/fallback ownership, mixed group sizing, exact plus artwork and rings, app media adapters and migrations. Independently inspected the saved official light badge comparison, native light badges, Forest 360px/200% RTL groups and actual dark RTL 200% ForumIcon/AvatarImage fixture. Native inspection and app closure are complete; only the example status changed afterward. Merge retains all prior component owners and the Tooltip rail surface, token radius and fitted monogram while adopting its DAvatar frame.
- Coordinator combined-main verification: all 593 focused library/styleguide, image/media/cache, shell/rail/forum, topic, Chat, Voice, Assign and Events cases passed, seed 342701054; log /private/tmp/component-avatar-integration-tests.log. All 41 touched Dart files pass formatting; flutter analyze --no-pub is clean (6.8s), log /private/tmp/component-avatar-integration-analysis.log; git diff --check passes. Generic Avatar, examples and AvatarImage/ForumIcon adapters exactly match the reviewed branch. All changed app source retains the prior Spinner, Tooltip, Skeleton, Aspect Ratio and Label owners, including Tooltip rail geometry and fitted monograms.

**limitations**

- No iOS/Linux device or spoken VoiceOver run. Nested styleguide main native AX tree was sparse; fixture/menu AX and visual/keyboard interaction verified without forcing global semantics.
- Reference and native screenshots have different capture/preview dimensions; intrinsic metrics compared at 100% with exact widget geometry tests, not pixel-diff equality. Palette, font and local artwork intentionally use app inputs.
- Button and Dropdown Menu examples use their available temporary controls pending owning catalogue tasks; domain flair/presence and non-avatar media retain documented ownership.

### card

Status: merged. Task: 01a082d9-6c59-7443-8e64-f76105fd5e56. Branch: codex/ui-card.

**acceptanceCriteria**

- Export all seven passive Card composition APIs, with default/small metrics and live shared spacing; preserve child focus, selection, callbacks and lifecycle.
- Match base-nova surface, foreground ring, radius, title/description metrics, header action alignment, footer border/shading, absent parts and clipped edge images; document registry hashes and CSS mapping.
- Reproduce frozen login, small, spacing, edge-to-edge terms, image and RTL examples with local state; document pending Button/Input/Badge/Toggle Group owners.
- Audit core and every bundled plugin presentation owner; migrate appropriate group/member/activity, Chat, Poll, Events and Skeleton surfaces while preserving domain behavior; justify retained alternatives.
- Pass format, static analysis and focused seeded component/example/adoption/downstream tests; inspect byte-matched isolated macOS styleguide and real local-data production fixtures in exclusive desktop slot across palettes/narrow/200%/RTL.

**decisions**

- Frozen Card Markdown and all seven APIs covered. Registry raw SHA256 e73e3fe00ab2e14c4db1dccb1ff5c67041a94c0926ac3216c1dc6dd6dee9d7e0; decoded source 645c3d73e387a99f1492220cc619453b0c7f5454134ee3cd548be7a80f7eccde. Exact metrics and complete adoption audit: docs/component-library/card.md.
- Passive DCard with Header/Title/Description/Action/Content/Footer; 16/12px spacing, shared override, 1px foreground/10 outer ring, live radius ×1.4, explicit typography and native Material ink without elevation or action. Semantic container preserves existing grouping.
- Direct footer children and explicit footer slot remove bottom padding. Leading/trailing edge slots clip images; edgeToEdge and joinNext express shared-spacing negative margins. Header reflows below 240px or above 150% text using stable Flex topology, preserving child element/focus.
- Eight runnable local-state examples reproduce reference compositions before application states. Adjacent Button link/outline/secondary/submit, Input email/password visuals, Badge and Toggle Group remain explicitly pending owners. Bundled package image has no network fallback.
- Examples reuse already-merged Label, Aspect Ratio and Skeleton; the frozen catalogue dependency remains typography.

**migrations**

- Core Groups directory, compact members, activity and requests; Preferences, Badge and Category directories; Aggregate passive panels. Existing navigation, permission, callbacks, fields and state ownership preserved.
- Chat browse channels and preference form; Poll interactive and cooked fallback; Events loaded/unavailable/cooked fallback; Voice diagnostics controls. Plugin services, hydration and write ownership remain in their modules.
- Skeleton reference Card now uses DCard; removed its competing frame decoration and Aggregate custom surface owner.

**retainedAlternatives**

- See docs/component-library/card.md for per-owner audit covering all bundled plugins. Retain core popovers/sheets/menus and divider-only topic sidebar; media/identity chips and tables are not passive Card surfaces.
- Retain Chat message/thread previews with focus/unread/selection contracts, Assign scrollable member navigation pane, Voice video/ringing tiles, Events calendar/chips, Local Dates overlay preview, Poll voting/chart decorations, GitHub labels, Prometheus tables, GIF media and reaction controls.

**verification**

- flutter pub get --enforce-lockfile passed in root and profiles/full; lockfiles and Flutter 3.47.2 pin unchanged.
- flutter analyze --no-pub passed in root and profiles/full with no issues.
- Seed 834729: Card/component/examples + Skeleton examples + Groups/Group + Chat browse + Poll card + Event card/lifecycle + Preferences + Badge + Category suites passed 181 tests. Initial run caught and fixed Poll semantic-container regression.
- Seed 834729: Card/examples + Voice diagnostics + Aggregate + Preferences + d_button_adoption suites passed 48 tests.
- Seed 834729: final Card/examples run passed 12 tests, including 1fr/auto LTR/RTL geometry, shared spacing, direct footer, image/joined content, retained editing, keyboard activation, 200% reflow and unchanged header action element/focus.
- macOS debug local fixture build succeeded. Isolated /tmp/DiscourseCard5995.app uses org.discourse.native.card5995 and discourse-card5995 scheme. Deep/strict ad-hoc signature and App.framework payload byte matching verified. Native screenshots and AX evidence are inline in the Card task; ignored build/card-review/native-manifest.json and byte-match.json record the inspected build.
- Exclusive macOS native pass compared official rendered Card metrics and light/dark screenshots with all eight examples, Plum palette, RTL, narrow layout and 200% text. Exercised login, spacing draft retention, terms acceptance, image details, disabled/selected/busy/error/empty states; inspected actual bundled styleguide. Real local-data Groups, Members, Activity, Poll, Events, Chat and Badge fixtures exercised navigation, retry, vote, RSVP and join/unfollow callbacks.
- Coordinator reviewed stable clean Card HEAD 31663949f52a70ff90f791641a156e272cd8fd90, its seven passive APIs, exact 16/12px spacing and 1.4× radius, retained action elements/focus during header reflow, direct footer spacing, eight complete examples and core/plugin adoptions. Native inspection and isolated app closure are complete, including official light/dark comparison, narrow/RTL/200%/Plum examples and real Groups/Members/Activity/Poll/Events/Chat/Badge fixtures; device and other surface limitations remain explicit. Applied pre-reviewed reconciliation with both-parent fingerprints verified, preserving current Tooltip and Avatar within Event Card surfaces.
- Coordinator combined-main verification: all 466 focused library/styleguide/Tooltip and affected core, Chat, Poll, Events, preferences, directory, aggregate and Voice tests passed, seed 3790819455; log /private/tmp/component-card-integration-tests.log. The full profile passed 63 Card/Skeleton/Aspect Ratio component and example cases, seed 2853461005; log /private/tmp/component-card-full-tests.log. Root and full analysis are clean (11.3s and 3.2s); full-profile locked pub get passed with no lockfile/pin changes. All 19 touched Dart files are formatted and git diff --check passes. Generic Card, its eight examples and adopted Skeleton source exactly match the reviewed branch. All previously merged Tooltip, Avatar, Spinner, Skeleton, Aspect Ratio and Label owners remain present in changed application source.

**limitations**

- iOS and Linux native device inspection unavailable in this macOS session. Widget tests and platform overrides are not device testing.
- No VoiceOver audit; some native accessibility snapshots were sparse. Widget tests verify semantic grouping and keyboard/focus behavior. Preferences, Categories, Aggregate, Voice diagnostics and cooked/request fallback migrations have focused test coverage but were not individually inspected natively.
- Adjacent Button/Input/Badge/Toggle Group visuals remain pending their owners, as documented in the examples. Native inspected build displayed baseline status before the final metadata-only promotion to implemented.

### empty

Status: merged. Task: 01a0843e-76da-7911-ac98-49bd6dba8384. Branch: codex/ui-empty.

**acceptanceCriteria**

- Expose DEmpty, DEmptyHeader, DEmptyMedia (plain/icon), DEmptyTitle, DEmptyDescription and DEmptyContent with arbitrary-child composition and one generic rendering owner; no app dependencies or inert props.
- Match frozen base-nova 24px padding, 16/8/10px gaps, 384px slots, 32px icon media with 16px artwork and 8px bottom margin, proportional xl/lg radii, 14/20 medium tight title and 14/22.75 muted description; record source hashes and native wrapping adaptations.
- Provide actual-component basic, dashed outline, muted background, 48px avatar/group, local native search composition and RTL examples; preserve action/editing/keyboard/focus/Form ownership. Record later Input Group reconciliation without claiming its implementation.
- Audit core and bundled plugins; migrate appropriate page empty/error/no-results owners preserving retry/login/add/navigation/refresh callbacks and async/permission/loading behavior; retain compact inline statuses with reasons.
- Verify geometry, live palette/font/radius, narrow 200% RTL, semantics and actual callbacks through focused widget/downstream tests, touched formatting and root/full-profile analysis without changing pins/locks.
- Commit independent source/check work; build uniquely identified isolated macOS fixture/styleguide, record source equality, kernel hash and deep strict signature; remain in_progress awaiting_slot until explicit reference/native review.

**decisions**

- Frozen MD hash matches assignment; complete embedded example sources and base-nova registry captured under reference/empty with URL/SHA256 manifest and Tabler artwork/license. See empty-reference.md for measured geometry, semantic roles and adaptations.
- Single DEmpty owner exports all six slots plus plain/icon media; arbitrary child composition leaves input/Form/focus/semantics/controller lifetime to native children. 24/16/8/10px spacing, 384px slots, 32/16px media, 14/20 medium tight title and 14/22.75 muted description; proportional xl/lg radii and multiplied alpha.
- Seven self-contained actual-widget examples include outline, background, avatar/group, RTL and working native search Form. Final DButton variants and captured Lucide artwork match the frozen compositions; Input Group reconciliation remains explicitly deferred to its owner. Avatar fallback samples are local data.
- Independent browser and exact-source native review passed. Examples are implemented and the component is accepted for merge; no generic or application boundary issue remains known.
- The first native comparison exposed omitted/substituted RefreshCcw, Plus and ArrowUpRight artwork plus standard variants on reference primary actions. Review commits 6fd972c3 and 6134b938 restore the captured artwork and correct button roles with regression coverage.
- Integration update: merged pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7 into codex/ui-empty; all 17 merged components and Group/Sidebar/Topic Inbox fixes retained, every non-Empty progress row matches pinned main exactly. Earlier baseline Button/native TextFormField notes are superseded: actual examples now compose final DButton variants/sizes and DInput Form/prefix/suffix APIs. Badge/Checkbox/Radio owners retained unchanged; no substitute Input Group.

**migrations**

- Core page owners: no-sites (preserved h1/add-site callback), aggregate, categories, tags, drafts, user activity/pull-to-refresh, topic feed/retry key, groups directory/shared group state, users directory/progress, badge catalogue, signed-out private messages/connecting/error.
- Plugins: Chat channel/thread/browse/search/thread-list empty/error/retry, Assign no matching assignments, Voice empty room with cooked HTML/raw description preservation. Domain callbacks, permissions, requests and state/controller ownership remain in the original callers.

**retainedAlternatives**

- Compact forum-search/picker/channel-info status rows; stale-content/pagination errors; user-summary/awards subsections; latest-reply text; Voice chat messages; event period feedback; diagnostics; unsupported embedded media. These remain inline in dense usable surfaces, not oversized page cards.
- All loading skeleton/spinner owners and controller/network/business code remain outside Empty. Full audit details and plugin accounting in empty-reference.md.

**verification**

- flutter pub get --enforce-lockfile and full-profile enforced resolution passed; Flutter 3.47.2 and pins/lockfiles unchanged.
- Root flutter analyze --no-pub and profiles/full flutter analyze --no-pub passed with no diagnostics before final fixture additions; final commands recorded with build evidence.
- Focused downstream command in /tmp/empty-downstream.log: 244 tests passed covering examples, categories, tags, drafts, aggregate, groups, topics lifecycle, Chat browse/thread/search, Assign, Voice, users, badges, account accessibility and Button adoption.
- flutter test --no-pub test/empty_native_fixture_test.dart test/styleguide/empty_examples_test.dart test/ui/d_empty_test.dart --test-randomize-ordering-seed=random: 7 passed, seed 2421918493. Geometry/text metrics, live palette/radius plus borrowed editing/focus, Form validation/save/reset/keyboard, large RTL semantics, all examples at 320px/200% and wide dark, local search/support and actual production fixture retry.
- Additional changed-owner regression: 142 tests passed, seed 3270558952, covering group page/host, activity section lifecycle/totals, connection/session (including private messages), native fixture and final component API. Log /tmp/empty-extra-tests.log.
- Final root flutter analyze --no-pub passed with no diagnostics in 3.3s; all 30 touched Dart files formatted, git diff --check passed; no pubspec, lockfile or pin changes. Downstream 244-test seed was 2113997266.
- Final fixed-height centering/arbitrary-title and viewport-preserving offline fixture checks: 6 tests passed; /tmp/empty-tight-fixture-tests.log. Final root analysis clean in 3.0s, full-profile final analysis clean in 3.1s.
- macOS debug offline fixture/styleguide built successfully from clean source b5730d9ff6b6d58b19b392270459723e891a7361 (tree f689d8b50a0854148913fcc29ee268d057e1c079). Isolated review bundle /private/tmp/DiscourseEmptyReview-01a0843e.app; ID org.discourse.native.empty.01a0843e; scheme discourse-empty-review-01a0843e. Source/copied kernel SHA256 d87ca41a3c701fb7ea7fbcf7369d7c6fc487deaeaaec9894a390027c3cc458a4. Deep strict signature verification passed. Evidence: evidence/empty/native-preparation.json. No launch performed; user main-checkout build untouched.
- Pinned integration root and full-profile enforced-lockfile resolution passed. Root analysis clean (9.4s), full-profile analysis clean (2.0s). 172 focused integration tests passed, seed 1576441260: Empty examples/component/native fixture, Groups/group page, aggregate/users, Topic Inbox and Button adoption; log /tmp/empty-integration-tests.log. Formatting and git diff --check passed.
- Integrated offline fixture built from clean source 8bdc0386d7434dc5c440c1e8132b4b95edca7d13, tree fdfd00b8c4510428a56897cb34fba7462c3a50fd. Review bundle /private/tmp/DiscourseEmptyReview-8bdc0386.app, ID org.discourse.native.empty.8bdc0386, scheme discourse-empty-review-8bdc0386. Source/copy kernel SHA256 d76f9bb4ef47a699f8f90b68e61ed100dc5ff65a916bebbe731994313f78bda8. Explicit ad-hoc debug/JIT entitlements omit restricted developer/push/team identifiers; signed readback exactly matches and deep strict signature passes. Evidence evidence/empty/native-preparation-integrated.json supersedes earlier bundle. Runner identities/pins/locks unchanged from pinned main. Not launched; signature verification does not prove launch eligibility.
- Independent tests after review fixes: 9 Empty component/example/fixture tests passed with seed 2018809090; root flutter analyze --no-pub passed clean. Earlier review runs passed seeds 2442956183, 3444197866 and 1609925340, and full-profile analysis passed. Formatting and git diff --check passed.
- Official Base UI Empty examples were inspected in browser light/dark themes. The corrected exact-source bundle /private/tmp/DiscourseEmptyReview-6134b938.app was inspected for Basic, Outline, Background, Avatar Group, Arabic RTL, search, 200% text and dark/Forest palettes. Search empty validation, literal editing, submission and support action worked; primary/outline/link roles and captured artwork matched the reference.
- Native production-fixture inspection passed for no-sites, categories empty/error, groups and Chat. Chat Try again changed Local request failed. to No threads yet. The exact bundle uses source commit 6134b938b1b007d55ee56bf2a71fb16823af8663, tree 9e531629e0d3ecd075dcd32d61e25394f899825b and matching source/copied kernel d670ec098b6103300b509c81e907838f7ce73b276b392d496d10066b6c6260d0; deep strict signature and restricted-free entitlement readback passed. Evidence: evidence/empty/native-review.json.
- Latest-main reconciliation preserved all concurrent component rows and combined Empty's users-directory state with the merged DProgress owner. Empty component/example/fixture plus users-page suites passed 59 tests, seed 4052415972; root and full-profile analysis passed clean, formatting and git diff --check passed.

**limitations**

- Input Group example reconciliation remains pending that component after its Textarea prerequisite; final DInput/Form composition is functional but is not an Input Group implementation.
- No iOS/Linux device, VoiceOver speech or pixel-parity claim. Other migrated owners beyond the inspected no-sites/categories/groups/Chat fixtures retain downstream widget coverage rather than native screen inspection.

### item

Status: merged. Task: 01a084bf-dd8a-7c13-86dd-63f2e60d20cd. Branch: codex/ui-item.

**acceptanceCriteria**

- Provide one exported reusable owner for all ten Item parts with default/outline/muted variants, default/sm/xs metrics, image/icon/avatar media, multiple content columns, full-width header/footer and group/separator compositions.
- Match frozen markdown SHA c4a69c25199741ad3baea25f07a869e1aebf08cf3274f1a4f2e9da04afbbe0f0 and base-nova registry: 1px border, host lg radius, 12x10/10x8 padding, 10/8 gap, 14px title at 1.375 leading, 14/12px description at 1.5 leading, image 40/32/24 with sm radius; multiply muted/focus alpha and paint 3px exterior ring.
- Passive Item adds no control role; opt-in action/link supports keyboard visible focus, pointer/touch and borrowed FocusNode ownership. Child actions cannot activate parent by keyboard or pointer. Expose no editable state: native Form descendants retain their own owner.
- Prove geometry, live tokens, RTL, narrow/large text reflow, reduced motion, focus lifecycle, disabled interaction, child action isolation and group semantics with meaningful widget tests.
- Self-contained real-component styleguide covers every documented example and pending Button/Dropdown dependency reconciliation explicitly; source/artwork URLs and hashes retained.
- Audit core/plugin rows, migrate tag directory presentation and assignment detail rows while preserving lazy builders, per-row state, callbacks, permission guards and complete assignment notes; leave Empty/Alert regions to their owners.
- Run touched format, root/full static analysis, focused component/styleguide/migration checks, and distinct source-exact native fixture/styleguide verification with recorded kernel/signature provenance.

**decisions**

- Own Item only on main base 402fe578. Proposed migrations: TagsPage row presentation and AssignmentDetailRow; shared tags empty/error regions overlap Empty/Alert and remain untouched. Thread messaging tool absent in this task; handoff via progress/final.
- One generic owner exports all ten parts; full source hashes, CSS/logical metrics, semantics/layout/keyboard/native adaptations and audit are in docs/component-library/item.md.
- Thirteen actual-component examples use bundled reference artwork. The implementation's temporary MenuAnchor was historical preparation only and did not reach the accepted candidate.
- Independent review compared the live official Base UI Item page and exact-source native production fixture under the serialized desktop lease.
- Bounded integration merges pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7 via 1462873c; all 17 merged components, coordinator Group/Sidebar/Topic Inbox fixes and every non-Item progress row preserved.
- Final Button outline/small and accessible round icon-only outline/ghost actions, Badge role composition, controlled Checkbox fixture settings and DInput Form regression replace applicable temporary composition. No radio choices require replacement.
- Native RTL/200% inspection exposed inherited ellipsis on intentionally unclamped assignment notes; review fix fcc26238982fb062a84b4f964995d7026e547af7 uses clip only when maxLines is null and preserves explicit clamp ellipsis.
- The final current-main candidate composes accepted Dropdown Menu merge 5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787 with passive xs Items; menu focus, selection, dismissal and restoration remain Dropdown-owned.

**migrations**

- TagsPage ready rows now use exported TagDirectoryRow/DItem; lazy builder, ShellSelector, request identity, refresh, navigation, keys and count semantics remain app-owned.
- AssignmentDetailRow uses muted Item with existing avatar adapter and untruncated identity/status/note; permission callback and accessible full label retained.

**retainedAlternatives**

- Specialized topic/inbox/notification/read-state rows, draft/resume rows, activity tables and menu/field choices retain their existing state and interaction contracts; see item.md.
- Events participants and event-day records are candidate follow-ups for coordinated Calendar/Dialog/Events migration; no changes to their async authority or navigation checks.
- Empty page messages, Alert banners, Voice message rendering and reaction UserCardTarget rows remain with adjacent component owners.

**verification**

- Frozen markdown hash exactly matches; registry and artwork URLs/hashes committed under reference/item.
- Flutter 3.47.2 unchanged. Root and full-profile enforced-lockfile resolution passed; all pins/lockfiles unchanged.
- Root and full-profile flutter analyze --no-pub passed.
- 47 focused tests passed with seed 9092026: d_item, item_examples, item_migration_fixture, tags_page, assignment_sheet and styleguide_page. Includes pixel evidence that focus paints outside and does not tint muted interior; this is not native parity.
- Touched formatting and git diff --check passed.
- Final inherited-clamp correction: 34 focused component/styleguide/migration tests passed with seed 9092026; root and full-profile analysis passed again. Earlier 47-test run also covered the unchanged styleguide shell.
- Isolated ItemReview82f4 macOS debug build succeeded from e792c515; actual Info.plist confirms org.discourse.itemreview82f4 and discourse-item-review-82f4 URL scheme. Local ad-hoc signature passes codesign --verify --deep --strict.
- Build and copied App.framework kernels both SHA256 7f7f633347d1a22adc56397fec4be1298837c0702253676fef1662d46991b596. Runner files restored; lib/pubspec/macos equality to source commit and all pin/lockfile equality to 402fe578 verified. See item-build.md and reference/item/build.json.
- Pinned-main integration: Item/styleguide examples/TagsPage/AssignmentSheet suites passed; fixture control-width/settled-scroll correction then passed final 11 Item/fixture tests including final Checkbox pointer/Space isolation and final Input Form retention. Root and full-profile analysis pass after final changes.
- Integrated exact-source macOS build from 68402409 succeeded: ItemReview82f4Integrated.app / org.discourse.itemreview82f4integrated / discourse-item-review-82f4-integrated. Explicit local debug/JIT entitlement signed readback is restricted-free across main app/frameworks/dylibs; strict deep signature passes and no embedded profile remains.
- Integrated copied/build kernel SHA256 cf0a1efc46876ee29e0fc93fcee132e6b14977e82d0f1dd725c472b55df48122. Source/runner equality to 68402409 and all pins/locks equality to e612ad7b verified; all non-Item progress and coordinator Group/Sidebar/Topic Inbox source preserved. See item-build.md and reference/item/integration-build.json.
- Live official Base UI comparison confirmed the 448px Item width, 10x12 default/sm and 8x10 xs padding, 10/8 gaps, 1px border, 10px radius and 14/20 text geometry in light and dark rendering.
- Initial native production-fixture inspection exercised tag navigation, assignment editing and permission-disabled rows. RTL, dark and 200% text exposed the unclamped-note ellipsis defect fixed in fcc26238.
- Corrected exact-source ItemReviewD14aFinal.app uses org.discourse.itemreviewd14afinal / discourse-item-review-d14a-final; build and copied kernels match SHA256 b792631873ef9e75576a154432c7f7e6eb9c6d0d9915843c2f945fa2d4675013 and deep strict signing passed with only recorded debug/JIT/network entitlements.
- Corrected native confirmation showed every line of both real assignment notes at RTL/dark/200% without ellipsis and retained Edit assignment 2 activation.
- Final accepted Dropdown composition plus Item/component/migration suites passed 35 tests with seed 9092026; root and full-profile flutter analyze --no-pub, Dart formatting and git diff --check passed. Dependency resolution used existing enforced lockfiles without changes.

**limitations**

- No iOS/Linux device, spoken VoiceOver, authenticated screen or pixel-parity validation. macOS Accessibility roles/actions and focused widget semantics were inspected.
- Events participant/day rows remain candidate follow-ups for their Calendar/Dialog/Events owners; this review did not change their async or navigation authority.

### table

Status: merged. Task: 01a0844a-0669-7780-92e8-33cc4314f64a. Branch: codex/ui-table.

**acceptanceCriteria**

- Port base-nova table/header/body/footer/row/head/cell/caption with 14/20 typography, 40px heads, 8px cell padding, 1px section rules, caption gap 16px, muted alpha hover/expanded and controlled selected state.
- Support column sizing and spanning footer cells, shared column alignment, intrinsic horizontal overflow, RTL reading order, large text growth, semantic headers and keyboard-accessible composed actions; borrowed scroll controllers survive disposal.
- Provide self-contained default seven-invoice, footer, product actions, selected/expanded and Arabic RTL styleguide examples using production DTable.
- Audit core and plugin tables; migrate appropriate presentation preserving business callbacks, permissions and scrolling; document concrete specialized retained owners.
- Pass touched format, root/full analysis and focused component/adoption tests; build exact-source uniquely identified signed macOS fixture, then await desktop slot for reference/native comparison.

**decisions**

- Single generic eager DTable owner with immutable typed sections/rows, widget cells/caption, Flutter column sizing and spanning footer layout; source mapping and exact frozen source hashes in table.md.
- Controlled selected/expanded presentation, semantic table/rows/headers/cells and child-owned native actions/Form; live palette/font, RTL, reduced-motion alpha multiplication and intrinsic overflow.
- Task worktree /Users/joffreyjaffeux/.codex/worktrees/7328/discourse-native; no Users/Poll changes or unmerged component dependencies.

**migrations**

- Prometheus AlertTables presentation migrated; plugin collapse/link/timezone/quote permission/order/scrollbar/sizing behavior retained.
- Skeleton ready-state table example migrated with its authored spacing.

**retainedAlternatives**

- Users pinned virtualized synchronized grid retained for specific scrolling/width persistence/hover isolation contracts; Data Table owner review boundary, Chart/Resizable adjacent ownership preserved.
- CookedHtml authored DOM tables remain with HtmlWidget CSS/spans/selection; Typography frozen 16/24 full-grid article examples remain distinct.
- Responsive discovery/group/member lists and Poll result bars are not generic presentation tables; detailed audit in table.md.

**verification**

- flutter pub get --enforce-lockfile (root and profiles/full): passed; Flutter 3.47.2 and lockfiles unchanged.
- dart format touched Dart files and git diff --check: passed.
- flutter analyze --no-pub (root): no issues; profiles/full: no issues.
- flutter test --no-pub test/d_table_test.dart test/alert_tables_test.dart test/alert_data_test.dart test/alert_links_test.dart test/prometheus_alert_receiver_plugin_test.dart test/styleguide/styleguide_page_test.dart test/styleguide/skeleton_examples_test.dart --test-randomize-ordering-seed=9092026: 65 passed.
- Widget checks: source geometry, spanning alignment/caption, semantic table-row-header-cell hierarchy, selected semantics, live multiplied alpha/reduced motion, borrowed controller, RTL large-text horizontal scrolling, keyboard menu edit and all examples at 360px/200%.
- Native review fixture entrypoint tool/table_review.dart prepared; build provenance follows after source commit.
- flutter build macos --debug --no-pub -t tool/table_review.dart: passed in isolated checkout; copied /tmp/table-review-7328/Table Review 7328.app, ID org.discourse.tablereview7328, URL scheme discourse-table-review-7328.
- Build source f98c86e983088205647b11c97c6027ce706ad8dd; tracked lib/fixture/pin/root-lock bytes unchanged, temporary runner edits restored. Copied kernel equals original build kernel SHA256 8f46827b04e593cd6fa1f05daea14e315b1a00c42a60f4cf5291ea4b622a6e79.
- Copied Info.plist ID corrected after debug configuration override; ad-hoc codesign and codesign --verify --deep --strict passed. Detailed build log/provenance/signature in /tmp/table-review-7328/. Native app has not been launched.
- Integration: merged pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7; all non-Table progress rows preserved exactly. Table examples now compose merged DButton; retained custom spans/semantics, AlertTables/Skeleton adapters and Users boundary.
- Integration root/full enforced-lockfile resolution and analysis passed. 50 focused Table/AlertTables/Skeleton/styleguide tests passed seed 9092026; final trigger-size follow-up: all 7 DTable tests passed.
- Superseding native artifact source 80c801e69ee94b8f1d02ca71ccb489bc53aec257, /tmp/table-review-7328/Table Review 7328.app; final ID org.discourse.tablereview7328 and URL scheme discourse-table-review-7328 verified. Copied kernel equals built SHA256 ec4e523c98e3978b530bf4adda8f52ce452864c006d8d9bb3d54f0c392c54e4a.
- Ad-hoc debug entitlement read-back equals only allow-jit, allow-unsigned-executable-memory and disable-library-validation; no restricted entitlements. Deep strict signature verification passed; tracked source/fixture/pin/lock equality passed and runner edits restored.
- Independent reviewer reran the final 66-test Table/AlertTables/Skeleton/styleguide bundle with seed 9092026 after fixes; all passed. Root analysis passed in 66.8s, profiles/full analysis passed in 11.7s, touched formatting and git diff --check passed, and lockfiles remained unchanged.
- Approved browser comparison inspected the official Base UI Table default, Footer, Actions and RTL examples in light and dark themes. Native default/dark/Forest renders matched the compact geometry, alignment, rules, footer/caption spacing and 32px action trigger; production AlertTables links, dates, actions, collapse persistence, quote permissions, empty-to-ready transition, Local Dates, dark RTL and 200% text were exercised without overflow.
- Native keyboard review found and fixed initial menu-item focus plus trigger-focus restoration. The final exact-source app confirmed Return opens Actions with Edit focused, activates Edit, restores trigger focus and reopens on the next Return.
- Final exact-source macOS bundle /tmp/table-review-fdec-907ddaf1/Table Review fdec final.app was built from 907ddaf18f703ed3aed95c5456705d73b97dc20f with ID org.discourse.tablereviewfdecfinal, URL scheme discourse-table-review-fdec-final and matching copied/built kernel SHA256 d5db668fc8233f8772cf612ccf79a9797d527539ec132ab2a0f9475680356282. Deep strict ad-hoc signature passed; entitlement read-back contains only allow-jit, allow-unsigned-executable-memory and disable-library-validation.

**limitations**

- Actions temporarily compose merged DButton and native MenuAnchor until Dropdown Menu merges; the temporary composition is keyboard-functional and restores trigger focus.
- Native horizontal trackpad scrolling was not conclusively established during CUA inspection; the overflow/controller behavior is covered by widget tests.
- No spoken VoiceOver or iOS/Linux device inspection was performed, and no pixel-parity claim is made.

### scroll-area

Status: merged. Task: 01a083e1-420b-7711-b8e8-f268576dcc3b. Branch: codex/ui-scroll-area.

**acceptanceCriteria**

- Port base-nova 10px transparent scrollbar track, 1px padding plus 1px transparent leading border and border-colored rounded thumb with live palette/radius and visible viewport keyboard focus.
- Expose vertical, horizontal and combined viewport/scrollbar/thumb/corner composition with one Flutter scroll owner per axis, owned or borrowed controllers and preserved position across rebuilds.
- Verify wheel, thumb drag, touch and keyboard scrolling, RTL, visibility, resizing and controller replacement/removal without disposing borrowed resources.
- Reproduce Tags/Horizontal/RTL reference examples and local combined/lazy composition; preserve styleguide explicit 360/768/1024 widths and state during preview changes.
- Audit core/plugins, migrate appropriate Sidebar and wide-preview scrollbar ownership, document retained specialized timelines/menus and any additional migrations.
- Pass focused component/downstream tests, root/full-profile analysis, isolated signed macOS fixture build, reference comparison and native macOS inspection.

**decisions**

- Source mapping, native adaptations and full adoption audit: docs/component-library/scroll-area.md; hashed official registry/Markdown/Base UI behavior and reference photos in reference/scroll-area/sources.json.
- DScrollArea uses one native position per enabled axis; DScrollBar decorates existing native scrolling, with composable DScrollViewport, DScrollThumb and DScrollCorner. Live tokens, 7px capsule in 10px track, 16px minimum thumb and keyboard focus ring.
- Tags, Horizontal, RTL, combined overflow and lazy-controller composition are actual public-component styleguide examples; independent native acceptance promoted the styleguide entry to implemented.
- Coordinator keyboard follow-up: only overflowing areas enter root Tab traversal; descendant focus/state survive content and viewport resize transitions. Shift+Space pages upward; unrelated Ctrl/Alt/Meta and Shift-modified keys bubble.
- Browser-only review completed and released: measured light/dark/RTL/keyboard reference, corrected exterior-only focus ring with alpha multiplication, rounded-md×0.8 and rendered photo150×200 dimensions. Font-loaded actual examples/production fixtures exported; scroll-area-render-review.md and hashed rendered artifacts preserve findings.

**migrations**

- DSidebarContent and explicit wide styleguide preview scrollbar (width/state/controller preservation).
- CodeBlock, DiagnosticsPanel, VoiceDiagnosticsView, Assign people rail, Prometheus tables and EventCalendar month scrollbar decorators preserve native viewport/controllers and domain behavior.

**retainedAlternatives**

- Synchronized split-column Users directory scrollbars need dedicated adapter/fixture review; retained.
- Topic/Chat/SuperList timelines, shell sliver sidebar and restoration/pagination owners are retained without a second viewport.
- ChoiceMenu/CommandMenu/AnchoredPicker focus/intrinsic viewport owners and existing example-specific scroll demonstrations remain with their catalogue owners; no unmerged dependency used.

**verification**

- Flutter 3.47.2/Dart 3.13.2 unchanged; root and full-profile flutter pub get --enforce-lockfile succeeded with unchanged lockfiles.
- flutter analyze --no-pub: no issues; full-profile flutter analyze --no-pub: no issues.
- flutter test --no-pub test/d_scroll_area_test.dart test/styleguide/scroll_area_examples_test.dart test/d_sidebar_test.dart test/styleguide/sidebar_examples_test.dart test/styleguide/styleguide_page_test.dart test/code_block_test.dart test/diagnostics_panel_test.dart test/voice_diagnostics_view_test.dart test/assigned_group_view_test.dart test/alert_tables_test.dart test/event_calendar_test.dart --test-randomize-ordering-seed=random: 103 passed; log /tmp/scroll-area-focused.log.
- Touched Dart formatting and git diff --check pass. Native offline fixture entrypoint lib/scroll_area_review_main.dart mounts actual migrated widgets and styleguide.
- Final source f3ad79ca78f2552771803e8722fd72e5774644ec: root and full-profile analysis clean. Self-contained usage snippets rechecked with example test; 103-test focused run seed 1005865238.
- Isolated macOS debug build succeeded. Unique final app ID org.discourse.scrollareareviewd422 and URL scheme discourse-scroll-area-review-d422. Kernel equality and deep strict ad-hoc signature verification passed; full provenance in docs/component-library/scroll-area-native.md.
- Keyboard follow-up: 35 focused Scroll Area/Sidebar/styleguide tests passed, including real Tab traversal, child text selection and button Enter/Space activation, content/viewport overflow transitions and modified-key propagation. Log /tmp/scroll-area-keyboard.log.
- Keyboard follow-up final executable source 5ccd42497c6db763d5e37f3ffb5a5d89f5111209: root/full-profile analysis clean; rebuilt isolated macOS fixture, production source equality checked, copied/build kernel SHA256 042805352d6b28602593333032112aad0aa7b45e17eadb65cd35671894251d63; deep strict signature verification passed. Awaiting native slot.
- Rendered follow-up:106 focused tests passed (seed1519015133), including RGBA focus interior/exterior/alpha regression; root/full-profile analysis clean. Export runner captured registered examples and migrated widgets with loaded SFNS/SFArabic/MaterialIcons/JetBrains Mono; fixture errors explicitly recorded, not treated as native acceptance.
- Rendered-review final executable source 1514d822c89c30e32cc5d46419682c6541d7e3ad: clean source equality after runner restoration; isolated macOS debug build succeeded; unique ID verified; build/copied kernel SHA256 42b26b4ed21e2f0a366893cbc3822dc84a8a1e590396b476a20c9a7c554e8192; deep strict signature passed. No native launch.
- Backlog preparation: merged pinned main00f82d280a602c4ec86be3a24664f4052e6c1477; preserved all non-Scroll-Area progress rows and current shared owners.109 affected component/Sidebar/styleguide/production tests passed seed1438380230; root/full analysis clean. No unchanged browser/export review repeated.
- Final pinned-main native preparation source ad0647a4d46b756b87d5b9c5c0ca526e26cb2e17: isolated build passed; clean source equality and build/copied kernel SHA256 cb549143dbb2b4307b93a606c34e0090c8d9026ab36684d07c2b710c01ac6579 verified. Deep strict signature and exact read-back of sandbox/JIT/network client+server entitlements passed; no APS/team/application IDs. Native remains awaiting_slot.
- Final17-component baseline: mergede612ad7b at source 3e40cb9e1afc3441bc4f8e3d9fb2f6b2adf40f6e without conflicts, other progress rows equal pinned main.114 targeted integration tests pass seed4102292575; root/full analysis clean. Unique isolated debug build, clean source equality, copied kernel SHA256 1361361d520ac8cb0e836ed7581c2e4713c6777a666fc625977f382feda4acc0, strict signature and restricted-free sandbox/JIT/network entitlement read-back verified. No UI use.
- Independent macOS native review launched that exact signed bundle: accepted light/dark Tags geometry, RTL leading scrollbar, bundled horizontal photos, vertical wheel and thumb drag, horizontal thumb drag, two-axis corner composition, and native accessibility separation. Migrated Sidebar and Code scrolled; Alerts and Diagnostics ready states rendered, with Diagnostics rows unclipped.
- Independent review branch: root and profiles/full flutter pub get --enforce-lockfile completed without lockfile changes; 109 focused component/styleguide/Sidebar/production tests passed with seed238741; root and profiles/full flutter analyze --no-pub found no issues; git diff --check passed.
- Latest-main reconciliation integrated reviewed Switch and preserved its exports/migrations. 27 overlapping Scroll Area/styleguide/Voice tests passed with seed238742; root analysis and git diff --check remained clean.

**limitations**

- No iOS/Linux device or VoiceOver testing; no pixel-parity claim.
- No physical touch-device or native trackpad pass; touch, reduced-motion, large-text, resize and controller lifecycle behavior are covered by focused widget/render evidence.
- The captured Diagnostics large-text overflow artifact is historical; the main-owned row-sizing fix is integrated and the independent native fixture showed unclipped rows.

### collapsible

Status: merged. Task: 01a08445-7647-7a83-a366-e06252405043. Branch: codex/ui-collapsible.

**acceptanceCriteria**

- Composable DCollapsible root, trigger and content support controlled/default open state, disabled activation, nested scopes and borrowed focus ownership without app dependencies.
- Match captured base-nova unstyled disclosure primitive and measured demo/Basic/Settings Panel/File Tree/RTL composition; incidental Button variants remain Button concerns.
- Verify Enter/Space, expanded/disabled semantics, visible focus, focus restoration on collapse, lazy unmount and explicit keep-mounted editing retention, transition reversal and reduced motion.
- Audit core/plugin disclosure owners and migrate appropriate single panels preserving editing, callbacks, permissions, async and scroll ownership; document retained sliver/Accordion alternatives.
- Provide actual-component local examples and production fixtures; pass touched format, root/full analysis and focused component/migration checks on pinned Flutter; isolated signed native bundle and reference/native inspection required before review_ready.

**decisions**

- Frozen markdown SHA256 verified; base-nova wrappers have no visual classes or animation. Sources/registry/Base UI/Lucide URLs and hashes plus CSS mapping: docs/component-library/evidence/collapsible/implementation.md and sources.json.
- Public DCollapsible/Trigger/Content expose composition, controlled/default state, disabled focusable triggers, passive state builder, borrowed focus nodes and explicit retained/lazy content with optional reduced-motion-aware height animation. Browser hiddenUntilFound maps to host-controlled open for search, not an inert native prop.
- Actual order, Basic, Settings, nested File Tree, RTL and lifecycle/Form examples use merged Card and available DButton/StyleguideAction/native editing. Input/Field/Tabs remain pending and exact dependent button/editor visuals are explicitly identified for reconciliation.
- Integration refresh: merged pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7 preserving all other progress rows and coordinator fixes. Examples use final DInput and DButton; trigger remains the sole disclosure interaction owner. Field/Tabs still unmerged.
- Independent native review found and fixed an oversized semantics boundary: DCollapsibleTrigger is now an explicit semantic container, keeping enclosing cards, fields and sibling controls outside its button role.
- Latest-main reconciliation preserves DSwitchTile in Local Dates and DScrollBar in AlertTables while DCollapsible remains the only disclosure owner. Field remains a documented DInput-owned label boundary. Tabs reviewer 01a08581-d666-7f81-b039-f9caae6c45c2 completed the explicit File Tree DTabs.controlled follow-up without changing disclosure ownership.

**migrations**

- Events More options and Local Dates Display options replace ExpansionTile with retained DCollapsible editor composition, preserving controllers, selection, values, permissions, stale guards, asynchronous pickers and Apply outputs.
- Prometheus AlertTables groups use controlled DCollapsible, preserving group refresh/default override, lazy content, horizontal scroll ownership, quote/link callbacks and compact app sizing. Stable PageStorage key retains horizontal offset across collapse.

**retainedAlternatives**

- Persisted InstanceSidebar lazy sliver groups retain their sliver disclosure; box content would change eager/lazy scroll ownership.
- Composer reply excerpt retains constrained header/Expanded scrolling adaptation; topic inbound links and Chat deleted-message reveals are one-way domain show-more actions.
- AI summary/inbox AnimatedSize are asynchronous/responsive layout transitions. Markdown collapsed projection state belongs to source editing. Sidebar styleguide submenu reconciliation remains with coordinator to avoid adjacent ownership changes.

**verification**

- Flutter 3.47.2; flutter pub get --enforce-lockfile at root and profiles/full passed with pins/lockfiles unchanged.
- Touched dart format and git diff --check passed; flutter analyze --no-pub at root and profiles/full passed.
- 61 focused tests passed: test/ui/d_collapsible_test.dart, test/styleguide/collapsible_examples_test.dart, test/collapsible_editor_migration_test.dart, test/collapsible_review_fixture_test.dart, test/event_composer_test.dart, test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart, test/plugins/local_dates/local_date_composer_component_test.dart, test/alert_tables_test.dart, test/prometheus_alert_receiver_plugin_test.dart, test/styleguide/styleguide_page_test.dart.
- Isolated Collapsible Review 3c15 macOS debug app built from e05de6002a37f1dfbc7483a29f921086dffb0d3d; restored source equality and deep strict ad-hoc signature verification passed. Embedded/built kernel SHA256 57c4799f2342c03b9638bccf126114ce1f70ecc2dfcea46f9a2a472e850955f2. Exact path/identity/temporary signing adaptations: docs/component-library/evidence/collapsible/native-build.json. No launch.
- Integration: 47 focused tests and root/full analysis passed. Source 39159f39becd55a320da35aab967aaaad2ef6d6f built as Collapsible Integrated 3c15.app. Embedded/built kernel SHA256 0c06245b0af44db0d0cb2220cc4e98ad6b00cbbc3b300a497e3d7696fd1054c1; source equality, restricted-free signed debug/JIT readback and strict deep signature passed. Exact identity/path/evidence in native-build.json. No launch.
- Independent reviewer reran 63 focused component, example, migration, fixture and styleguide tests after the semantics correction; all passed. Root and profiles/full flutter analyze --no-pub passed with no issues; touched formatting and git diff --check passed.
- Approved browser inspection covered the official rendered Base UI dark Order disclosure and the documented Basic, Settings, File Tree and RTL compositions. Controlled collapsed/expanded state and two revealed detail rows matched the frozen source geometry and state treatment closely.
- Native macOS inspection covered light/dark Order, keyboard activation, Settings, Events More options, Local Dates Display options and 32-row AlertTables groups. The initial Settings tree exposed the merged button semantics defect; the rebuilt fix confirmed a passive card, one bounded trigger and four independent text fields, with hidden descendants added only on expansion.
- Latest-main overlap verification preserved merged DSwitchTile and DScrollBar child owners; 32 focused overlap tests plus root/full analysis passed. Final isolated Collapsible Final c91e.app rebuilt successfully with kernel SHA256 390c06fa872ff7a43f04cdb1fc59de7cce8472df097857b858e56612048a2ddc, restored runner equality and strict deep ad-hoc signature verification.
- Final source/adoption/evidence review found no remaining Collapsible-owned issue. Full suite was not run under the user's focused-verification policy.
- Final main 27ddc513, including the reviewed Progress owner and complete workflow metadata, integrated without Collapsible conflict. The 21 component/editor/AlertTables overlap checks and root/full analysis passed again; all other component rows were preserved.

**limitations**

- No iOS or Linux device run and no spoken VoiceOver claim. Target-platform widget coverage is not device testing.
- Native production inspection used actual Events, Local Dates and AlertTables widgets with fixed local data; no authenticated live account or network session was opened.
- Browser Geist and native host font rasterization differ, so no pixel-equality claim is made. Geometry, palette mapping, interaction and native semantics were compared directly.
- The separately reviewed Tabs owner replaced the temporary File Tree Explorer/Outline buttons with controlled DTabs; Collapsible continues to own only folder disclosure state.

### accordion

Status: merged. Task: 01a0859b-73ff-7190-8c59-b71fe74d2b2f. Branch: codex/ui-accordion.

**acceptanceCriteria**

- Match all frozen Basic, Multiple, Disabled, Borders, Card and RTL variants and the complete native API contract against official source and rendered behavior.
- Compose accepted Collapsible state/lifecycle behavior with genuine controlled/uncontrolled expansion, dynamic/disabled items, keyboard/focus, bounded actionable headings/triggers and accessible descendants.
- Preserve exact reference geometry and states while supporting live palette/font/radius, touch, RTL, text scaling, narrow layout, reduced motion and panel lifecycle.
- Audit and migrate appropriate related disclosure groups, retain independent disclosures when appropriate, and add complete styleguide/usage plus meaningful focused component/consumer verification.
- Create a fresh independent reviewer that owns fixes, remaining rendered/native acceptance and the final local main merge.

**decisions**

- Collapsible is accepted and merged as 985b4efd; its corrected native trigger semantics boundary must be preserved. Card and other shared foundations are also merged.
- Existing Events/Local Dates standalone disclosures retain the merged Collapsible owner unless a real grouped accordion use case justifies migration.
- Frozen Markdown hash, current registry hash, exact measurements, API mapping and acceptance are recorded in docs/component-library/accordion-reference.md.
- DAccordion<T>, DAccordionItem<T>, DAccordionHeader, DAccordionTrigger, DAccordionContent and DAccordionController<T> expose typed single/multiple composition with controlled, internally owned or explicitly borrowed state.
- Items key their root wrappers so reorder preserves expansion and descendant identity; local/controller state prunes removed values after the frame while controlled values remain caller-owned.
- Accordion composes DCollapsible for activation, expanded semantics, focus restoration, panel lifecycle and reduced motion. A narrow optional Collapsible focus-painter extension supplies the base-nova rounded one-pixel border and outside-only three-pixel 50% ring without changing existing defaults.
- Independent review corrected borrowed-to-local controller transitions, duplicate null wrapper keys and reused-child root-state propagation; it also preserved non-uniform focus geometry outside outlined clipping and removed an undocumented pressed fade.
- The styleguide reserves an 800px Accordion preview so the 360px/200% RTL sample remains visible, and its controlled dynamic-item action prunes a removed open value before an item can be re-added.

**retainedAlternatives**

- Event Composer and Local Dates advanced options remain independent accepted DCollapsible disclosures; coordinating them as Accordion items would invent group semantics.
- Prometheus raw payload remains one independent DCollapsible disclosure. Browser tabs, topic/user filters, settings navigation and nested routes retain their navigation/domain owners because Accordion would change routing, persistence or disclosure behavior.

**verification**

- Frozen shadcn Markdown SHA256 reproduced exactly as ccd53e3cb2e6d1cd1cc72588b853fdc8aefe08aab3d5cb515d28dfe09dcf149f; current base-nova registry inspected as 01509cb2a91779ee74c2d4a1f75842c0a258bed1758be4f2567af9daabdc39ac and current Base UI behavior API inspected.
- 50 Accordion, Collapsible, styleguide, Alert-overlap and styleguide-shell tests passed with random seed 417203 after integration, covering single/multiple/controlled/controller state, dynamic reorder/removal, pointer, Enter/Space, Tab, disabled state, bounded heading/expanded semantics, independent fields, focus restoration, retention, geometry, touch, RTL, 200% text, live tokens and reduced motion.
- After integrating Empty through main b1720522, 46 Accordion, Collapsible, Accordion styleguide and styleguide-page tests passed again with random seed 417203; root and profiles/full analysis remained clean.
- Root and profiles/full flutter analyze --no-pub pass with no issues after latest-main integration; Dart formatting and git diff --check pass and dependency pins/lockfiles are unchanged.
- flutter build macos --debug --no-pub -t lib/styleguide_main.dart passed from integrated source. The compiled kernel SHA256 is d79bdf1ebd81dd8fe4a3cce15e8791ae86a01036738ac4ba4a386d0343ae8fed.
- The latest-main candidate based on 15e65e76 passed 88 focused Accordion, Collapsible, styleguide and retained-consumer tests with random seed 417203 after the Toast production migration; root and profiles/full flutter analyze --no-pub, Dart formatting and git diff --check passed.
- Approved official-browser inspection covered every registered reference variant, light/dark rendering, pointer and keyboard behavior, disabled state and exact focus geometry. Computed 14/20 medium text, 10px vertical padding, 16px chevron, 50% disabled opacity and one-plus-three-pixel focus bands matched the source mapping.
- The uniquely identified macOS styleguide bundle passed dark/light/Forest, pointer, Tab/Return/Space, single/multiple/disabled, Borders/Card/RTL, 360px/200%, reduced-motion, semantics and controlled lifecycle inspection. Its final embedded/build kernel SHA256 is 4aa2785f5a67437389be0bb82516afa130e549e09a7584e1fc182dd4ccd81a2d and its strict deep ad-hoc signature passed; full evidence is docs/component-library/evidence/accordion/native-review.md.
- A final native follow-up on source 8f24147b7870eebb55debd28d304eccb0cff0f07 confirmed removing an open controlled Security item changed live state from profile, security to profile, and re-adding it left the panel closed.
- The accepted latest-main candidate was merged locally from the shared main checkout as f3aa5074a848a6f8ee793de7323cf9de766be1d4; no remote push or external release change was made.

**limitations**

- Native device inspection was macOS only. No iOS or Linux device was run and no spoken VoiceOver claim is made; macOS Accessibility API roles/actions were inspected directly and have widget regressions.
- Browser Geist and native host font rasterization differ, so no pixel-equality claim is made. Geometry, palette/state mapping, direction, interaction and semantic ownership were compared directly.
- Browser hidden-until-found has no native equivalent; hosts reveal search matches using controlled values or DAccordionController.

### tabs

Status: merged. Task: 01a08560-5018-7e52-aa73-14ff2ce6cc28. Branch: codex/ui-tabs.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova default/line, horizontal/vertical, disabled, icon, RTL and Card compositions with explicit source-to-Flutter geometry and behavior mapping.
- Provide generic local, controlled and borrowed-controller selection; dynamic fallback; native selected-button semantics; roving focus; panel lifecycle and focus restoration without app dependencies.
- Support live host theme/font/radius, light/dark/custom palettes, touch, narrow layouts, text scaling, RTL and reduced motion while retaining compact shadcn artwork.
- Migrate appropriate core/plugin tab surfaces while preserving application routing, permissions, plugin data and state ownership; document retained domain alternatives.
- Provide complete interactive examples, meaningful component/consumer tests, root/full-profile analysis and honest rendered/native evidence owned to completion by the independent reviewer.

**decisions**

- Exact frozen/reference source hashes, measurements, API mapping and acceptance are recorded in docs/component-library/tabs-reference.md.
- DTabs<T>, DTabList<T>, DTabTrigger<T>, DTabPanel<T> and DTabController<T> expose composition and selection. Hidden panels unmount by default; maintainState keeps them offstage without ticking/semantics.
- Horizontal lists scroll and reveal focused triggers. Vertical content stacks below its still-vertical list below 320px or above 150% text scaling to prevent narrow overflow.
- Independent review corrected roving entry focus, explicit controller clear, 48px trigger hit targets around 25px artwork, structural replacement validation and whole-trigger disabled opacity. The fixes preserve compact browser geometry while providing native touch accessibility.
- The Collapsible File Tree now composes Explorer/Outline with controlled DTabs while its nested disclosure and selected-file state remain Collapsible-owned.
- Collapsible reviewer 01a08558-a79c-7911-8f75-53b3528fc08f received the final API handoff for its temporary File Tree selector; the Tabs reviewer will notify it after merge.

**migrations**

- Group primary core/plugin route tabs use controlled DTabs while capability filtering and GroupRoute translation remain in group_page.dart.
- Chat channel-info Settings/Members use the line variant inside the retained 58px app bar; ChatShellService remains routing owner.
- Diagnostics General/Topic scroll/plugin routes use controlled DTabs; capture and plugin state remain diagnostics-owned.

**retainedAlternatives**

- ForumTabsBar and Aggregate tabs retain browser-workspace close/reopen/reorder/persistence/context-menu behavior and are not layered content tabs.
- Topic list and User Menu strips retain unread/filter/period/notification domain rendering; Group secondary and Preferences navigation remain sidebar/picker owners.

**verification**

- Frozen shadcn Markdown SHA256 reproduced exactly; current base-nova registry and Base UI Markdown inspected with hashes recorded in tabs-reference.md.
- 27 component, Tabs styleguide and Collapsible File Tree tests passed with random seed 1188269210 after independent corrections, covering geometry, local/controlled/controller selection and clear, pointer/semantics, manual/automatic/RTL/vertical roving focus, structural replacement, disabled/dynamic fallback, panel lifecycle, focus restoration, 48px touch targets around 25px artwork, narrow/200% text, reduced motion and live tokens.
- 39 Group and Chat channel-info production regression tests passed with random seed 592397163 after latest-main reconciliation; four focused Diagnostics route/capture checks passed with the same seed. An earlier pre-correction 65-test migration batch also passed, but it is not presented as final-source coverage.
- The two Chat shell migration-specific layout/routing tests pass after retaining the full-width 58px app bar and distinguishing its 48px interaction trigger from the measured 25px artwork.
- Full test/chat_shell_integration_test.dart passed all 138 tests with random seed 1517999890 after the Chat tab migration correction.
- Root and profiles/full flutter analyze --no-pub pass with no issues after latest-main reconciliation. Touched Dart format check and git diff --check pass; dependency pins, SDK and lockfiles are unchanged.
- Approved official-browser inspection measured the 32px list, 25px default artwork, selected/inactive palettes, complete 0.5 disabled opacity, 2px line indicator, vertical geometry and right-to-left logical order; pointer selection replaced the active Card panel.
- Two uniquely identified signed macOS bundles passed native review. The styleguide rendered all seven examples in dark/light palettes, RTL and 200% text without clipping, and exposed one bounded button per trigger plus active-panel-only content. The production harness exercised actual Group, Chat channel-info and Diagnostics route tabs. Full observations and bundle hashes: docs/component-library/evidence/tabs/native-review.md.
- Final latest-main reconciliation preserved every other component row, integrated Toggle Group dispatch metadata and passed 27 component/example checks, 43 production overlap checks, and root/full static analysis before local main merge 7e6bf1234fcd55aced4037c7e36946d017fe5c79.

**limitations**

- No iOS or Linux device run and no spoken VoiceOver claim. Target-platform widget coverage is not device testing.
- The production harness used local fixture data without an authenticated account; Chat Members reached its unauthenticated network-error state after the tab route changed.
- The production harness's macOS launch image remained painted over captured frames while its live accessibility tree and route actions updated underneath. Production-widget evidence is therefore interaction/semantics only; native raster comparison comes from the separately signed styleguide bundle.
- Browser Geist and native host font rasterization differ, so no pixel-equality claim is made. Geometry, palette/state mapping, direction, interaction and semantic ownership were compared directly.

### resizable

Status: merged. Task: 01a083e2-4063-7c30-89ea-fa664ff9c943. Branch: codex/ui-resizable.

**acceptanceCriteria**

- Port frozen Base Nova horizontal, vertical, nested and with-handle examples: 1px border divider and centered 4x24px rounded pill, live token colors/radius, visible 1px focus ring with transparent native hit targets.
- Typed pixel/percentage sizing, stable panel IDs, default/min/max, controlled and imperative layouts, collapse/expand restoration, disabled group/panel/handle, adjacent constraint propagation and dynamic panel insertion/removal. Explicit bounded-layout and infeasible-constraint policy.
- Keyboard arrows/Home/End/Enter, RTL physical drag and keyboard direction, semantics increase/decrease, mouse/touch cancellation and borrowed controller/focus lifecycle. No Form integration needed for layout geometry.
- Audit core and plugins; migrate pane persistence adapter and appropriate split handles without changing storage, temporary maximum behavior, responsive modes or async ownership; document retained domain controls.
- Self-contained production-widget styleguide and local fixture; focused interaction/migration tests, root/full static analysis, pinned SDK/locks, isolated uniquely identified signed macOS debug build. Native/reference comparison remains pending locked-desktop slot.

**decisions**

- See docs/component-library/resizable.md for primary source hashes, measurements, API/constraint and native adaptation decisions. Frozen page hash matches catalogue; Base Nova 1px divider + 4x24 pill, rounded-lg = 1x token radius.
- Public group/panel/handle plus typed explicit pixel/percentage sizes and controller; controlled/uncontrolled state, constraints/collapse, disabled panels, dynamic stable IDs, relative/pixel parent sizing. Native 48px coarse targets with in-bounds collapsed-edge semantics.
- App adapters reuse DResizableHandle.standalone; persistence/async races remain outside generic UI. No Form field or unmerged component dependency. Styleguide status is implemented after independent native acceptance.
- Independent reviewer accepted the unchanged source after official Base UI rendered comparison and native macOS inspection; no source correction or rebuild was required.

**migrations**

- ResizablePane: sidebar, diagnostics and topic inbox retain PanelWidthController/store behavior and responsive callers.
- Users Matrix column handles now UsersColumnResizeHandle using shared renderer; forum persistence, generation guards and pre-frame accumulation preserved.
- ChatThreadPaneDivider replaces duplicate thread split interactions; physical-right adapter and stored widths preserved. Actual Chat split expands touch hit overlap without changing panel space.

**retainedAlternatives**

- Composer and Chat drawer two-axis floating corner resize/movement are domain geometry, not panel groups. Calendar resize disabled. Scrollbars and seek/volume/timeline controls remain separate owners.

**verification**

- flutter pub get --enforce-lockfile at root and profiles/full passed; Flutter 3.47.2 and lockfiles unchanged.
- Final focused tests: d_resizable_test, styleguide/resizable_examples_test, resizable_pane_test, panel_width_controller_headless_test, users_page_test, chat_thread_workspace_test passed (88 tests), including radius-zero, coarse targets, RTL collapsed-edge drag and all migrations.
- Final root and full-profile flutter analyze --no-pub passed with no issues; touched Dart formatting and git diff --check passed. Four extracted self-contained usage programs passed Dart analysis.
- Isolated local-data native fixture built successfully from source 7ba6dd15a5134b195d8b9fb5fda6e457e8005eb0. Copied /tmp/discourse-resizable-review-c1fc/DiscourseResizableReview.app has unique name/ID/URL scheme; build app.dill and original/copied kernels share SHA256 564d2ae4fcee4c667fbd4aa80521d3454cef17195e76723758130b1398918b1b. Deep strict signature verification passed. See docs/component-library/resizable-native.md and evidence/resizable logs.
- Integrated pinned main e612ad7b; source 0629571a58e927f480c03de909bdfd4f676cdbd1. 180 focused tests and root/full analysis pass. Unique isolated bundle /tmp/discourse-resizable-integration-0629571a/ResizableIntegration.app; kernel 2ffa27d7519d1edc17b8d8da3f204814298a298c4ae4b3c5cb10b76526f46840. Explicit restricted-free ad-hoc entitlement readback equals signing plist, allow-jit=true; deep strict signature passes. See resizable-native.md and evidence/resizable/integration.
- Independent reviewer reran 90 focused component/styleguide/ResizablePane/Users/Chat tests and root/full-profile analysis after integrating current main; all passed.
- Approved browser/native review passed: official 384px Base UI horizontal, vertical, handle, nested and RTL renders were compared with the exact signed macOS fixture. Dark/light documentation canvases, RTL, 200% text, reduced motion and 360px preview remained usable. Keyboard resize, controlled collapse/expand/disabled state, and pointer commits on Users 160 to 228px, Chat 160 to 226px and pane 208 to 267px succeeded; native AX exposed independent named adjustable handles.

**limitations**

- No iOS/Linux device run or spoken VoiceOver verification was performed.
- Browser Geist and native host-font rasterization differ; the review establishes geometry, styling, interaction and semantics rather than pixel equality.

### popover

Status: merged. Task: 01a084fb-b319-7053-8265-8cdfd4e2c2bd. Branch: codex/ui-popover.

**acceptanceCriteria**

- Provide one public DPopover owner with DPopoverTrigger, DPopoverContent, DPopoverAnchor, DPopoverHeader, DPopoverTitle, DPopoverDescription and DPopoverClose composition, borrowed-or-owned DPopoverController lifecycle, uncontrolled defaultOpen and controlled open/onOpenChange behavior with explicit change reasons.
- Match frozen base-nova geometry at 100%: 288px default content width, 10px padding and gap, 4px default side offset, 10px (lg) host-relative radius, 14px/20px text with medium title and muted description, 1px foreground/10% exterior ring, medium shadow, and 100ms 95%-scale/fade/8px side-aware entrance; read live palette, font and radius tokens while open and eliminate motion when reduced motion is enabled.
- Support top/bottom/left/right/inline-start/inline-end sides; start/center/end alignment; side and alignment offsets; configurable collision boundary/padding and flip/shift/none policies; custom DPopoverAnchor geometry; continuous anchor tracking through layout/scroll; narrow constraints, large text and RTL logical positioning without overflow.
- Open from pointer or keyboard trigger activation, move focus into nested interactive content except touch opening, expose a named semantic container and independent nested controls, dismiss by trigger/close/Escape/outside press/lifecycle/anchor removal, restore the trigger or prior focus, and tolerate controlled callbacks or child removal during open/close without stale overlays or disposing borrowed focus/controller resources.
- Add self-contained actual-component styleguide examples and accurate snippets for Basic, all Align values, With Form composed with the merged DInput owner while retaining Field ownership, RTL physical/logical sides, controlled state/close, custom moving anchor, collision/scroll edge behavior, live theme, large text and reduced motion.
- Audit core and bundled-plugin anchored panels. Adopt only genuine rich non-menu popovers while preserving callback, persistence, permission, async and touch-sheet ownership; retain menus, Select, Combobox, Hover Card, navigation menus, dialogs and Tooltip under their specialized owners and record shared positioning follow-up.
- Pass touched formatting, focused interaction/accessibility/positioning/styleguide/downstream tests, root and full-profile locked dependency resolution and static analysis, and an isolated uniquely identified macOS debug fixture build mounting actual adopted production widgets; record exact source/kernel/signature evidence and keep status in_progress awaiting serialized reference/native inspection.

**decisions**

- Frozen documentation fetched byte-for-byte from https://ui.shadcn.com/docs/components/base/popover.md: SHA256 833273ce2ef2e83164a1824c0e6151452d4fc5f7d602c4871f9705bdef163587. Registry source https://ui.shadcn.com/r/styles/base-nova/popover.json: SHA256 ba5fe84f353f6c0fd2133a2ab893f5e8861fc60dc4dea548a7ec875acaa37b2c. Base UI API snapshot https://base-ui.com/react/components/popover.md: SHA256 e50617eaad64fbc205f0ff730bb60001f9152e319a24c4d08e9cdc154cc863bf.
- Public composition is DPopover root with builder-based DPopoverTrigger, styled DPopoverContent, optional DPopoverAnchor, header/title/description, builder-based DPopoverClose and a borrowed-or-owned DPopoverController. Builders keep DButton or another nested control as the sole semantic action instead of layering competing gesture/button nodes.
- Measured mapping is recorded in docs/component-library/popover.md: 288px width, 10px content gap/padding, 2px header gap, host-radius lg factor 1.0, 14/20 text, weight-500 title, muted description, foreground alpha multiplied by 10% for the 1px ring, Tailwind medium shadow, 4px side gap and 100ms 0.95-scale/fade/8px side slide. Open overlays read live DTokens and inherited text scaling; reduced motion finishes immediately.
- Base UI collision behavior maps to explicit side/align flip, shift and none policies inside a safe-area or caller Rect. A paint-transform tracker requests overlay layout only when the trigger/custom anchor moves or resizes; bounded content scrolls when collision space or accessible text makes it taller than the available side.
- Keyboard opening focuses the first nested control; touch opening focuses the popup scope to avoid summoning an editor. Escape, outside/trigger/close press, lifecycle loss, controller action and trigger removal dismiss safely and restore trigger/previous focus. The named explicit semantic container does not merge independently interactive descendants.
- Nested dismissal is layered: the latest open DPopover owns outside pointers, descendant MenuController scopes close before their parent, and outsidePress never schedules trigger restoration over the newly clicked focus owner. This preserves nested Popover/MenuAnchor composition and prevents one physical pointer from cascading through registered layers.
- Independent review corrected controlled lifecycle synchronization in 8281dda2: lifecycle loss reports its reason, hides without restoring focus into an inactive view, and reconciles a still-true controlled open value on resume.
- Native styleguide review found that an ancestor Escape shortcut could shadow the local DismissIntent. d9ecd110 makes the topmost Popover layer own Escape directly while retaining descendant-menu-first dismissal and trigger focus restoration.

**migrations**

- TopicInboxHeader plugin-property details now uses DPopover on pointer platforms, including Assign's real management surface. Live topic-store and plugin listenables, navigation-revision dismissal, plugin callbacks/permissions and compact/custom headers are preserved; iOS/Android retains the established touch sheet.

**retainedAlternatives**

- showAnchoredPicker category/tag/time-range/assignment pickers, ChoiceMenuAnchor, CommandMenuAnchor, MenuAnchor, PopupMenuButton, Select, Combobox, Hover Card, navigation menus, dialogs and Tooltip remain specialized owners for selection/command keyboard models, search/large lists, result futures, modal or hover behavior. Their shared collision needs are deferred until their catalogue owners exist.
- With Form now uses the merged DInput owner inside Flutter Form. Rich Field label/description/error layout remains with the separate in-progress Field owner; no substitute Field API was created.
- DNativeSelect remains the specialized plain-selection owner. After its accepted main merge, 6a608c56 verified a non-focused option outside the Popover bounds without dismissing the parent, followed by Native Select-first and Popover-second Escape dismissal.

**verification**

- Frozen page, base-nova registry and Base UI API fetches matched the recorded SHA256 values; docs/component-library/popover.md records CSS-to-Flutter geometry, typography, colors, radius, shadow, motion, state and native adaptations.
- flutter pub get --enforce-lockfile at root and profiles/full completed with Flutter 3.47.2; the incidental root dependency-classification rewrite was reverted and all pins/lockfiles are byte-unchanged.
- flutter analyze --no-pub at root and profiles/full passed with no issues. Touched Dart formatting and git diff --check passed.
- Final reconciled focused/downstream run passed 102 tests with seed 826145 across d_popover, Popover examples, the whole styleguide page, DButton adoption and the full TopicInbox file. The dedicated Popover suite covers 16 cases, including controlled lifecycle resynchronization, ancestor-shortcut Escape ownership, nested Popover/MenuAnchor, real DNativeSelect selection outside the parent rectangle, layered Escape, non-cascading pointers and outside-field focus retention.
- The three inherited Android compact-geometry failures originally reproduced at base commit 9d7a49e797dff14c908369315d035a1437d49c07; after the coordinator's pinned-main fixes were reconciled, the complete TopicInbox file passes in the final 102-test run.
- Official Base Nova Popover Basic was inspected live in light and dark documentation themes. The native mapping preserves the compact surface, title/description hierarchy, outline trigger, foreground ring and shadow; host font rasterization differs from the browser's Geist rendering.
- The final isolated macOS debug fixture at /private/tmp/discourse-popover-review-85d07f90/build/macos/Build/Products/Debug/Popover Review 85d07f90.app uses unique ID org.discourse.popover.review.85d07f90. Current Popover and TopicInboxHeader source hashes match the fixture; kernel SHA256 is cdb5be91cff62cf7e2822b1a3883b266a92a424312d09aa131efa4659283c3c5. Deep strict Apple-development signature verification passed with sandbox/JIT/network client+server/user-selected files/audio/camera entitlements.
- Native macOS inspection passed the actual TopicInboxHeader Details adoption: the named Local topic details container exposes independent description, text field and Save locally controls; pointer open, outside dismissal and Escape work. Final styleguide Basic visibly renders the expected compact surface and independent AX controls; Escape closes beneath the page-level shortcut and restores the trigger focus ring.

**limitations**

- No spoken VoiceOver session or iOS/Linux device inspection was performed.
- Browser Geist and native host-font rasterization differ; review establishes geometry, styling, interaction and accessibility structure rather than pixel equality.

### hover-card

Status: merged. Task: 01a085fd-5d84-7e40-bce5-c4ed49e7f2d8. Branch: codex/ui-hover-card.

**acceptanceCriteria**

- Export one generic DHoverCard owner with DHoverCardTrigger and DHoverCardContent composition, local/controlled state, borrowed-or-owned controller lifecycle, rapid peer-trigger handoff, opening/closing callbacks and explicit change reasons; generic code must contain no Discourse services, fetching, permissions or navigation.
- Match the frozen 8f30193c Hover Card Markdown and base-nova registry at 100% scale: 256px popup, 10px padding, 14px/20px text, host-relative lg radius, popover surface/foreground, foreground/10 ring, reference shadow, 4px side offset, 4px alignment offset and 100ms fade/95% scale/2px directional slide with reduced-motion support.
- Implement physical and logical sides, start/center/end alignment, offsets, collision flipping/shifting, viewport and safe-area bounds, live anchor tracking, narrow/200% text/RTL behavior, and live light/dark/custom token/font/radius updates while the overlay is open.
- Implement the Base UI preview-card interaction model: 600ms/300ms defaults plus per-trigger delays, pointer travel across the trigger/content gap without flicker, rapid trigger handoff and timer cancellation, keyboard-focus opening without moving focus into the preview, Escape ownership/closure, blur/outside closure and safe removal/disable/controller replacement/disposal behavior.
- Keep the trigger's real link/button action and semantics as the only accessible interface. The supplementary popup must not become a modal focus trap, Tooltip replacement or touch-only destination, while visible text selection, scrolling and pointer hover retention remain usable and any focusable popup descendants are excluded from traversal and assistive semantics.
- Reproduce runnable Basic, Composition, Trigger Delays, Positioning, all physical Sides and Arabic RTL physical/logical-side examples with real Button and Avatar owners, truthful code snippets and interaction/native-adaptation notes.
- Audit current core and bundled-plugin user/topic/link/reaction hover surfaces. Migrate suitable visual destination previews through application adapters while preserving original click/touch routing and fetch/cache/permission ownership, and record interactive pickers/essential-content panels as deliberate retained alternatives.
- Add focused regression coverage for timers, trigger-to-content pointer travel, multiple-trigger races, focus/Escape and semantics, controlled/controller lifecycle, disposal/disable, positioning/collision/RTL/live theme, styleguide registration and each actual migration; format and analyze touched code plus root and profiles/full, then prepare exact-source browser/native fixtures and hand remaining acceptance and local-main merge to a new independent reviewer task.

**decisions**

- Created from current local main after accepted Popover, with source preparation in its own worktree and direct handoff to a new independent reviewer. Required final parent and example-owner acceptance remains mandatory.
- Implementation handed directly to verified independent task Review and merge Hover Card (01a08619-dc41-7213-a887-5afb891b99da), which owns remaining fixes, first actual browser/native acceptance, final current-main reconciliation and local merge. Source commit c03c39b5 and metadata tip 4d0a7058 are verified local objects; no native inspection is claimed at handoff.
- The frozen Hover Card Markdown was downloaded again and its SHA-256 exactly matches 8f30193c745aaf270cdf63043ca452cdffb895e8643a86c662ca0804c6022dc8. hover-card.md records the official base-nova registry and Base UI Preview Card behavior source with a measurement-by-measurement Flutter mapping.
- DHoverCard composes a real DHoverCardTrigger and DHoverCardContent, supports local or controlled state, borrowed/owned DHoverCardController lifecycle, explicit open/close reasons and completion callbacks, and keeps every Discourse service/model/navigation dependency outside generic code.
- The visual owner uses the accepted DPopoverSide/DPopoverAlign/DPopoverCollision public positioning vocabulary while leaving Popover source and its accepted lifecycle/Escape/layering corrections unchanged. Hover Card independently owns its non-modal focus, hover timer and assistive-visibility contract.
- Base UI's accessibility guidance is preserved: the action trigger remains the only accessible and keyboard/touch navigable interface; the supplementary surface never takes focus and is excluded from assistive semantics. It remains pointer-hoverable, scrollable and text-selectable for sighted mouse users.
- Default 600ms open/300ms close timers are per-trigger configurable. Polygonal trigger-to-content bridge retention, content entry, rapid peer-trigger cancellation, disable, lifecycle, outside press, topmost Escape, trigger activation and disposal all cancel the appropriate pending work.
- Eight accepted styleguide examples reproduce frozen Basic, Composition, Trigger Delays, Positioning, all physical Sides and Arabic RTL physical/logical sides, plus strongly typed multiple-trigger payloads and controlled/controller lifecycle. Real merged Button and Avatar owners are used.
- The review handoff supplied a non-resolving long SHA c03c39b5b5d2dc549e5c016e098ec404bc8cf20d. The clean codex/ui-hover-card branch and its own progress evidence identify the actual implementation commit as c03c39b5bf037e33dd84e86db6216ee3b7febaa9; review preserves that exact history.
- Independent review fixed duplicate immediate-animation completion callbacks, deferred overlay mutations during controller/focus ownership changes, retained the polygonal pointer bridge until the pointer truly leaves it, and paints the reference ring outside rather than consuming surface size.
- DHoverCardGroup<T> and DHoverCardGroupItem<T> cover Base UI's shared-root multiple-trigger, payload and controlled-trigger-id API with arbitrary Flutter trigger layouts and rapid same-root handoff. Detached imperative ownership remains available through DHoverCardController; DOM-only detached viewport animation is not applicable to this Flutter owner.
- The production UserCardTarget adapter schedules a missing-cache load through its existing ShellController after build and remains safe when signed-in account replacement unmounts an open preview. Generic Hover Card code still owns no networking, cache, permissions or navigation.

**migrations**

- UserCardTarget now composes DHoverCard around its unchanged InlineAction. Hover or traditional keyboard focus loads the existing ShellController user-card cache and renders a read-only app adapter with DAvatar/AvatarImage, name, username, title and location; click, touch, Enter and Space still open the full user-card route.
- InlineAction now accepts a borrowed FocusNode so the generic Hover Card owner can observe the existing action's true focus without adding a duplicate semantic or focus target.

**retainedAlternatives**

- HoverPanel remains for reaction pickers and liker/reactor panels because those surfaces contain essential focusable selection/actions and touch-sheet adaptation, which conflict with Base UI's supplementary non-navigable Preview Card contract.
- The full user-card dialog remains the click/touch destination because it owns plugin actions, cooked links, retry behavior, routing and focus. Composer, chat and topic previews are persistent inline content rather than hover-triggered destination previews; Tooltip remains for concise labels and shortcuts.
- No separate generic topic/link preview fetch cache currently exists. Networking or a second cache was not added to the reusable component.

**verification**

- Implementation evidence: flutter pub get --enforce-lockfile completed at root and profiles/full using existing pins; no lockfile changes remain.
- Implementation evidence: root and profiles/full flutter analyze --no-pub passed with no issues; touched Dart formatting and git diff --check passed.
- Implementation evidence: a focused Hover Card/styleguide/UserCard run passed 27 tests, and a broader run including the complete styleguide_page_test.dart passed 42 tests.
- Implementation evidence: flutter build macos --debug --no-pub -t tool/hover_card_review_main.dart succeeded; build success is not native inspection.
- Independent review: root and profiles/full flutter pub get --enforce-lockfile and flutter analyze --no-pub passed; touched formatting and git diff --check passed.
- Independent review: 54 focused Hover Card, styleguide and production UserCard tests passed with randomized seed 3337741303, including timers, pointer bridge, focus/Escape, semantics exclusion, controlled/controller lifecycle, duplicate callback regression, peer roots, typed payload handoff, collision/RTL, 216px width at 200%, loading/error and account replacement.
- Independent browser inspection completed against https://ui.shadcn.com/docs/components/base/hover-card: rendered Basic, physical side and Arabic logical-side surfaces matched the frozen source's content, size, spacing, ring/shadow and placement behavior.
- Independent native inspection completed in the exact-source signed macOS fixture at /private/tmp/hover-card-review-7204.JR8WST/Hover Card Review 7204.app: Basic, collision flipping, RTL, typed payload handoff, controlled triggerHover reporting, controller open, keyboard focus/Escape, ready/loading/error user cards, activation/dismissal, dark/custom palettes, 200% text and the eight-section full styleguide all passed.
- Exact-source fixture evidence: source 7204dd2d2895a332b01a14dafbfcb796127336b7; copied kernel SHA-256 69650cc5717b0c86c151c367cd1f004e7a8f3d8ba12e619898777267f42588be; component SHA-256 ce0128a9b09a2475990cdb92cd6a7a92eaac66d17f9435b4e552c2c058201005; strict deep codesign verification passed with only local debug runtime entitlements.

**limitations**

- No spoken VoiceOver session or iOS/Linux device inspection was performed.

### dialog

Status: merged. Task: 01a084fb-b319-7053-8265-8cb4db577932. Branch: codex/ui-dialog.

**acceptanceCriteria**

- Provide one public generic Dialog owner exported from discourse_ui.dart with typed DDialogController<T>, DDialog/DDialogTrigger/DDialogContent/DDialogHeader/DDialogTitle/DDialogDescription/DDialogFooter/DDialogClose composition and a showDDialog<T> helper that uses the nearest Navigator by default.
- Match the frozen base-nova registry at 100% scale: black/10 blurred backdrop, full-width popup capped at 384px with 16px viewport margins, 16px grid gaps and padding, xl radius, foreground/10 one-pixel exterior ring, popover surface, 16px medium/leading-none title, 14px muted description, 8px header/footer gaps, muted/50 bordered footer, and a 28px ghost X close control at logical top/end 8px.
- Support uncontrolled and externally controlled open state, typed close results, trigger/close reasons, custom or omitted corner close controls, footer close composition, custom initial/final focus, focus trap/restoration, Escape and barrier dismissal policies, programmatic close, route/widget removal, nested Navigators/dialogs, and live inherited theme/direction/text-scale/reduced-motion changes while open.
- Keep background content modal/inert and expose a correctly labeled dialog route and independent close/actions to assistive technology; preserve keyboard Tab/Shift-Tab traversal, mouse/touch activation, 48px invisible touch affordances where needed, logical RTL placement, and focus visibility without merging editable field semantics with surrounding controls.
- Provide constrained and scrollable layouts that avoid keyboard/view-inset obstruction and overflow at 320px width and 200% text, including documented default profile form, Custom Close Button, No Close Button, Sticky Footer, Scrollable Content and Arabic RTL examples; compose the merged Input owner while keeping Field with its separate catalogue owner.
- Define explicit async-submit ownership so completion, failure, double activation and disposal cannot close or mutate the wrong dialog; retain caller-owned validation, errors, permissions, persistence and routing behavior in application adapters.
- Audit ordinary modal dialogs in core and bundled plugins and migrate appropriate usages to DDialog while preserving callbacks, async/lifecycle behavior and accessibility; record Alert Dialog, Sheet, Drawer, Popover, native system dialogs and specialized media/composer surfaces as narrowly retained alternatives rather than conflating their owners.
- Format and analyze touched code, run focused component/styleguide/downstream migration tests and affected profile checks, build a uniquely identified isolated macOS local-data fixture that mounts actual changed production dialogs, and after coordinator slot approval compare the reference and native styleguide/migrated fixtures in light/dark/custom palettes, narrow/large-text/RTL/reduced-motion states with source, kernel and strict permitted-signature evidence.

**decisions**

- Frozen shadcn Base UI Dialog Markdown, generated base-nova registry and upstream abstract owner are recorded with SHA-256 hashes and commit provenance in dialog.md; CSS pixels map one-to-one to Flutter logical pixels at 100% scale.
- DDialog<T> provides controlled or uncontrolled declarative ownership; DDialogController<T> provides borrowed imperative ownership and coalesced typed submit futures. A submission is bound to one attachment and one open session, so late completion, disposal or reopening cannot mutate the wrong dialog.
- A route-owned configuration notifier keeps content, barrier/Escape policy, label and initial focus current while open. Replaced controllers detach immediately; obscured parent closure removes its own route instead of popping a typed child route.
- showDDialog<T> defers its builder into a route-descendant context and bridges live caller-scoped Theme, MediaQuery and Directionality updates while retaining caller-owned Form state.
- The native surface uses shared DButton and DInput owners, live DTokens, exact 16px custom X artwork, closed-loop focus traversal, logical placement, modal semantics, SafeArea/view-inset handling and reduced-motion behavior.
- Seven actual styleguide examples cover default profile editing, custom/no close controls, sticky and scrollable layouts, RTL and controlled/typed results without implementing the separately owned Field primitive.
- Independent rendered review measured the current base-nova icon-sm close surface at 28px rather than the source task's provisional 32px criterion. The default corner close now uses DButtonSize.small without an inset surface, preserving the 16px artwork, logical 8px inset and larger invisible touch affordance.

**migrations**

- Chat channel details now uses showDDialog<void>/DDialogContent while preserving validation, error/loading state, disabled barrier dismissal, metadata diffing and its original async controller callback.
- Voice room create/edit now uses typed showDDialog<VoiceRoomDraft> while preserving fields, switches, required-name validation, cancellation, latest-controller resolution and caller-owned persistence.

**retainedAlternatives**

- Destructive confirmations and adaptive Cupertino alerts remain Alert Dialog; sheets, drawers, popovers, pickers, media/full-screen routes and native system dialogs keep their distinct catalogue or platform owners.
- App Settings remains a large navigation workspace; composer and vendored WebRTC examples retain their specialized or third-party lifecycle contracts.

**verification**

- Root and profiles/full flutter analyze --no-pub pass; touched Dart is formatted and git diff --check is clean.
- Final randomized Dialog/styleguide/Chat/Voice run passes all 393 tests with seed 4147437372. The 22 focused Dialog/example checks pass with seed 4094924130, including typed nested routes, controller replacement, current content/dismissal policy, open-session submit ownership, disposal, live helper scope and retained Form state.
- Isolated flutter build macos --debug --no-pub -t lib/dialog_native_fixture.dart and unique DialogNativeReview Xcode scheme build pass from final source b75bee83e15f75692e8391502e5640124f83b9ed.
- The implementation-prepared unlaunched bundle /private/tmp/discourse-native-dialog.qNoMNI/build/DialogNativeReviewDerived/Build/Products/Debug/Dialog Native Review.app has identifier org.discourse.native.styleguide.dialog; six production source files byte-match the implementation worktree and its d_dialog.dart SHA-256 is 05993f5cb8c3e388e8ab7d5bd7a2b8260862eeef24e3c769d53a6675e34438db.
- The implementation-prepared bundle kernel SHA-256 is cce09d0ea6b8e0139c0ce9f7698efaa826896280f51df75d22afa3a79486528b. Ad-hoc codesign --verify --deep --strict passes; entitlements contain only sandbox, JIT, audio/camera, user-selected read/write and network client/server, with no APS, application identifier or team identifier.
- Independent review after the 28px close correction: 23 randomized Dialog/styleguide tests passed with seed 2145466268; root analysis passed with no diagnostics. The full profile analysis passed, and focused real Chat and Voice migration checks passed 2 + 2 tests.
- Official rendered base-nova comparison covered light and dark default Dialog, Arabic RTL and Scrollable Content. Measured default geometry was 384x305, 16px padding/gap, 14px radius, 16px/16px weight-500 title, 14px/20px description, 384x65 footer with 16px padding and 8px gaps, and a 28x28 close surface at logical top/end 8px. RTL moved the close to logical start and mirrored actions; the scroll example kept its header visible over a 50vh body.
- Final isolated native fixture /private/tmp/discourse-native-dialog.qNoMNI/build/macos/Build/Products/Debug/Dialog Native Review.app mounts the real Chat and Voice editors plus the actual component styleguide. Reviewed Dialog source SHA-256 is f438edbbc8b0484044389d3df603bf09212ee40ad680628af930557563b80b5e; final fixture kernel SHA-256 is 662c83fdf2d391f64f8e5a34d14324bb5e6bf417c64d158fb810b0fb546a580c. Strict ad-hoc signature verification passed with the previously recorded permitted entitlements.
- Native CUA inspection covered real Chat field editing and cancellation; real Voice edit/create in Plum, RTL and 200% text with independently scrollable bodies and sticky actions; disabled/enabled save validation; reduced-motion opening; Escape dismissal; closed-loop forward Tab focus; and default, Scrollable Content and Arabic RTL styleguide examples. The 28px close remained an independent Close button and moved to logical start in RTL. The isolated app was quit and the desktop lease released.
- Latest-main candidate verification after preserving merged Collapsible, Popover, Table, Tabs and Native Select plus current dependent-task metadata: all 23 randomized Dialog/styleguide tests passed with seed 2165732119, and root flutter analyze --no-pub passed with no diagnostics.
- Accepted candidate 1b1e9e1e merged into local main with merge commit 6a0aaa54d86aaa492681f5cc4dcd32b5e2feefe3.

**limitations**

- No physical iOS/Linux execution or VoiceOver speech session was performed. macOS AX inspection and widget semantics checks cover the route label and independent fields/actions, but do not substitute for device assistive-technology testing.
- Rich Field composition remains with its separate catalogue owner; Dialog composes the merged DInput where applicable. Native font shaping and antialiasing differ from browser rendering, so no automated pixel-identical cross-renderer claim is made.

### alert-dialog

Status: in_progress. Task: 01a085d9-7909-7fd0-b1b8-30914ac699b4. Branch: codex/ui-alert-dialog.

**acceptanceCriteria**

- Reproduce the frozen Alert Dialog full anatomy/API and Basic, Small, Media, Small with Media, Destructive and RTL examples with primary-source mapping.
- Implement actual alert-specific confirmation, cancellation/dismissal, focus/lifecycle, typed results and async behavior through the shared Dialog owner; inspect reference alert semantics rather than inheriting ordinary Dialog defaults blindly.
- Migrate appropriate core/plugin confirmations while preserving permission/busy guards and business state; support live themes, native accessibility, keyboard/touch, narrow/scaled/RTL and reduced motion.
- Run meaningful focused component/migration checks and root/full analysis, prepare exact-source fixtures, then create a new reviewer for required rendered/native acceptance, final compositions, fixes and local main merge.

**decisions**

- Implementation task created from latest local main with the tested parent source pinned for isolated preparation. It must create its own independent review/merge task; parent acceptance and all required examples remain mandatory.

### sheet

Status: in_progress. Task: 01a08606-5dcc-7381-bbbb-719367c8f574. Branch: codex/ui-sheet.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Sheet complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Sheet (01a0862f-b27f-76d2-a441-8a77594aedc8) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### drawer

Status: in_progress. Task: 01a08606-5dd1-75a2-9dbb-a652188d7bd5. Branch: codex/ui-drawer.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Drawer complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Drawer (01a08643-3074-72e1-8b18-a2266dd724e6) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### select

Status: merged. Task: 01a085bb-1d11-7f52-a7bd-667348469087. Branch: codex/ui-select.

**acceptanceCriteria**

- Match frozen Base Nova Select geometry and state artwork: 32/28px trigger, 14/20px type, directional 10/8px padding, 16px chevron/check, input border, proportional lg/md radii, transparent/light and multiplicative dark input tint, exterior 3px focus/invalid rings, 144px popup minimum, 4px offset, 28px pointer rows and 100ms motion.
- Provide typed value/item/group/separator composition, null placeholder/clearable values, custom value/trigger/icon/indicator builders, controlled nullable and uncontrolled ownership, object equality, disabled/read-only/required/invalid states, Form validation/save/reset and a multiple-selection counterpart.
- Use DPopover and DScrollArea as overlay/scroll owners; implement selected-row alignment with mouse/keyboard plus touch/edge/insufficient-space fallback, collision boundaries, large-list initial reveal, scroll arrows, outside/Escape dismissal, deepest-layer behavior, focus restoration and live overlay themes.
- Support pointer/touch, compact 48px transparent touch targets, hover/press/focus, disabled-option skipping, looped arrows/Home/End/Tab containment, keyboard typeahead, stable actionable option semantics, scaling, narrow widths, RTL and reduced motion without state reset.
- Replace the shell DropdownButton renderer with the public ui/components owner, preserve current core/plugin callback/form/permission behavior through the compatibility adapter until accepted Native Select integration reclassifies plain consumers, and retain DNativeSelect only for genuine native/simple selection.
- Add exhaustive real-component styleguide examples for default composition, selected alignment toggle, groups/separator, scrolling, disabled, invalid/Form, RTL, multiple/custom composition and app edge cases; run focused component/consumer tests, root and full-profile analysis and exact-source build evidence before reviewer handoff.

**decisions**

- Frozen Select Markdown SHA256 fc566bd829748e1caec337728e3198a951599be1c4c96f132e20d62266e2d0a9 verified on 2026-09-09; Base Nova registry SHA256 425e9b0a28b72617f18fabd75384050113295b88e7ba01c35bede2c72bd5d476 inspected with the full Base UI API.
- DSelect is the single rich rendering owner and Flutter FormField; DSelect.controlled represents controlled null explicitly, the default constructor owns initialValue, and DMultiSelect maps Base UI multiple mode. Borrowed FocusNode, DPopoverController and ScrollController remain caller-owned.
- The optional DPopoverPlacementResolver receives read-only target/boundary/content geometry and returns a candidate that remains subject to Popover boundary correction. Select alone decides touch and selected-row fallback; no overlay lifecycle is duplicated.
- Accepted Popover main merge dc6ab75fe99f2af8b401bae60285fdbe65e8012a is reconciled, retaining lifecycle correction 8281dda2, DNativeSelect layering regression 6a608c56 and topmost Escape ownership d9ecd110.
- Accepted Field remains a metadata/layout owner around Select; DSelect stays the sole Form/value/validation/focus/action owner. Button Group's internal joined-edge scope is downstream and will adapt the trigger in its own accepted composition without moving the popup into joined geometry.

**migrations**

- Reduced lib/src/shell/select.dart to a compatibility export and moved DSelect/DSelectField rendering to lib/src/ui/components/d_select.dart; discourse_ui and discourse_plugin_sdk export the new owner.
- Preserved accepted DNativeSelect across plain/simple Preferences, Poll, Local Dates, Chat, Assign, Voice, Bookmark, Invite, Group and status consumers; rich DSelect remains the public owner for composed selection, grouping, selected alignment, typeahead and multiple selection.

**retainedAlternatives**

- DSelectField remains a source-compatibility FormField adapter only; it translates DropdownMenuItem/InputDecoration into DSelect entries and does not retain the old DropdownButton renderer.
- Accepted DNativeSelect remains the owner for plain/simple platform-adapted selection. Searchable, date and other purpose-built pickers retain their distinct owners.

**verification**

- Independent review fixed controlled-open focusability, disabled selected fallback, repeated-letter typeahead, selected-row positioning, large-text sizing, initial scroll-arrow action, disabled hover, invalid semantics and trigger state artwork; review commits f930b2d7 and 7d474def preserve source history.
- flutter test --no-pub test/d_popover_test.dart test/d_select_test.dart --test-randomize-ordering-seed=391447 passed all 38 tests, including custom placement geometry/boundary correction and live theme inheritance while open.
- flutter test --no-pub test/preferences_page_test.dart test/assignment_sheet_test.dart test/voice_room_view_test.dart test/topic_inbox_test.dart --test-randomize-ordering-seed=391447 passed all 168 downstream tests. Earlier Select/native-consumer and accepted-Popover integration runs passed 122 and 106 tests respectively with the same seed.
- Root and profiles/full flutter analyze --no-pub passed with no diagnostics after the final Popover/Select corrections; git diff --check passed.
- Exact reviewed source rebuilt as /private/tmp/select-review-56d8.VCyNHv/source/build/macos/Build/Products/Debug/Select Review 56d8.app with bundle org.discourse.select.review.56d8. DSelect, DPopover, examples and fixture hashes match the review branch; restricted debug entitlements read back correctly, strict deep signature passed, CDHash d9d20849ecee43fcbea8badef0e8dd312dfa57be and TeamIdentifier is not set.
- Official ui.shadcn.com Base Select was inspected in light/dark for default, selected-item alignment, groups, scrollable, disabled, invalid and RTL surfaces. The isolated macOS fixture was inspected for pointer selection, keyboard typeahead/End/Tab/Escape and focus restoration, selected-row reveal, scroll arrows, disabled trigger/item, invalid Form state, actionable group/option semantics, multiple selection remaining open, light/dark/Forest/Plum palettes, RTL, 216px width, 200% text and reduced motion.

**limitations**

- Native device inspection was macOS only. Spoken VoiceOver output and iOS/Linux devices were not exercised; macOS Accessibility API roles, values and actions were inspected and widget regressions cover semantics and platform-independent behavior.
- Live theme replacement while the popup stays open is covered by a widget regression because clicking the external fixture theme control normally dismisses a modal popup before activating it.
- The Mac locked only during cleanup after all required captures; the reference tab was closed and the exact isolated app process was then terminated by PID before merge preparation.

### native-select

Status: merged. Task: 01a083f3-9a01-7c71-9931-3674b85e81b3. Branch: codex/ui-native-select.

**acceptanceCriteria**

- Port base-nova closed-control geometry (32/28px, 14/20px text, directional 10/32px padding, 16px chevron), token palette/radius, disabled opacity, invalid and keyboard focus rings.
- Provide typed text options and disabled optgroups, placeholder, controlled and initial selection, Form save/reset/validation, borrowed focus lifecycle and accessible names.
- Use Flutter MenuAnchor/MenuItemButton as selection/popup owner (coordinator correction: open overlays must update live), document exact platform adaptation distinct from custom rich Select; cover keyboard, touch, dismissal, scrolling, large text, RTL and theme changes.
- Self-contained actual-component styleguide covers reference simple/groups/disabled/invalid/RTL plus form and state; audit core/plugins and migrate suitable simple selectors preserving callbacks and permission/busy guards.
- Pass focused interaction/migration tests, touched format and root/full-profile analysis with unchanged pins/lockfiles; build isolated identifiable macOS local-data fixture with source/kernel/signature evidence.
- Remain in_progress awaiting_slot until coordinator grants desktop and reference/native production-fixture review passes.
- Provide typed-character prefix navigation and repeated-letter cycling; finish the concrete whole-app plain-selector audit rather than deferring eligible selectors to Select.

**decisions**

- Typed DNativeSelectOption/OptGroup, single DNativeSelect FormField adapter and Flutter MenuAnchor/MenuItemButton owner; no rich custom Select dependency.
- Default content width measures widest text plus 44px including borders and a scaled em for grouped options; apps use isExpanded. 32/28px heights, input token/multiplicative alpha, proportional radii, exterior-only focus ring and exact Lucide chevron documented with hashed sources.
- Controlled Form callbacks/validation/reset always see accepted props synchronously; uncontrolled defaults freeze at mount. Nonnullable app choices disable the placeholder and retain initial reset values.
- Live menu palette/direction/text scale without dismissal; immediate transitions; type-ahead supports prefix and repeated-character cycling with disabled/headings skipped and no timers.
- Expired/blurred/reset type-ahead sessions restart from current accepted selection; repeated-letter proposals can cycle while a controlled parent declines.

**migrations**

- 28 plain selector owners across Preferences, Group management, Bookmarks, Invites, Status editor, Chat, Assign, Poll, Local Dates and Voice. Full per-owner callback/permission audit in native-select.md.
- Preserved Voice _heldDevice fallback, Custom expiry cancellation, legacy Assign status, nullable Default order and controlled async preference/filter changes.

**retainedAlternatives**

- Topic-move category selector retains icons/colors/hierarchy for rich Select; searchable/multi-choice/action/date pickers keep their distinct capabilities.
- Existing DSelect baseline source/export and documentation chrome remain per coordinator ownership; no simple app callers remain on DSelect.

**verification**

- Flutter 3.47.2 and pins/lockfiles unchanged; enforced root/full-profile pub resolution passed.
- 323 selected component, fixture, styleguide and production migration tests passed; routed Chat notification integration test also passed.
- Root and profiles/full flutter analyze --no-pub passed; touched dart format and git diff --check passed.
- Isolated uniquely identified macOS fixture built and ad-hoc signature verified; four matching kernel hashes and exact source provenance recorded in native-select-build.md. No launch.
- 2026-09-09 correction: 155 impact tests and 2 manual font-loaded render tests passed. Official light/dark/disabled/invalid/focus/groups/RTL/narrow browser capture compared with registered examples; production fixture renders captured in both app themes. See native-select-review.md and reference/native-select-review/manifest.json.
- Corrected source d2e500f95d25f9901f74b37d0784aeb1e1ebf071 rebuilt into the unique ad-hoc verified review app; all four kernels match 47fabe4db51b73135427cc6ab941765ad04b53c4433693b36b29babf03691efc.
- Integrated pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7; final shared component implementations and all other progress rows preserved. 327 integration tests passed initially; sole obsolete 100px post-action test fixture resized to120px for final touch targets, all24 bookmark tests then passed. Root/full analysis clean.
- Merge-queue bundle rebuilt from f9baeaa86c2bd88058ab815687543587aeec5296 with matching four-kernel hash bb7dca4c9c8906921f677cc834ff2b2bbe1990f4e29009a3b8144cedf1de8a37; restricted-free debug entitlements verified by signed read-back and strict deep signature.
- Independent macOS review inspected the exact fixture and real Preferences route across light/dark, grouped scrolling, invalid, narrow RTL at 200% text, Form state, and accessibility. The first pass found popup choices exposed as static text; c58487c650c7ecb01f5ffe04ec35ddaf103189af adds bounded actionable choice semantics and a regression.
- A second native pass confirmed AX choice actions and keyboard selection, then found Escape was not reliably dismissed by the native event path. 3512489c explicitly owns Escape while the select menu is open; the focused component suite passes and the final exact bundle confirmed dismissal with focus restoration.
- Final exact bundle /tmp/native-select-review-escape-4d1e.2aGZte/Native Select Review Escape 4d1e.app has matching source/build/copied kernel SHA-256 962a99807d014c8b839aa00512c5c0afe50f2243476c2de6e23920c5829fa4f5, matching restricted entitlement read-back, and a passing strict deep signature.
- Independent verification passed 180 focused component/styleguide/fixture/migration tests before the Escape-only correction, the 12-test component suite afterward, and a randomized 67-test component/styleguide/fixture/Preferences/Bookmark/Local Dates integration run after current-main reconciliation (seed 660499389). Root plus profiles/full flutter analyze --no-pub are clean.

**limitations**

- Native device inspection was macOS only. Spoken VoiceOver output and iOS/Linux devices were not exercised; macOS Accessibility API roles/actions were inspected directly and are covered by widget regressions.
- The open popup is intentionally Flutter-owned, so neither the font-loaded browser comparison nor native inspection claims OS-popup parity.

### field

Status: merged. Task: 01a084bf-dd8a-7c13-86dd-63d635b7bf97. Branch: codex/ui-field.

**acceptanceCriteria**

- Capture and hash frozen Field Markdown (1afe174f74b982ec86fad520dab464a16bfe289c2d54fde88241ce3a791112ee), official base-nova registry and reference examples; document measured CSS geometry, typography, states and native adaptations.
- Export a single generic DFieldSet/Legend/Group/Field/Content/Label/Title/Description/Separator/Error owner with vertical, horizontal and 448px container-responsive layout, both legend variants, nested/choice groups, rich content, error deduplication and no competing Form state.
- Provide explicit native control-label-description-error association and label activation without duplicate tab stops; verify validation semantics, Form save/reset, disabled handling, borrowed focus lifecycle and state retention across layout changes.
- Match choice cards: 10px padding plus 1px border, proportional lg radius, selected primary border/background with multiplicative alpha, disabled opacity, hover and outside-only 3px keyboard focus ring.
- Cover every frozen reference composition in self-contained actual Field examples and reconcile the accepted Button/Input/Textarea/Checkbox/Radio/Switch/Slider/Native Select owners without duplicating their state or semantics.
- Audit core and all bundled plugins, migrate surrounding composition without taking Input/Textarea/Alert ownership, record precise overlaps and retained alternatives, and verify changed production behavior.
- Format touched code; pass root/full-profile analysis and meaningful Field/styleguide/downstream tests with pins unchanged. Prepare and inspect an isolated uniquely identified macOS debug styleguide/production fixture with source equality and kernel/signature evidence.

**decisions**

- Primary source hashes and measured geometry/API/semantics/native mapping are recorded in docs/component-library/field.md and reference/field/.
- DField is the single layout/metadata owner and never a second Form, value, validation, focus or action owner. DFieldControl wraps exactly one otherwise-unlabelled native/custom control; completed DInput, DTextarea, DCheckbox, DRadioGroup, DSwitch/DSwitchTile, DSlider/DMultiSlider and DNativeSelect retain their public ownership.
- Choice cards use an outside-only 3px focus ring and live multiplicative selected alpha. Disabled opacity covers the complete choice surface, including border and background, while pointer/focus guards keep it inert.
- Nine actual-component examples use the accepted control owners. The responsive custom-error example deliberately retains one native FormField/TextField because DInput has no custom error builder.
- Downstream Input Group composes DField/DFieldLabel/DFieldDescription around DInputGroup while DInputGroupInput remains the sole Form/value/validation/focus owner. Select composes Field metadata around DSelect without taking its Form/value/focus owner. Toggle Group and Button Group use Field layout/metadata without DFieldControl around multiple independent controls.

**migrations**

- Preferences _PreferenceCard uses DFieldGroup with spacing:0 to retain adapter-owned gaps; device-timezone help uses DFieldDescription. Saving, restoration, permissions and notice owners unchanged.
- Voice editor retains the accepted Dialog owner and direct DInput, DTextarea, DSwitchTile and DNativeSelect control owners. showVoiceRoomEditor keeps controller lifetimes, required-name guard, draft conversion and latest-controller save behavior.
- Field examples were reconciled with accepted Input, Textarea, Checkbox, Radio Group, Switch, Slider, Native Select and Button owners; generated runnable sources were refreshed when example bodies changed.

**retainedAlternatives**

- Alert owns inline status/error notices and Empty owns page-scale states. Domain composite editors retain their existing value and interaction owners.
- The responsive DFieldError demonstration retains one native FormField/TextField because DInput does not expose a custom error builder; it does not introduce a second state owner.

**verification**

- Independent source reconciliation fixed complete disabled choice-surface opacity and replaced temporary Switch, range Slider, Textarea and native selection examples with accepted DSwitchTile, DMultiSlider, DTextarea and DNativeSelect owners. Public-owner regressions cover single toggle activation, per-thumb slider semantics, multiline label/focus/setText, native selection and whole-surface disabled opacity.
- flutter test --no-pub test/styleguide/field_examples_test.dart test/ui/d_field_test.dart test/voice_room_view_test.dart --test-randomize-ordering-seed=random: 88 passed on inspected source (seed 3512437341) and again after preparing the latest-main candidate (seed 690915376).
- flutter test --no-pub test/preferences_page_test.dart --test-randomize-ordering-seed=random --reporter expanded: 22 passed, seed 2423156486.
- Root flutter analyze --no-pub passed with no issues (7.8s). profiles/full flutter pub get --enforce-lockfile followed by flutter analyze --no-pub passed with no issues (1.6s). git diff --check passed and lockfile pins remained unchanged.
- Fresh detached source 4efec6cc built with flutter build macos --debug --no-pub -t tool/field_review_main.dart. Exact bundle /private/tmp/field-review-ready-4efec6cc.em0DBs/Field Review 4EFEC6.app uses identifier org.discourse.field.review4efec6 and scheme discourse-field-review4efec6.
- 3362/3366 tracked entries match source blobs; only four documented runner identity/signing files differ. Original/copied kernel SHA256 17c143b2e45abd69da86715ad941ad1df77b8446f446ad694c3cfd06b8e81cbe. Deep strict signature and exact seven-key ad-hoc entitlement read-back passed; no embedded profile or team/developer/application identifiers.
- Approved browser inspection covered the official Field page in light/dark and confirmed all documented compositions, 448px group breakpoint, spacing, choice geometry/typography/state and responsive row behavior.
- Exact macOS bundle inspection covered light/dark, LTR/RTL, 100%/200%, pointer selection, disabled choice inertness/full-surface opacity, invalid submission, responsive reflow, the actual Field styleguide, real Preferences Native Select/Switch and real Voice DInput/DTextarea/DSwitchTile/DNativeSelect ownership.

**limitations**

- Native inspection was macOS only; iOS/Linux devices and spoken VoiceOver output were not run. Widget tests cover keyboard and accessibility roles/actions.
- CUA could validate empty submission visually, but its direct set-value proxy did not update the Flutter TextEditingController for a manual successful-submit observation; Form save/reset and valid submission remain covered by widget tests.
- The responsive custom-error example intentionally uses one native FormField/TextField because DInput has no custom error builder.

### input-group

Status: merged. Task: 01a085af-d606-7281-ac25-34c83adc855e. Branch: codex/ui-input-group.

**acceptanceCriteria**

- Reproduce the frozen Base UI/base-nova Input Group documented composition, addon alignments, icon/text/button/Kbd/Dropdown/Spinner/Textarea/custom-input/RTL examples and complete public API; record source hashes and visual/behavior mapping.
- Compose final shared DInput, DTextarea, DButton, DKbd and DSpinner owners with unified surfaces, precise focus/error geometry, independent addon actions, bounded native editor semantics and preserved controller/Form/focus/IME lifecycle.
- Support live host palettes/font/radius, keyboard and touch, narrow/scaled/RTL layouts and reduced motion; demonstrate every documented state and required final-owner composition.
- Audit and migrate appropriate core/plugin compound fields and existing prototype compositions, preserving domain behavior; coordinate Empty, Field and Button Group directly and document retained alternatives.
- Run meaningful focused component/consumer tests and root/full-profile analysis, prepare source-exact production fixtures, then create a new reviewer to complete official browser/native acceptance and local main merge. Every prepared dependency must first be accepted and merged in main.

**decisions**

- Source preparation overlapped Textarea review using pinned committed source; final review reconciled the accepted Textarea parent from main before acceptance.
- DInputGroup owns only the joined exterior surface and focus/invalid/disabled state. DInputGroupInput and DInputGroupTextarea retain native editing, selection, IME, controller, Form and focus ownership; addons and nested buttons retain independent actions and semantics.
- FocusNode listeners repaint the exterior ring and are removed on replacement/disposal. Group-disabled state dims and excludes composed editors from interaction/focus. The mobile 48px wrapper focuses the editor from outer touch bands without stealing descendant button actions.
- Grouped DInput and DTextarea suppress their standalone label/helper/error/counter blocks. Accepted DField metadata surrounds the group without DFieldControl wrapping multiple independent controls.
- The accepted Dropdown Menu/Popover composition uses the menu trigger's own focus node and external expanded semantics; opening or selecting a menu item does not replace the editable control or its value ownership.
- Independent reviewer 01a085d3-1acf-7361-9dc8-fc4a99de7c45 accepted the implementation source 30078b3bf4e4eac96411c19c3bc16b2732ceff59 after source fixes, final-owner reconciliation, official browser/native inspection and the complete affected verification matrix.

**migrations**

- Chat global search, channel message search and thread message search compose public DInputGroup while preserving their controllers, keys, focus, clear actions, keyboard behavior and navigation state.
- Spinner's Input Group example now composes public DInputGroup and preserves its documented validation/loading surface.
- Empty's functional search example now composes DField metadata and public DInputGroup while preserving Form validation, save, submission, reset and local state.

**retainedAlternatives**

- Multiline/rich composers, domain-specific selection controls and standalone DInput/DTextarea fields remain with their specialized owners; Input Group does not absorb their lifecycle or presentation.

**verification**

- Official frozen-reference browser review passed in light/dark themes for all nine actual styleguide examples; exact-bundle native macOS review passed styleguide/default/alignment/buttons/Form/RTL/360px and 200% scaling plus all three Chat search migrations. Evidence is recorded in docs/component-library/evidence/input-group/native-review.md and native-preparation.json.
- Final affected matrix passed 290 tests: flutter test --no-pub test/d_input_group_test.dart test/styleguide/input_group_examples_test.dart test/styleguide/spinner_examples_test.dart test/styleguide/empty_examples_test.dart test/d_input_test.dart test/d_textarea_test.dart test/styleguide/input_examples_test.dart test/styleguide/textarea_examples_test.dart test/ui/d_field_test.dart test/d_dropdown_menu_test.dart test/styleguide/dropdown_menu_examples_test.dart test/d_popover_test.dart test/chat_navigation_test.dart test/chat_shell_integration_test.dart --test-randomize-ordering-seed=314159265.
- Accepted Input API and Chat reconciliation passed 210 tests with randomization seed 42424242; Field/Empty reconciliation and focused Dropdown composition tests also passed independently.
- flutter analyze --no-pub passed; profiles/full flutter analyze --no-pub passed; git diff --check passed.

**limitations**

- Native inspection was performed on macOS; physical iOS/Android devices, Linux and spoken VoiceOver output were not run. Widget tests cover touch targets, keyboard/focus, semantics, RTL and narrow/200% layouts.
- No automated pixel-diff baseline was produced; geometry and state comparisons were inspected against the frozen official browser reference.

### button-group

Status: in_progress. Task: 01a08581-831f-7751-b714-096b5aebf86a. Branch: codex/ui-button-group.

**acceptanceCriteria**

- Match the complete frozen Button Group, Separator and Text API and every orientation, size, nested, split, control composition and RTL example with measured shadcn geometry and behavior.
- Preserve independent control interaction and semantics, joined edges and exterior state rings, live themes, native targets, scaling and nested overlay appearance without leaking broad theme overrides.
- Audit/migrate suitable core/plugin action groups; preserve domain callbacks and distinguish grouped actions from tabs or group selection.
- Verify focused component/consumer regressions and root/full analysis; create an independent reviewer to finish remaining real-owner compositions, rendered/native acceptance and local main merge.

**decisions**

- Button and Separator dependencies are merged.
- Field, Input Group, Dropdown Menu, Select and Popover compositions must reconcile with their final owners; track outstanding compositions and coordinate directly, without duplicating components or reducing the frozen examples.
- DButtonGroup is a passive semantic/layout boundary for independent controls. It owns no selection, roving focus or toolbar shortcuts; each child retains its callback, state, focus and native role.
- A narrowly scoped DJoinedControlScope is installed per direct child. DButton and DInput consume only joined-edge geometry; nested groups replace the scope and overlays receive no broad Theme or radius override.
- DButtonGroupExpanded is the explicit finite-width Flutter flex adaptation for the reference input:flex-1 selector. The styleguide remains baseline until the reviewer replaces four dependency-aware fixtures with final owning components.
- Independent reviewer 01a085f4-2a6b-7c82-9dc3-c9b14d76b355 owns remaining review, fixes, required final compositions, rendered/native acceptance and the final local main merge directly. The implementation handoff 97554adac80cf4a702408966add2702f3bc313e0 is source evidence, not acceptance.

**migrations**

- ContentNavigationControls now uses a labeled DButtonGroup for Back, Forward and Refresh while preserving keys, shortcuts, enabled guards, refresh lifecycle and shell callbacks.

**retainedAlternatives**

- Forum/preferences/topic tab rows remain navigation or selection controls, not independent Button Groups.
- Radio, checkbox, switch and toggle rows retain their selection owners; Button Group does not absorb Toggle Group semantics.
- Dialog/sheet action rows retain spaced or wrapping presentation because joining cancel and destructive confirmation changes narrow modal behavior.
- Inline-video alternative link actions remain wrapping links, and composer controls remain overflow-aware toolbars pending their dedicated component owners.

**verification**

- Frozen Markdown downloaded and SHA-256 verified exactly as 9118d89c3e715a7e77ec0454be6a276c24d114c8b3099505bb463487e9545eda. Base registry source and all twelve linked Base examples were inspected; source mapping and concrete acceptance criteria are recorded in docs/component-library/button-group-reference.md.
- Before current-main integration, 109 randomized focused Button Group, Button, Input, Separator, styleguide and production navigation tests passed (seed 3806760654); after merging main 27ddc513, 33 direct component/styleguide/consumer tests passed (random seed recorded in /private/tmp/button-group-post-main-tests.log).
- Root flutter analyze --no-pub and profiles/full flutter analyze --no-pub passed before and after current-main integration with no issues. dart format covered lib/test and git diff --check passed.
- flutter build macos --debug --no-pub succeeded at build/macos/Build/Products/Debug/Discourse.app. This is build/kernel evidence only; the app was not launched and no browser/native/VoiceOver inspection is claimed.
- Created the persisted reviewer task `Review and merge Button Group` (`01a0859e-170c-7821-b0fd-9ff24a9bfaac`) in isolated worktree `/Users/joffreyjaffeux/.codex/worktrees/bgrp/discourse-native` on `codex/review-button-group`; it owns dependency reconciliation, remaining rendered/native review, fixes, verification and the final local-main merge.

**limitations**

- The styleguide has complete accounted sections, but Input Group, library Dropdown Menu, rich Select and Popover use explicitly labeled local handoff fixtures because those final owners are still pending or in review. Native Select is not substituted. The new Button Group reviewer owns coordinating their final replacements.
- No shared desktop lease was available during source implementation. Official rendered-page comparison, native macOS interaction/visual inspection, VoiceOver, iOS and Linux device checks remain for the new reviewer.
- DInput joined-edge painting was source- and widget-tested after replacing its uniform BoxDecoration with an equivalent animated custom decoration, but requires rendered pixel comparison in final review.

### command

Status: merged. Task: 01a085bc-5eda-7712-9863-190bf6846bcc. Branch: codex/ui-command.

**acceptanceCriteria**

- Match the frozen Command/cmdk wrapper API and embedded/Dialog Composition, Basic, Shortcuts, Groups, Scrollable and RTL examples with primary-source visual and behavioral mapping.
- Compose final DInput, DScrollArea, DKbd and Dialog owners with explicit query/filter/selection/focus ownership, native IME and accessible keyboard navigation, dynamic results, disabled/group/empty/loading behavior and no networking/business logic in the generic component.
- Audit and migrate appropriate core/plugin command/search/action pickers while preserving app adapters, permissions, async lifecycle and result actions; record specific retained alternatives and prepare the API for later Combobox composition.
- Verify complete examples, live overlay themes, focus entry/restoration/Escape, narrow/scaled/RTL/touch/reduced-motion behavior, meaningful focused tests and root/full analysis; create a new reviewer for actual rendered/native acceptance and final local merge after accepted Dialog main.

**decisions**

- Frozen Markdown SHA256 was reverified as 1a810090b9cc629efe885d8795365280c2653fdf3e0f5d20f4ac2354b876a4b6. Official rendered HTML, base-nova registry source and cmdk API were inspected; complete geometry/API mapping is recorded in command.md.
- DCommand<T> owns controlled or local query/highlight state, scored filtering, keyboard navigation and activation. DCommandInput and DCommandList separately own or borrow native editing/focus and scroll resources; generic code has no application networking or business state.
- The public composition covers root, input, list, empty, loading, group, item, separator, shortcut and Dialog. Flutter cannot inspect arbitrary child text, so searchValue defaults to value.toString() and is explicit when presentation differs.
- Arrow and Ctrl-N/J/P/K navigation use a visual active-descendant highlight while retaining native editable focus/selection/composing state. Return activates; optional looping, pointer-highlight opt-out and reduced-motion scroll behavior map cmdk.
- Base-nova geometry maps to 4px root/group padding, 32px input and desktop rows, 8px row insets/gaps, 12px headings, 288px list cap, token surface/radius/color roles and 48px touch rows on iOS/Android.
- CommandDialog composes prepared DDialog rather than duplicating modal lifecycle. Backward-compatible DDialogContent contentPadding/verticalPadding/spacing options preserve current defaults and enable the official edge-to-edge Command composition.
- Prepare against the recorded tested parent source while final review continues; independent reviewer 01a085d3-21b9-75d0-a4f0-c739439ccb9d owns acceptance, required rendered/native verification and local merge only after accepted Dialog main integration.
- Independent reviewer 01a085d3-21b9-75d0-a4f0-c739439ccb9d owns remaining review, fixes, required final compositions, rendered/native acceptance and the final local main merge directly. The implementation handoff f3180d998bd901ce24c2f21e386d5b08f78afbd5 is source evidence, not acceptance.
- Accepted Dialog landed on main as 6a0aaa54. The reviewer reconciled Command from that accepted parent and retained only additive DDialogContent spacing parameters plus a post-frame route-notifier correction verified by the combined Dialog/Command suite.
- Official Command shortcuts are unboxed trailing text rather than keycaps. DCommandShortcut therefore preserves the rendered reference and accepts any Widget so callers may compose DKbd/DShortcutKeycaps when an application intentionally wants keycap presentation; the generic owner does not duplicate DKbd styling.

**migrations**

- lib/src/shell/command_menu.dart retains CommandMenuAnchor/showCommandMenu anchoring, transparent route barrier, result and app callback ownership while replacing its private Material MenuItemButton rows with the public DCommand/DCommandList/group/item/separator owner. Topic/group core actions and Chat add actions inherit the migration without moving permissions, stale-result checks or async/domain callbacks.
- Registered five actual-component styleguide examples covering embedded Composition, Basic Dialog, Shortcuts/Groups, custom filter/loading/dynamic results, Scrollable and Arabic RTL. Added tool/command_review_main.dart with all examples plus the actual production CommandMenuAnchor adapter using local data.

**retainedAlternatives**

- anchored_picker.dart remains a selected-value picker/combobox owner; the later Combobox task composes the accepted Command API.
- choice_menu.dart and DSelect retain finite choice/form semantics. Composer autocomplete, emoji/GIF pickers and global topic/Chat search retain domain networking, token replacement, pagination or navigation ownership; they are not generic command-menu renderers.

**verification**

- Root and profiles/full flutter pub get --enforce-lockfile passed from committed dependencies with no lockfile or pin changes; Flutter 3.47.2 remains unchanged.
- After current-main reconciliation, root and profiles/full flutter analyze --no-pub passed with no diagnostics; touched formatting and git diff --check passed.
- 32 randomized Command component, narrow 200% RTL styleguide and real group-member adapter tests passed with seed 1561896842. The affected topic action hover/cursor/anchored-viewport test passed independently.
- Focused coverage includes keyword/empty filtering, custom score ordering, filtering opt-out, controlled callbacks, native IME-composing preservation during keyboard activation, disabled suppression, loading/dynamic rendering, borrowed lifetimes, RTL, Dialog Escape/restoration and retained application result ownership.
- Source preparation began at main 6fbecbce, integrated exact prepared Dialog 8a800783 only locally at 778539e2, committed component source at c73c39b8, reconciled current main at 072bbee3 and added the source-only native fixture at e91927bf. Reviewer merged that exact history into codex/review-command at 92800e83.
- Independent review fixes persist imperative query/highlight state, retire disabled or removed dynamic highlights, suppress invalid Return activation, avoid compounded disabled opacity, expose checked/editor/custom-label semantics, support numpad Return, keep selected shortcuts readable, announce empty results and preserve live Dialog inherited-state updates. Pointer/touch and accessibility regressions were added.
- After latest-main and accepted Dialog reconciliation, 86 randomized Command, Dialog, DInput, styleguide and production-adapter tests passed with seed 927417; the affected topic hover/viewport test also passed independently. Root and profiles/full flutter analyze --no-pub passed with no diagnostics.
- The official rendered page was inspected in light and dark across embedded, Basic, Shortcuts, Groups, Scrollable and Arabic RTL examples. It confirmed the compact 384px surface, 32px rows/input, grouped separators, 288px scrolling viewport, disabled 50% treatment and plain trailing shortcut text.
- Native CUA inspected the exact isolated f0ae622b source bundle in light and Plum dark themes. Literal AZERTY-safe entry filtered to Billing, Return activated it, unmatched text announced No results found, loading changed to Privacy/Security/Devices, pointer actions updated state, and the real CommandMenuAnchor adapter returned close.
- The native dialog retained the focused editor, dismissed with Escape, and stayed open across live palette/radius/font/RTL/200%/reduced-motion changes. At 200% RTL the result list scrolled without overflow and 15 Arrow Down movements kept View action 4 visible. RTL logical placement and disabled/checked states rendered correctly.
- The unique bundle used identifier org.discourse.command-review.f0ae622b, display name Command Review f0ae622b and URL scheme discourse-command-review-f0ae622b. codesign --verify --deep --strict passed with only allow-jit, allow-unsigned-executable-memory and disable-library-validation entitlements. DCommand source SHA256 was 29a101237c7ef04b916e9bf6ecb3a796aca567acdf3402d3d3fec18546b3322e; fixture SHA256 adf7e5d040a0dc037c0ce3f46c3329ef900569d486fb98e1da64c6703c7cd7b3; built/copied pre-sign kernel SHA256 2788c6c952471cd70b1079f2f533bc3adf5e2db5a6049cfb2c94d531cf5f0c2a.
- Independent reviewer merged the accepted Command candidate into local main as 090d4f5448c2d8f87183d62092c6a5393ce90bd6 without pushing.

**limitations**

- No spoken VoiceOver session or iOS/Linux device run is claimed. macOS AX exposed named editors, result groups, enabled/disabled buttons, checked result content and live status text; touch-target/activation behavior is covered by widget tests rather than a touch device.
- Native CUA Arrow navigation and Return activation were visible. Its Ctrl-N/P injection produced no visible signal on the AZERTY host, so Ctrl-N/J/P/K and native IME-composing preservation are claimed only from focused widget tests, not from the native CUA pass.
- The full topic_reading_integration_test run showed unrelated/order-sensitive failures when run concurrently with other files; the only changed topic action test passes independently. The full suite is not required.

### combobox

Status: in_progress. Task: 01a085fd-5d83-79c3-b598-bd49a5152023. Branch: codex/ui-combobox.

**acceptanceCriteria**

- Implement the frozen Base UI Combobox complete autocomplete/chips/collection API and Simple, chips, groups, custom items, multiple selection, clear, invalid, disabled, auto highlight, Popup, Input Group and RTL examples with primary-source mapping.
- Provide typed selection/query/filter/highlight ownership, editable focus/IME, dynamic/disabled results, chip navigation/deletion, keyboard selection, anchored scrolling/collision, dismissal/restoration and safe lifecycle; preserve domain querying/network state in adapters.
- Use accepted shared popup/input owners and reconcile Command/Field/Input Group/Item APIs where the actual Base UI semantics fit; retain every required example and prevent prepared parents reaching main before acceptance.
- Migrate appropriate core/plugin searchable selectors and multi-value fields, preserving permissions, asynchronous results and callbacks; verify focused component/consumer regressions and root/full analysis with live themes and native/scaled/RTL behavior.
- Create a new independent reviewer for remaining official rendered/native acceptance, fixes, required compositions and final local main merge.

**decisions**

- Created from current local main after accepted Popover, with source preparation in its own worktree and direct handoff to a new independent reviewer. Required final parent and example-owner acceptance remains mandatory.
- Verified independent reviewer Review and merge Combobox (01a08628-7889-7dd2-a93c-c854fcdf1e9a) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### dropdown-menu

Status: merged. Task: 01a085b3-05fc-79f1-bde2-dc6936b2bcd4. Branch: codex/ui-dropdown-menu.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Dropdown Menu API and Composition, Basic, Submenu, Shortcuts, Icons, Checkbox/Radio variants, Destructive, Avatar, Complex and RTL examples with recorded primary-source visual/behavior mapping.
- Preserve full native menu focus entry, roving/typeahead/Home/End navigation, selection and nested submenu behavior, deepest Escape, trigger restoration, outside pointer dismissal, positioning/scrolling and overlay lifecycle through the final shared owners.
- Support live host palette/font/radius, disabled/destructive/checked states, keyboard/touch semantics, narrow/scaled/RTL layouts and reduced motion; provide every documented interactive example.
- Audit and migrate appropriate core/plugin popup actions and temporary Table/Item/Button Group/Input Group compositions, preserving callbacks, permissions, async ownership and accepted keyboard regression behavior.
- Pass focused component/consumer tests and root/full-profile analysis; create a new reviewer for all remaining official browser/native acceptance, dependency composition and final local main merge. The accepted Popover main revision is a required final merge gate.

**decisions**

- Implemented DDropdownMenu on the exact tested Popover review pin so menu overlays share Popover placement, collision, lifecycle, outside dismissal, reduced-motion and trigger-focus behavior instead of adding a native MenuAnchor owner.
- Recorded the verified frozen Markdown SHA256 3a8ab9398fa074c3cdf023e31bc9368a3b6bafb0b0f146a326eb2c76808ba7fa and observed base-nova registry SHA256 335c59dba30145f434a9cc9ccb0438a3c5e2afe857fc11b029de1ecb415224d7 with measured mapping in docs/component-library/dropdown-menu.md.
- Checkbox and radio items default to closeOnSelect false for repeated local editing; ordinary actions default to closing the full menu chain.
- Submenus compose nested DDropdownMenu instances with one active sibling owner, shared close-all scope, inline-end placement, RTL mirrored chevron/directional keys and submenu-local Escape handling.
- Independent reviewer 01a085cf-f401-7813-80da-7c687de8a5d5 owns remaining review, fixes, required final compositions, rendered/native acceptance and the final local main merge directly. The implementation handoff 48599440787a16d27c00d1b399d021f385113be5 is source evidence, not acceptance.

**migrations**

- Added the public Dropdown Menu API export in package:discourse_native/discourse_ui.dart and registered all thirteen frozen interactive styleguide examples.
- Migrated TableActionsExample from temporary DButton + native MenuAnchor/MenuItemButton to DButton + DDropdownMenu, preserving local edit/duplicate/delete behavior, expanded row highlighting, 32px trigger geometry and trigger focus restoration.

**retainedAlternatives**

- Generic ChoiceMenuAnchor/CommandMenuAnchor, category/tag/search adapters and rich chat/action menus remain specialized because they own search, async busy state, permissions, rich domain rows or additional keyboard behavior; docs/component-library/dropdown-menu.md records the audit rather than claiming these are migrated.
- Independent review inspected the available diagnostics, bookmarks, emoji, Events, Voice and composer fixtures. Their remaining PopupMenuButton call sites preserve multi-select state, per-row async identity, rich previews, callback snapshots, permissions or platform-owned editor behavior and remain explicit adapter follow-ups; third-party package examples are outside the product owner.
- Public icon slots accept caller widgets. Styleguide outline icons demonstrate the exact 16px slot geometry; production app icon vocabulary remains caller-owned while the internal check indicator is component-owned.

**verification**

- Frozen Markdown was downloaded and reproduced the required SHA256 exactly; official page, registry source and Base UI behavior API were inspected and mapped.
- Focused coverage proves pointer/Return/Space open and first enabled focus, arrow/Home/End traversal, repeating typeahead, controlled checkbox/radio retention, deepest Escape, RTL submenu arrows, sibling submenu non-overlap, outside focus behavior, controlled open requests, live theme/text scale, desktop/iOS geometry, semantics and Table edit/duplicate/delete focus/action regressions.
- After reconciling the accepted Popover implementation from current main, 48 Dropdown Menu, Popover, styleguide and Table tests passed with seed 826145, including overlay lifecycle, custom-anchor tracking and ancestor-shortcut Escape precedence.
- The exact 05d9f78f review candidate passed clean root and profiles/full static analysis, a debug macOS styleguide build, deep strict code signing and a copied-kernel SHA256 match of a6ee5d5cd0bb1142547fdc3045276559fd19afac0aadf9d52a61f1e5fc489e8e.
- Official Base Nova rendered comparison covered dark and light Composition geometry, states, separators, shortcuts and submenu affordance. Native macOS interaction covered Return/Space entry, arrows, End, typeahead, checkbox/radio retained-open selection, nested deepest Escape, trigger restoration, outside dismissal and app-switch lifecycle dismissal.
- Native styleguide inspection covered light, Forest and Plum palettes, 200% text with bounded scrolling, 360 px layout, reduced motion and RTL Arabic content with mirrored submenu affordance. The Table Actions adoption performed Edit and Duplicate callbacks with row mutation, status feedback, expanded-row highlighting and restored trigger focus; Delete remains covered by the focused consumer test.

**limitations**

- No iOS/Linux device, spoken VoiceOver session or pixel-identical screenshot claim is made; those platforms remain covered by widget behavior and geometry tests rather than this macOS acceptance pass.

### context-menu

Status: in_progress. Task: 01a08606-5dce-7b91-9ee6-7713872f1fa7. Branch: codex/ui-context-menu.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Context Menu complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Context Menu (01a0861f-38ca-7122-b18f-5f286ab90ccb) owns fixes, accepted Dropdown Menu reconciliation, first required rendered/native acceptance and final local main merge. Source d1c954fe and handoff e9b29538 are verified local commits; implementation is not accepted by this handoff.

### menubar

Status: in_progress. Task: 01a08606-5dd4-7b80-b330-d7ebfff967f9. Branch: codex/ui-menubar.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Menubar complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Menubar (01a08628-7042-7173-a37d-7f1f04eade66) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### navigation-menu

Status: in_progress. Task: 01a08606-5dd7-73d2-b6f5-15b1bfbc34e7. Branch: codex/ui-navigation-menu.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Navigation Menu complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Navigation Menu (01a08621-0e86-7a62-82b9-6a8eca71227f) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### breadcrumb

Status: in_progress. Task: 01a08606-c290-7772-8b90-e5358efa6752. Branch: codex/ui-breadcrumb.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Breadcrumb complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Breadcrumb (01a08623-9d6e-7393-b3e8-fb4c402b8c71) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.
- Reviewer preserved the finalized cd9c542d implementation history, added a source-exact local-data TopicListView fixture, and completed Breadcrumb's first official browser and native macOS comparison. Final acceptance remains gated on Dropdown Menu's accepted local-main merge.

**migrations**

- topic_list_view.dart: the real topic-row parent-category to category path uses DBreadcrumb composition while preserving LinkTarget navigation, rich badges, controller callbacks, labels and dense-row ellipsis behavior.

**verification**

- Reviewer measured the live Base UI light/dark and RTL examples: 14/20 text, 6px list gap, 4px item gap, 14px separators, 20px ellipsis and 28px collapsed trigger; the temporary reference tab was closed.
- Reviewer launched an isolated macOS fixture and inspected Light, Dark, Forest, Plum, pointer/keyboard callbacks, visible focus, RTL, 240px/200% text, reduced motion, wrapping/scrolling, native AX boundaries, Dropdown/Collapsed focus/navigation/typeahead/selection/Escape/restoration/outside dismissal. No VoiceOver/iOS/Linux claim.
- A source-exact offline DiscourseApp/TopicListView fixture exposed both production category links in native AX, kept the long path bounded and confirmed parent/child callbacks navigate to the correct local feeds.
- 48 Breadcrumb/Dropdown/styleguide tests passed with seed826145; both focused topic-row regressions passed; root and profiles/full analysis are clean.

**limitations**

- Dropdown Menu remains unaccepted. Breadcrumb's successful approved native inspections preceded the parent reviewer's latest 2026-09-09 12:53 UTC locked-Mac denial and therefore do not supersede it. Dropdown correctly did not merge. Acceptance remains pending a manual unlock and parent-owned resume; Breadcrumb will not carry the unaccepted source into main.

### pagination

Status: in_progress. Task: 01a08606-c9d5-7741-bfe0-e4ff531ff9b7. Branch: codex/ui-pagination.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Pagination complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Pagination (01a08629-4841-73d0-a5a6-c723f253b4b0) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### calendar

Status: in_progress. Task: 01a085fd-5d83-79c3-b598-bd3ffc5b366e. Branch: codex/ui-calendar.

**acceptanceCriteria**

- Use the existing kalender package pinned to 0.29.1 as the Calendar engine; theme its supported styles/components/builders with shared styleguide colors, typography, spacing, radii and state treatments, including existing EventCalendar and TopicCalendar app surfaces. Preserve kalender navigation/event layout and app domain behavior; Date Picker composes this same Kalender-backed Calendar API.
- Match the frozen Base UI/base-nova Calendar API and every Basic, Range, month/year selector, Presets, date/time, booked dates, custom cell size, week numbers and RTL example; account explicitly for timezone and alternate-calendar guidance with exact primary-source mapping.
- Provide typed date/selection/display ownership and correct date boundaries, disabled/hidden/outside/booked states, localization and keyboard navigation/focus; keep civil-day, instant/timezone and application scheduling semantics explicit.
- Compose shared final selection, Field and Input Group owners for required examples; preserve compact shadcn geometry, live host tokens, native accessibility, touch, narrow/scaled/RTL layouts and reduced motion.
- Audit core/plugin calendar and date surfaces, migrate appropriate uses while preserving server/domain state, and verify meaningful boundary/selection/focus/adoption regressions plus root/full analysis.
- Prepare exact-source fixtures and create an independent reviewer that owns all remaining reference/native acceptance, final compositions and local main merge after parent acceptance.

**decisions**

- Created from current local main after accepted Popover, with source preparation in its own worktree and direct handoff to a new independent reviewer. Required final parent and example-owner acceptance remains mandatory.
- Explicit user direction on 2026-09-09 requires kalender and visual consistency with the rest of the styleguide. Calendar owner acknowledged that its uncommitted custom engine will be removed, retaining only shadcn-specific state models, styling/builders and adapters around kalender. The new requirement must be carried into the independent review handoff.
- Verified independent reviewer Review and merge Calendar (01a08631-7574-70b0-a98f-4e7217e03209) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### date-picker

Status: in_progress. Task: 01a08606-ca30-7bc1-8e27-69575273d443. Branch: codex/ui-date-picker.

**acceptanceCriteria**

- Compose the user-required Kalender-backed Calendar; verify an actual committed tested API from its owner before dependent integration. A baseline branch commit is not implementation readiness, and a handwritten competing engine is not permitted.
- Match the frozen Base UI/base-nova Date Picker complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.

### carousel

Status: merged. Task: 01a08567-ac29-7dd0-ba78-16f423c97dd9. Branch: codex/ui-carousel.

**acceptanceCriteria**

- Reproduce every frozen documented variant, behavior and composition with official source/geometry mapping and live host palette/font/radius integration.
- Implement complete generic native APIs, state/controller lifecycle, keyboard/focus/semantics, touch, RTL, scaling, narrow layouts and reduced motion; every exposed feature must work.
- Add all interactive styleguide examples and accurate usage; audit/migrate appropriate core and plugin usages with real application behavior preserved and retained alternatives documented.
- Run meaningful focused component/consumer checks and root/full-profile analysis, prepare exact source/native evidence, then create a new independent reviewer task to finish acceptance and local main merge.

**decisions**

- Button is the implementation dependency and is merged; Card composition is also merged. Frozen sections include Sizes, Spacing, Orientation, Options, API, Events, Plugins and RTL. Reproduce complete documented behavior and native API counterparts, including responsive slide extents/spacing, horizontal/vertical and direction-aware navigation, previous/next enabled states, scrolling/selection events and controller lifecycle, options, and the demonstrated autoplay plugin behavior with correct interaction/reduced-motion/disposal handling. Inspect official Embla-linked behavior to define the actual supported native contract; no inert options or ornamental plugin API. Audit shell/composer_image_gallery.dart, shell/lightbox.dart, other media/page-view owners and plugins for appropriate adoption. Preserve zoom/pan, media lifecycle, keyboard navigation, accessibility and domain state; record retained grids or specialized viewers rather than converting inappropriate surfaces simply to add a usage. Provide real migrated local-data fixtures and all documented Card compositions.
- Implementation uses the direct reviewer workflow; root is not an approval gate.
- Frozen Markdown hash 98fdaa46f982b7ebf29b3c18f5e848f478244a766a0270f9c520f5e2eaf2fd59 was reproduced; base-nova registry response hash is 14737a7cf92048df9de47f9d1a9527d6d3beafba12115f52a3c353134ee2b50b. Exact geometry and behavior mapping is in carousel-reference.md.
- DCarousel exposes only faithful native options: horizontal/vertical orientation, start/center snap alignment, bounded/loop navigation, fractional/responsive extents and spacing. DOM watch/free-drag options are not accepted as inert values.
- Borrowed DCarouselController and plugins are detached but not disposed; internally created controllers and ownedPlugins are disposed by DCarousel. DCarouselAutoplay implements timing, play/stop/reset, interaction stopping, optional hover pause, focus pause and reduced-motion suppression.
- Reference navigation reserves a real 48px outer hit-test inset around the viewport because Flutter children painted outside parent bounds cannot receive pointer input; navigationInsets:false is explicit for composed tracks without reference controls.

**migrations**

- ImageGridCarousel now composes DCarousel for its real production page track, swipe, selection, looping and axis-key handling while preserving ImageGridTile media rendering, gallery callbacks, dot/counter controls and topic-scroll isolation.

**retainedAlternatives**

- LightboxGallery retains its specialized PageView because every page owns PhotoView zoom/pan/scale controllers, resize bounds, download state, keyboard chrome and media lifecycle; generic carousel composition would compete for gestures and duplicate ownership.
- Composer image-gallery code retains markup editing and its grid/carousel mode selector because it edits post markup rather than rendering a carousel.
- Event calendar paging is retained because it owns unbounded domain-date navigation and post-layout state publication, not finite carousel content; no plugin PageView was an appropriate adoption.

**verification**

- 10 Carousel widget tests passed with randomized seed 940219: controller/API state, bounded and adjacent loop navigation, touch and mouse drag progress/events, responsive extents without state reset, horizontal RTL and vertical keyboard input, slide semantics, serialized autoplay interaction/reduced-motion behavior, and borrowed lifecycle.
- 33 ImageGrid production-widget tests passed with randomized seed 940219, including pointer/keyboard/dot navigation, looping, edited-item clamping, outer-topic scroll isolation, accessibility, narrow layout and gallery opening.
- 17 styleguide access/page tests passed with randomized seed 940219; Carousel registration preserves frozen catalogue accounting and documentation shell behavior.
- Root flutter analyze --no-pub clean. profiles/full locked dependency resolution and flutter analyze --no-pub clean. Flutter 3.47.2, dependency pins and lockfiles unchanged.
- flutter build macos --debug --no-pub -t lib/styleguide_main.dart succeeded and produced build/macos/Build/Products/Debug/Discourse.app.
- Touched Dart formatting and git diff --check passed. Implementation integrated current main before handoff.
- Independent browser review reproduced both official hashes and inspected the live dark default: 320px viewport, 336px item including 16px gutter, and 28px circular controls at the documented 48px outside offset.
- Independent native macOS review used the exact-source isolated Carousel Review 2d5354ca app (kernel SHA256 ce5acb89990f8acd5c1b7bec62fdd5062266048ed936f9514d1440198143482f; deep strict signature passed). It covered light/dark/Forest, 360px, 200% text, RTL/reduced-motion settings, horizontal/vertical drag and keys, bounded/loop controls, autoplay play/stop and accessibility semantics; focused widget tests cover controller events, interaction pause and reduced-motion suppression.
- The production ImageGridCarousel fixture mounted three real local ImageGridItem records and passed native next/selection inspection without network or account writes. Full evidence is recorded in carousel-native.md.
- Reviewer fixes are covered by 10 Carousel and 33 ImageGrid tests with seed 940219; 17 styleguide tests and root/profiles-full analysis passed on the integrated review branch.

**limitations**

- No physical iOS/Linux device run or spoken VoiceOver session; widget semantics coverage is not a device claim.
- The production native fixture used deterministic local media metadata and did not open an authenticated gallery or network session. Browser/native font rasterization differs, so no pixel-equality claim is made.

### toast

Status: merged. Task: 01a0857a-fcd6-7880-90c0-501e72f034df. Branch: codex/ui-toast.

**acceptanceCriteria**

- Implement a scoped DToaster, DToastController and reusable typed content/action API matching the frozen base-nova Toast/Sonner appearance, including default, success, info, warning, error and loading treatments.
- Support controlled add/update/upsert/close/close-all and owned/borrowed lifecycle, deterministic promise loading/success/error transitions, stable repeated ids, limits, pause/resume, timeouts and close reasons without late completion leaks.
- Support safe-area-aware six-position placement, stacking, swipe dismissal, close/action controls, F6 focus entry, Escape dismissal, visible focus, live regions, touch/pointer input, reduced motion, RTL, narrow layouts and large text.
- Mount one live-theme root app scope and nested local styleguide scopes; provide interactive examples for Basic, Types, Action, Promise, custom content, stacking/limits/dismissal, positions and theme/direction/scale changes.
- Audit all core and bundled plugin transient notifications, migrate appropriate SnackBar/ScaffoldMessenger sites while preserving callback, permission, async and navigation ownership, and retain permanent inline statuses for Alert/Field/Empty with specific reasons.
- Pass formatting, focused manager/widget/styleguide/consumer regression tests and root/full-profile analysis; provide exact source/build evidence and leave rendered browser/native acceptance to the direct reviewer if the shared desktop lease remains occupied.

**decisions**

- Frozen Markdown hash e1dd1c08ccb082e6ca90fe352e09242cbf81132e37e05db889c67c8e601e1174 reverified. Inspected base-nova toast registry source hash 161ed77c409fe7345ee6308f7cf66f7bcf2717d8d5e1a8b36a7f8e8fa0df745e and supporting Sonner registry hash 831967f80f645ac3908b356a44748698a9ceed1c6a51b232dd5e87c52a54d7c3; mapping is recorded in toast.md.
- DToaster is a local inherited manager plus renderer, not a Material SnackBar wrapper. An omitted controller is owned/disposed; a supplied controller is borrowed. Root and styleguide preview scopes are independent and read live inherited tokens on every build.
- Promise completion is revision-checked. Replacement, repeated ids, explicit dismissal and scope disposal prevent stale terminal updates. Loading promise state is persistent; terminal options control their own duration.
- Flutter Focus/Shortcuts, Semantics, SafeArea, Dismissible and app lifecycle observation are the native equivalents for the reference landmark, keyboard entry, ARIA live region, viewport, swipe and pause behavior.
- Independent review added a replacement close reason and independent pause owners so controller replacement and overlapping lifecycle, hover, focus and manual pauses remain observable and deterministic.
- Independent native review found and fixed two layout/token defects: oversized limited stacks now use a bounded position-aware scroll viewport, and custom content inherits the toast surface foreground and icon tokens.

**migrations**

- Root DiscourseApp and standalone styleguide mount DToaster; every interactive styleguide preview mounts a nested scope so notices disappear with the preview lifecycle.
- Migrated transient feedback across core topic, user, diagnostics, composer, media, instance, bookmark, group and post flows while preserving async guards, captured-controller ownership and stable replacement behavior.
- Migrated bundled Assign, Chat, Events, GIF, Local Dates, Poll, Reactions and Voice feedback with success/error/loading types and stable ids where repeated state replaces an existing notice.
- Button and Alert styleguide feedback demonstrate DToast instead of Material SnackBar. The final audit finds no ScaffoldMessenger or SnackBar use under lib/src.

**retainedAlternatives**

- Permanent inline validation/status and page-scale errors remain owned by Alert, Field and Empty rather than becoming temporary notifications.
- Specialized recording, progress and modal error surfaces retain caller-owned persistent state because replacing them with an expiring notice would lose task context.

**verification**

- Fresh-worktree root and profiles/full flutter pub get --enforce-lockfile passed with committed versions and hashes unchanged.
- Fifteen final Toast component/styleguide tests pass after both reviewer fixes. Earlier focused consumer runs passed 176 tests; a larger 451-test regression passed 450, with its sole message-hover semantics failure reproduced unchanged in the untouched implementation worktree.
- Root and profiles/full flutter analyze --no-pub passed with no issues after current-main integration; dart format and git diff --check pass.
- flutter build macos --debug --no-pub succeeded from accepted review source 964b2f39. The isolated Toast Review a758 bundle and build kernel SHA256 are both 704b7a4a8b8c6c6bb096bb14e4adac48b3de85a2a8630219f7ebffdbadfa7814; its uniquely identified deep strict ad-hoc signature and restricted entitlement readback passed.
- Official rendered Base UI Toast examples were compared in light/dark. Native macOS inspection passed basic/type/action/close/promise/custom/stack, light/dark/Plum, RTL, 360px and 200% text checks, plus a realistic production local-date apply flow. Keyboard focus/Escape, swipe, timeout pause and reduced-motion behavior have focused widget coverage.

**limitations**

- No physical iOS/Linux device run or spoken VoiceOver session was performed; Flutter semantics assertions and native accessibility-tree inspection are not a spoken-screen-reader claim.
- The host treated F6 as a system function-key path during CUA, so focus entry and Escape dismissal are accepted from deterministic widget tests rather than a visible native key sequence. Browser/native font rasterization differs, so no pixel-equality claim is made.

### alert

Status: merged. Task: 01a08454-55a6-7681-8da9-bec8b23899a4. Branch: codex/ui-alert.

**acceptanceCriteria**

- Implement DAlert, DAlertTitle, DAlertDescription and DAlertAction with default/destructive and custom live-token colors; exact base-nova 10/8px padding plus 1px border, 16px icon with 2px offset, 8px column and 2px row gaps, 14/20 typography and proportional lg radius.
- Match basic, destructive, action, custom-color and RTL reference compositions using original Lucide artwork. Preserve compact action placement and reflow at narrow/large text.
- Expose live-region opt-out for static notices; preserve child keyboard focus, semantics and callback ownership without adding timers/controllers or form state to passive Alert.
- Audit core and bundled plugin inline banners; migrate appropriate error/status notices with existing callbacks, async states and permissions unchanged; record retained alternatives.
- Verify focused component and migration tests, root/full-profile analysis, format and an exact-source unique signed macOS actual-production fixture; complete official reference comparison and native inspection before merge.

**decisions**

- Four-part passive DAlert owner with exact base-nova source metrics, two actual variants, live tokens, multiplied destructive alpha, measured action reflow and platform live-region opt-out. Source/artwork hashes and geometry in docs/component-library/alert.md.
- Reference examples include basic/demo/destructive/action/custom colors/Arabic RTL and rich/static composition. The independent rendered/native gate passed, so Alert examples are implemented.
- Integrated pinned main e612ad7b47413fa890b35ae3b55a6f6d37b08cf7; retained every non-Alert progress row and merged owner. Final DButton extraSmall replaces temporary small example action; inline adapters retain callbacks and coordinator Group/Sidebar/Topic Inbox fixes.
- Independent review found and reconciled four additional eligible persistent inline owners: UserSummary refresh, Badges loading/pagination, Assign loaded-list failure and Preferences loading/saved/error status. Their existing retry, loading, semantic announcement and status-color behavior remains app-owned.

**migrations**

- Inline errors: topic feed, categories, tags, groups/group, aggregate, activity pagination, draft refresh, revision history, user-summary refresh, badges, Assign loaded-list failure and GIF paging. Preferences persistent status and Composer tag removal notice retain their existing state, announcement, dismissal and controller behavior.

**retainedAlternatives**

- Page-scale states owned by Empty; historical cooked post notices, chat deleted/read runs, recording/diagnostic indicators, specialized tables, field validation, media errors and Toast/Dialog content retained with specific audit rationale in alert.md.

**verification**

- 107 focused component/styleguide/core/plugin tests passed; 42 additional component/draft/activity checks passed (three component tests repeated). Root and full-profile enforced-lockfile resolution and static analysis passed; 18 touched Dart files formatted; git diff --check clean. Pins/locks unchanged.
- Unique local macOS debug bundle Alert Review 38df / org.discourse.alertreview38df / discourse-alert-review-38df built from implementation commit with zero lib/fixture diff. Source app.dill and both copied kernels SHA256 e543ad77e1bf1c877db0a3c43c55a9e1e124fe239d725d8b6a38ee9f8a275a99. Deep strict ad-hoc signature verification passed; temporary runner settings restored. Exact paths in evidence/alert/build.json.
- Integration: 129 focused component and migrated adapter tests passed; 2 styleguide tests then passed including explicit final extraSmall Button toggle behavior. Root/full-profile analysis passed. Unique Alert Integration Review 38df bundle built from 1efab06c; app.dill/framework/copied kernels all SHA256 43527a2e8cdda4ec7f3e8ed7079ac9ecab5bef98560d03cd866bbbbfcff2ddb8. Restricted-free local debug/JIT/network signed readback and deep strict signature verification passed. Exact source/path/entitlements in evidence/alert/integration-build.json.
- Independent review: 62 post-fix Alert/UserSummary/Assign/Badges/Preferences tests passed, followed by 77 affected tests after latest-main reconciliation. Root and full-profile analysis passed. The accepted-source Alert Final Review ae77 bundle kernel SHA256 is 2a5f2508f01d86b37dcbae2d9731c47fe5b0be49c0dbc9a046ca572151f75d5f; deep strict signature and restricted-identity checks passed. Official Base UI basic/destructive/action/custom/RTL examples were compared in light/dark. Native macOS production fixtures passed light/dark, retry/dismiss, RTL and 200% text checks; styleguide action, live Plum palette and 360px RTL were accepted. Evidence: evidence/alert/final-review-build.json. No iOS/Linux claim.

### attachment

Status: in_progress. Task: 01a085d4-9afd-7082-8081-f8b1f8f66287. Branch: codex/ui-attachment.

**acceptanceCriteria**

- Reproduce the frozen Attachment, Media, Content, Title, Description, Actions, Action, Trigger and Group APIs and full Image, States, Sizes, Group and Trigger examples with recorded primary-source mapping.
- Support actual interaction, keyboard focus, native semantics, grouped scrolling, narrow/scaled/RTL layouts, reduced motion and live host theme/font/radius while keeping upload/network/domain ownership in app adapters.
- Audit and adopt throughout appropriate core/plugin file/upload/image previews including composers and Chat; preserve existing media state, async lifecycle and callbacks and record retained alternatives.
- Run meaningful focused component/consumer checks and root/full analysis, prepare exact-source fixtures and create a new reviewer for remaining rendered/native acceptance, final compositions, fixes and local main merge.

**decisions**

- Implementation task created from latest local main with the tested parent source pinned for isolated preparation. It must create its own independent review/merge task; parent acceptance and all required examples remain mandatory.

### marker

Status: merged. Task: 01a0842f-af4f-7341-95c2-06a97f4ff0c4. Branch: codex/ui-marker.

**acceptanceCriteria**

- Match frozen base-nova Marker/MarkerIcon/MarkerContent: inline, border, separator, 14/20 typography, 16px decorative artwork, 8px gaps and 1px border geometry using live host tokens.
- Provide explicit status announcements, controlled status composition, optional button/link actions with disabled semantics, keyboard/visible focus and borrowed focus ownership; shimmer respects RTL, reduced motion, ticker and app lifecycle.
- Reproduce all documented examples with local state; audit core/plugins and migrate appropriate conversation separators without moving domain callbacks or adopting unrelated Badge/Spinner/progress controls.
- Pass touched formatting, root/full analysis and focused component/styleguide/downstream tests; prepare uniquely identified isolated native fixture bundle with source/kernel/signature provenance, then await explicit desktop slot before reference/native review.

**decisions**

- Reference source, hashes, measured geometry, shimmer color/motion and native adaptations: docs/component-library/marker-reference.md; captured Markdown matches frozen SHA256.
- One public DMarker/DMarkerIcon/DMarkerContent owner; explicit liveRegion and button/link semantics, borrowed focus node, owned lifecycle-aware shimmer; no new dependency or domain state.

**migrations**

- Shared StreamDaySeparator now composes Marker for Topic/Chat date boundaries, preserving date formatting, label-only callback, tooltip, floating appearance and timeline sizing.
- Four actual-component styleguide groups plus local-data native fixture lib/marker_review_main.dart.

**retainedAlternatives**

- Chat one-sided destructive New boundary retains DSeparator; delivery retries, badges, presence dots, circular loading and numeric progress retain existing appropriate owners. Full core/bundled-plugin audit in marker-reference.md.

**verification**

- Flutter 3.47.2 unchanged; root/full enforced-lockfile resolution passed without lockfile changes.
- Root/full analysis clean; touched Dart formatting and git diff --check passed.
- 115 focused Marker, Topic date separator, Chat stream/channel lifecycle and styleguide-page tests passed with randomized ordering; /tmp/marker-focused.log.
- Final shimmer alpha correction passed all13 Marker tests; root/full analysis remains clean.
- Isolated macOS fixture build succeeded: Marker Review 3d0a.app in /tmp/marker-review-3d0a-c9dffe43; ID org.discourse.markerreview3d0a, URL scheme discourse-marker-review-3d0a. All1340 lib/packages/pubspec/pin files match source4e48ba45; three-way kernel SHA256056c1ff41d714c630b966e954b39879d6c9fc78dd3bc41e05520edb4d57067fa and deep strict signature verified. Full provenance and pending inspection checklist: docs/component-library/marker-native.md.
- Integration merge ba156a2c includes only pinned main e612ad7b; all non-Marker progress rows and17 merged owners preserved. Root/full locked resolution and analysis clean;116 focused tests passed seed2335286571, plus13 Marker tests for static-versus-live semantics seed2483898728.
- Current exact-source isolated bundle: /tmp/marker-review-3d0a-ba156a2c/build/macos/Build/Products/Debug/Marker Review ba156a2c.app. All1350 source/package/pin files equal source ba156a2c; three-way kernel SHA256 a290d26bba0b82caefbc0645fd42c0e1725b3ac54a550bd44139e4f29279bc83. Restricted-free explicit ad-hoc JIT entitlements verified by signed readback; strict deep signature passed. Full current provenance: marker-native.md.
- Independent reviewer reran 116 focused Marker, Topic date separator, Chat stream/channel lifecycle and styleguide tests with seed1313617513; root and profiles/full flutter analyze --no-pub passed with no issues. Touched formatting and git diff --check passed; full suite was not run.
- Official Base UI Marker rendered comparison completed in the approved in-app browser at the source 384px example width. Live DOM measurement confirmed 14/20 Geist text, 8px flex gap, 16px icon artwork, 20px inline rows, balanced 12px separator clearance and 29px bordered rows with 8px bottom padding. The Flutter overview, status, separator, border, icon and action compositions visually matched while mapping the host font and semantic palette.
- Native macOS inspection completed against the exact ba156a2c signed bundle. Light, dark, Plum and Forest mappings; 360px/200%/RTL wrapping; shimmer and reduced motion; retained complete/restart state; separator/border/stacked-icon examples; and the real Topic/Chat StreamDaySeparator fixture were inspected. Date label activation incremented the jump counter while rule activation did not. Return and Space activated distinct link/button markers, the disabled action was inert and skipped by Tab, and the outside focus ring was visible.
- Native accessibility inspection exposed separate StreamDaySeparator date buttons, ordinary static marker text, live status text, link, enabled button and disabled button; decorative spinner/icon semantics remained absent. The isolated Marker app quit and the sole comparison tab closed before releasing the desktop lease. No source defect was found; only behavior-neutral status/evidence promotion follows the exact-source build.
- After behavior-neutral styleguide status promotion, all13 Marker component/example/adoption tests passed with seed1313617514.
- Latest main d0722ed0, including reviewed Switch plus Scroll Area/Slider owners and the dependency-classification lock metadata, was integrated without Marker source conflict. All13 Marker checks passed again with seed1313617515; exports, examples and all other progress rows were preserved.

**limitations**

- No iOS or Linux device run and no spoken VoiceOver claim. Target-platform widget coverage is not device testing.
- The native fixture mounts the actual shared StreamDaySeparator used by Topic and Chat with local callbacks; no authenticated live account or network session was opened.
- Browser Geist and native host font rasterization differ, so no pixel-equality claim is made. Geometry, palette mapping, motion, interaction and native semantics were compared directly.

### bubble

Status: merged. Task: 01a085d9-7909-7fd0-b1b8-30a76c6ab2af. Branch: codex/ui-bubble.

**acceptanceCriteria**

- Match the frozen Bubble, Content, Reactions and Group API and every variant, alignment, link/action, Collapsible, Tooltip and Popover composition with recorded reference geometry and behavior.
- Compose shared owners with accessible independent actions/reactions, focus/keyboard/touch behavior, narrow/scaled/RTL layouts, reduced motion and live host tokens; preserve domain message/network ownership outside generic widgets.
- Audit and migrate appropriate core/plugin bubble surfaces, coordinate final Toast reaction and later Attachment/Message boundaries directly, and retain all documented examples without primitive duplication.
- Pass focused component/consumer checks and root/full analysis, prepare exact-source fixtures, then create a new independent reviewer to finish required rendered/native review and final local main merge.

**decisions**

- Implementation task created from latest local main with the tested parent source pinned for isolated preparation. It must create its own independent review/merge task; parent acceptance and all required examples remain mandatory.
- Verified independent reviewer Review and merge Bubble (01a08639-b066-7882-85f5-a759c5fdab6f) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.
- Independent review preserved the frozen 12x8px and host-radius mapping despite current live-site global token drift, corrected ghost focus to remain square, and derived secondary as muted plus 1% foreground so secondary and muted remain subtly distinct in light, dark and arbitrary site palettes.
- Application audit retained ChatMessageTile, chat/topic ReactionPill surfaces and Voice room chat for Message ownership because they combine rich rendering, selection/virtualization, permissions, async mutation or room-domain state; Bubble remains the generic presentational owner.

**verification**

- Independent review added exact geometry, typography, natural semantics, borrowed FocusNode, reduced-motion and secondary-versus-muted token regressions. Fourteen Bubble/example tests passed with randomized seeds 6864 and 6865 after the final visual correction; root flutter analyze --no-pub and git diff --check passed.
- Official rendered reference inspection covered variants, logical alignment, grouping, links/buttons, reactions, Collapsible, Tooltip and Popover in light and dark. DOM measurements confirmed 80% width, 8px group spacing, overlapping reactions and the exterior interactive focus treatment; current global token drift was recorded separately from the frozen registry contract.
- Exact-source isolated macOS review bundle /private/tmp/Discourse Bubble Review e456fc7d.app used identifier org.discourse.native.bubble.e456fc7d and kernel SHA256 e0115b275e4a8cb16ae913e4f60e2a515d9609e98a8c2c3642973ccab2fe010c. Pre-sign kernel equality, explicit restricted-free entitlements and deep strict ad-hoc signature verification passed.
- Native acceptance exercised all eight styleguide examples, pointer actions, visible focus, selected/disabled/busy/error states, static and interactive reactions, disclosure expansion, Popover details, light/dark/Forest/Plum palettes, 360px, 200% text, RTL and reduced motion. The isolated app and reference tab were closed before desktop lease release; full provenance is in docs/component-library/evidence/bubble/native-build.json.
- Candidate 86526407 reconciled accepted Bubble onto main 411ee32d without source conflicts outside progress regeneration. Fourteen focused tests passed again with seed6866; root and profiles/full flutter analyze --no-pub passed with no issues. Main merged the reviewed candidate with --no-ff as c3d6ae97af486134b32067aecc29f7191b05367d.

**limitations**

- No iOS or Linux device run and no spoken VoiceOver claim. Target-platform widget coverage is not device testing.
- The generic Bubble audit intentionally made no production migration before Message owns the existing rich chat row and domain-specific reaction surfaces.
- Browser Geist and native host-font rasterization differ, so no pixel-equality claim is made; geometry, semantic palette relationships, interaction, motion and accessibility structure were compared directly.

### message

Status: in_progress. Task: 01a08606-ca30-7bc1-8e27-693690217969. Branch: codex/ui-message.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Message complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Message (01a08627-8995-7b43-9c06-8a219d472681) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### message-scroller

Status: in_progress. Task: 01a08606-ce86-7be2-b92f-59676b40cb40. Branch: codex/ui-message-scroller.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Message Scroller complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Message Scroller (01a08639-b066-7882-85f5-a7729bfd111b) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### chart

Status: merged. Task: 01a08400-ced8-7f22-a1aa-4955c7d28383. Branch: codex/ui-chart.

**acceptanceCriteria**

- Port frozen base-nova chart container/config, grouped bar composition, grid/axes, themed colors, tooltip dot/line/dashed indicators, label/value formatters and custom tooltip/legend content; account for every frozen documentation section.
- Keep data adapters outside the generic chart owner; audit core and every plugin, migrate suitable existing poll result presentation while preserving confidential results, voting callbacks and async ownership.
- Provide controlled and initial chart selection with mouse/touch/keyboard focus, Escape dismissal, semantic values, responsive/large-text/RTL/live-theme support and explicit lifecycle; chart inspection is not a Form value.
- Supply self-contained actual-component examples and offline production fixtures, meaningful component/adoption tests, root/full analysis and isolated uniquely identified macOS build with source/kernel/signature evidence; remain in_progress awaiting native/reference slot.

**decisions**

- Frozen Markdown hash matches catalogue exactly; base-nova registry and complete inline examples saved with URLs/hashes. Full section accounting, CSS geometry, API and adaptation mapping: docs/component-library/chart.md.
- One generic owner exports DChartContainer/config, typed DBarChart series and controlled inspection, reusable tooltip/legend content and inline DChartBar. Existing native drawing/focus primitives; no plotting package or unmerged dependency.
- Ten actual-component styleguide examples remain baseline pending native/reference gate. Colors resolve live; proportional tooltip radius and multiplicative alpha rules applied.
- Independent source/tests/build complete; awaiting_slot. Keep status in_progress and examples baseline until coordinator grants and completes reference/native review.
- Independent review added DChartColors.series so multiple series remain visually distinct when a site palette collapses primary and tertiary roles; the fallback stays live and palette-relative instead of introducing fixed swatches.
- Independent native review added the actual multiple-choice PollCard Checkbox path and made Tooltip anatomy card widths scale with accessible text. Browser and macOS review passed, so the ten actual-component examples are promoted to implemented.

**migrations**

- PollCard private result bars replaced with DChartBar; percentage/confidential-count rules, permissions, voting/withdrawal and async accepted-result behavior preserved.
- UsersPage metric cells use DChartBar while retaining maxima, minimum-width/intensity/value overlay, synchronized scrolling, sorting and persistence. Actual PollCard/UsersPage local-data fixture: lib/chart_review_main.dart.

**retainedAlternatives**

- Core/plugin loading indicators, topic reading progress, skeleton fractions and text statistics keep their appropriate owners.
- Ranked-choice and pie-markup native accessible option tallies remain Poll domain composition; no speculative chart-family expansion. Prometheus tables and Voice diagnostic text remain unchanged.

**verification**

- Root/full flutter pub get --enforce-lockfile passed; Flutter 3.47.2 and pins/lockfiles unchanged.
- Root/full flutter analyze --no-pub clean; touched formatting and git diff --check passed.
- 147 focused Chart/example/offline-fixture/PollCard/UsersPage/Poll integration/controller tests passed with randomized ordering; final log /tmp/chart-browser-focused.log. Covers native semantic current/next/previous values, keyboard/RTL pointer mapping, borrowed lifetimes, live theme/alpha, image paint, confidential values, maxima/width/scroll persistence and account/accepted-result regressions.
- Final focused rerun: 147 passed, seed 24615266; final executable source 3dceccf13e327e931290d4f25d13f94e1fb695f5 (rendered reference and Escape corrections).
- Isolated macOS debug build succeeded; unique bundle /tmp/chart-review-eab4-3dceccf1/Chart Review eab4.app, ID org.discourse.chartrevieweab4, scheme discourse-chart-review-eab4. Source equality, three-way kernel SHA256 ddd4ce813f3caf72ae4fa11e2f165e1574b89c1dfdafe7b65d4e7ffacf6458f0 and deep strict ad-hoc signature verification passed. Provenance/inspection checklist: docs/component-library/chart-native.md.
- 15 existing styleguide-page/Button-adoption integration tests passed, seed 2936222072; /tmp/chart-styleguide-integration.log.
- Pinned main e612ad7b merged at 1edacc28; final component owners/adapters and all non-Chart rows preserved. 193 integration tests pass seed 4024479176; root/full analysis clean. Source-exact isolated bundle /tmp/chart-review-eab4-1edacc28/Chart Review eab4.app; explicit restricted-free debug/JIT signed readback and deep strict signature pass. Evidence: docs/component-library/evidence/chart/integration/build-identity.json. No CUA/browser/native launch; awaiting_slot.
- Independent macOS review exercised actual Users ready/loading/empty/error states; Poll radio, checkbox, confidential and closed-zero paths; Chart pointer/keyboard/Escape semantics; light/dark, Forest/Plum, RTL and narrow/large-text states. Palette corrections were rechecked natively.
- Final exact-source bundle /tmp/chart-review-c0d7-6a07c5ea/Chart Review c0d7.app (org.discourse.chartreviewc0d7) passed deep strict signature verification; source/copy kernel SHA256 3f0236a425737cfafc39f2d7577481d26e9e8c15a1d6c511810fe92ade77cae2. Plum + 360px + 200% Tooltip anatomy remained readable, stacked and complete in the native accessibility tree.
- After final latest-main integration, 151 focused Chart/styleguide/Poll/Users tests passed with randomized seed 2389001480; root and full-profile flutter analyze --no-pub were clean.

**limitations**

- Browser comparison and macOS native fixture/styleguide inspection are complete; evidence is recorded in chart-browser-review.md and chart-native.md.
- No iOS/Linux device or VoiceOver speech testing was performed; macOS accessibility-tree inspection and test image geometry are not cross-platform or pixel-parity evidence.

### data-table

Status: in_progress. Task: 01a08606-ca45-73b1-9be1-7486d4e3fe1d. Branch: codex/ui-data-table.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Data Table complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Data Table (01a0863a-ff5a-7fe1-bc5c-5f0809bfd69a) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.

### sidebar

Status: merged. Task: 01a08352-7665-7f90-a637-75478a83ea53. Branch: codex/ui-sidebar.

**acceptanceCriteria**

- Reproduce base-nova Sidebar provider, physical sides, sidebar/floating/inset variants, offcanvas/icon/static modes, mobile modal behavior and all documented composition subparts.
- Preserve controlled/uncontrolled state, keyboard shortcut, focus entry/restoration, Escape/outside dismissal, selected/disabled semantics, independent scrolling and live palette/font/radius/RTL/large text.
- Provide independent examples, document reference metrics and dependency boundaries, audit app/plugin adoption; coordinator owns first styleguide shell adoption.
- Pass focused tests and analysis; compare isolated native sample app with official rendered reference in coordinator inspection slot.

**decisions**

- Full mapping, API and dependency boundary: docs/component-library/sidebar.md. Official base-nova registry hash 02b1ea430fb246da062048f0161a01d1b34a2c787f6974958c9b20a3142120a6.
- Provider exposes controlled/uncontrolled desktop and separate mobile state, configurable bounded-width breakpoint and scoped Cmd/Ctrl+B. Native modal route owns focus/dismissal; site colors/fonts/radius update live.
- Operational Flutter dependencies are the completed Tooltip, Separator and Skeleton components. Sheet/Input/Collapsible remain pending catalogue owners; native modal/TextField and local disclosure composition do not claim those tasks complete. The frozen website dependency graph stays unchanged in catalogue.json.
- Native review fixed floating icon2px overflow by painting its border outside layout and gave the mobile shortcut subtree initial focus. Pointer actions own keyboard focus; iOS/Android48px hit areas preserve compact visuals; leaving mobile clears obsolete openMobile. Public API remains stable.

**migrations**

- Public barrel export and six independent sidebar_examples.dart examples registered.
- The actual ComponentStyleguidePage adopts DSidebarProvider, DSidebar, content/groups/menus/buttons/header and trigger, including its responsive modal navigation.

**retainedAlternatives**

- InstanceSidebar and Chat drawer retain domain-specific persistence, permissions, panel switching and unread/reorder adapters; Events/Voice contribute models to those owners. Per-plugin audit is in sidebar.md.

**verification**

- Root/full locked pub get passed; final root/full analysis clean; touched-file format and git diff --check passed. No lockfile,pin,runner or coordinator-owned shell source changes.
- Final21 focused Sidebar,example and existing styleguide tests passed with seed9092026, including pointer-to-keyboard,macOS modal Escape,breakpoint reset,iOS/Android hit areas and floating icon geometry regressions.
- Native comparison and exact evidence/limits: docs/component-library/sidebar-native.md. Final isolated bundle matches build kernel SHA256 b400402635cd61ec213815b387448a848a08bca5fe36f6081f43ee86191488a7; deep strict ad-hoc signature passes.
- macOS inspected reference dark/light/icon modes; native all six examples,documentation30px,360px RTL200 Forest/Plum live open modal,controlled pointer/Return toggle,immediate Escape,loading/error/retry,submenu selection/disclosure and scrolling. App/tab cleanup verified and slot released.
- Coordinator integration passed the 160 affected tests plus the final 14 styleguide-page tests. Compact menu semantic bounds have a dedicated regression; native first-adoption observations and final-scrollbar limit are recorded in docs/component-library/styleguide-design.md.
- Merged separately into local main at 93bfcf65f64868c92340f9aec8236d77585c3cd8; documentation adoption and semantic-bound corrections are included by 0eb34a59ab5de86a1c28c6ebbf08ccb746dab9a5. The integrated real application build passes.

**limitations**

- Native CUA Cmd/Ctrl+B attempts did not visibly toggle; exact bindings pass widget tests. Return,Tab and Escape visibly verified. No spoken VoiceOver or iOS/Linux device run.
- Reference/native capture dimensions differ; intrinsic metrics and visual comparison,not pixel-diff equality. Sample labels/caller icons and app font/palette differ.
- The documentation shell is the first verified adoption. Live forum/Chat adapters remain retained; pending Sheet/Input/Collapsible/Dropdown Menu owners are not declared complete.

### input-otp

Status: in_progress. Task: 01a08606-ca44-78f3-98f2-d147200278ef. Branch: codex/ui-input-otp.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Input OTP complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.

### questionnaire

Status: merged. Task: 01a08606-ca34-7a13-b7ec-79b90b5ebd8f. Branch: codex/ui-questionnaire.

**acceptanceCriteria**

- Match the frozen Base UI/base-nova Questionnaire complete API, behavior, geometry and all documented examples, with recorded exact primary-source mapping.
- Complete all documented capabilities and applicable native keyboard/focus/semantics/touch/overlay lifecycle behavior, narrow and 200% text layouts, RTL, reduced motion and live host palette/font/radius.
- Audit core and plugin usages and migrate appropriate surfaces using shared component owners, preserving domain state, permissions and callbacks; document retained alternatives and finish all required final-owner examples.
- Run meaningful focused component/consumer regressions, formatting and root/full-profile analysis; prepare exact-source fixtures and create a NEW independent reviewer for remaining actual reference/native acceptance, fixes and final local main merge after parent acceptance.
- Export a typed, serializable and resumable Questionnaire controller plus styled composition matching the frozen base-nova root, progress, item, title, description, choices, input, error and action geometry.
- Support single, multiple, freeform and explicit skipped answers; stable item identity; conditional visibility; visited/navigation/progress state; controlled active-item acceptance; reset; shortcuts; external and cancellation-safe asynchronous validation.
- Preserve focus restoration and failed-validation focus, keyboard/touch activation, IME editing, announcements, disabled/inert inactive items, narrow/200% text/RTL reflow, reduced motion and live host palette/font/radius changes.
- Demonstrate reference basic, multiple, freeform, skip, shortcuts, validation, controlled, resume, conditional, custom progress, animated, Card, Dialog and headless/unstyled compositions with final shared component owners.
- Audit core and bundled plugins for surveys, onboarding and stepped forms; migrate only a suitable flow without changing domain validation, permission, persistence or transport ownership, and document retained alternatives.
- Pass meaningful controller/state-transition, async cancellation, resume/conditional/backtracking, widget/accessibility/styleguide and real-consumer regressions plus root/full-profile analysis; require official browser and native macOS acceptance in the independent reviewer.

**decisions**

- User requested queuing every remaining unimplemented component on 2026-09-09. This sole implementation owner begins reference/API/app audit now and coordinates directly with parent owners for committed tested APIs; no coordinator admission gate and no substitute final primitives.
- Verified independent reviewer Review and merge Questionnaire (01a08633-c9ed-7062-86c4-16b0835eb303) owns remaining fixes, required final compositions, actual browser/native acceptance and the final local main merge. This committed source handoff does not establish acceptance.
- Pinned the frozen official Markdown at SHA256 174687e701dfa6b70a0583de3bfee8dd2885b4c8fd51a899adfaffd689a9dc7c and the 2026-09-09 base-nova registry payload at SHA256 7eac8ca2fb479be1a18c97cced020b93c22cec1926dea72c8be324cdb3b62fa9.
- Use an immutable heterogeneous typed item model and a ChangeNotifier controller as the headless/unstyled behavior owner; styled widgets remain free of persistence, networking and Discourse branching.
- The official unstyled API Markdown (SHA256 b6b1f21e3b12dcae85fa89a1582b29ec0e8aede97b02ad33bcbd8db748b06d58), @shadcn/react 0.3.1 tarball (SHA256 0c40a06316d9bac27029f1d81874d894d77ef43a74cad0d12aaab620907563d8), registry TypeScript payload (SHA256 fb5db703937410dee230586678a859b7add61114d7fbf6d6bbfb7101cdfc86ff) and official repository main at 3ba91b1cc83e1bbee4ab35a422ff2a694849c5048 were inspected to resolve navigation, skip, validation and reset semantics.
- Compose accepted Field 5cd7f3694498e4e09e3c114639baca834b56705e, Button eb6d8ea0d9417f0edc830c5ce715b52436f12c94, Progress 15da313eb259c51c6bbed5974895b6616c32c84c, Card a73f465ac86105fdda35f5b56f8b491da4b3936d, Dialog 6a0aaa54d86aaa492681f5cc4dcd32b5e2feefe3 and Native Select 0cdec859288cb2fa0369f64e1a9c1c022dc033e4 owners; Questionnaire only owns its state machine, choice surface and composition.
- Optional unanswered and explicitly skipped are distinct; Skip remains available after answering and skips/submits the final optional item, matching the inspected package behavior. Hidden conditional items retain drafts but leave navigation, progress, validation and submission.

**retainedAlternatives**

- No production multi-step questionnaire exists after searching core and bundled plugins for Stepper, PageView, currentStep, stepIndex, wizard, onboarding, survey, questionnaire, intake, clarification, Form, dialog and sheet compositions, so no production migration is truthful.
- PollCard remains a server-owned single poll with voting permissions, deadlines, result modes and network mutation behavior; PollComposerSheet remains an atomic poll definition editor.
- Bookmark, invite, account, Preferences and Voice editor forms keep interdependent fields visible and save atomically; media/date PageViews remain navigation rather than questions.

**verification**

- 21 Questionnaire controller/widget/styleguide tests passed after final Field composition, covering typed single/multiple/freeform/skipped answers, optional/required behavior, disabled answers, conditional draft retention, backtracking, controlled acceptance/rejection, JSON resume/reset, initial values, stale async-validation cancellation, external errors, shortcuts, Enter submission, focus, narrow 200% RTL reduced motion and real Dialog lifecycle.
- 127 affected owner regressions passed together for Field, Input rendering/state, Button reference/adoption, Progress, Card, Dialog and Native Select.
- Root and profiles/full flutter pub get --enforce-lockfile passed without lockfile or SDK-pin changes; flutter analyze --no-pub passed in both profiles with no diagnostics.
- Touched Dart formatting and git diff --check passed. flutter build macos --debug -t tool/questionnaire_review_main.dart --no-pub produced build/macos/Build/Products/Debug/Discourse.app.
- The source-exact local-data macOS fixture mounts all nine public examples and exposes light/dark/forest/plum, RTL, 100/200% text, reduced-motion and 216px/wide controls.
- Independent review re-downloaded every frozen official source and reproduced the recorded SHA-256 hashes. The rendered Base UI reference was measured at 1024px and 375px in light/dark states; root, progress, type, choice, input and action geometry matched the Flutter mapping.
- Independent review added direct regressions and corrections for editable-field shortcut suppression with active-IME guarding, focus transfer after shortcut selection while disabled choices consume no slot, freeform Enter navigation, and logical RTL slide direction. Final focused Questionnaire coverage passed 23 tests; 139 composed Field/Input/Button/Progress/Card/Dialog/Native Select owner regressions passed.
- The exact-source uniquely identified macOS fixture was built, ad-hoc signed and deep/strict verified. Native inspection exercised the three-step flow, empty validation, radio and checkbox keyboard behavior, disabled shortcut mapping, ordinary freeform editing, progress/action changes and the public example geometry. The final kernel SHA-256 was 77e51f8523b54537b4ad78eddd62f7d4a49b95b5c611d001ee4642329245261c.
- Independent-review root and profiles/full flutter analyze --no-pub were clean; locked pub resolution, touched formatting and git diff --check passed. Accepted source commit after latest-main reconciliation: b7fcd56ecb661ce320e305e6263373f090741d4f.
- After reconciliation onto local main 28723e4fe98560a35b897be1e2b70b38c67c1a4a, 129 combined Questionnaire and composed-owner tests passed with randomized seed 847291; root and profiles/full analysis remained clean.
- The accepted candidate was merged from the repository's main checkout with no-fast-forward merge commit 4217ffe98a37c61510d464f21cfef87c563e82f1. No remote push or release action was performed.

**limitations**

- Official browser comparison and native macOS inspection are complete. Native IME composition itself was not synthesized; active-composition behavior is covered by a direct widget regression.
- No iOS/Linux device, spoken VoiceOver session or production consumer claim is made. Native accessibility-tree inspection is not a spoken-reader or cross-platform claim.

### Final audit

Status: planned. Task: —. Branch: —.

