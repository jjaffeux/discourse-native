# Account request sessions

## Problem and existing ownership

`SiteLease` guards publication into one account generation. `AccountSessionCoordinator` owns durable connect, disconnect, rollback, and revocation. Before this change, retiring a lease left queued HTTP work alive. Raw credential reads also needed manual lease checks at every await.

An ordinary request now starts with a credential capability captured under its original lease. The capability checks that lease before and after private credential reads. `run` carries the same identity through domain API methods to transport admission. The transport validates the destination and explicit credential arguments against that snapshot. It does not log the snapshot.

## Caller usage

```dart
final lease = lifecycle.capture(siteUrl);
final snapshot = await AccountRequestSession(siteUrl, lease)
    .credentials(credentials);
final payload = await snapshot.run(() => api.topicContent.topic(
  siteUrl: siteUrl,
  slug: slug,
  id: topicId,
  apiKey: snapshot.apiKey,
  clientId: snapshot.clientId,
));
lease.commit(() => publish(payload));
```

Plugin callers use `PluginRequestCredentials.run`. The shell creates its executor from the same credential capability. Plugins retain their existing HTTP capabilities and do not receive the authenticator or lifecycle implementation.

## Shape and acceptance contract

`SiteLifecycle` owns each generation and its detachable retirement observers. The map loses the old generation before observers run. Completed requests detach, so an account does not retain every completed request until sign-out. `AccountRequestSession` checks credential acquisition. Its immutable `AccountRequestCredentials` creates an independent scope for each `run` operation. Each run installs an internal `AccountRequestScope` in a child Dart Zone. The transport is the only consumer of that Zone value. It preserves the caller's diagnostics Zone.

`DiscourseRequestCoordinator` owns one physical GET exchange and a separate waiter per caller. Its key includes URL, normalized headers, response limit, timeout, and session generation. Per-caller cancellation removes only that waiter. The last departing waiter removes the exchange from the sharing map before aborting HTTP. A successor generation cannot join an abandoned or previous-generation exchange, even when credentials are identical.

Safe GET/HEAD retirement withdraws queued work and signals active HTTP cancellation. The caller abandons a shared GET promptly even if a platform HTTP client cannot stop the physical exchange. Existing HTTP deadlines still bound that exchange. A response body is cancelled where the client supports it. Each redirect is checked again before credentials can follow it.

Writes have three meaningful outcomes. A queued request removed before its send callback reports `DiscourseQueuedRequestCancelledException`, which maps to `WriteException.notSent`. A dispatched request keeps its successful response or definitive server refusal. A dispatched request that loses its response retains `notSent == false` unless the existing connection checks prove no request was sent. Retirement does not abort a dispatched write, retry it, or assert that its effects were undone. Explicit upload cancellation keeps its existing behavior.

Account revocation explicitly leaves an ambient request scope. It remains available after retirement and retains the coordinator's compensation and durability policy. Publication and optimistic rollback still require their existing lease guards.

## Synthesis decision and alternatives

Two independent candidates compared an explicit request argument across domain signatures with a narrow execution context. An independent cross-judge recommended the context after adding generation identity to GET keys and a concrete queued-write outcome. The explicit design's credential acquisition checks and generation isolation were retained. A public request parameter on every endpoint would require broad API and plugin adapter churn for the same transport policy. A mutable transport-wide current account was rejected because simultaneous sites and generations must remain independent.

This design follows Model the Domain by representing a shared exchange and its waiter owners separately. It accepts one internal Zone dependency to keep endpoint APIs small. The explicit `run` capability marks the request boundary and must wrap awaited API operations, without launching detached work.

## Migration and reconciliation

Ordinary shell and controller API operations retain the capability through their awaited request. This includes post paging and mutations, current-user and sidebar requests, category/tag knowledge, account activity, feeds, searches, preferences, directories, invites, presentation metadata and composer draft persistence. Callback-based operations acquire or retain their capability at the owner that dispatches HTTP. Category hydration acquires credentials only for an owned nonempty HTTP batch; cached categories and followers of an existing lookup do not read private storage. Publication, optimistic rollback, request revisions and reconciliation remain with those owners.

`keyCredentials(SiteApiKeyReader)` captures endpoints that previously omitted the client ID. It checks the original lease before and after the key read and never reads a client ID. `anonymousCredentials()` captures deliberately public work without consulting private storage. Existing `credentials(ApiCredentialReader)` retains the full key/client-ID policy. Endpoint headers must match the selected capability, including a nonempty migration client ID.

Plugin helpers retain `PluginRequestCredentials` rather than rebuilding raw key/client-ID records. `PluginWriteCredential` carries a key-only request capability or the existing write refusal. Ordinary Chat, Voice, Assign, GIF, Events, Poll, Solved, Reactions and AI proofreading requests execute through their retained capability. Calendar export scopes its HTTP read before local save/share work. Already adopted AI summary/conversation and reaction reactor requests use the same boundary.

Draft persistence keeps its local-first recovery, per-draft serialization and original operation leases. The draft `owner` is payload identity and remains a separate client-ID read. Draft HTTP keeps its existing key-only header policy.

`SiteAppearanceLoader` has a separate HTTP sender. Its forum metadata and document requests explicitly retain the request scope, generation-specific GET identity and independent waiter cancellation. Early metadata failure cancels and drains the concurrent document request before its enclosing scope ends. The loader validates the captured site and credential arguments at entry, then validates headers and currentness at each hop. Its existing redirect policy permits public anonymous canonical redirects and rejects authenticated cross-origin redirects. Ordinary transport retains strict origin validation. Discovered CSS and CDN requests keep their credential-free transfer policy.

The explicit exceptions are durable account establishment/revocation, pre-account public discovery, long-lived MessageBus sessions, native media and image/video/download transfers with their own redirect and teardown policies. Voice leave, join compensation, signal batching and LiveKit credential refresh retain their call-resource lifetime. A dispatched join can still complete and require compensation after account retirement. These exceptions do not authorize ordinary one-shot API work to discard its capability.

The implementation uses detachable observers rather than a permanent retirement future on every lease. This was accepted by the design cross-judge to avoid retaining completed requests. Existing `WriteException.notSent` carries the write outcome instead of adding another parallel result type. Account transactions remain unchanged except their explicit unscoped revocation call. Request priority and dispatch fairness remain owned by the scheduler. Each waiter joins the existing `RequestIntentGroup`, and the gate continues to resolve that group at admission. Cancellation removes its intent source only after the last waiter using that source leaves. This prevents a departed interactive consumer from promoting background work. An interactive joiner promotes its exchange without promoting sibling work, including when its original background waiter cancels.

Focused tests exercise credential races, key-only and anonymous acquisition, withdrawal from a bounded queue, response-body cancellation, starter and joiner cancellation, successor isolation, write outcomes, plugin adoption, draft payload identity, appearance metadata/CDN behavior and existing account rollback. They use controlled HTTP clients and explicit test paths. No performance improvement is claimed.
