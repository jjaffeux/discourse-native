# Route page contract

`ContentPageContract.resolve` declares built-in route lifecycle, core URL
admission, retry ownership, preferred search scope and shell heading policy.
It resolves the existing sealed `ContentDestination` and `CorePage` values.
`ContentRouteCodec` remains the only URL and saved-route decoder.

Shell lifecycle callers select a declared `PageLoad`. One private `_loadPage`
adapter calls existing feature owners. It does not own their state, caches or
account leases. Users loading calls the captured `ShellTabContext.loadUsers`,
including its tab-owned query. Mounted About and Group refreshers retain
priority over the fallback loader.

Restoration schedules the root, a distinct retained list source, and the current
document separately. Destination identity determines whether a load is already
covered by the root. Readers retain saved-anchor precedence. Both selected
desktop panels hydrate through their own captured tab contexts. A pathless
Group or extension root can retain its legacy root feed fallback; typed feeds
and messages always use their own identities.

Extensions continue to use the installed homepage, route hydrator and retry
capabilities. Registered homepages skip root feed loading. Current extension
hydration prefers the plugin, with a path-bearing distinct-root fallback.
Refresh preserves its broader forced-feed fallback. Matching a built-in key
does not grant an extension capability ownership of a typed built-in route.

`MainContent` constructs existing widgets from the destination. Host readiness,
retained child identity, page sheets and workspace composition remain in UI.
The contract returns the base shell header policy from platform, connection,
navigation and live plugin title/chrome facts. A topic toolbar can additionally
suppress that header or make it search-only because its eligibility depends on
constructed plugin contributions. The Native page host owns its page title.

`ForumSearch` uses the declared preferred scope. Pages without a preferred
scope can still search. Dynamic extension scopes and contextual search hooks
remain with the plugin registry.

An immutable declaration keeps each page's rules together without capturing a
live controller or tab. A class per page with a generic event protocol added
more interfaces while leaving root/current/source scheduling necessary. Typed
load request wrappers repeated data already carried by the route and context.
The finite loader adapter keeps that boundary smaller.

The route heading characterization covers iOS and desktop Native headers,
including connected and signed-out Bookmarks. Existing tab, feed selection,
plugin chrome, navigation refresh and About panel tests pin lifecycle behavior.
