# Offline cooking milestone 5

This milestone completes the bundled post dialect and the Native reader handling needed for the supported plugin markup. Chat's existing optimistic send/edit integration remains the application consumer. Post cooking is available through the shared host's `post` profile. No composer preview control or panel is added; creating topics and replies still waits for the normal server response before inserting a canonical post.

## Behavior ownership

| Module | Native owner | Activation | Result |
| --- | --- | --- | --- |
| `details` | `cooking` | Post | Pinned details syntax; explicit open state; existing Native details renderer |
| `d-wrap` | `cooking` | Post | Core parser with a finite placeholder attribute policy |
| `poll` | `poll` | Post; `poll_enabled` | Pinned numeric/list/title poll syntax and UTF-8 JSON MD5 option identifiers |
| `post-event` | `discourse-events` | Post; both event switches | Event definitions and reviewed metadata |
| `calendar` | `discourse-events` | Post; base Events switch | Calendar blocks and group-timezone markers |
| `livestream-preview` | `discourse-events` | Post; base Events switch | Pinned `[preview]`/`[hidden]` syntax |
| `livestream-visibility` | `discourse-events` | Post; depends on livestream syntax | Removes concealed content after cached HTML restoration |

Each behavior has a separate adapter and catalog entry. Vendor files remain byte-identical to Discourse `07a0e7b94717b45207749578df1f0bd2dd4d12e1`; source hashes, notices and the generated bundle are checked together. Poll's embedded MD5 attribution is included in package distribution notices. Post-only modules do not become Chat features, including inside nested Chat transcripts. Literal code and Chat examples retain their source syntax, while actual hidden HTML descendants are removed even inside those wrappers.

Poll enablement now survives settings persistence and gates its existing authoring actions. Older stored records without the flag retain the prior enabled default. Events persist independent base and Post Event switches; the existing `.enabled` accessor still means both are enabled. Old persisted records that already lost the distinction need the ordinary settings refresh to recover calendar-only configuration; cooking does not initiate that refresh.

## Native rendering

`CookedHtml` conceals spoiler descendants behind the existing Native accordion. Closed content has no mounted media, selection text or accessibility text. Nested spoilers reveal independently; replacing the source resets disclosure state. Inline spoilers use the disclosure layout, so layout differs from the web app's inline blur. Outer lightbox galleries exclude hidden and disclosure descendants; revealed bodies own their own galleries. Plain details summaries replace concealed spoiler text with a label instead of flattening it into the trigger.

Poll fragments use the existing read-only poll card. Cooked definitions do not create vote totals or voting authority; authoritative post records still select the existing interactive renderer. Poll title, option and ranked-result accessibility labels preserve concealment. Revealing a choice disclosure is independent of selecting that choice. The existing bare Native radio activates through its painted indicator and keyboard, but its blank surrounding area does not activate; this UI kit limitation is unchanged. Event and calendar fallbacks render their descendant HTML through `CookedHtml` without a fabricated `Post`, preserving spoilers and nested plugin rendering without triggering record hydration. Existing Native details, Local Dates, Mermaid and placeholder renderers continue to own their widgets.

Attendance state and group-member timezone snapshots are not available in the immutable cooking context. Livestream hidden content is suppressed; preview content remains readable. Group-timezone markers show an explicit unavailable-data fallback. Neither path fetches missing records or infers access from markup. These are renderer limitations, not claims of complete web interaction parity.

## Extension and upgrade contract

The full example in [milestone 2](milestone-2.md#small-complete-extension-example) remains the authoring contract: add a behavior source and catalog entry, register its versioned `CookingModule` in its owning Native `CookingPlugin`, project only that owner's finite cached JSON settings, and rebuild the trusted bundle. Source, syntax, token and document stages retain deterministic ordering and profile/dependency checks. Add shared Node/native fixtures and a Native renderer test when introducing new markup.

Ruby hooks are not loaded or executed on the client. Pure transformations need bundled portable equivalents; database lookups, authorization, remote oneboxing and arbitrary Ruby plugins remain server-owned. A server setting can select bundled behavior but cannot supply executable code. The final sanitizer runs after all behavior transforms and cached HTML restoration, with reviewed tag/attribute additions only. New `details[open]` is confined to details; event URL/image metadata passes normalized URL checks.

Tests and final results are recorded in [the coordinator evidence](evidence/milestone-5/coordinator-review.md). The consolidated [implementation report](implementation-report.md) records all five milestones, merge points and remaining limits.
