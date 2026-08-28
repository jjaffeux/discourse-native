# Plugin architecture

The application installs one immutable `PluginManifest` before creating its
API or shell. The full build uses `bundledPluginManifest`; the core-only build
uses `corePluginManifest` and can be run with `flutter run -t lib/main_core.dart`.

```text
discourse_plugin_api (pure Dart contracts)
        │
        ▼
PluginManifest ──► PluginInstaller ──► InstalledPlugins
                                           ├── model codec ────► PluginData
                                           ├── static catalog ──► typed extension points
                                           ├── registry ────────► typed UI seams
                                           ├── app lifecycle ───► bootstrap / appReady
                                           └── openSession(...) ─► PluginSession
                                                                   │
                                         typed services + host capabilities + lifecycle
```

## Module contract

A module exposes a stable id/version/dependency descriptor and registers only
the capabilities and lifecycles it owns. Installation validates all module
ids, semantic-version requirements, dependency cycles, record keys, route
namespaces, syntax ids, exclusive claims, static contribution points, and
service ownership before the app uses the graph. Registered route, syntax, and
exclusive claims must exactly match the descriptor, and contributed record,
service, syntax, and static-point keys must name their module as their owner.
Singleton and exclusive ownership is rejected deterministically during
installation rather than discovered while rendering. Registration order is
deterministic and runtime dependencies always precede their consumers.
Descriptors and their collections are snapshotted once before validation, so
registration cannot mutate the graph being installed.

Static contribution targets are a separate authority from runtime service
dependencies. They let one module contribute an immutable typed value to a
point owned by another module without changing session startup order or
granting access to that module's services. Optional targets become dormant when
their owner is absent. The installed, owner-scoped catalog preserves manifest
order and validates point ownership, value type, contribution ids, and
cardinality before any session is opened.

App startup has idempotent `bootstrap` and `appReady` phases. A failed phase
rolls back every lifecycle already started in reverse order. A shell opens one
session, receives only explicitly declared host ports, and dispatches
foreground, site-forget, and close events with failure isolation. Session
teardown awaits each module in reverse dependency order.

Session factories receive a restricted binding view containing exactly their
declared ports, so the declaration is an authority boundary rather than only a
startup dependency check. Consumer-scoped ports materialize a facade for the
calling module before its factory runs, so a plugin cannot recover another
module's authority from the binding view.

Session factories receive an immutable service snapshot containing only
already-created modules named in their descriptor dependencies. `require`
fails for a missing dependency service; `maybe` returns null for a declared
optional integration that is absent. Both reject undeclared owners, so this
boundary cannot become a global service locator.

Cross-plugin imports stop at an owner-provided contract file. A consumer never
receives another feature's full API client, controller, credentials, settings,
or lifecycle machinery merely to reuse one operation. Dependencies are
required only when the consumer cannot function without that capability;
optional integrations must define and test their absent-provider behavior.

## Dependency rule

Production core never imports or exports a file under `lib/src/plugins`.
Dependencies point in one direction: plugins may use core and the stable
`lib/src/plugin_api` surface, while core discovers optional behavior through
registries, session capabilities, services, and host ports. Only
`lib/main.dart`, `lib/discourse_full.dart`, and the bundled manifest compose the
full feature set. Every bundled feature owns a production module and its
service keys under `lib/src/plugins/<feature>/`; the bundled manifest imports
only those module entrypoints. `plugin_dependency_boundary_test.dart` enforces
this rule.

## Data and APIs

Core records hold immutable `PluginData` addressed by stable
`PluginDataKey(owner, name)` values. `DiscourseApi` receives the installed
model codec; `SiteConfig` and `DiscourseUser` contain only core fields plus that
opaque bag. Installed `SiteSettingsPlugin<T>` and `CurrentUserPlugin<T>`
readers own their feature's wire keys and defaults. Poll, Assign, Chat,
Reactions, GIFs, Local Dates, and Resenha therefore decode only when their
modules are in the selected manifest. A core-only manifest ignores those live
schemas rather than silently growing optional model fields.

Chat's current-user value also owns `ignored_users`. Core retains no ignored
user field; Chat decodes and persists the usernames it uses to suppress unread
state for messages from ignored authors.

Notification totals use a parallel open registry. A
`PluginNotificationCounter` declares a stable `PluginId`/local-name identity,
the feature-owned wire field, and whether an available value contributes to
the global badge. Core retains the typed count and presence separately: zero
is an available count, while an absent wire field keeps the feature
unavailable. Chat owns the `chat/notifications` declaration and every use of
`chat_notifications`; the shared API only asks the installed model codec to
decode the response.

Notification rows are open at the wire boundary too. Core retains the exact
numeric type id, an optional type name only when the response supplied one,
the complete immutable envelope, and the type-owned `data` map. Response ids
and request filter names are separate value types because Discourse normally
sends only the former and accepts only the latter; neither is collapsed to an
`unknown` enum member. A `PluginNotificationType` pairs the known wire values
with a namespaced owner and the owner's payload decoder. That decoder owns its
payload keys, route, wording, actor policy, and icon. Chat, Assign, and
Reactions register their definitions beside their modules. If an owner is not
installed, or its decoder rejects malformed data, core still renders a bell
and the row title and follows only a topic route derivable from stable envelope
fields. The fallback reads only the top-level `fancy_title`; a type-owned
`data.topic_title` remains opaque until a registered owner decodes it. The
shared API therefore parses and filters open values without importing any
feature implementation.

Plugin HTTP contracts and route/payload parsing live beside their feature
(`poll`, `reactions`, `gifs`, and `chat`) and use the shared transport only as a
narrow wire boundary. `DiscourseApi` exposes no typed plugin endpoint.

Topic recommendation sources are a sibling resource, not values in a topic's
`PluginData`. Their catalog and decoder therefore use a separate
`TopicRecommendationSourceCodec` seam. Core recognizes only
`suggested_topics`; each optional source recognizes and normalizes its own
payload into the shared recommendation-topic row shape before core constructs
`Topic` values. Absence remains distinct from a present, empty source.

GIFs exposes one picker session rather than its wire API. That session owns the
API client, credentials, lifecycle lease, settings lookup, and catalog/picker
assembly; topic and Chat composers receive only availability and a selected
GIF. Chat similarly exposes an embedded thread-conversation capability. It
owns paging, sending, read receipts, timeline merging, and live subscriptions,
while Resenha retains only its room-to-thread association and room UI. The
viewing handle is released when that UI closes and pruned when its room leaves
the directory, so hidden rooms retain no Chat subscription or read receipt.

## Persistence and compatibility

The instance snapshot stores plugin values under a `plugins` object keyed by
the stable `owner/name` id. Each settings/current-user reader also registers a
`PluginDataPersistenceCodec<T>` which owns that namespace and the migration
from its pre-codec flat fields. `InstanceStore` uses the same installed model
codec as `DiscourseApi`, so live and stored data cannot disagree about which
manifest is active.

On load, installed codecs claim and type their namespaces. Every unclaimed
JSON namespace remains opaque in `PluginData` and is emitted unchanged on the
next save. This makes a snapshot safe to open and rewrite with a core-only or
otherwise smaller build. A successful live settings/current-user refresh
replaces installed typed values while carrying those opaque namespaces
forward; current-user data is carried only when the stable user id still
matches (with a case-insensitive username fallback for legacy snapshots that
lack ids), so a rename retains data but another account cannot inherit it.
Migration from the old flat snapshot fields requires the owning module to be
installed: a smaller manifest deliberately has no schema with which to claim
those legacy keys. Once data has been written under `plugins`, every manifest
can preserve it losslessly without decoding it.

The remembered recommendation tab follows the same ownership rule. Core
accepts stable namespaced source ids and migrates only its old `suggested`
value. Optional source codecs declare their own pre-stable aliases; the
validated registry rejects whitespace, namespaced aliases, duplicate claims,
and attempts to claim core's alias. Thus `related` becomes
`discourse-ai/related` only while the Discourse AI codec is installed.

Persistence codecs receive both their namespaced value and the complete stored
record for migrations which span schema generations. Chat uses this hook for
the transition where a snapshot already has `chat/current-user` but still
stores `ignoredUsernames` at the account root. The first save with Chat
installed folds that list into the namespace and removes the flat field.

Malformed data in one installed namespace is isolated to that codec and does
not make the connected site unreadable. Once claimed, malformed data is not
re-emitted indefinitely.

The last account totals are part of `DiscourseInstance` and restore before the
first network refresh. Plugin counters are stored under the totals `plugins`
object by their stable `owner/name` identity. Unknown namespaces retain their
opaque JSON through a core-only load/save; reinstalling the owner claims the
same value again. Installed unavailable counters are omitted rather than
turning absence into a synthetic zero. HTTP refresh presence is authoritative,
while a count changed by a live event during the request remains live. Every
changed accepted refresh or event is written through the instance store's
coalescing snapshot writer.

Totals snapshots are account-bound as well as site-bound. If the live
current-user id does not match the stored account, the shell clears the warm
totals and cancels the previous account's in-flight totals request before it
publishes and persists the replacement user.

## UI extensions

`PluginScope` resolves required session services by `PluginServiceKey` and
exposes `maybeService` for genuinely optional UI integrations, independently
of `ShellScope`. Core owns navigation and shared write coordination through
plugin-neutral host APIs; plugins own their route syntax, typed commands,
controllers, optimistic transforms, and bookmark reconciliation.

The registry currently provides typed seams for:

- post/topic records, cooked elements, footers, decorations, metadata, small
  actions, menus, headers, and live invalidation;
- registered hashtag kinds, including their server wire type and shared cooked
  and composer presentation policy;
- namespaced composer target policies (drafts, uploads, editing, validation,
  mentions, and emoji usage), toolbar actions, shortcuts, and lossless
  namespaced syntax projections;
- ordered user-menu sections, plugin notification type definitions and feeds,
  bookmark target strategies, and ordered owner-decoded topic recommendation
  sources;
- sidebar sections, content routes, content chrome, shell header actions, and
  app-global overlays;
- owner-local icon catalogs for optional artwork and semantic aliases, with a
  required generic fallback for unknown or uninstalled names; shared wire
  readers receive this resolver explicitly, so an installed owner alias works
  without returning that alias to core's generated icon table;
- session route handlers, restored-route hydration, tracker attachments,
  site/totals observers, bookmark strategies, and background-site ownership.

Shared emoji history is keyed by a namespaced `EmojiUsageContext`; unknown
contexts remain in the persisted document so a temporarily absent plugin does
not lose its reader preferences. Emoji preference hosts are materialized per
plugin and reject foreign or malformed context values; the forum skin-tone
choice intentionally remains shared across pickers. Composer and notification
hosts are also materialized per consumer: foreign composer targets and
foreign, undeclared, or altered feed definitions fail at the host boundary.
Notification type installation rejects duplicate numeric ids, duplicate wire
names, and definitions outside the contributing plugin's namespace; a
filtered feed may name only types registered by that same owner.
The account-events host is likewise scoped to its consumer: a plugin may
update only a notification counter registered to its own id, and receives a
count reducer rather than authority to replace core totals.
Plugin-owned widgets receive narrow services such as composer, emoji,
bookmark, or notification hosts rather than a concrete `ShellController`.
Bookmark mutation services are bound to one registered target type and require
the originating site explicitly, so a sheet that outlives a forum switch
cannot write through the newly selected forum. Core post/topic actions bind a
real topic context; the separate plugin bookmark host exposes only its opaque,
owner-scoped target context. Shared reminder UI adapts those two contracts and
never invents a sentinel topic id for a plugin record.

Sidebar destinations likewise carry only generic presentation and navigation
state. Optional owners may contribute prefix and label-suffix builders that
watch their own live records; Chat uses those hooks for presence avatars and
user status. Resenha contributes its indented participant rows directly in
its section, so the core DTO has no Chat-user or voice-room child fields.

Hashtag kinds are an open registry rather than a core enum. Core owns the
`category` and `tag` definitions and a neutral fallback for a wire type no
installed plugin recognizes. A plugin definition owns its type's default
style, icon, emoji, and colour policy; the same resolved presentation is used
for cooked HTML, composer suggestion rows, and the composer's lossless pill
projection. Consequently, a confirmed or cooked hashtag from an absent or
newer plugin keeps its label, link, and opaque type instead of being rejected
or silently presented as a tag.

The registered kinds themselves extend the deterministic composer type order;
search and exact-ref lookup consume that same order. Recognition therefore
cannot race a plugin's asynchronously loaded per-site state, and a type cannot
appear in autocomplete while being unavailable to the lookup which turns
hand-written composer text into the same presentation. A server without an
installed kind's data source simply filters that type from its answer. Cooked
hashtag navigation remains ordinary link navigation: `openLink` first offers
the URL to registered `PluginLinkHandler`s, then falls back to core routes and
safe external navigation. Resenha therefore owns the `room` wire type, its
microphone presentation, and its room-link handler; core contains none of that
feature vocabulary.

Each composer resolves stable per-composer syntax policies from its installed
contributions. A policy owns its feature configuration, parser, validation,
projection state, and lossless source projection; core only supplies a narrow
editor host for guarded document edits. Poll option limits and permissions and
Local Dates timezone/configuration therefore never appear in the generic
composer API. Target policies likewise own upload permission, including Chat's
policy, instead of passing an `isChat` boolean through a global upload gate.

Chat's provisional preview document, projector, renderers, and trusted GIF
seed are all Chat-owned. Other modules extend that preview through Chat's typed
static contribution point. Core sees only the generic owner-scoped catalog and
cannot construct or interpret a Chat preview node. Chat also turns a selected
transcript into a generic composer seed; core owns only the route-safe
open-new-topic operation and has no transcript semantics or wording.

The full manifest declares route and namespaced syntax ownership up front. Chat
and Resenha own separate route namespaces; Poll and Local Dates declare syntax
kinds under their own module ids. Local Dates owns cooked date markup, Chat
owns its header action and preview contribution point, and Resenha owns its
global call overlay rather than being imported by core shell widgets. Optional
AI, GIF, and Poll artwork lives beside those plugins; core's generated icon
catalog no longer embeds it, and Chat owns the `d-chat` alias it contributes to
Discourse's wire vocabulary. Core flag models likewise expose only a generic
target predicate; Chat owns the `Chat::Message` target constant used by its
flag and bookmark paths.

Reaction pills and reactor lists use plugin-neutral presentation contracts.
Chat and Reactions each own their wire model, cache identity, controller, and
writes; neither constructs the other's post- or message-specific types merely
to draw the shared UI.

GitHub oneboxes declare Local Dates as optional and ask its cooked-time parser
for an instant. They no longer recognize `.discourse-local-date` or interpret
its attributes themselves. Without that service the GitHub card, author,
labels, and diff metadata still render; only relative-time metadata is omitted.

## Deferred UI contribution seams

The user menu and Resenha top-level capability remain plugin-neutral registry
interfaces. Moving those remaining surfaces to full UI contributions is
intentionally deferred; core does not import a plugin type or wire key through
these compatibility seams.

## Build profiles

- `lib/discourse_core.dart` exports the public core/runtime surface.
- `lib/discourse_full.dart` adds the bundled manifest.
- `lib/main.dart` launches the full profile.
- `lib/main_core.dart` launches the empty optional-plugin profile.
- `packages/discourse_plugin_api` is a pure-Dart package containing the stable
  manifest, lifecycle, host-port, and service-key contracts.

Native feature SDKs remain behind the Resenha module and are initialized only
when that module is present in the chosen manifest. The core-profile regression
test verifies that the shell can load and mount with no optional services.
