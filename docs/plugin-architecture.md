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
                                  typed services + lifecycle
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

## Data and APIs

Core records hold immutable `PluginData` addressed by stable
`PluginDataKey(owner, name)` values. `DiscourseApi` receives the installed
model codec; core models no longer import the bundled plugin list. Plugin HTTP
contracts and route/payload parsing live beside their feature (`poll`,
`reactions`, `gifs`, and `chat`) and use the shared transport only as a narrow
wire boundary.

## UI extensions

`PluginScope` resolves session services by `PluginServiceKey`, independently
of `ShellScope`. Core still owns navigation and shared presentation commands,
while plugin widgets obtain their own controllers through the plugin scope.

The registry currently provides typed seams for:

- post/topic records, cooked elements, footers, decorations, metadata, small
  actions, menus, headers, and live invalidation;
- composer toolbar actions and optimistic Chat preview syntax;
- sidebar sections, content routes, content chrome, shell header actions, and
  app-global overlays.

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
