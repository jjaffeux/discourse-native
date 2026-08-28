# Plugin architecture

The application installs one immutable `PluginManifest` before creating its
API or shell. The full build uses `bundledPluginManifest`; the core-only build
uses `corePluginManifest` and can be run with `flutter run -t lib/main_core.dart`.

```text
discourse_plugin_api (pure Dart contracts)
        │
        ▼
PluginManifest ──► PluginInstaller ──► InstalledPlugins
                                           │
                       ┌───────────────────┼──────────────────┐
                       ▼                   ▼                  ▼
                 model codec          registry          app lifecycle
                       │                   │                  │
                       ▼                   ▼                  ▼
                 PluginData         typed UI seams     bootstrap/appReady
                                           │
                                           ▼
                                      PluginSession
                                           │
                         typed services + host capabilities + lifecycle
```

## Module contract

A module exposes a stable id/version/dependency descriptor and registers only
the capabilities and lifecycles it owns. Installation validates all module
ids, semantic-version requirements, dependency cycles, record keys, route
namespaces, syntax ids, exclusive claims, and service ownership before the app
uses the graph. Registered route, syntax, and exclusive claims must exactly
match the descriptor, and contributed record and service keys must name that
module as their owner. Registration order is deterministic and dependencies
always precede their consumers. Descriptors and their collections are
snapshotted once before validation, so registration cannot mutate the graph
being installed.

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

The same ownership rule continues after construction. `PluginSession` keeps
the complete service graph private to the host and produces an immutable
`PluginOwnedServices` view for one installed owner. That view rejects every
foreign service key before lookup. A plugin dependency must therefore be
adapted and republished under the consumer's own key during session creation;
UI code cannot walk the session graph.

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

Plugin HTTP contracts and route/payload parsing live beside their feature
(`poll`, `reactions`, `gifs`, and `chat`) and use the shared transport only as a
narrow wire boundary. `DiscourseApi` exposes no typed plugin endpoint.

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

Malformed data in one installed namespace is isolated to that codec and does
not make the connected site unreadable. Once claimed, malformed data is not
re-emitted indefinitely.

## UI extensions

`PluginScope` is a host-only root which carries the installed registry and
private session. It exposes neither the session nor a global service lookup.
Every registry dispatch stamps the contribution owner onto the callback
context and wraps returned widgets in `PluginUiScope`. Plugin widgets resolve
only their owner's keys through `PluginUiScope.require`, `optional`, or
`maybe`; resolving another owner's key fails even when that service is
installed. Late builders—including composer syntax, diagnostics, sidebar
hover and long-press actions, user-menu sections, previews, and nested cooked
widgets—are adapted along with immediately returned widgets.

A standalone `PluginRegistryScope` still supports pure cooked rendering. Its
contributions receive a detached owner view: widgets which need no session
service render normally, while a service request fails instead of falling
through to unrelated application state.

Core owns navigation and cross-feature coordination through narrow host ports;
plugins own their route syntax, typed commands, controllers, optimistic
transforms, and reconciliation. The runtime ports are capability-shaped:

- `PluginRequestHost` returns credentials only for an explicit site request
  and issues a commit-only `PluginSiteLease`; it exposes neither the
  authenticator nor lifecycle invalidation.
- `PluginPostHost` grants Poll and Reactions only post/topic reads, scoped post
  mutation, the shared per-post write lane, and post reconciliation.
- `PluginTargetHost` and `PluginFreshAccountHost` are materialized per
  consumer; target and current-user reads accept only that plugin's
  namespaced record key, while Poll receives only staff/group presentation
  fields in addition to its own current-user record.
- `PluginChannelHost` subscribes to a named plugin channel and returns only a
  cancel handle; tracker start, stop, polling, topic watches, and disposal stay
  host-owned.
- `PluginPreviewHost` gives Chat an immutable list of typed preview adapters
  and a single render callback; owner stamping and the application-wide
  registry stay host-owned.
- Account connection, current-site identity, post-flag catalog, composer
  activity, navigation, emoji, bookmarks, notifications, and presentation are
  separate ports, so receiving one does not imply the others.

Chat and Reactions keep private stores inside their sessions. Poll and
Reactions keep writes, optimistic state, credentials, and lifecycle guards in
their plugin-owned controllers. Assign, Chat, Discourse AI, GIFs, and Resenha
likewise use `PluginRequestHost`; Chat, Discourse AI, and Resenha subscribe
through `PluginChannelHost`. No plugin receives core's `Store`,
`SiteLifecycle`, `SiteTracker`, credential reader, or concrete
`ShellController`.

The registry currently provides typed seams for:

- post/topic records, cooked elements, footers, decorations, metadata, small
  actions, menus, headers, and live invalidation;
- namespaced composer target policies (drafts, uploads, editing, validation,
  mentions, and emoji usage), toolbar actions, shortcuts, lossless syntax
  projections, and optimistic Chat preview syntax;
- ordered user-menu sections, plugin notification feeds, bookmark target
  strategies, and ordered topic recommendation sources;
- sidebar sections, content routes, content chrome, shell header actions, and
  app-global overlays;
- session route handlers, restored-route hydration, channel attachments,
  site/totals observers, bookmark strategies, and background-site ownership.

Shared emoji history is keyed by a namespaced `EmojiUsageContext`; unknown
contexts remain in the persisted document so a temporarily absent plugin does
not lose its reader preferences. Emoji preference hosts are materialized per
plugin and reject foreign or malformed context values; the forum skin-tone
choice intentionally remains shared across pickers. Composer and notification
hosts are also materialized per consumer: foreign composer targets and
foreign, undeclared, or altered feed definitions fail at the host boundary.
Plugin-owned widgets receive narrow services such as composer, emoji,
bookmark, or notification hosts rather than a concrete `ShellController`.
Bookmark mutation services are bound to one registered target type and require
the originating site explicitly, so a sheet that outlives a forum switch
cannot write through the newly selected forum.

The full manifest declares route and syntax ownership up front. Chat and
Resenha own separate route namespaces; Poll and Local Dates declare their
composer syntax ids. Local Dates owns cooked date markup, Chat owns its header
action, and Resenha owns its global call overlay rather than being imported by
core shell widgets.

`plugin_dependency_boundary_test.dart` makes the UI boundary executable. It
rejects plugin imports or exports of `shell_scope.dart` and
`shell_controller.dart`, registry-only owner-stamping and global-scope lookups
from plugin code, and the retired broad credential, store, lifecycle, and
tracker host ports. There is no migration allowlist.

## Remaining shared presentation seams

`NotificationTotals` still carries Chat's total/presence fields and core still
parses notification kinds used by the shared user menu. The user menu, shared
composer limit, upload gate, and Resenha top-level capability query
remain plugin-neutral registry contracts. These are typed shared presentation
models, not escape hatches to shell state: core imports no plugin
implementation or wire key through them, and plugin UI still runs inside its
owner service view.

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
