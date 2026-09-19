# Milestone 3 validation evidence

Validated in the assigned worktree, based on main `88a2aad35030fe655a833958c498a4e026da86ab`, on macOS ARM64 with Flutter 3.47.4 / Dart 3.13.3. Source remains pinned to Discourse `07a0e7b94717b45207749578df1f0bd2dd4d12e1`, QuickJS-NG v0.17.0. Logs below are retained without truncation, compressed when large.

| Check | Actual result |
| --- | --- |
| Locked npm clean installation | Passed (`npm ci --offline`) |
| JavaScript suite | 105 passed |
| Package native Dart suite, seed 67214 | 140 passed |
| Package analyzer, fatal infos | Clean |
| Focused installed-owner/host/lifecycle/settings/boundary/packaging tests | 50 passed |
| Root analyzer | Clean |
| Root/package format gates | 1,759 root files and 19 handwritten package files, zero changes |
| Compatibility wrapper analyzer | Clean |
| Root, full wrapper and package enforced lockfile resolution | Passed, using cached dependencies |
| Exact JS bundle / license / provenance reproduction | Passed |
| Vendored QuickJS verification | 21 files match the pinned engine |
| Root iOS simulator debug build | Passed; embedded cooking framework verified |
| Full-wrapper iOS simulator debug build | Passed; embedded cooking framework verified |
| Root unsigned macOS debug build | Passed; embedded cooking framework verified |
| Full-wrapper unsigned macOS debug build | Passed; embedded cooking framework verified |
| Corrected full root suite, seed 67214 | **11,923 passed, 7 skipped, zero failures (5m45s)** |

The initial full root run completed with **11,921 passed, 7 skipped, 2 failures** in 6m18s. Both failures were Local Dates persistence tests comparing maps without the newly persisted `emailFormat` and `emailTimezone` fields. Expectations now verify the pinned defaults; wire decoding additionally checks explicit email settings. This is a milestone regression corrected here, not an old baseline failure. The initial complete log is retained. The initial package analyzer also found two missing test-loop braces; those are corrected and the final analyzer is clean.

The 77-case shared Chat corpus checks pinned command/newline behavior, indented raw versus submission input, ordinary/bot/editor profiles and exclusions, HTML safety, nested/chained transcripts, dates/ranges/DST/aliases/invalid zones/locales/email settings, typed/unknown/boolean mentions, custom/denied/compound/skin-tone/variation-selector emoji, bidi handling, links, hotlinks/CDN uploads, media cache misses/poisoning, and watched-word/censor snapshots. Separate tests cover hashtag collisions inside a post transcript, malicious metadata, cross-site isolation, native installed-owner coexistence with an independent extension, disabled owners, typed fingerprints, cache guards, and a 60,000-character Unicode boundary input under the existing watchdog.

No compiler HTTP client was created in the installed native-chain test. The shell metadata regression exercises the actual shell request builder and worker, preserving lease-ingested oneboxes/groups while collecting a cached user and retaining the site's subfolder in mention navigation. Worker tests include the milestone 2 caller-zone/real-deadline and widget-teardown regressions.

Apple builds used:

```sh
flutter build ios --simulator --debug --no-codesign --no-pub
flutter build macos --debug --config-only --no-pub
xcodebuild build -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -derivedDataPath build/macos-cooking-ci \
  CODE_SIGNING_ALLOWED=NO
```

The same commands ran in `profiles/full`. The embedded-framework log verifies the actual built application outputs. The native corpus executed on macOS; Apple app build success is not a device interaction test. No iOS physical-device execution or Linux execution occurred in this worktree. Linux CI remains configured, not claimed as locally tested. Android and Windows remain planned targets; web is unsupported. No new native C dependency or engine version was introduced. The larger JS closure now contains Moment/timezone/locales and structural HTML parsing under the existing heap/time/result bounds.

Full-suite command:

```sh
flutter test --no-pub --reporter expanded --test-randomize-ordering-seed=67214
```

The final bundle is 2,411,137 bytes, SHA-256 `9dbdedba1a57bf7dae9940d4af2c306550bcf61d99c60aac3e408dc0f44c9f60`. Source changes were frozen before the final full-suite/package-artifact pass. Separate cleanup files/catalog entries own link rel, code/bidi, cached mentions, and media policy. Bot carousel `data-mode` is retained for the pre-existing native image-grid renderer; fence tests retain only reviewed wrap/height metadata.

The four final Apple application kernels contain the exact final compiler bundle revision, in addition to their embedded native cooking frameworks. `embedded-frameworks.log` records those artifact checks. `full-root-suite.log.gz` is the final run after all source/policy changes; the earlier corrected runs are not substituted for this gate.

A final adversarial cached-HTML check exposed two related media-policy bypasses: template content lives in a separate parse5 fragment, and stripping unsupported raw-text wrappers could expose their unprocessed contents. The shared walker now traverses template content; the closed sanitizer discards unsupported opaque bodies. Media cleanup also checks the native video parser’s original-source fallback. Nine additional shared JS/native regression cases cover these paths. The superseded in-progress root run was interrupted; the final full-suite log is a fresh run after these fixes.
