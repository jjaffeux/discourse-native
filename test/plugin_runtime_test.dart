import 'dart:async';

import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart' as public_api;
import 'package:flutter_test/flutter_test.dart';

const _hostValuePort = PluginHostPortKey<String>(
  owner: PluginId('core'),
  name: 'value',
);
const _undeclaredHostValuePort = PluginHostPortKey<String>(
  owner: PluginId('core'),
  name: 'undeclared-value',
);
const _scopedHostValuePort = PluginHostPortKey<String>(
  owner: PluginId('core'),
  name: 'scoped-value',
);
const _revocableHostPort = PluginHostPortKey<_RevocableHost>(
  owner: PluginId('core'),
  name: 'revocable-host',
);
const _serviceKey = PluginServiceKey<String>(
  owner: PluginId('feature'),
  name: 'value',
);
const _spoofedServiceKey = PluginServiceKey<String>(
  owner: PluginId('other'),
  name: 'value',
);
const _providerServiceKey = PluginServiceKey<String>(
  owner: PluginId('provider'),
  name: 'value',
);
const _optionalServiceKey = PluginServiceKey<String>(
  owner: PluginId('optional-provider'),
  name: 'value',
);
const _foreignServiceKey = PluginServiceKey<String>(
  owner: PluginId('foreign'),
  name: 'value',
);
const _featureRecordKey = PluginDataKey<String>(
  owner: 'feature',
  name: 'record',
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

  test('registrar retains capabilities declared against the pure API', () {
    final installed = PluginInstaller.install(
      const PluginManifest([
        _Module(
          'public-only',
          capabilities: [_PublicCapability('public-only')],
        ),
      ]),
    );

    expect(installed.capabilities<_PublicCapability>(), [
      const _PublicCapability('public-only'),
    ]);
    expect(installed.registry.plugins, isEmpty);
    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module('owner', capabilities: [_PublicCapability('someone-else')]),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('installation snapshots each descriptor exactly once', () {
    final dependencies = <PluginDependency>[
      const PluginDependency(PluginId('provider')),
    ];
    final routes = <String>{'consumer'};
    final consumer = _MutableDescriptorModule(dependencies, routes);
    final installed = PluginInstaller.install(
      PluginManifest([
        consumer,
        _Module(
          'provider',
          sessionFactory: (_, _) => PluginSessionContribution(
            lifecycle: _SessionLifecycle(<String>[]),
            services: const [
              PluginService<Object>(_providerServiceKey, 'ready'),
            ],
          ),
        ),
      ]),
    );

    expect(consumer.descriptorReads, 1);
    expect(dependencies, isEmpty);
    expect(routes, isEmpty);
    expect(installed.descriptors.map((item) => item.id.value), [
      'provider',
      'consumer',
    ]);
    final descriptor = installed.descriptors.last;
    expect(descriptor.dependencies.single.id, const PluginId('provider'));
    expect(descriptor.routeNamespaces, {'consumer'});
    expect(() => descriptor.dependencies.clear(), throwsUnsupportedError);
    expect(() => descriptor.routeNamespaces.clear(), throwsUnsupportedError);

    installed.openSession(const PluginHostBindings.empty());
    expect(consumer.resolvedService, 'ready');
  });

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

  test(
    'session dependencies expose declared services after provider creation',
    () {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'consumer',
            dependencies: const [PluginDependency(PluginId('provider'))],
            sessionFactory: (_, dependencies) {
              events.add(
                'consumer:${dependencies.require(_providerServiceKey)}',
              );
              return PluginSessionContribution(
                lifecycle: _SessionLifecycle(events, name: 'consumer'),
              );
            },
          ),
          _Module(
            'provider',
            sessionFactory: (_, _) {
              events.add('provider');
              return PluginSessionContribution(
                lifecycle: _SessionLifecycle(events, name: 'provider'),
                services: const [
                  PluginService<Object>(_providerServiceKey, 'ready'),
                ],
              );
            },
          ),
        ]),
      );

      final session = installed.openSession(const PluginHostBindings.empty());

      expect(events, ['provider', 'consumer:ready']);
      expect(session.require(_providerServiceKey), 'ready');
    },
  );

  test('optional dependency lookup is genuinely nullable', () {
    late PluginDependencies absentDependencies;
    final withoutProvider = PluginInstaller.install(
      PluginManifest([
        _Module(
          'consumer',
          dependencies: const [
            PluginDependency(PluginId('optional-provider'), optional: true),
          ],
          sessionFactory: (_, dependencies) {
            absentDependencies = dependencies;
            return PluginSessionContribution(
              lifecycle: _SessionLifecycle(<String>[]),
            );
          },
        ),
      ]),
    );

    final absentSession = withoutProvider.openSession(
      const PluginHostBindings.empty(),
    );
    expect(absentDependencies.maybe(_optionalServiceKey), isNull);
    expect(
      () => absentDependencies.require(_optionalServiceKey),
      throwsA(isA<PluginInstallationException>()),
    );
    expect(absentSession.maybeService(_optionalServiceKey), isNull);
    expect(absentSession.service(_optionalServiceKey), isNull);

    final events = <String>[];
    final withProvider = PluginInstaller.install(
      PluginManifest([
        _Module(
          'consumer',
          dependencies: const [
            PluginDependency(PluginId('optional-provider'), optional: true),
          ],
          sessionFactory: (_, dependencies) {
            events.add('consumer:${dependencies.maybe(_optionalServiceKey)}');
            return PluginSessionContribution(
              lifecycle: _SessionLifecycle(events, name: 'consumer'),
            );
          },
        ),
        _Module(
          'optional-provider',
          sessionFactory: (_, _) {
            events.add('provider');
            return PluginSessionContribution(
              lifecycle: _SessionLifecycle(events, name: 'provider'),
              services: const [
                PluginService<Object>(_optionalServiceKey, 'optional'),
              ],
            );
          },
        ),
      ]),
    );

    withProvider.openSession(const PluginHostBindings.empty());
    expect(events, ['provider', 'consumer:optional']);
  });

  test('dependency lookup rejects services from undeclared owners', () {
    for (final lookup in <void Function(PluginDependencies)>[
      (dependencies) => dependencies.require(_providerServiceKey),
      (dependencies) => dependencies.maybe(_providerServiceKey),
    ]) {
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'provider',
            sessionFactory: (_, _) => PluginSessionContribution(
              lifecycle: _SessionLifecycle(<String>[]),
              services: const [
                PluginService<Object>(_providerServiceKey, 'private'),
              ],
            ),
          ),
          _Module(
            'consumer',
            sessionFactory: (_, dependencies) {
              lookup(dependencies);
              return PluginSessionContribution(
                lifecycle: _SessionLifecycle(<String>[]),
              );
            },
          ),
        ]),
      );

      expect(
        () => installed.openSession(const PluginHostBindings.empty()),
        throwsA(isA<PluginInstallationException>()),
      );
    }
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
        PluginManifest([
          _Module(
            'consumer',
            dependencies: const [PluginDependency(PluginId('absent'))],
            onRegister: registered.add,
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
    expect(registered, isEmpty);

    expect(
      () => PluginInstaller.install(
        PluginManifest([
          _Module(
            'one',
            dependencies: const [PluginDependency(PluginId('two'))],
            onRegister: registered.add,
          ),
          _Module(
            'two',
            dependencies: const [PluginDependency(PluginId('one'))],
            onRegister: registered.add,
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
    expect(registered, isEmpty);
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

  test('live-channel scopes are segment safe and may overlap', () {
    const chat = PluginLiveChannelScope.prefix('/chat');
    expect(chat.allows('/chat'), isTrue);
    expect(chat.allows('/chat/42'), isTrue);
    expect(chat.allows('/chatty'), isFalse);

    final installed = PluginInstaller.install(
      PluginManifest([
        _Module('chat', liveChannelScopes: {chat}),
        _Module('resenha', liveChannelScopes: {chat}),
      ]),
    );

    expect(installed.liveChannelScopesFor(const PluginId('chat')), {chat});
    expect(installed.liveChannelScopesFor(const PluginId('resenha')), {chat});
    expect(installed.liveChannelScopesFor(const PluginId('missing')), isEmpty);
  });

  test('live-channel declarations must be exact, valid, and non-core', () {
    for (final module in <PluginModule>[
      _Module(
        'mismatch',
        liveChannelScopes: {const PluginLiveChannelScope.prefix('/declared')},
        registeredLiveChannelScopes: const [
          PluginLiveChannelScope.prefix('/actual'),
        ],
      ),
      _Module(
        'invalid',
        liveChannelScopes: {const PluginLiveChannelScope.prefix('/invalid/')},
      ),
      _Module(
        'core-child',
        liveChannelScopes: {
          const PluginLiveChannelScope.prefix('/notification/plugin'),
        },
      ),
    ]) {
      expect(
        () => PluginInstaller.install(PluginManifest([module])),
        throwsA(isA<PluginInstallationException>()),
      );
    }

    const reserved = [
      '/latest',
      '/new',
      '/notification',
      '/reviewable_counts',
      '/user-status',
      '/do-not-disturb',
      '/topic',
    ];
    for (var index = 0; index < reserved.length; index++) {
      final scope = PluginLiveChannelScope.prefix(reserved[index]);
      expect(
        () => PluginInstaller.install(
          PluginManifest([
            _Module('reserved-$index', liveChannelScopes: {scope}),
          ]),
        ),
        throwsA(isA<PluginInstallationException>()),
      );
    }
  });

  test('registered claims must exactly match descriptors and syntax', () {
    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module(
            'feature',
            routeNamespaces: {'route'},
            syntaxIds: {'syntax'},
            exclusiveClaims: {'exclusive'},
            capabilities: [_SyntaxCapability('feature', 'syntax')],
          ),
        ]),
      ),
      returnsNormally,
    );

    for (final mismatch in <PluginModule>[
      const _Module(
        'route-owner',
        routeNamespaces: {'declared'},
        registeredRouteNamespaces: ['actual'],
      ),
      const _Module(
        'syntax-owner',
        syntaxIds: {'declared'},
        registeredSyntaxIds: ['declared'],
        capabilities: [_SyntaxCapability('syntax-owner', 'actual')],
      ),
      const _Module(
        'exclusive-owner',
        exclusiveClaims: {'declared'},
        registeredExclusiveClaims: ['actual'],
      ),
    ]) {
      expect(
        () => PluginInstaller.install(PluginManifest([mismatch])),
        throwsA(isA<PluginInstallationException>()),
      );
    }
  });

  test('duplicate actual claims are rejected within one module', () {
    for (final duplicate in <PluginModule>[
      const _Module(
        'route-owner',
        routeNamespaces: {'route'},
        registeredRouteNamespaces: ['route', 'route'],
      ),
      const _Module(
        'syntax-owner',
        syntaxIds: {'syntax'},
        registeredSyntaxIds: ['syntax', 'syntax'],
        capabilities: [_SyntaxCapability('syntax-owner', 'syntax')],
      ),
      const _Module(
        'exclusive-owner',
        exclusiveClaims: {'exclusive'},
        registeredExclusiveClaims: ['exclusive', 'exclusive'],
      ),
      const _Module(
        'syntax-capability-owner',
        syntaxIds: {'syntax'},
        capabilities: [
          _SyntaxCapability('syntax-capability-owner', 'syntax'),
          _SyntaxCapability('syntax-capability-owner', 'syntax'),
        ],
      ),
    ]) {
      expect(
        () => PluginInstaller.install(PluginManifest([duplicate])),
        throwsA(isA<PluginInstallationException>()),
      );
    }
  });

  test('declared claims cannot be omitted or supplemented at registration', () {
    for (final mismatch in <PluginModule>[
      const _Module(
        'route-omitted',
        routeNamespaces: {'declared'},
        registeredRouteNamespaces: [],
      ),
      const _Module(
        'route-supplemented',
        routeNamespaces: {'declared'},
        registeredRouteNamespaces: ['declared', 'extra'],
      ),
      const _Module(
        'syntax-omitted',
        syntaxIds: {'declared'},
        registeredSyntaxIds: [],
      ),
      const _Module(
        'exclusive-omitted',
        exclusiveClaims: {'declared'},
        registeredExclusiveClaims: [],
      ),
    ]) {
      expect(
        () => PluginInstaller.install(PluginManifest([mismatch])),
        throwsA(isA<PluginInstallationException>()),
      );
    }
  });

  test('record and service keys must be owned by their module', () {
    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module(
            'feature',
            capabilities: [
              _RecordCapability(
                'feature',
                PluginDataKey<String>(owner: 'foreign', name: 'record'),
              ),
            ],
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );

    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (_, _) => PluginSessionContribution(
            lifecycle: _SessionLifecycle(<String>[]),
            services: const [
              PluginService<Object>(_foreignServiceKey, 'wrong owner'),
            ],
          ),
        ),
      ]),
    );
    expect(
      () => installed.openSession(const PluginHostBindings.empty()),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('duplicate record and service keys are rejected', () {
    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module(
            'feature',
            capabilities: [
              _RecordCapability('feature', _featureRecordKey),
              _RecordCapability('feature', _featureRecordKey),
            ],
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );

    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (_, _) => PluginSessionContribution(
            lifecycle: _SessionLifecycle(<String>[]),
            services: const [
              PluginService<Object>(_serviceKey, 'first'),
              PluginService<Object>(_serviceKey, 'second'),
            ],
          ),
        ),
      ]),
    );
    expect(
      () => installed.openSession(const PluginHostBindings.empty()),
      throwsA(isA<PluginInstallationException>()),
    );
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
    'app lifecycles receive only owner-scoped declared host ports',
    () async {
      final received = <String>[];
      var materializations = 0;
      final installed = PluginInstaller.install(
        PluginManifest([
          for (final id in const ['first', 'second'])
            _Module(
              id,
              appLifecycle: _AppLifecycle(
                id,
                [],
                inspectBindings: (bindings) {
                  received.add('$id:${bindings.require(_scopedHostValuePort)}');
                  received.add(
                    '$id:undeclared:${bindings.contains(_hostValuePort)}',
                  );
                },
              ),
              requiredAppPorts: const [_scopedHostValuePort],
            ),
        ]),
      );
      final rootBindings = PluginHostBindings([
        PluginHostPort<Object>(
          _scopedHostValuePort,
          'root',
          scopeToConsumer: (owner) {
            materializations += 1;
            return 'scoped:${owner.value}';
          },
        ),
        const PluginHostPort<Object>(_hostValuePort, 'private'),
      ]);

      await installed.startPhase(
        PluginStartupPhase.bootstrap,
        bindings: rootBindings,
      );
      await installed.startPhase(PluginStartupPhase.appReady);

      expect(received, [
        'first:scoped:first',
        'first:undeclared:false',
        'second:scoped:second',
        'second:undeclared:false',
        'first:scoped:first',
        'first:undeclared:false',
        'second:scoped:second',
        'second:undeclared:false',
      ]);
      expect(materializations, 2);
    },
  );

  test('app lifecycle rollback and close revoke scoped authority', () async {
    for (final failStart in [true, false]) {
      late _RevocableHost retained;
      final hosts = <PluginId, _RevocableHost>{};
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'feature',
            appLifecycle: _AppLifecycle(
              'feature',
              [],
              failStart: failStart,
              inspectBindings: (bindings) {
                retained = bindings.require(_revocableHostPort);
              },
            ),
            requiredAppPorts: const [_revocableHostPort],
          ),
        ]),
      );
      final bindings = PluginHostBindings([
        PluginHostPort<Object>(
          _revocableHostPort,
          _RevocableHost(),
          scopeToConsumer: (consumer) =>
              hosts.putIfAbsent(consumer, _RevocableHost.new),
          revokeConsumer: (consumer) => hosts[consumer]?.revoke(),
        ),
      ]);

      if (failStart) {
        await expectLater(
          installed.startPhase(
            PluginStartupPhase.bootstrap,
            bindings: bindings,
          ),
          throwsA(isA<PluginLifecycleException>()),
        );
      } else {
        await installed.startPhase(
          PluginStartupPhase.bootstrap,
          bindings: bindings,
        );
        expect(retained.read(), 'available');
        await installed.close();
      }
      expect(retained.read, throwsStateError);
    }
  });

  test('app lifecycle startup rejects missing declared host ports', () async {
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          appLifecycle: _AppLifecycle('feature', []),
          requiredAppPorts: const [_hostValuePort],
        ),
      ]),
    );

    await expectLater(
      installed.startPhase(PluginStartupPhase.bootstrap),
      throwsA(
        isA<PluginLifecycleException>().having(
          (error) => error.failures,
          'failures',
          contains(isA<PluginInstallationException>()),
        ),
      ),
    );
  });

  test(
    'app lifecycle hooks isolate failures and dispatch every contributor',
    () async {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module('first', appLifecycle: _AppLifecycle('first', events)),
          _Module(
            'sync-failure',
            appLifecycle: _AppLifecycle(
              'sync-failure',
              events,
              failObserve: true,
              failFlush: true,
            ),
          ),
          _Module(
            'async-failure',
            appLifecycle: _AppLifecycle(
              'async-failure',
              events,
              failObserve: true,
              failFlush: true,
              asyncHookFailures: true,
            ),
          ),
          _Module('last', appLifecycle: _AppLifecycle('last', events)),
        ]),
      );
      await installed.startPhase(PluginStartupPhase.bootstrap);
      events.clear();

      await expectLater(
        installed.observeAppState('paused', foreground: false),
        throwsA(
          isA<PluginLifecycleException>()
              .having(
                (error) => error.operation,
                'operation',
                'observeAppState',
              )
              .having((error) => error.failures, 'failures', hasLength(2)),
        ),
      );
      expect(events, [
        'first:state:paused:false',
        'sync-failure:state:paused:false',
        'async-failure:state:paused:false',
        'last:state:paused:false',
      ]);

      events.clear();
      await expectLater(
        installed.flush(),
        throwsA(
          isA<PluginLifecycleException>()
              .having((error) => error.operation, 'operation', 'flush')
              .having((error) => error.failures, 'failures', hasLength(2)),
        ),
      );
      expect(events, [
        'first:flush',
        'sync-failure:flush',
        'async-failure:flush',
        'last:flush',
      ]);
    },
  );

  test(
    'app lifecycle close drains an in-flight hook before teardown',
    () async {
      final events = <String>[];
      final hookStarted = Completer<void>();
      final releaseHook = Completer<void>();
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'feature',
            appLifecycle: _GatedAppLifecycle(
              events,
              hookStarted: hookStarted,
              releaseHook: releaseHook,
            ),
          ),
        ]),
      );
      await installed.startPhase(PluginStartupPhase.bootstrap);
      events.clear();

      final observing = installed.observeAppState('paused', foreground: false);
      await hookStarted.future;
      final closing = installed.close();
      await Future<void>.delayed(Duration.zero);

      expect(events, ['observe:start']);
      await installed.flush();
      expect(events, ['observe:start']);

      releaseHook.complete();
      await observing;
      await closing;
      expect(events, ['observe:start', 'observe:end', 'close']);
    },
  );

  test(
    'sessions require declared host ports and expose typed services',
    () async {
      final events = <String>[];
      var receivedUndeclaredPort = false;
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'feature',
            sessionFactory: (bindings, _) {
              receivedUndeclaredPort = bindings.contains(
                _undeclaredHostValuePort,
              );
              return PluginSessionContribution(
                lifecycle: _SessionLifecycle(events),
                services: [
                  PluginService<Object>(
                    _serviceKey,
                    'plugin:${bindings.require(_hostValuePort)}',
                  ),
                ],
              );
            },
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
          PluginHostPort<Object>(_undeclaredHostValuePort, 'private'),
        ]),
      );
      expect(session.require(_serviceKey), 'plugin:host');
      expect(receivedUndeclaredPort, isFalse);

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

  test('scoped host ports materialize once for each consuming plugin', () {
    final received = <String>[];
    final installed = PluginInstaller.install(
      PluginManifest([
        for (final id in const ['first', 'second'])
          _Module(
            id,
            sessionFactory: (bindings, _) {
              final value = bindings.require(_scopedHostValuePort);
              received.add('$id:$value');

              // Restricted views no longer carry the root materializer, so a
              // plugin cannot rebind its value under another identity.
              final rebound = bindings
                  .restrictedTo(const [
                    _scopedHostValuePort,
                  ], consumer: const PluginId('other'))
                  .require(_scopedHostValuePort);
              received.add('$id:rebound:$rebound');
              return PluginSessionContribution(
                lifecycle: _SessionLifecycle([]),
              );
            },
            requiredPorts: const [_scopedHostValuePort],
          ),
      ]),
    );
    final rootBindings = PluginHostBindings([
      PluginHostPort<Object>(
        _scopedHostValuePort,
        'root',
        scopeToConsumer: (consumer) => 'scoped:${consumer.value}',
      ),
    ]);

    expect(rootBindings.require(_scopedHostValuePort), 'root');
    expect(
      () => rootBindings.restrictedTo(const [_scopedHostValuePort]),
      throwsA(isA<PluginInstallationException>()),
    );

    installed.openSession(rootBindings);

    expect(received, [
      'first:scoped:first',
      'first:rebound:scoped:first',
      'second:scoped:second',
      'second:rebound:scoped:second',
    ]);
  });

  test('factory rollback revokes hostile retained scoped authority', () {
    late _RevocableHost retained;
    final hosts = <PluginId, _RevocableHost>{};
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (bindings, _) {
            retained = bindings.require(_revocableHostPort);
            throw StateError('hostile factory failure');
          },
          requiredPorts: const [_revocableHostPort],
        ),
      ]),
    );
    final bindings = PluginHostBindings([
      PluginHostPort<Object>(
        _revocableHostPort,
        _RevocableHost(),
        scopeToConsumer: (consumer) =>
            hosts.putIfAbsent(consumer, _RevocableHost.new),
        revokeConsumer: (consumer) => hosts[consumer]?.revoke(),
      ),
    ]);

    expect(() => installed.openSession(bindings), throwsStateError);
    expect(retained.read, throwsStateError);
  });

  test('session close revokes retained scoped authority', () async {
    late _RevocableHost retained;
    final hosts = <PluginId, _RevocableHost>{};
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (bindings, _) {
            retained = bindings.require(_revocableHostPort);
            return PluginSessionContribution(lifecycle: _SessionLifecycle([]));
          },
          requiredPorts: const [_revocableHostPort],
        ),
      ]),
    );
    final session = installed.openSession(
      PluginHostBindings([
        PluginHostPort<Object>(
          _revocableHostPort,
          _RevocableHost(),
          scopeToConsumer: (consumer) =>
              hosts.putIfAbsent(consumer, _RevocableHost.new),
          revokeConsumer: (consumer) => hosts[consumer]?.revoke(),
        ),
      ]),
    );

    expect(retained.read(), 'available');
    await session.close();
    expect(retained.read, throwsStateError);
  });

  test('session close drains an in-flight hook before teardown', () async {
    final events = <String>[];
    final hookStarted = Completer<void>();
    final releaseHook = Completer<void>();
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (_, _) => PluginSessionContribution(
            lifecycle: _GatedSessionLifecycle(
              events,
              hookStarted: hookStarted,
              releaseHook: releaseHook,
            ),
          ),
        ),
      ]),
    );
    final session = installed.openSession(const PluginHostBindings.empty());

    final foregrounding = session.setForeground(false);
    await hookStarted.future;
    final closing = session.close();
    await Future<void>.delayed(Duration.zero);

    expect(events, ['foreground:start']);
    await session.forget('https://ignored.example');
    expect(events, ['foreground:start']);

    releaseHook.complete();
    await foregrounding;
    await closing;
    expect(events, ['foreground:start', 'foreground:end', 'close']);
  });

  test('session contributions cannot provide another plugin service', () {
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (_, _) => PluginSessionContribution(
            lifecycle: _SessionLifecycle([]),
            services: const [
              PluginService<Object>(_spoofedServiceKey, 'spoofed'),
            ],
          ),
        ),
      ]),
    );

    expect(
      () => installed.openSession(const PluginHostBindings.empty()),
      throwsA(
        isA<PluginInstallationException>().having(
          (error) => error.message,
          'message',
          allOf(contains('other/value'), contains('feature')),
        ),
      ),
    );
  });

  test('session factories cannot access undeclared host ports', () {
    final installed = PluginInstaller.install(
      PluginManifest([
        _Module(
          'feature',
          sessionFactory: (bindings, _) {
            bindings.require(_hostValuePort);
            return PluginSessionContribution(
              lifecycle: _SessionLifecycle(<String>[]),
            );
          },
        ),
      ]),
    );

    expect(
      () => installed.openSession(
        PluginHostBindings(const [
          PluginHostPort<Object>(_hostValuePort, 'host'),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test(
    'session teardown isolates failures and continues in reverse order',
    () async {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'first',
            sessionFactory: (_, _) => PluginSessionContribution(
              lifecycle: _SessionLifecycle(events, name: 'first'),
            ),
          ),
          _Module(
            'second',
            sessionFactory: (_, _) => PluginSessionContribution(
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

  test('session bookmark targets are distinct and namespaced', () async {
    final distinct = PluginInstaller.install(
      PluginManifest([
        _bookmarkModule('first', 'message', 'First::Message'),
        _bookmarkModule('second', 'message', 'Second::Message'),
      ]),
    );
    final session = distinct.openSession(const PluginHostBindings.empty());
    expect(session.capabilities<PluginBookmarkTargetStrategy>(), hasLength(2));
    await session.close();

    final duplicateId = PluginInstaller.install(
      PluginManifest([
        _Module(
          'shared',
          sessionFactory: (_, _) => PluginSessionContribution(
            lifecycle: _SessionLifecycle([]),
            capabilities: [
              _BookmarkStrategy('shared', 'message', 'First::Message'),
              _BookmarkStrategy('shared', 'message', 'Second::Message'),
            ],
          ),
        ),
      ]),
    );
    expect(
      () => duplicateId.openSession(const PluginHostBindings.empty()),
      throwsA(isA<PluginInstallationException>()),
    );

    final duplicateWire = PluginInstaller.install(
      PluginManifest([
        _bookmarkModule('first', 'message', 'Shared::Message'),
        _bookmarkModule('second', 'message', 'Shared::Message'),
      ]),
    );
    expect(
      () => duplicateWire.openSession(const PluginHostBindings.empty()),
      throwsA(isA<PluginInstallationException>()),
    );

    for (final coreTarget in const [
      BookmarkTargetType.post,
      BookmarkTargetType.topic,
    ]) {
      final spoofedCoreWire = PluginInstaller.install(
        PluginManifest([
          _bookmarkModule('feature', 'spoof', coreTarget.wireName),
        ]),
      );
      expect(
        () => spoofedCoreWire.openSession(const PluginHostBindings.empty()),
        throwsA(
          isA<PluginInstallationException>().having(
            (error) => error.message,
            'message',
            allOf(contains(coreTarget.wireName), contains('core')),
          ),
        ),
      );
    }
  });

  test('session capability lookup preserves contributing owners', () async {
    final installed = PluginInstaller.install(
      PluginManifest([
        for (final id in const ['first', 'second'])
          _Module(
            id,
            sessionFactory: (_, _) => PluginSessionContribution(
              lifecycle: _SessionLifecycle([]),
              capabilities: [_SessionProbe(id)],
            ),
          ),
      ]),
    );
    final session = installed.openSession(const PluginHostBindings.empty());

    expect(
      session.ownedCapabilities<_SessionProbe>().map(
        (entry) => '${entry.owner.value}:${entry.capability.value}',
      ),
      ['first:first', 'second:second'],
    );
    expect(session.capabilities<_SessionProbe>().map((item) => item.value), [
      'first',
      'second',
    ]);
    await session.close();
  });

  test(
    'async session teardown completes in reverse dependency order',
    () async {
      final events = <String>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _Module(
            'provider',
            sessionFactory: (_, _) => PluginSessionContribution(
              lifecycle: _AsyncSessionLifecycle('provider', events),
            ),
          ),
          _Module(
            'consumer',
            dependencies: const [PluginDependency(PluginId('provider'))],
            sessionFactory: (_, _) => PluginSessionContribution(
              lifecycle: _AsyncSessionLifecycle('consumer', events),
            ),
          ),
        ]),
      );

      final session = installed.openSession(const PluginHostBindings.empty());
      await session.close();

      expect(events, [
        'consumer:close:start',
        'consumer:close:end',
        'provider:close:start',
        'provider:close:end',
      ]);
    },
  );
}

final class _MutableDescriptorModule implements PluginModule {
  _MutableDescriptorModule(this.dependencies, this.routeNamespaces);

  final List<PluginDependency> dependencies;
  final Set<String> routeNamespaces;
  int descriptorReads = 0;
  String? resolvedService;

  @override
  PluginDescriptor get descriptor {
    descriptorReads += 1;
    return PluginDescriptor(
      id: const PluginId('consumer'),
      dependencies: dependencies,
      routeNamespaces: routeNamespaces,
    );
  }

  @override
  void register(PluginRegistrar registrar) {
    dependencies.clear();
    routeNamespaces.clear();
    registrar
      ..addCapability(const _Capability('consumer'))
      ..addRouteNamespace('consumer')
      ..addSession((_, dependencies) {
        resolvedService = dependencies.require(_providerServiceKey);
        return PluginSessionContribution(
          lifecycle: _SessionLifecycle(<String>[]),
        );
      });
  }
}

_Module _bookmarkModule(String owner, String name, String wireName) => _Module(
  owner,
  sessionFactory: (_, _) => PluginSessionContribution(
    lifecycle: _SessionLifecycle([]),
    capabilities: [_BookmarkStrategy(owner, name, wireName)],
  ),
);

final class _Module implements PluginModule {
  const _Module(
    this.id, {
    this.dependencies = const [],
    this.routeNamespaces = const {},
    this.syntaxIds = const {},
    this.exclusiveClaims = const {},
    this.liveChannelScopes = const {},
    this.registeredRouteNamespaces,
    this.registeredSyntaxIds,
    this.registeredExclusiveClaims,
    this.registeredLiveChannelScopes,
    this.capabilities,
    this.onRegister,
    this.appLifecycle,
    this.sessionFactory,
    this.requiredAppPorts = const [],
    this.requiredPorts = const [],
  });

  final String id;
  final List<PluginDependency> dependencies;
  final Set<String> routeNamespaces;
  final Set<String> syntaxIds;
  final Set<String> exclusiveClaims;
  final Set<PluginLiveChannelScope> liveChannelScopes;
  final List<String>? registeredRouteNamespaces;
  final List<String>? registeredSyntaxIds;
  final List<String>? registeredExclusiveClaims;
  final List<PluginLiveChannelScope>? registeredLiveChannelScopes;
  final List<PluginCapability>? capabilities;
  final void Function(String)? onRegister;
  final PluginAppLifecycle? appLifecycle;
  final PluginSessionFactory? sessionFactory;
  final List<PluginHostPortKey<Object>> requiredAppPorts;
  final List<PluginHostPortKey<Object>> requiredPorts;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: PluginId(id),
    dependencies: dependencies,
    routeNamespaces: routeNamespaces,
    syntaxIds: syntaxIds,
    exclusiveClaims: exclusiveClaims,
    liveChannelScopes: liveChannelScopes,
  );

  @override
  void register(PluginRegistrar registrar) {
    onRegister?.call(id);
    for (final capability
        in capabilities ?? <PluginCapability>[_Capability(id)]) {
      registrar.addCapability(capability);
    }
    for (final namespace in registeredRouteNamespaces ?? routeNamespaces) {
      registrar.addRouteNamespace(namespace);
    }
    for (final syntaxId in registeredSyntaxIds ?? syntaxIds) {
      registrar.addSyntaxId(syntaxId);
    }
    for (final claim in registeredExclusiveClaims ?? exclusiveClaims) {
      registrar.addExclusiveClaim(claim);
    }
    for (final scope in registeredLiveChannelScopes ?? liveChannelScopes) {
      registrar.addLiveChannelScope(scope);
    }
    if (appLifecycle case final lifecycle?) {
      registrar.addAppLifecycle(lifecycle, requires: requiredAppPorts);
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

final class _PublicCapability implements public_api.PluginCapability {
  const _PublicCapability(this.name);

  @override
  final String name;
}

final class _SessionProbe implements PluginSessionCapability {
  const _SessionProbe(this.value);

  final String value;
}

final class _BookmarkStrategy implements PluginBookmarkTargetStrategy {
  _BookmarkStrategy(String owner, String name, String wireName)
    : pluginBookmarkTarget = BookmarkTargetType(
        owner: PluginId(owner),
        name: name,
        wireName: wireName,
        refreshLabel: 'record',
      );

  @override
  final BookmarkTargetType pluginBookmarkTarget;

  @override
  void putPluginBookmark(String siteUrl, int targetId, Bookmark bookmark) {}

  @override
  void removePluginBookmark(String siteUrl, int targetId) {}

  @override
  void reconcilePluginBookmark(String siteUrl, int targetId) {}
}

final class _SyntaxCapability implements SitePlugin, ComposerSyntaxPlugin {
  const _SyntaxCapability(this.name, this.syntaxId);

  @override
  final String name;

  @override
  final String syntaxId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordCapability implements SitePlugin, PluginRecord<String> {
  const _RecordCapability(this.name, this.record);

  @override
  final String name;

  @override
  final PluginDataKey<String> record;
}

final class _AppLifecycle extends PluginAppLifecycle {
  _AppLifecycle(
    this.name,
    this.events, {
    this.failStart = false,
    this.failObserve = false,
    this.failFlush = false,
    this.asyncHookFailures = false,
    this.inspectBindings,
  });

  final String name;
  final List<String> events;
  final bool failStart;
  final bool failObserve;
  final bool failFlush;
  final bool asyncHookFailures;
  final void Function(PluginHostBindings bindings)? inspectBindings;

  @override
  void startPhase(PluginStartupPhase phase, PluginHostBindings bindings) {
    events.add('$name:start:${phase.name}');
    inspectBindings?.call(bindings);
    if (failStart) throw StateError(name);
  }

  @override
  FutureOr<void> observeAppState(String state, {required bool foreground}) {
    events.add('$name:state:$state:$foreground');
    if (failObserve) {
      if (asyncHookFailures) return Future<void>.error(StateError(name));
      throw StateError(name);
    }
  }

  @override
  FutureOr<void> flush() {
    events.add('$name:flush');
    if (failFlush) {
      if (asyncHookFailures) return Future<void>.error(StateError(name));
      throw StateError(name);
    }
  }

  @override
  void close() => events.add('$name:close');
}

final class _GatedAppLifecycle extends PluginAppLifecycle {
  _GatedAppLifecycle(
    this.events, {
    required this.hookStarted,
    required this.releaseHook,
  });

  final List<String> events;
  final Completer<void> hookStarted;
  final Completer<void> releaseHook;

  @override
  Future<void> observeAppState(String state, {required bool foreground}) async {
    events.add('observe:start');
    hookStarted.complete();
    await releaseHook.future;
    events.add('observe:end');
  }

  @override
  void close() => events.add('close');
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

final class _GatedSessionLifecycle extends PluginSessionLifecycle {
  _GatedSessionLifecycle(
    this.events, {
    required this.hookStarted,
    required this.releaseHook,
  });

  final List<String> events;
  final Completer<void> hookStarted;
  final Completer<void> releaseHook;

  @override
  Future<void> setForeground(bool foreground) async {
    events.add('foreground:start');
    hookStarted.complete();
    await releaseHook.future;
    events.add('foreground:end');
  }

  @override
  void close() => events.add('close');
}

final class _RevocableHost {
  bool _revoked = false;

  String read() {
    if (_revoked) throw StateError('Scoped authority was revoked.');
    return 'available';
  }

  void revoke() => _revoked = true;
}

final class _AsyncSessionLifecycle extends PluginSessionLifecycle {
  _AsyncSessionLifecycle(this.name, this.events);

  final String name;
  final List<String> events;

  @override
  Future<void> close() async {
    events.add('$name:close:start');
    await Future<void>.delayed(Duration.zero);
    events.add('$name:close:end');
  }
}
