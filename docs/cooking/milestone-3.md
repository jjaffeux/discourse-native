# Offline cooking milestone 3

Milestone 3 adds pure Chat syntax, Local Dates, portable cleanup, and explicit immutable request facts to the installed native cooking owners. It does not integrate Chat sending, editing, drafts, or previews. Server cooked HTML remains canonical and `CookedHtml` remains the native renderer.

## Ownership and stages

The installed `cooking` owner supplies missing-upload handling, spoiler syntax, and individual link, code/bidi, mention, and media cleanup modules. The existing `ChatPlugin` adds a cooking capability while retaining its native settings, rendering, navigation, notifications, and composer interfaces. `LocalDatesPlugin` similarly retains its existing interfaces and owns date settings and syntax. Core host code imports generic cooking contracts, not these implementations.

The generated module catalog selects individual behavior files. Stages are `source`, `syntax`, `token`, and `document`; configuration rejects dependencies on later stages. A source transform receives original text before parsing and returns bounded text. All stages receive their owner's frozen projected settings and a per-cook API. Owner-local state is newly allocated for each request, allowing Chat's source recognizer to pass a command to its document formatter without globals. The original raw text still determines request identity and readable failure output. Final sanitization follows every transform and upstream HTML hoist.

Chat applies the pinned standard features/rules, settings-controlled shortcuts, forced quote links, and Chat hashtag order. The effective cooking user is the editor when supplied, otherwise the author; a negative effective ID enables headings and image grids. Installed syntax/token extensions survive both the outer Chat profile and transcript nested cooking. Post-only details, polls, events, and d-wrap are excluded from ordinary Chat. Restricted inline HTML recognizes `kbd` and `mark`, not general raw HTML.

Transcript syntax uses the pinned wrapper structure, author/time/channel/thread metadata, chained messages, and nested Chat profile, including inside a post. Each request constructs a private transcript setup closure. The profile-generic `cookProfile` API lazily assembles a separate nested parser from the declared target profile. It selects syntax/token implementations, owner activation, and transitive dependencies again for that profile, with separate owner state; post-only extensions cannot leak into nested Chat and Chat-only extensions remain available there. Reviewed nested output policies survive the parent sanitizer. The Chat adapter supplies its hashtag/quote overrides. Metadata text is escaped and channel/thread identifiers are constrained; executable output is still removed by the final policy. SVG thread artwork is deliberately removed by the closed sanitizer; structural markup and readable title remain.

## Frozen context and cached enrichment

`CookingContext` carries author/editor/topic/post IDs, author username, locale, timezone, as-of epoch milliseconds, and source policy. Defaults are deterministic (`en`, `Etc/UTC`, epoch zero); producers must supply the intended context. Every field participates in the existing canonical fingerprint. Neither compiler execution nor context assembly calls a live composer resolver, HTTP client, filesystem, or native host bridge.

`CookingSourcePolicy.raw` preserves source whitespace, including indented code. `submission` explicitly applies TextCleaner's pinned Unicode-space normalization, ASCII boundary trim, and U+200B removal before slash recognition. It is not implicitly applied to raw cooking, and does not collapse interior ASCII spaces.

`CookingCachedMetadata` accepts bounded immutable fields and typed mention, topic, media, censor, and watched-word records. It supports cached avatars/primary groups/full and inline oneboxes, emoji translations and deny lists, hashtag priorities/icons, and explicit allowed media origins (including known CDN/S3 CDN origins). `ApplicationCooking.ingestMetadata` uses the same owner/account/generation lease as uploads. A per-request `cachedMetadata` value can also cross the narrow plugin request port. Per-request maps override colliding ingested entries; empty maps do not discard other ingested enrichment. Nonempty per-request lists replace ingested lists. Forget/disposal clears ingestion state and late leases cannot write it.

The shell selects already-cached referenced topics and user cards, preserves encoded site-subfolder user paths, and combines them with its existing hashtag/custom emoji/existence snapshots and any ingested enrichment. Topic titles and avatar URLs are escaped. No unbounded entity-store dump is serialized. Existing boolean `_mentioned` entries remain existence-only: they do not establish kind, canonical spelling, or group notification eligibility. Typed cached records hydrate `a.mention` / `a.mention-group`; unresolved references remain readable. Known uploads require authoritative metadata; misses do not fetch or invent `/404` URLs. Selected uploads also select media metadata keyed by their resolved URLs, so short upload references retain cached thumbnails.

The host checks oversized source before touching cached metadata or owner projectors. It selects referenced values directly from separately validated caches before constructing the final snapshot. Supplied map entries override stored entries; empty supplied maps/lists retain stored data. One 96 KiB encoded-JSON budget covers every metadata field, with the existing 128-entry/32 KiB field and 8 KiB entry limits for optional enrichment. Always-needed matching and policy maps/lists reserve their complete cost first. If those required fields alone exceed the budget, the host returns a readable `inputLimit` result instead of truncating censor, deny, or media policy. The preflight verdict is session-owned and weakly keyed by the returned request; callers use the paired host `request`/`cook` methods. Account invalidation still takes precedence for admitted requests.

Source/context/result bounds, account generation guards, inflight admission, cache identity, stale-write rejection, native interruption, and real wall-clock worker deadlines remain in force. Generic lookup namespaces map to valid typed unresolved-reference kinds; optional media misses generate no invalid diagnostic or undefined key.

## Dates, emoji, and portable cleanup

The pristine pinned Local Dates module runs with locked Moment 2.30.1 / Moment Timezone 0.6.3 and its bundled timezone database and locales. It preserves date/date-range parsing, date normalization, aliases, zone validation, DST interpretation, UTC readable text, and email-preview format/timezone settings. The existing native settings owner persists those email settings, including the pinned `llll z` / `Etc/UTC` defaults for older snapshots. Moment locale/default timezone/clock are established from frozen input before parsing and cleared afterwards; translation context is reset after every request. Unrecognized locales have readable English fallback. The explicit reader timezone participates in identity; syntax's absent-zone fallback remains UTC as upstream requires, rather than ambient device timezone.

Unicode emoji use the pure pinned `buildEmojiUnicodeReplacer`, preserving complete sequences, skin tones, variation-selector behavior, and adjacent-text boundaries. Standard/custom emoji, shortcuts, Unicode translations, deny lists, and watched-word/censor snapshots are applied inside the compiler. Cached rich HTML is untrusted even if it originated from a plugin.

Portable cleanup structurally parses cooked HTML. It adds upstream-style external/internal/allowlisted link `rel`, makes dangerous bidi characters visible only inside code/pre, applies hotlinked-media policy using explicit allowed origins, hydrates proven mention records, and attaches cached video thumbnail metadata. Source command recognition preserves pinned case-sensitive and terminal-newline rules. `/me` escapes its author and applies only to one paragraph; `/shrug` and `/tableflip` append literal Unicode only to empty or single-paragraph output. Lists and multiple blocks retain their cooked shape.

Reviewed final-policy additions cover transcript/date/quote metadata, action emphasis class, code-wrap/height metadata, bidi titles, and specific cached media URLs. URL-valued metadata undergoes normalized URI validation. Scripts, event handlers, styles, arbitrary data attributes, SVG, executable schemes, and raw cached HTML cannot bypass final sanitization. Hotlinked media blocking removes active source URLs, including the native video parser’s original-source fallback, while retaining safe blocked-source metadata. Template fragments are traversed before cleanup; unsupported opaque/raw-text containers (including xmp, plaintext, noembed, noscript, textarea, and title) lose their bodies at final sanitation rather than exposing unprocessed media when their tags are removed. This deliberately narrows cached HTML compared with a browser’s opaque-container behavior.

## Capability and renderer coverage

| Behavior | Local syntax / cleanup | Cached enrichment | Server-only work | Current native renderer |
| --- | --- | --- | --- | --- |
| Standard/bot Chat Markdown | Complete pinned profile and bot additions | Settings and effective user ID | Permissions remain server-owned | Existing text, headings, code, tables, images |
| Slash actions | Recognition and structural formatting | Escaped author name | Submission/account policy | Existing emphasis rendering; class emitted |
| Chat transcripts | Wrappers, chains, nested Chat dialect | Avatars, channel/topic metadata | Remote avatar/topic lookup and authorization | Existing transcript parser/widgets; SVG thread icon stripped |
| Local Dates | Pinned syntax, ranges, normalized UTC fallback/email metadata | Owner settings, fixed locale/time | Server email delivery | Existing Local Dates widget/parser; generation is tested separately |
| Mentions/hashtags | Parsing and safe attributes | Typed known identity/kind/href, priorities/icons | Group eligibility and access checks | Existing mention/group/hashtag rendering |
| Emoji/censors/watched words | Pinned Unicode and parser behavior | Custom images, translations, deny/rule snapshots | Rule acquisition/moderation decisions | Existing emoji/text rendering |
| Uploads/video | Readable misses, safe media metadata and hotlink handling | Authoritative upload/thumbnail/CDN metadata | Upload resolution, processing, remote enrichment | Existing image/audio/video paths; no new renderer feature |
| Oneboxes/quotes | Safe cached markup and quote links | Existing supplied cached HTML/topic title/avatar | Fetching, rich remote oneboxing | Existing native cooked renderer; closed sanitizer can reduce richness |
| Spoilers | Shared-owner syntax/classes | Owner activation | None for syntax | **Pre-existing conceal/reveal gap**; emitting classes does not prove concealment |

This is a pure compiler, not a replacement for database/Guardian checks, network enrichment, server moderation, or email delivery. Settings and permission-dependent snapshots must already be authorized by their producer. Missing cache entries intentionally lose enrichment rather than fetching. Current native renderer behavior is not expanded merely because syntax now emits metadata.

## Authoring example

A source behavior can retain state for its owner's later document behavior:

```js
// modules/example-source.js
export function transform(raw, ownerContext, api) {
  if (!ownerContext.settings.enabled) return raw;
  api.state.author = api.context.authorUsername; // only this owner's state
  return raw;
}
```

Register it in `src/modules/catalog.json` with `stage: "source"`, a stable owner/id/version, and an empty final policy. Register a separate document file through that same catalog; it reads `api.state.author` and must escape text before composing HTML. The native owner selects both bundled IDs with `CookingModule`, declares a dependency from the document module to the source module, and projects its own typed settings with `CookingPluginData.read`. Core host code needs no feature import or switch. Syntax callbacks may use `api.context`, read-only `api.lookup(namespace,key)`, and `api.activeFeatures`; setup can register cleanup for trusted per-request library state. `api.cookProfile(name, raw, overrides)` constructs a lazy nested syntax/token parser; `api.policiesForProfile(name)` exposes the reviewed nested policies for a wrapping module's allowlist. This API contains no host resolver or transport.

```dart
final request = cookingHost.request(
  siteUrl: siteUrl,
  raw: '/me **waves**',
  profile: CookingProfile.chat,
  context: const CookingContext(
    authorId: 7,
    editorId: 7,
    authorUsername: 'Alice',
    locale: 'fr',
    timezone: 'Europe/Paris',
    asOfEpochMilliseconds: 1789819200000,
  ),
);
final result = await cookingHost.cook(request);
// A later consumer must still compare identity and reconcile server HTML.
```

## Provenance and verification

Discourse remains pinned to `07a0e7b94717b45207749578df1f0bd2dd4d12e1`; QuickJS-NG remains v0.17.0 at `6d46d07d04041b40f4f49eaa7fdebe44c314c699`. Upstream files remain pristine and individually hashed, including the Chat Ruby rules, TextCleaner, PrettyText cleanup, transcript/inline/date sources, and Unicode interface authority. Adapters are separate source/build inputs. The manifest additionally hashes the build script because it performs the reviewed closure, Moment import, and general nested-option assembly adaptations. Locked npm inputs, full licenses/notices, exact bundle regeneration, and native source verification remain reproducible without the reference checkout.

The shared Chat corpus runs in Node and the actual Dart worker. Installed native owner tests exercise the host/worker/sanitizer chain, account leases, disabled modules, shell cache merging, subfolder links, coexistence with an independent syntax/token/document extension, and zero HTTP clients. The existing widget teardown and real-deadline regressions remain included. See [validation evidence](evidence/milestone-3/README.md) for actual final counts, commands, failures encountered, packaging results, and platform limits.
