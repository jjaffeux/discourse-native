# Plugin HTTP transport ownership

`DiscoursePluginTransport` adapts the public SDK's generic HTTP capabilities to
one `DiscourseTransport`. `DiscourseApi` delegates its existing plugin transport
methods to this adapter, just as it delegates core domain operations to domain
clients. Optional feature endpoints and wire parsing remain in their plugin
modules; this adapter contains only shared HTTP and path policy.

The adapter borrows the facade's existing transport. It does not create another
client, coordinator, account session, or disposal lifetime. The facade remains
responsible for closing that transport. Awaited calls retain their ambient
`AccountRequestScope`, and cancellation and request priority continue to be
handled by the shared transport and coordinator.

## Contracts

- Paths resolve from the connected forum's root, including its subfolder prefix.
  A leading slash is accepted; cross-origin destinations and scheme-relative
  paths to another origin are rejected before credentials can be attached.
- Object, list, and text reads retain their existing decoding and failure shapes.
  List reads ignore non-object entries and return an unmodifiable list.
- The established forum search routes retain the configured search timeout.
  Other reads use the transport's ordinary timeout; long-running writes retain
  the caller's explicit timeout.
- Cancellable reads forward their cancellation trigger unchanged. Query POSTs
  and mutations retain separate transport operations and exception contracts.
- Writes are never retried by this adapter. Transport admission, credential
  validation, response limits, redirect checks, and write ambiguity remain owned
  by `DiscourseTransport`.

## Design decision

Leaving these methods on the facade concentrates unrelated policy in its large
endpoint catalogue. Extracting them gives generic plugin HTTP policy one owner
without changing the public facade or any plugin caller. Moving them into
`DiscourseTransport` instead would make the underlying transport depend on SDK
capabilities and forum-relative path conventions. The adapter keeps that
boundary explicit while sharing the existing transport resources.

The facade's forwarding methods remain for API compatibility. New shared HTTP
policy belongs in the adapter or underlying transport according to the contracts
above; optional feature routes and response decoding belong in plugin modules.

## Verification

The existing plugin HTTP, query, text, transport contract, and account request
session tests exercise this path through the public facade. They cover the
adapter's observable behavior without depending on its internal decomposition.
