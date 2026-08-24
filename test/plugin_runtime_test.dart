import 'package:discourse_native/src/plugins/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/site_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _hostValuePort = PluginHostPortKey<String>(
  owner: PluginId('core'),
  name: 'value',
);
const _serviceKey = PluginServiceKey<String>(
  owner: PluginId('feature'),
  name: 'value',
);

void main() {
  test(
    'installation snapshots modules and keeps manifest order among peers',
    () {
      final source = <PluginModule>[
        const _Module('first'),
        const _Module('second'),
      ];
      final installed = PluginInstaller.install(PluginManifest(source));
      source
        ..clear()
        ..add(const _Module('late'));

      expect(installed.descriptors.map((item) => item.id.value), [
        'first',
        'second',
      ]);
      expect(installed.registry.plugins.map((item) => item.name), [
        'first',
        'second',
      ]);
      expect(
        () => installed.registry.plugins.add(const _Capability('late')),
        throwsUnsupportedError,
      );
    },
  );

  test('dependencies order providers first without reordering other peers', () {
    final installed = PluginInstaller.install(
      const PluginManifest([
        _Module(
          'consumer',
          dependencies: [PluginDependency(PluginId('provider'))],
        ),
        _Module('peer'),
        _Module('provider'),
      ]),
    );

    expect(installed.descriptors.map((item) => item.id.value), [
      'peer',
      'provider',
      'consumer',
    ]);
  });

  test('invalid manifests fail before any module registers', () {
    final registered = <String>[];

    expect(
      () => PluginInstaller.install(
        PluginManifest([
          _Module('same', onRegister: registered.add),
          _Module('same', onRegister: registered.add),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
    expect(registered, isEmpty);

    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module(
            'consumer',
            dependencies: [PluginDependency(PluginId('absent'))],
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );

    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module('one', dependencies: [PluginDependency(PluginId('two'))]),
          _Module('two', dependencies: [PluginDependency(PluginId('one'))]),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('declared route, syntax, and exclusive claims cannot be ambiguous', () {
    for (final conflict in <PluginManifest>[
      const PluginManifest([
        _Module('one', routeNamespaces: {'shared'}),
        _Module('two', routeNamespaces: {'shared'}),
      ]),
      const PluginManifest([
        _Module('one', syntaxIds: {'shared'}),
        _Module('two', syntaxIds: {'shared'}),
      ]),
      const PluginManifest([
        _Module('one', exclusiveClaims: {'shared'}),
        _Module('two', exclusiveClaims: {'shared'}),
      ]),
    ]) {
      expect(
        () => PluginInstaller.install(conflict),
        throwsA(isA<PluginInstallationException>()),
      );
    }
  });

  test(
    'startup failure rolls back started lifecycles in reverse order',
    () async {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module('first', appLifecycle: _AppLifecycle('first', events)),
          _Module('second', appLifecycle: _AppLifecycle('second', events)),
          _Module(
            'broken',
            appLifecycle: _AppLifecycle('broken', events, failStart: true),
          ),
        ]),
      );

      await expectLater(
        installed.startPhase(PluginStartupPhase.bootstrap),
        throwsA(isA<PluginLifecycleException>()),
      );
      expect(events, [
        'first:start:bootstrap',
        'second:start:bootstrap',
        'broken:start:bootstrap',
        'second:close',
        'first:close',
      ]);
    },
  );

  test('startup phases are idempotent and close once', () async {
    final events = <String>[];
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module('feature', appLifecycle: _AppLifecycle('feature', events)),
      ]),
    );

    await installed.startPhase(PluginStartupPhase.bootstrap);
    await installed.startPhase(PluginStartupPhase.bootstrap);
    await installed.startPhase(PluginStartupPhase.appReady);
    await installed.startPhase(PluginStartupPhase.appReady);
    await installed.close();
    await installed.close();

    expect(events, [
      'feature:start:bootstrap',
      'feature:start:appReady',
      'feature:close',
    ]);
  });

  test(
    'sessions require declared host ports and expose typed services',
    () async {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'feature',
            sessionFactory: (bindings) => PluginSessionContribution(
              lifecycle: _SessionLifecycle(events),
              services: [
                PluginService<Object>(
                  _serviceKey,
                  'plugin:${bindings.require(_hostValuePort)}',
                ),
              ],
            ),
            requiredPorts: const [_hostValuePort],
          ),
        ]),
      );

      expect(
        () => installed.openSession(const PluginHostBindings.empty()),
        throwsA(isA<PluginInstallationException>()),
      );

      final session = installed.openSession(
        PluginHostBindings(const [
          PluginHostPort<Object>(_hostValuePort, 'host'),
        ]),
      );
      expect(session.require(_serviceKey), 'plugin:host');

      await session.setForeground(true);
      await session.forget('https://example.com');
      await session.close();
      expect(events, [
        'foreground:true',
        'forget:https://example.com',
        'close',
      ]);
    },
  );

  test(
    'session teardown isolates failures and continues in reverse order',
    () async {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'first',
            sessionFactory: (_) => PluginSessionContribution(
              lifecycle: _SessionLifecycle(events, name: 'first'),
            ),
          ),
          _Module(
            'second',
            sessionFactory: (_) => PluginSessionContribution(
              lifecycle: _SessionLifecycle(
                events,
                name: 'second',
                failClose: true,
              ),
            ),
          ),
        ]),
      );
      final session = installed.openSession(const PluginHostBindings.empty());

      await expectLater(
        session.close(),
        throwsA(isA<PluginLifecycleException>()),
      );
      expect(events, ['second:close', 'first:close']);
    },
  );
}

final class _Module implements PluginModule {
  const _Module(
    this.id, {
    this.dependencies = const [],
    this.routeNamespaces = const {},
    this.syntaxIds = const {},
    this.exclusiveClaims = const {},
    this.onRegister,
    this.appLifecycle,
    this.sessionFactory,
    this.requiredPorts = const [],
  });

  final String id;
  final List<PluginDependency> dependencies;
  final Set<String> routeNamespaces;
  final Set<String> syntaxIds;
  final Set<String> exclusiveClaims;
  final void Function(String)? onRegister;
  final PluginAppLifecycle? appLifecycle;
  final PluginSessionFactory? sessionFactory;
  final List<PluginHostPortKey<Object>> requiredPorts;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: PluginId(id),
    dependencies: dependencies,
    routeNamespaces: routeNamespaces,
    syntaxIds: syntaxIds,
    exclusiveClaims: exclusiveClaims,
  );

  @override
  void register(PluginRegistrar registrar) {
    onRegister?.call(id);
    registrar.addCapability(_Capability(id));
    if (appLifecycle case final lifecycle?) {
      registrar.addAppLifecycle(lifecycle);
    }
    if (sessionFactory case final factory?) {
      registrar.addSession(factory, requires: requiredPorts);
    }
  }
}

final class _Capability implements SitePlugin {
  const _Capability(this.name);

  @override
  final String name;
}

final class _AppLifecycle extends PluginAppLifecycle {
  _AppLifecycle(this.name, this.events, {this.failStart = false});

  final String name;
  final List<String> events;
  final bool failStart;

  @override
  void startPhase(PluginStartupPhase phase) {
    events.add('$name:start:${phase.name}');
    if (failStart) throw StateError(name);
  }

  @override
  void close() => events.add('$name:close');
}

final class _SessionLifecycle extends PluginSessionLifecycle {
  _SessionLifecycle(this.events, {this.name, this.failClose = false});

  final List<String> events;
  final String? name;
  final bool failClose;

  @override
  void setForeground(bool foreground) {
    events.add('foreground:$foreground');
  }

  @override
  void forget(String siteUrl) => events.add('forget:$siteUrl');

  @override
  void close() {
    events.add(name == null ? 'close' : '$name:close');
    if (failClose) throw StateError(name ?? 'session');
  }
}
