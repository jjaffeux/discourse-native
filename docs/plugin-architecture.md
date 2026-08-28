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
uses the graph. Registration order is deterministic and dependencies always
precede their consumers.

App startup has idempotent `bootstrap` and `appReady` phases. A failed phase
rolls back every lifecycle already started in reverse order. A shell opens one
session, receives only explicitly declared host ports, and dispatches
foreground, site-forget, and close events with failure isolation.
Session factories receive a restricted binding view containing exactly their
declared ports, so the declaration is an authority boundary rather than only a
startup dependency check.

## Dependency rule

Production core never imports or exports a file under `lib/src/plugins`.
Dependencies point in one direction: plugins may use core and the stable
`lib/src/plugin_api` surface, while core discovers optional behavior through
registries, session capabilities, services, and host ports. Only
`lib/main.dart`, `lib/discourse_full.dart`, and the bundled manifest compose the
full feature set. `plugin_dependency_boundary_test.dart` enforces this rule.

## Data and APIs

Core records hold immutable `PluginData` addressed by stable
`PluginDataKey(owner, name)` values. `DiscourseApi` receives the installed
model codec; core models no longer import the bundled plugin list. Plugin HTTP
contracts and route/payload parsing live beside their feature (`poll`,
`reactions`, `gifs`, and `chat`) and use the shared transport only as a narrow
wire boundary. `DiscourseApi` exposes no typed plugin endpoint.

## UI extensions

`PluginScope` resolves session services by `PluginServiceKey`, independently
of `ShellScope`. Core owns navigation and shared write coordination through
plugin-neutral host APIs; plugins own their route syntax, typed commands,
controllers, optimistic transforms, and bookmark reconciliation.

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
- session route handlers, restored-route hydration, tracker attachments,
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
