# Milestone 4: local Chat cooking

Chat uses the bundled Discourse engine for prepared drafts and provisional sent/edited messages. The normal send/edit requests remain independent; no cooking, preview, onebox, or lookup endpoint is called by this pipeline. Server-confirmed HTML remains authoritative, including an empty body.

## Ownership and scheduling

`ChatModule` requires the shared core cooking and timezone ports. Shell owns runtime prewarm/disposal. Chat owns two small collaborators:

- `ChatCookingCoordinator` keeps one physical cook active, coalesces draft work before context/snapshot assembly, and gives submitted sends/edits priority. Drafts debounce for 40 ms. There are at most 16 queued jobs; overflow evicts the oldest queued draft or declines new work if every queued job is urgent. Cancelling the consumer never falsely frees an occupied worker slot.
- `ChatPreparedCooking` owns exact source revisions, original host requests, subscriptions and prepared HTML. Its limits are 32 draft entries, 2 MiB of UTF-8 prepared HTML and 32 submitted jobs. Repeated text/controller notifications coalesce. A → B → A has a new identity. Drafts are shared by channel/thread presentations; each editor has a separate presentation/message identity, so closing one cannot cancel another editor of the same message.

Closing the last normal composer suspends draft work while retaining its source and any ready HTML. Reopening resumes it. Source changes, account retirement, eviction and disposal cancel ownership and subscriptions. Closing an edit cancels only unsent preparation, so an already submitted edit retains its independent lifetime.

## Instant staging and canonical reconciliation

Sending synchronously inserts the negative-ID row. If an exact current prepared result exists it is used immediately; otherwise readable source is shown while urgent cooking is scheduled on a microtask. Snapshot assembly and worker startup do not run on the staging stack. The existing per-stream FIFO send coordinator and cross-stream transport concurrency remain intact.

`ChatMessage.provisionalCooked` is distinct from canonical `cooked`. Both enter the existing Native `CookedHtml` with the same site, styles, selection and plugin reader configuration. Ordinary production messages no longer use the legacy preview parser. The validated GIF picker seed remains an immediate interim presentation until the bundled pipeline's sanitized output arrives. Compatibility preview APIs remain available for existing embedders without a cooking host.

Submitted results must still own their message token, account lease, source, target membership and locale revision. Results cannot recreate retired rows or overwrite a canonical body. Content-only rollback restores failed edits while preserving concurrent reactions/bookmarks/pins and any newer canonical edit. Transport failure and cooking failure are independent.

Uploads stay in `upload_ids` and `ChatUploads`. They are not appended to raw source or rendered a second time through cooking. Empty provisional HTML suppresses source fallback while preserving separate attachments.

## Context changes

Requests capture author/editor identity, locale, resolved reader timezone, a single as-of time, Chat profile and submission source policy. The original host request is passed to `cook`; no reconstruction loses its preflight verdict.

The generic host adds `isCurrent(request)` and `watch(siteUrl, raw, onChanged)`. Currentness compares lightweight epochs and cached identities, without rebuilding/fingerprinting a snapshot or advancing its clock. Subscriptions cover site/plugin settings, custom emoji, account identity, device timezone, accepted metadata/upload ingestion and bounded referenced user/topic records. Notifications are deferred/coalesced and unsubscribe cancels pending delivery. Entity generations conservatively invalidate any same-site cached user/topic change; active notifications subscribe only to the selected records.

Failures or stale results retain readable content. A changed locale during a submitted cook drops that old result; eventual canonical HTML still settles the message. No new backend fallback is introduced.

## Validation and limits

See `evidence/milestone-4/coordinator-review.md` for final checks and measured latency. Native compilation and renderer coverage are separate: emitted HTML does not imply support for every upstream interaction. Milestone 5 covers the remaining consumers/plugin behavior and records renderer exclusions.
