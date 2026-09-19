# Milestone 4 coordinator acceptance

Accepted implementation: `4e6684c22ca0fa423ddec84d2fdb6e84815b4527`, based on local main `507bf410df7ffc1d1e9a53fa560cec7ef5ec84d1`.

Implemented in the coordinator session with bounded collaborators, as the user requested. The coordinator reviewed the scheduling, host freshness, native model/rendering and composer wiring; separate reviewers checked the other contributors' code. Review fixes include per-editor preparation ownership, locale/device-timezone invalidation, pausing hidden draft work, preserving any newer canonical edit during rollback, and content-only row updates.

## Actual checks

- Complete root suite, seed 67214: **12,028 passed, 7 skipped, 0 failures**, 5m49s.
- Final focused acceptance: **96 passed**, including 15 controller race tests, five editor-ownership regressions, two real pipeline tests and the complete 74-test composer suite.
- Additional focused run: **369 passed**, covering scheduler/prepared state, host freshness, message value/rendering, existing send/controller behavior and real-worker/widget lifecycle tests.
- Root, full-profile and voice analyzers: clean, including the final root run after all source changes.
- Enforced root/full/voice dependency locks: passed; lockfiles unchanged.
- Repository format gate: **1,881 files, zero changes**. Final new/changed-file checks also passed.
- `git diff --check`: passed.

The first broad run found nine debounce timers surviving composer unmount and three tests expecting the retired preview renderer. The implementation now suspends hidden preparation and resumes it on remount; deterministic provisional `CookedHtml` expectations replace those legacy assertions. All affected tests and the complete suite pass after these fixes. An earlier overlapping Flutter invocation hit native-asset code-signing staging contention; subsequent acceptance runs were serialized in this worktree.

## Whole-path measurements

`pipeline-metrics.json` and `acceptance-focused.txt.gz` retain the coordinator's real Shell → installed Chat/Local Dates owners → native worker → message row → Native renderer measurements. Optional prewarm was deliberately suppressed, and the host result cache disabled. These are desktop debug widget-test observations, including JIT, polling and frame overhead; they are not device-release targets or statistical latency guarantees.

| Scenario | Synchronous row staging | Provisional HTML ready | Native rendering observed |
| --- | ---: | ---: | ---: |
| New worker, rich content | 0.677 ms | 109.686 ms | 252.625 ms |
| Warm rich content | 0.269 ms | 40.284 ms | 84.921 ms |
| 14,031-byte source, 155,741-byte unrelated cache | 0.261 ms | 96.662 ms | 159.048 ms |
| Warm trusted GIF source | 2.614 ms | 38.439 ms | 71.787 ms |
| Warm text and separate attachment | 0.669 ms | 35.122 ms | 41.290 ms |
| Prepared submission | 4.789 ms | 4.789 ms | 109.011 ms |

The long-input request snapshot was only 1,599 bytes. Two shared composers and 41 source revisions produced one cook, with one maximum physical cook and zero new cooks on prepared submission. Final-keystroke-to-ready wall time was 146.548 ms, with a separately recorded 50 ms simulated widget debounce advance. Both pipeline cases recorded zero compiler HTTP attempts. Renderer media used a separately counted mock client. Normal Chat send requests remained held while local cooking/rendering completed.

## Platform and remaining scope

The actual native worker and Flutter Native rendering were executed on macOS arm64. M4 changes no compiler bundle, native source, dependency or packaging configuration. The unchanged bundle is 2,414,193 bytes, SHA-256 `95490083fe13f2e3c44133cf2dc5d037f49016c99ee58d0b3c8a7a33f03568f3`, independently matched against its manifest. Package/JS regeneration and Apple app rebuilds were not repeated for this integration-only milestone; the four Apple build results belong to M3. No new iOS-device, Linux or release/AOT performance claim is made here.

Prepared results are provisional and readable fallback remains available on missing context/runtime failure. A locale change during an active submitted cook drops its old result. Unknown server plugin behavior and server-owned enrichment still require canonical responses. Topic consumers and remaining compatible plugin syntax/native fallback behavior are M5 scope. No push was performed.
