import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
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
        _Module(
          'one',
          syntaxIds: {'one/shared'},
          capabilities: [_SyntaxCapability('one', 'shared')],
        ),
        _Module(
          'two',
          syntaxIds: {'one/shared'},
          capabilities: [_SyntaxCapability('two', 'shared')],
        ),
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

  test('registered claims must exactly match descriptors and syntax', () {
    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module(
            'feature',
            routeNamespaces: {'route'},
            syntaxIds: {'feature/syntax'},
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
        syntaxIds: {'syntax-owner/declared'},
        registeredSyntaxIds: ['syntax-owner/declared'],
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

  test('composer syntax kinds cannot claim a foreign owner', () {
    expect(
      () => PluginInstaller.install(
        const PluginManifest([
          _Module(
            'feature',
            syntaxIds: {'feature/syntax'},
            capabilities: [
              _SyntaxCapability('feature', 'syntax', owner: 'other'),
            ],
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
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
        syntaxIds: {'syntax-owner/syntax'},
        registeredSyntaxIds: ['syntax-owner/syntax', 'syntax-owner/syntax'],
        capabilities: [_SyntaxCapability('syntax-owner', 'syntax')],
      ),
      const _Module(
        'exclusive-owner',
        exclusiveClaims: {'exclusive'},
        registeredExclusiveClaims: ['exclusive', 'exclusive'],
      ),
      const _Module(
        'syntax-capability-owner',
        syntaxIds: {'syntax-capability-owner/syntax'},
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
        syntaxIds: {'syntax-omitted/declared'},
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

  test(
    'static contributions preserve manifest order without a startup edge',
    () {
      const point = PluginStaticContributionPoint<String>(
        owner: PluginId('owner'),
        name: 'items',
      );
      final installed = PluginInstaller.install(
        PluginManifest([
          _StaticModule(
            'second',
            targets: const [PluginStaticContributionTarget(PluginId('owner'))],
            registerStatic: (registrar) => registrar.addStaticContribution(
              point,
              name: 'item',
              value: 'second',
            ),
          ),
          _StaticModule(
            'owner',
            registerStatic: (registrar) {
              registrar.addStaticContributionPoint(point);
              registrar.addStaticContribution(
                point,
                name: 'owned-item',
                value: 'owner',
              );
            },
          ),
        ]),
      );

      expect(installed.descriptors.map((item) => item.id.value), [
        'second',
        'owner',
      ]);
      expect(
        installed
            .staticContributionsFor(const PluginId('owner'))
            .contributions(point),
        ['second', 'owner'],
      );
    },
  );

  test('static contribution order ignores runtime dependency order', () {
    const point = PluginStaticContributionPoint<String>(
      owner: PluginId('owner'),
      name: 'items',
    );
    final installed = PluginInstaller.install(
      PluginManifest([
        _StaticModule(
          'first',
          dependencies: const [PluginDependency(PluginId('second'))],
          targets: const [PluginStaticContributionTarget(PluginId('owner'))],
          registerStatic: (registrar) => registrar.addStaticContribution(
            point,
            name: 'item',
            value: 'first',
          ),
        ),
        _StaticModule(
          'second',
          targets: const [PluginStaticContributionTarget(PluginId('owner'))],
          registerStatic: (registrar) => registrar.addStaticContribution(
            point,
            name: 'item',
            value: 'second',
          ),
        ),
        _StaticModule(
          'owner',
          registerStatic: (registrar) =>
              registrar.addStaticContributionPoint(point),
        ),
      ]),
    );

    expect(installed.descriptors.map((item) => item.id.value), [
      'second',
      'first',
      'owner',
    ]);
    expect(
      installed
          .staticContributionsFor(const PluginId('owner'))
          .contributions(point),
      ['first', 'second'],
    );
  });

  test('static contribution points and catalog reads enforce ownership', () {
    const point = PluginStaticContributionPoint<String>(
      owner: PluginId('owner'),
      name: 'items',
    );
    expect(
      () => PluginInstaller.install(
        PluginManifest([
          _StaticModule(
            'other',
            registerStatic: (registrar) =>
                registrar.addStaticContributionPoint(point),
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );

    final installed = PluginInstaller.install(
      PluginManifest([
        _StaticModule(
          'owner',
          registerStatic: (registrar) =>
              registrar.addStaticContributionPoint(point),
        ),
      ]),
    );
    expect(
      () => installed
          .staticContributionsFor(const PluginId('other'))
          .contributions(point),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('foreign static contributions require declared target authority', () {
    const point = PluginStaticContributionPoint<String>(
      owner: PluginId('owner'),
      name: 'items',
    );
    expect(
      () => PluginInstaller.install(
        PluginManifest([
          _StaticModule(
            'owner',
            registerStatic: (registrar) =>
                registrar.addStaticContributionPoint(point),
          ),
          _StaticModule(
            'contributor',
            registerStatic: (registrar) => registrar.addStaticContribution(
              point,
              name: 'item',
              value: 'value',
            ),
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('optional absent static contribution targets are dormant', () {
    const absentPoint = PluginStaticContributionPoint<String>(
      owner: PluginId('absent'),
      name: 'items',
    );
    final installed = PluginInstaller.install(
      PluginManifest([
        _StaticModule(
          'contributor',
          targets: const [
            PluginStaticContributionTarget(PluginId('absent'), optional: true),
          ],
          registerStatic: (registrar) => registrar.addStaticContribution(
            absentPoint,
            name: 'item',
            value: 'value',
          ),
        ),
      ]),
    );

    expect(installed.descriptors.single.id, const PluginId('contributor'));
  });

  test(
    'static contribution point type metadata must match its declaration',
    () {
      const declared = PluginStaticContributionPoint<String>(
        owner: PluginId('owner'),
        name: 'item',
      );
      const incompatible = PluginStaticContributionPoint<int>(
        owner: PluginId('owner'),
        name: 'item',
      );
      expect(
        () => PluginInstaller.install(
          PluginManifest([
            _StaticModule(
              'owner',
              registerStatic: (registrar) =>
                  registrar.addStaticContributionPoint(declared),
            ),
            _StaticModule(
              'contributor',
              targets: const [
                PluginStaticContributionTarget(PluginId('owner')),
              ],
              registerStatic: (registrar) => registrar.addStaticContribution(
                incompatible,
                name: 'item',
                value: 1,
              ),
            ),
          ]),
        ),
        throwsA(isA<PluginInstallationException>()),
      );
    },
  );

  test('singleton static contribution cardinality is validated at install', () {
    const point = PluginStaticContributionPoint<String>(
      owner: PluginId('owner'),
      name: 'singleton',
      cardinality: PluginStaticContributionCardinality.atMostOne,
    );
    expect(
      () => PluginInstaller.install(
        PluginManifest([
          _StaticModule(
            'owner',
            registerStatic: (registrar) =>
                registrar.addStaticContributionPoint(point),
          ),
          for (final id in ['first', 'second'])
            _StaticModule(
              id,
              targets: const [
                PluginStaticContributionTarget(PluginId('owner')),
              ],
              registerStatic: (registrar) => registrar.addStaticContribution(
                point,
                name: 'item',
                value: id,
              ),
            ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );

    const required = PluginStaticContributionPoint<String>(
      owner: PluginId('required-owner'),
      name: 'singleton',
      cardinality: PluginStaticContributionCardinality.exactlyOne,
    );
    expect(
      () => PluginInstaller.install(
        PluginManifest([
          _StaticModule(
            'required-owner',
            registerStatic: (registrar) =>
                registrar.addStaticContributionPoint(required),
          ),
        ]),
      ),
      throwsA(isA<PluginInstallationException>()),
    );
  });

  test('singleton catalog reads successful and absent contributions', () {
    const optional = PluginStaticContributionPoint<String>(
      owner: PluginId('owner'),
      name: 'optional',
      cardinality: PluginStaticContributionCardinality.atMostOne,
    );
    const required = PluginStaticContributionPoint<String>(
      owner: PluginId('owner'),
      name: 'required',
      cardinality: PluginStaticContributionCardinality.exactlyOne,
    );
    final installed = PluginInstaller.install(
      PluginManifest([
        _StaticModule(
          'owner',
          registerStatic: (registrar) {
            registrar.addStaticContributionPoint(optional);
            registrar.addStaticContributionPoint(required);
            registrar.addStaticContribution(
              required,
              name: 'only',
              value: 'value',
            );
          },
        ),
      ]),
    );
    final catalog = installed.staticContributionsFor(const PluginId('owner'));

    expect(catalog.single(optional), isNull);
    expect(catalog.single(required), 'value');
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
    this.registeredRouteNamespaces,
    this.registeredSyntaxIds,
    this.registeredExclusiveClaims,
    this.capabilities,
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
  final List<String>? registeredRouteNamespaces;
  final List<String>? registeredSyntaxIds;
  final List<String>? registeredExclusiveClaims;
  final List<PluginCapability>? capabilities;
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
    if (appLifecycle case final lifecycle?) {
      registrar.addAppLifecycle(lifecycle);
    }
    if (sessionFactory case final factory?) {
      registrar.addSession(factory, requires: requiredPorts);
    }
  }
}

final class _StaticModule implements PluginModule {
  _StaticModule(
    this.id, {
    this.dependencies = const [],
    this.targets = const [],
    required this.registerStatic,
  });

  final String id;
  final List<PluginDependency> dependencies;
  final List<PluginStaticContributionTarget> targets;
  final void Function(PluginRegistrar registrar) registerStatic;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: PluginId(id),
    dependencies: dependencies,
    staticContributionTargets: targets,
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(_Capability(id));
    registerStatic(registrar);
  }
}

final class _Capability implements SitePlugin {
  const _Capability(this.name);

  @override
  final String name;
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
  const _SyntaxCapability(this.name, this.syntaxName, {this.owner});

  @override
  final String name;

  final String syntaxName;
  final String? owner;

  @override
  ComposerSyntaxKind get composerSyntaxKind =>
      ComposerSyntaxKind(owner: PluginId(owner ?? name), name: syntaxName);

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
