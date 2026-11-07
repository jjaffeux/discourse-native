# API domain libraries

`DiscourseApi` composes the application's endpoint capabilities from independent
Dart libraries. Each domain client imports its own models, codec, and transport
contracts. Its private validation and response projections are visible only inside that
domain library, rather than sharing the facade's private namespace.

- `DiscourseAccountApi` owns current-user, notification, bookmark, draft, and
  account-preference endpoint policy.
- `DiscourseComposerApi` owns draft persistence, upload, and post-creation policy.
- `DiscourseSearchApi` owns search and composer lookup policy.
- `DiscourseSiteApi` owns forum discovery, metadata, and taxonomy endpoint policy.
- `DiscourseTopicApi` owns topic reading and mutation endpoint policy.

The facade continues to expose the existing endpoint operations and limits.
It creates one `DiscourseTransport` and lends that same transport and model codec
to the domain clients. Separating libraries does not create new clients,
coordinators, account scopes, or disposal lifetimes. The facade still closes its
transport. The generic plugin HTTP adapter remains a separate library, and
optional feature endpoints stay in their plugin modules.

Domain implementation types are imported from their owning libraries when
needed by direct-client tests. They are no longer accidentally declared by the
facade library. Ordinary application consumers continue using the existing API
contracts and facade. Domain libraries do not import the facade or one another.

The alternative was to keep the files as Dart parts with a shared import list
and private scope. That permits an endpoint in one domain to depend on another
domain's private parser or on facade state without declaring that dependency.
Independent libraries make private ownership enforceable by the compiler and
keep each dependency list local. No additional repository or forwarding layer
is introduced.

All five implementation bodies remain unchanged by this migration. Existing
API, direct-domain, payload, autocomplete, timeout, bookmark, credential, and
transport tests exercise the same endpoints through the new library boundaries.
The account projection tests also retain their isolate-transfer checks.

## Direct transport boundary

Endpoint methods call the borrowed transport directly. Eleven former private
GET, object-GET, and write methods only repeated the transport's arguments;
removing them leaves request admission, credentials, deadlines, decoding and
write ambiguity with their actual transport owner. Domain helpers remain where
they add validation, model projection or endpoint-specific policy.

The transport's credential-header builder is private to its library. The unused
facade alias is removed, so the facade no longer exposes a second way to build
transport headers. Existing endpoint, timeout, upload, credential-session and
transport contract tests exercise these direct calls.
