# Milestone 3 validation evidence

Validated in the assigned worktree, based on main `88a2aad35030fe655a833958c498a4e026da86ab`, on macOS ARM64 with Flutter 3.47.4 / Dart 3.13.3. Source remains pinned to Discourse `07a0e7b94717b45207749578df1f0bd2dd4d12e1`, QuickJS-NG v0.17.0. Logs below are retained without truncation, compressed when large.

| Check | Actual result |
| --- | --- |
| Locked npm clean installation | Passed (`npm ci --offline`) |
| JavaScript suite | 109 passed |
| Package native Dart suite, seed 67214 | 144 passed |
| Package analyzer, fatal infos | Clean |
| Focused installed-owner/host/lifecycle/settings/boundary/packaging tests | 50 passed |
| Correction host/worker regressions | 12 passed |
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
| Corrected full root suite, seed 67214 | **11,925 passed, 7 skipped, zero failures (5m40s)** |

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

The final bundle is 2,414,193 bytes, SHA-256 `95490083fe13f2e3c44133cf2dc5d037f49016c99ee58d0b3c8a7a33f03568f3`. Source changes were frozen before the final full-suite/package-artifact pass. Separate cleanup files/catalog entries own link rel, code/bidi, cached mentions, and media policy. Bot carousel `data-mode` is retained for the pre-existing native image-grid renderer; fence tests retain only reviewed wrap/height metadata.

The four final Apple application kernels contain the exact final compiler bundle revision, in addition to their embedded native cooking frameworks. `embedded-frameworks.log` records those artifact checks. `full-root-suite.log.gz` is the final run after all source/policy changes; the earlier corrected runs are not substituted for this gate.

A final adversarial cached-HTML check exposed two related media-policy bypasses: template content lives in a separate parse5 fragment, and stripping unsupported raw-text wrappers could expose their unprocessed contents. The shared walker now traverses template content; the closed sanitizer discards unsupported opaque bodies. Media cleanup also checks the native video parser’s original-source fallback. Nine additional shared JS/native regression cases cover these paths. The superseded in-progress root run was interrupted; the final full-suite log is a fresh run after these fixes.


Coordinator review corrections select referenced metadata before constructing a merged snapshot, apply one 96 KiB aggregate metadata budget (including complete matching/policy maps and lists), and retain cached video thumbnails through resolved upload URLs. Overflow of required policy produces a readable host `inputLimit` result; it never silently truncates censor or deny rules. Host tests cover independent 150 KiB caches, precedence/empty incoming caches, aggregate enrichment, required map/list limits, invalidation, and the installed no-HTTP thumbnail path. Four additional JS/native tests cover post-only and Chat-only syntax/token extensions inside transcripts, missing dependencies, and disabled owners. The nested engine API selects the target profile independently, creates separate owner state, and preserves reviewed nested output through the parent's sanitizer.

The existing whole-worker benchmark on the final assembly reports 41.3 ms median and 45.8 ms p95 round-trip over 100 warm samples (39.7 ms median engine time; 10,227,696 bytes reported QuickJS allocation). It ran in local JIT mode while other validation was active, so this is a boundedness check, not a controlled performance comparison. Full output is retained in `worker-benchmark.log`.
