# Offline cooking implementation report

The native app now bundles Discourse's cooking engine and cooks Chat drafts, outgoing messages and edits locally, without a cooking or lookup request to the backend. The existing Native `CookedHtml` renderer displays provisional HTML; ordinary send responses and MessageBus updates supply authoritative HTML, including intentionally empty bodies.

## Delivered architecture

- A pinned Discourse JavaScript bundle runs in a persistent isolated QuickJS worker behind typed Dart contracts. No network, filesystem or generic native bridge is exposed to behavior code. Input, memory, output, time and queue limits bound work; failures retain readable content.
- Requests carry immutable site/account/profile context, cached settings and source-relevant metadata. Context and request fingerprints prevent cross-site, stale-account and old-revision reuse. Bounded caches, lifecycle invalidation and worker recovery are shared by the application.
- Plugins register versioned, owned cooking modules through the existing Native manifest. Each behavior has its own source/catalog entry. Source, syntax, token and document stages have deterministic ordering, dependency checks and profile gates. The final HTML policy remains closed after all transformations.
- Chat prepares coalesced drafts, reuses exact current results, stages sends immediately and cooks uncached submissions independently of transport. Edits, retries, duplicate deliveries, canonical replacement, rollback, account changes and editor ownership have race coverage. Upload records remain separate from cooked message text.
- The post profile supports the compatible bundled plugin syntax. No composer preview UI is included. Topic/reply insertion remains tied to the normal server response; the shared post cooking API is available to existing or future consumers.

Upstream Discourse is pinned to `07a0e7b94717b45207749578df1f0bd2dd4d12e1`; QuickJS-NG is pinned to v0.17.0, commit `6d46d07d04041b40f4f49eaa7fdebe44c314c699`. Reproducible generation checks the vendor sources, generated Dart module catalog, compiler bundle and redistributed licenses together.

## Behavior coverage

| Area | Local behavior and boundary |
| --- | --- |
| Core Markdown | Paragraphs, lists, emphasis, links, code/fences, tables, quotes, images/uploads, emoji, mentions and hashtags under the selected dialect |
| Chat | Pinned dialect, slash-command cleanup, bot/editor differences, restricted inline HTML, nested transcripts and preserved profile isolation |
| Portable cleanup | Separate modules for links, bidi/code handling, cached mentions and media policy; pinned Unicode emoji handling, watched/censored words and cached CDN/upload origins |
| Cached enrichment | Known mention/hashtag/upload/topic/onebox/media metadata only; missing records remain readable and do not trigger cooking requests |
| Local Dates | Bundled locale/timezone data, ranges, explicit clock/timezone context and existing Native date renderer |
| Details and spoilers | Pinned syntax and existing Native disclosures; hidden descendants do not mount media or expose selection/accessibility content |
| Polls | Pinned option IDs, numeric/list/title forms, setting gates, read-only local fragments; canonical records retain interactive authority |
| Events and calendars | Pinned post/event/calendar syntax and metadata; rich read-only fragments preserve nested content without record hydration |
| Livestream and group timezones | Concealed livestream content is suppressed; group membership/timezone snapshots are unavailable in the current cooking context |
| Mermaid and placeholders | Existing fence/d-wrap syntax and Native renderer contracts are preserved |

Reactions, Assign, GitHub, lazy video, GIF picker, Voice and Prometheus need no additional syntax module for their current Native behavior. Native AI remains limited to its existing summary/proofreading surfaces; this work does not add artifact/tool-approval rendering. Upstream-only checklist, footnotes, math, policy and graphviz behavior is outside the bundled Native feature set.

## Milestones and local main integration

| Milestone | Implementation / integration | Accepted main point |
| --- | --- | --- |
| 1. Engine and runtime | `a3ee11ec543fd9d2e281846198609b1c3bef0099`; integration `4dbf215e7` | `ff4df1488c9bb5fd2b032b6967b9965e147ad290` |
| 2. Contracts and plugin host | `03def6a971d987641dc98db4ac2d6f5217ef3e1d`, `29934eeb9b3167bf30cb361d969a6be3f59c993e`; integration `83a7129a8a83762ac2c80d9ef80a866e363963e2` | `88a2aad35030fe655a833958c498a4e026da86ab` |
| 3. Chat dialect and cleanup | `a06f3cca13bc9fb7b15be4ad55752bc28af8cbb5`, `49f4320eaf80afed86355eb47aeadc5214061581`, `bac37b73e442cba1c195f2d702b534c1602dd6df`; integration `f031dfd7c8ae01a8474aff90e8da61893f64fd49` | `507bf410df7ffc1d1e9a53fa560cec7ef5ec84d1` |
| 4. Optimistic Chat integration | `4e6684c22ca0fa423ddec84d2fdb6e84815b4527` | `ea9412fe234742d9134b429ab11872f8f54ba72e` |
| 5. Remaining compatible plugin behavior | `1c709b8c839047a4718ec3b9c963e4401a9b7b9f`, reader correction `2297a10bb255dea1a2c86a25f1dba806d9f7b04c` | `8777ab1a9958b173f20e7c8966805822ed6341bf` |

All five milestones are verified and merged into local `main`. The table records the exact fast-forward main points; separate merge commits are not created for fast-forwards. Each accepted branch was merged from `/Users/joffreyjaffeux/Code/discourse-native` on `main`. Before/after snapshots confirmed unrelated main changes were preserved; no push was performed. Milestones 1–3 used separate user tasks. Milestones 4–5 were implemented in the coordinator task after the user's workflow change.

## Validation

Final milestone 5: **12,071 app tests passed, 7 skipped, 0 failed**; 183 native compiler tests and 150 JavaScript tests passed. Root/full-wrapper/Voice/compiler analysis and formatting passed. All four final root/full iOS simulator Debug and unsigned macOS Debug builds passed, with independently verified engine artifacts; the standalone macOS ARM64 AOT benchmark also built and ran. The exact 2,438,567-byte compiler bundle has SHA-256 `0b445bf11e88a702f9eb0d9e5a9748977270f5d585cb9db21c92fba71d6c2529`. Earlier independently accepted results are retained in the milestone evidence directories:

- Milestone 2: 11,921 root tests passed, 7 skipped; 61 package tests and 22 JavaScript tests passed.
- Milestone 3: 11,933 root tests passed, 7 skipped; 144 native package tests and 109 JavaScript tests passed.
- Milestone 4: 12,028 root tests passed, 7 skipped; final focused controller/editor/pipeline checks and root/full-wrapper/Voice analyzers passed.

Milestone 1 encountered then-existing repository baseline failures; its incomplete suite is documented as such, not a pass. Later full-suite passes supersede those historical baseline limitations. Individual evidence reports preserve fixes found by review even after focused tests passed.

The retained milestone 4 macOS ARM64 whole-path sample measured warm rich-message staging at 0.269 ms, provisional HTML at 40.284 ms and rendering at 84.921 ms. Cold-worker HTML took 109.686 ms; exact prepared reuse required zero additional cooks. These are single-machine debug/JIT diagnostic samples, not device-wide latency guarantees. The test traps recorded zero compiler HTTP attempts and kept ordinary transport/media handling separate.

## Remaining limits

- Cooking performs no backend requests, but sending/editing/uploading, opening links and normal renderer media loading still use their existing network paths. Fully offline delivery is not implemented.
- Server validation, permission decisions, database data and uncached remote enrichment remain authoritative. Ruby plugins require an explicitly bundled portable module and a compatible Native renderer; they do not transfer automatically.
- Inline spoiler layout uses a disclosure instead of the web inline blur; details summary spoilers use a concealed-content label. The existing bare Native radio requires its painted indicator or keyboard; its blank surrounding area is not a working touch target. Group timezone membership and livestream attendance are not reconstructed. Older Events persistence that already collapsed two switches needs a normal settings refresh to recover the distinction.
- Topics/replies are still inserted on the server response; no new optimistic post lane or composer preview was added. Chat is the completed immediate-display consumer.
- Platform results distinguish executed worker/tests and actual built artifacts from configured CI. Linux CI is configured but was not executed locally; physical iOS interaction was not tested. Android/Windows remain planned and web is unsupported.

See [milestone 5](milestone-5.md) for the behavior/owner matrix and [milestone 2](milestone-2.md#small-complete-extension-example) for the complete extension contract.
