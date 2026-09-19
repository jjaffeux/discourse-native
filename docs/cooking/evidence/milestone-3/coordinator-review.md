# Milestone 3 coordinator verification

Accepted on 2026-09-19 after independent source review and checks in a clean integration checkout. The final merge runs from the main checkout and preserves any unrelated working changes.

- Implementation: `a06f3cca13bc9fb7b15be4ad55752bc28af8cbb5`.
- Cached HTML correction: `49f4320eaf80afed86355eb47aeadc5214061581`.
- Metadata and nested-profile correction: `bac37b73e442cba1c195f2d702b534c1602dd6df`.
- Main used for integration: `a60d119b8cdef09d2c86818390d1690b5bcaf643`.
- Initial integration: `071007834512054a76bbc7661dd19607b1603b19`.
- Final integration and tested tree: `f031dfd7c8ae01a8474aff90e8da61893f64fd49`.

## Independent results

| Check | Result |
| --- | --- |
| Complete final integrated Flutter suite, seed 67214 | **11,933 passed, 7 skipped, zero failures**, 5m23s |
| Final package native Dart suite, seed 67214 | 144 passed |
| Final JavaScript suite | 109 passed |
| Root and package analyzers after correction | Clean, including package fatal infos |
| Full-wrapper analyzer | Clean on the initial integration; correction changes no wrapper API/dependency |
| Root/full/package enforced lockfile resolution | Passed; correction changes no dependency locks |
| Root format gate | 1,873 files, zero changes; all four handwritten correction files separately clean |
| Handwritten package format gate | 20 files, zero changes; changed package regression separately clean |
| Exact JavaScript bundle reproduction | 2,414,193 bytes; SHA-256 `95490083fe13f2e3c44133cf2dc5d037f49016c99ee58d0b3c8a7a33f03568f3` |
| Pinned native source verification | All 21 QuickJS files match |
| Author evidence manifest | All 24 retained files match their hashes and lengths |
| Four author-built Apple artifacts | Independently verified final bundle revision in each Dart kernel and native cooking framework in each app |

The initial integration also passed 11,931 root tests with 7 skips. Review still found three issues that those tests did not cover; acceptance required their corrections and a fresh full run. The author's final branch run passed 11,925 tests with 7 skips. The higher integration count reflects additional tests already on current main. These runs are distinct, and earlier M1 baseline failures are not a current exemption.

## Review findings and corrections

Early review corrected compound Unicode emoji handling, active Chat extensions, effective editor identity for bot rules, configurable hashtag priorities, shell/ingested metadata precedence, site-subfolder mention paths, typed unresolved-reference diagnostics, cached CDN media origins, linked transcript metadata and pinned Local Dates email defaults. Link, bidi, mention and media cleanup are separate catalog modules. The author additionally fixed template-fragment traversal, unsupported opaque HTML bodies and the native video original-source fallback before handoff.

Final independent review required three further changes:

1. Metadata selection now precedes snapshot construction. A shared 96 KiB UTF-8 JSON budget reserves complete policy/matching fields before optional enrichment. Oversized policy returns a readable input-limit failure without partially applying censor, deny or origin rules.
2. Selected authoritative upload URLs also select their cached video thumbnail metadata, even when raw text contains only an `upload://` short URL.
3. Nested parsers select modules against their own profile, owner activation and dependency closure. Post-only syntax no longer leaks into Chat transcripts, and Chat-only syntax can run in a post's transcript. The generic lazy nested-profile API maintains separate owner state and reviewed output policies.

Both bounded independent reviewers accepted the final corrections. Native-worker regressions cover both directions of profile-scoped syntax/token behavior, filtered dependencies, disabled owners, aggregate metadata overflow, supplied precedence, stale-result precedence and actual short-upload video enrichment. Existing zero-HTTP and worker deadline/teardown regressions remain in the passing suites.

The policy-overflow verdict is weakly associated with the original request in its owning host. Consumers must pass that exact request to the same host's `cook`; serialization/reconstruction or another host loses this host preflight verdict. This paired contract is documented and current consumers preserve it. Account, configuration and disposal checks precede that fallback.

## Runtime and platform limits

The coordinator executed the native worker on macOS ARM64 with Flutter 3.47.4 / Dart 3.13.3. A final local JIT benchmark measured startup at 239.603 ms and 100 warm round trips at 30.778 ms median / 32.690 ms p95, with 10,227,696 bytes reported QuickJS allocation. The author's concurrent-validation sample measured 41.3 / 45.8 ms. These are single-machine generic worker samples, not composer-to-render latency or platform-wide performance claims; milestone 4 must measure the whole Chat path.

The author successfully rebuilt root and full-wrapper iOS simulator debug apps and unsigned macOS debug apps against the final bundle. The coordinator checked their actual kernels/frameworks; it did not independently rebuild these four apps on the integration tree. Neither physical iOS device interaction nor Linux execution was performed here. Linux CI remains configured; Android/Windows remain planned and web unsupported.

Chat drafts, sending and editing are intentionally milestone 4 work. Canonical server HTML still owns final content. Database/permission checks and remote enrichment remain server-owned, cache misses stay readable, and the closed sanitizer deliberately reduces unsupported rich HTML. Native spoiler conceal/reveal remains a documented renderer gap. This milestone does not claim those remaining behaviors are implemented.

## Retained coordinator evidence

Adjacent `coordinator-*.log` and compressed logs preserve the final full/package/JS checks, exact bundle verification, analysis/format checks, native provenance, Apple artifact inspection and benchmark. The author's original evidence and manifest are preserved separately.
