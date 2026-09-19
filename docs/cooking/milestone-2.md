# Offline cooking milestone 2

This milestone adds shared compiler configuration, native plugin contribution contracts, immutable request identity and a session-owned cooking service. Chat/message rendering and topic/composer rendering do not consume the service yet. Normal server cooked HTML remains canonical; local results are provisional.

## Request identity and immutable context

`CookingProfile` describes parser features, rules, scalar settings and quote-link behavior. The built-in `post` and `chat` profiles preserve milestone 1 behavior. `CookingConfiguration` snapshots and validates installed profiles and bundled module selections before work reaches a worker. Module dependencies determine ordering, with explicit order and stable IDs resolving independent contributions.

`CookingRequest` contains source, profile, configuration and an immutable `CookingSnapshot`. Snapshot fields include site/account identity, account generation, setting provenance, core settings, owner-projected plugin context and cached metadata. No `PluginData` container, callback, credential, transport or mutable service enters the worker. Unknown plugin records remain opaque to the host; the owning contributor reads only its namespace and returns finite JSON.

SHA-256 fingerprints use canonical JSON with sorted map keys. Context identity covers the complete snapshot, selected profile and configuration, bundled compiler hash and pinned native engine identity. Source identity combines the context fingerprint with the source. Results carry both identities, typed diagnostics and unresolved-reference information, alongside the existing readable fallback and provisional flag. A consumer must compare the returned request fingerprint with its current draft request before displaying an asynchronous completion. Rejected oversized source deliberately has no fingerprint, avoiding unbounded hashing before the input limit; it cannot qualify as a matching draft result.

## Application ownership and cache

`CookingHostService` owns `OfflineCookingService` through `CookingRuntimePort`. `CookingServicePort` supplies prewarm, cook, invalidation and disposal for the application/session adapter. There is no HTTP facility in either port.

The default cache retains at most 64 successful results and 2 MiB of serialized result/key data, using least-recently-used eviction. At most four unique requests occupy runtime slots. Identical inflight requests share a future; cache identity includes site, account generation, configuration and metadata, never only raw source or Dart object identity. Fallbacks are not cached. An invalidation clears cache entries and immediately resolves pending callers with a typed stale fallback. Stale work keeps its admission slot until it actually settles and cannot write the cache, bounding repeated account-change races.

Startup, transport and watchdog failures retire a service instance. Later demand may construct a replacement after a two-second cooldown, doubling to a maximum of one minute after repeated failures. There is no timer-driven retry and no automatic retry of the failed request. Successful work resets backoff. Ordinary per-cook engine failures replace the VM inside the worker. Disposal is idempotent, rejects pending callers, awaits startup/disposal and prevents new workers. Startup, transport and shutdown watchdogs use owned wall-clock timers independent of widget/client-zone clocks; result/error delivery stays in the caller zone. The original timeout bounds and termination paths remain intact, and every settled operation cancels its deadline.

The shell constructs `ApplicationCooking`, prewarms during session setup and disposes during teardown. Account changes invalidate cooking state. `corePluginCookingPort` supplies a narrow `PluginCookingHost` to consumers that declare that host port; it exposes request assembly and guarded cooking without runtime lifecycle authority. `ShellController.cookingRequest` uses the same assembly path.

Snapshot assembly uses already-cached presentation metadata and core `SiteConfig` values without invoking composer resolvers or issuing requests. It selects source-relevant metadata in deterministic key order, at most 128 entries and 32 KiB per dictionary (8 KiB per entry); omitted metadata stays unresolved/readable. Known hashtag IDs, style, emoji and icon survive the final policy. Oversized raw source bypasses metadata/projector work before reaching the service input-limit fallback.

Later upload consumers call `captureUploads(siteUrl, accountId)` before asynchronous work and `ingestUploads(lease, snapshot)` on completion. The lease is bound to this host, account and generation; late ingestion after replacement/forget/disposal returns false. Upload ingestion does not perform a lookup. `ApplicationCooking.cook` also rejects a captured request whose account/generation no longer matches, including requests submitted after invalidation.

## Settings persistence

Core cooking settings are decoded from the existing site initialization response and persist with ordinary site configuration. `cookingSettings` exposes wire-key values; `cookingKnownSettings` records fields actually supplied with valid values, and `cookingSettingsStale` preserves freshness separately from defaults. Cold defaults remain usable without claiming known server values. Serialization, copies, plugin-data replacement and equality include the cooking values and provenance. Installed plugin owners project their own settings; core does not decode optional plugin fields.

## Bundled feature authoring

Behavior code is trusted application code compiled into the pinned JS bundle. Registration selects module IDs and versions; it never accepts source text, remote URLs or server-supplied executable code. A module has one source file and an assembly catalog entry. The build generates imports from that catalog, so adding a behavior requires no hardcoded entrypoint import or central feature switch. The generated Dart catalog rejects missing/incompatible selections at configuration time; build validation rejects malformed module declarations or missing exports. The native registrar freezes each owner, declaration getter result and projector once while preserving the original capability for other interfaces such as `SiteSettingsPlugin`. Host configuration uses the separate frozen records. The installed `cooking` module registers the application adapters; the deliberately empty core-only manifest has no cooking modules.

Stages are explicit: syntax registers parser behavior, token transforms operate on parsed tokens, and document transforms operate on cooked HTML. Each stage receives only its owning plugin's projected context. Native widgets and rendering remain outside these modules. Module activation can be scoped to profiles and an owner-projected enabled setting.

The final sanitizer runs after every stage and after upstream cached HTML hoists. Feature policy declarations can add reviewed safe tags/attributes. They cannot admit scripts, event handlers, style, executable URI schemes or bypass sanitation. Policy declarations are bundled build inputs, not values accepted from messages or server settings.

The fixture feature sources under `packages/discourse_cooking/js/src/modules/` and their worker tests are executable authoring examples, including syntax, token and document stages and constrained policy additions. The fixture native owner is installed only by tests, not the application manifest.

## Verification and limitations

Actual final command results are recorded in [evidence/milestone-2](evidence/milestone-2). This milestone does not claim full server parity or a passing repository-wide suite. Initial author validation used focused tests because milestone 1 recorded 288 baseline failures and a hanging user-card lifecycle test. The coordinator later integrated onto main `95510b4be` with baseline test fixes and completed the full suite: 11,918 passed, 7 skipped, and two new worker-disposal fake-timer failures. This correction moves real worker watchdogs to owned wall-clock timers; the deterministic regression and both affected cases now pass, as do all 61 package tests. The coordinator will rerun the corrected full integration suite; no passing full-suite result is claimed here. The known `content_route_test.dart:19` analyzer lint and Assign's `shell_scope.dart` dependency-boundary failure are unrelated baseline issues.

No new Chat dialect, composer/send/edit integration, canonical reconciliation UI or later milestone feature scope is included. Compiler execution remains in the persistent worker with no network, filesystem or generic native bridge. The bundled engine remains a security-sensitive native dependency; existing native watchdog/finalizer and platform-validation limitations from milestone 1 still apply.

## Small complete extension example

The checked-in `fixture-mark` example turns `==text==` into a `<mark>` element. Its source registers one inline parser rule and an upstream allowlist entry:

```js
export function setup(helper, context) {
  helper.registerOptions(options => {
    options.features['fixture-mark'] = true;
  });
  helper.allowList(['mark[data-fixture]']);
  helper.registerPlugin(md => {
    md.inline.ruler.before('emphasis', 'fixture-mark', (state, silent) => {
      if (state.src.slice(state.pos, state.pos + 2) !== '==') return false;
      const end = state.src.indexOf('==', state.pos + 2);
      if (end < 0) return false;
      if (!silent) {
        const open = state.push('fixture_open', 'mark', 1);
        open.attrSet('data-fixture', 'bundled');
        const text = state.push('text', '', 0);
        text.content = state.src.slice(state.pos + 2, end);
        state.push('fixture_close', 'mark', -1);
      }
      state.pos = end + 2;
      return true;
    });
  });
}
```

Its `js/src/modules/catalog.json` entry owns the code identity, stage and final policy:

```json
{
  "id": "fixture-mark",
  "owner": "cooking-fixture",
  "version": "1",
  "source": "fixture-mark.js",
  "stage": "syntax",
  "policy": {"mark": ["data-fixture"]}
}
```

Run `npm run build --prefix packages/discourse_cooking/js` after adding or changing catalog/source files, then `npm run verify --prefix packages/discourse_cooking/js` to check reproducibility. The native owner registers a `CookingPlugin` capability through its normal `PluginRegistrar`; its `cookingModules` selects `CookingModule(id: 'fixture-mark', owner: 'cooking-fixture', version: '1')`. The capability's `projectCookingContext` receives an owner-restricted `CookingPluginData` view and returns a finite JSON map. Its `cookingProfiles` can be empty to reuse the installed post/chat profiles. The installed owner ID must match both the module catalog and capability registration.

Active syntax/token module IDs extend the selected profile's feature list, including Chat, without modifying a central profile. For a custom dialect, contribute a `CookingProfile` listing the desired parser features/rules. A module `profiles` list restricts activation to those registered dialect names; `enabledSetting` names a boolean under the owner's projected `settings` object, with core site settings as the fallback. An inactive dependency also disables its dependents. Dependency IDs must refer to installed compatible modules. The worker applies syntax setup, then token transforms, then document transforms, with final sanitation after all output modifications. Tests install the fixture owner and cook through the actual worker; production does not install that fixture owner.


A complete native declaration for that catalog entry is:

```dart
import 'package:discourse_native/discourse_plugin_sdk.dart';

final class MarkModule implements PluginModule {
  const MarkModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('cooking-fixture'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(MarkCapability());
}

final class MarkCapability implements CookingPlugin {
  @override
  String get name => 'cooking-fixture';
  @override
  List<CookingModule> get cookingModules => [
    CookingModule(id: 'fixture-mark', owner: name, version: '1'),
  ];
  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) => const {};
}
```

Install `MarkModule` through the normal application composition manifest. The
fixture owner is intentionally reserved for these examples/tests; a production
feature uses its own installed owner and unique catalog ID. See
`test/application_cooking_worker_test.dart` for the complete native-install →
request → worker → final-sanitizer path with a zero-HTTP trap.

Known references are reported when upload, hashtag, topic or avatar lookup
actually occurs; the result does not claim exhaustive mention/onebox reference
analysis. Mention hydration and complete portable server cleanup remain later
milestone work. The generated Dart bundle carries the same trusted modules in
both the root and `profiles/full` dependency graphs; there is no separately
fetched feature asset. No native C changes or new platform packaging builds were
required for this milestone; focused packaging tests and both locked app graphs
were validated, while milestone 1 retains the platform build evidence.
