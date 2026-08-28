import 'dart:async';

import '../models/bookmark.dart';
import 'discourse_model_codec.dart';
import 'plugin_manifest.dart';
import 'plugin_registry.dart';
import 'site_plugin_api.dart';

export 'plugin_contracts.dart';

final class PluginLifecycleException implements Exception {
  PluginLifecycleException(this.operation, Iterable<Object> failures)
    : failures = List.unmodifiable(failures);

  final String operation;
  final List<Object> failures;

  @override
  String toString() =>
      'Plugin lifecycle $operation failed ${failures.length} time(s).';
}

void _revokeConsumers(
  Iterable<void Function()> revocations,
  List<Object> failures,
) {
  for (final revoke in revocations.toList(growable: false).reversed) {
    try {
      revoke();
    } catch (error) {
      failures.add(error);
    }
  }
}

/// Serializes lifecycle operations while allowing each caller to observe its
/// own failure. A failed operation is absorbed only by the internal tail, so
/// teardown always advances after earlier hook failures.
final class _PluginLifecycleOperationQueue {
  Future<void>? _tail;

  Future<void> run(FutureOr<void> Function() operation) {
    final previous = _tail;
    final next = previous == null
        ? Future<void>.sync(operation)
        : previous.then((_) => Future<void>.sync(operation));
    final absorbed = next.then<void>((_) {}, onError: (_, _) {});
    _tail = absorbed;
    unawaited(
      absorbed.whenComplete(() {
        if (identical(_tail, absorbed)) _tail = null;
      }),
    );
    return next;
  }
}

final class PluginInstaller {
  const PluginInstaller._();

  static InstalledPlugins install(PluginManifest manifest) {
    final modules = manifest.modules;
    final ordered = _validateAndOrder(modules);
    final registrations = <_PluginRegistration>[];

    for (final module in ordered) {
      final registrar = _PluginRegistrar(module.descriptor);
      try {
        module.module.register(registrar);
      } catch (error) {
        throw PluginInstallationException(
          'Module ${module.descriptor.id} threw while registering.',
          error,
        );
      }
      registrations.add(registrar.freeze());
    }

    final capabilities = <PluginCapability>[
      for (final registration in registrations) ...registration.capabilities,
    ];
    late final PluginRegistry registry;
    try {
      registry = PluginRegistry.validated(capabilities.whereType<SitePlugin>());
    } catch (error) {
      throw PluginInstallationException('Capability validation failed.', error);
    }
    return InstalledPlugins._(
      registrations: List.unmodifiable(registrations),
      registry: registry,
    );
  }

  static List<_ModuleSnapshot> _validateAndOrder(List<PluginModule> modules) {
    final snapshots = <_ModuleSnapshot>[];
    for (final module in modules) {
      final PluginDescriptor descriptor;
      try {
        descriptor = _snapshotDescriptor(module.descriptor);
      } catch (error) {
        throw PluginInstallationException(
          'A module threw while describing itself.',
          error,
        );
      }
      snapshots.add(_ModuleSnapshot(module, descriptor));
    }

    final byId = <PluginId, _ModuleSnapshot>{};
    final manifestIndex = <PluginId, int>{};
    final routeOwners = <String, PluginId>{};
    final syntaxOwners = <String, PluginId>{};
    final exclusiveOwners = <String, PluginId>{};

    for (var index = 0; index < snapshots.length; index++) {
      final module = snapshots[index];
      final descriptor = module.descriptor;
      _validateDescriptor(descriptor);
      final previous = byId[descriptor.id];
      if (previous != null) {
        throw PluginInstallationException(
          'Duplicate module id ${descriptor.id}.',
        );
      }
      byId[descriptor.id] = module;
      manifestIndex[descriptor.id] = index;
      _claim(routeOwners, descriptor.routeNamespaces, descriptor.id, 'route');
      _claim(syntaxOwners, descriptor.syntaxIds, descriptor.id, 'syntax');
      _claim(
        exclusiveOwners,
        descriptor.exclusiveClaims,
        descriptor.id,
        'exclusive capability',
      );
    }

    final outgoing = <PluginId, Set<PluginId>>{
      for (final id in byId.keys) id: <PluginId>{},
    };
    final indegree = <PluginId, int>{for (final id in byId.keys) id: 0};

    for (final module in snapshots) {
      for (final dependency in module.descriptor.dependencies) {
        final provider = byId[dependency.id];
        if (provider == null) {
          if (dependency.optional) continue;
          throw PluginInstallationException(
            '${module.descriptor.id} requires missing ${dependency.id}.',
          );
        }
        if (!dependency.versions.allows(provider.descriptor.version)) {
          throw PluginInstallationException(
            '${module.descriptor.id} requires ${dependency.id} '
            '${dependency.versions}, found ${provider.descriptor.version}.',
          );
        }
        if (outgoing[dependency.id]!.add(module.descriptor.id)) {
          indegree[module.descriptor.id] = indegree[module.descriptor.id]! + 1;
        }
      }
    }

    final ready = <PluginId>[
      for (final entry in indegree.entries)
        if (entry.value == 0) entry.key,
    ]..sort((a, b) => manifestIndex[a]!.compareTo(manifestIndex[b]!));
    final ordered = <_ModuleSnapshot>[];
    while (ready.isNotEmpty) {
      final id = ready.removeAt(0);
      ordered.add(byId[id]!);
      for (final dependent in outgoing[id]!) {
        final remaining = indegree[dependent]! - 1;
        indegree[dependent] = remaining;
        if (remaining != 0) continue;
        ready.add(dependent);
        ready.sort((a, b) => manifestIndex[a]!.compareTo(manifestIndex[b]!));
      }
    }
    if (ordered.length != snapshots.length) {
      final cycle = [
        for (final entry in indegree.entries)
          if (entry.value > 0) entry.key.value,
      ];
      throw PluginInstallationException(
        'Dependency cycle among ${cycle.join(', ')}.',
      );
    }
    return ordered;
  }

  static PluginDescriptor _snapshotDescriptor(PluginDescriptor descriptor) {
    return PluginDescriptor(
      id: descriptor.id,
      version: descriptor.version,
      dependencies: List.unmodifiable(descriptor.dependencies),
      routeNamespaces: Set.unmodifiable(descriptor.routeNamespaces),
      syntaxIds: Set.unmodifiable(descriptor.syntaxIds),
      exclusiveClaims: Set.unmodifiable(descriptor.exclusiveClaims),
      liveChannelScopes: Set.unmodifiable(descriptor.liveChannelScopes),
    );
  }

  static void _validateDescriptor(PluginDescriptor descriptor) {
    if (!RegExp(
      r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$',
    ).hasMatch(descriptor.id.value)) {
      throw PluginInstallationException(
        'Invalid module id ${descriptor.id.value}.',
      );
    }
    if (descriptor.version.major < 0 ||
        descriptor.version.minor < 0 ||
        descriptor.version.patch < 0) {
      throw PluginInstallationException(
        'Invalid version ${descriptor.version} for ${descriptor.id}.',
      );
    }
    for (final scope in descriptor.liveChannelScopes) {
      _validateLiveChannelScope(descriptor.id, scope);
    }
  }

  static const _reservedLiveChannelScopes = <PluginLiveChannelScope>[
    PluginLiveChannelScope.prefix('/latest'),
    PluginLiveChannelScope.prefix('/new'),
    PluginLiveChannelScope.prefix('/notification'),
    PluginLiveChannelScope.prefix('/reviewable_counts'),
    PluginLiveChannelScope.prefix('/user-status'),
    PluginLiveChannelScope.prefix('/do-not-disturb'),
    PluginLiveChannelScope.prefix('/topic'),
  ];

  static void _validateLiveChannelScope(
    PluginId owner,
    PluginLiveChannelScope scope,
  ) {
    final path = scope.path;
    if (!RegExp(r'^/[A-Za-z0-9._~-]+(?:/[A-Za-z0-9._~-]+)*$').hasMatch(path)) {
      throw PluginInstallationException(
        '$owner declares invalid live-channel scope $path.',
      );
    }
    for (final reserved in _reservedLiveChannelScopes) {
      if (scope.allows(reserved.path) || reserved.allows(scope.path)) {
        throw PluginInstallationException(
          '$owner declares live-channel scope $path, which overlaps reserved '
          'core scope ${reserved.path}.',
        );
      }
    }
  }

  static void _claim(
    Map<String, PluginId> owners,
    Iterable<String> values,
    PluginId owner,
    String kind,
  ) {
    for (final value in values) {
      if (value.trim().isEmpty) {
        throw PluginInstallationException('$owner declares an empty $kind id.');
      }
      final previous = owners[value];
      if (previous != null) {
        throw PluginInstallationException(
          '$kind id $value is claimed by both $previous and $owner.',
        );
      }
      owners[value] = owner;
    }
  }
}

final class InstalledPlugins {
  InstalledPlugins._({
    required List<_PluginRegistration> registrations,
    required this.registry,
  }) : _registrations = registrations,
       descriptors = List.unmodifiable(
         registrations.map((registration) => registration.descriptor),
       ),
       models = DiscourseModelCodec(extensions: registry);

  final List<_PluginRegistration> _registrations;
  final List<PluginDescriptor> descriptors;
  final PluginRegistry registry;
  final DiscourseModelCodec models;

  final Set<_AppLifecycleRegistration> _started = {};
  final Map<_AppLifecycleRegistration, Set<PluginStartupPhase>>
  _completedPhases = {};
  final Map<_AppLifecycleRegistration, PluginHostBindings>
  _appLifecycleBindings = {};
  final Map<_AppLifecycleRegistration, List<void Function()>>
  _appLifecycleRevocations = {};
  final _appLifecycleOperations = _PluginLifecycleOperationQueue();
  PluginHostBindings _appBindings = const PluginHostBindings.empty();
  bool _closing = false;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Every installed capability implementing [T], in manifest order.
  Iterable<T> capabilities<T extends PluginCapability>() sync* {
    for (final registration in _registrations) {
      yield* registration.capabilities.whereType<T>();
    }
  }

  Set<PluginLiveChannelScope> liveChannelScopesFor(PluginId owner) {
    for (final registration in _registrations) {
      if (registration.descriptor.id == owner) {
        return registration.descriptor.liveChannelScopes;
      }
    }
    return const {};
  }

  Future<void> startPhase(
    PluginStartupPhase phase, {
    PluginHostBindings? bindings,
  }) {
    if (_closing || _closed) {
      return Future<void>.error(StateError('Installed plugins are closed.'));
    }
    return _appLifecycleOperations.run(
      () => _startPhase(phase, bindings: bindings),
    );
  }

  Future<void> _startPhase(
    PluginStartupPhase phase, {
    PluginHostBindings? bindings,
  }) async {
    if (bindings != null) _appBindings = bindings;
    try {
      for (final registration in _registrations) {
        for (final appLifecycle in registration.appLifecycles) {
          final completed = _completedPhases[appLifecycle];
          if (completed?.contains(phase) ?? false) continue;
          final restrictedBindings = _appLifecycleBindings.putIfAbsent(
            appLifecycle,
            () {
              _appLifecycleRevocations[appLifecycle] = _appBindings
                  .consumerRevocations(
                    appLifecycle.requiredPorts,
                    consumer: registration.descriptor.id,
                  )
                  .toList(growable: false);
              return _appBindings.restrictedTo(
                appLifecycle.requiredPorts,
                consumer: registration.descriptor.id,
              );
            },
          );
          await appLifecycle.lifecycle.startPhase(phase, restrictedBindings);
          _started.add(appLifecycle);
          (_completedPhases[appLifecycle] ??= {}).add(phase);
        }
      }
    } catch (error) {
      final failures = <Object>[error];
      await _closeAppLifecycles(failures);
      _closing = true;
      _closed = true;
      throw PluginLifecycleException('startPhase(${phase.name})', failures);
    }
  }

  Future<void> observeAppState(String state, {required bool foreground}) {
    if (_closing || _closed) return Future<void>.value();
    return _appLifecycleOperations.run(
      () => _dispatchAppLifecycles(
        'observeAppState',
        (lifecycle) => lifecycle.observeAppState(state, foreground: foreground),
      ),
    );
  }

  Future<void> flush() {
    if (_closing || _closed) return Future<void>.value();
    return _appLifecycleOperations.run(
      () => _dispatchAppLifecycles('flush', (lifecycle) => lifecycle.flush()),
    );
  }

  Future<void> _dispatchAppLifecycles(
    String operation,
    FutureOr<void> Function(PluginAppLifecycle lifecycle) invoke,
  ) {
    if (_closed) return Future<void>.value();
    final failures = <Object>[];
    final pending = <Future<void>>[];
    for (final registration in _registrations) {
      for (final appLifecycle in registration.appLifecycles) {
        if (!_started.contains(appLifecycle)) continue;
        try {
          final result = invoke(appLifecycle.lifecycle);
          if (result is Future<void>) {
            pending.add(
              result.onError((error, _) {
                failures.add(error ?? StateError('Unknown plugin failure.'));
              }),
            );
          }
        } catch (error) {
          failures.add(error);
        }
      }
    }
    return _finishAppDispatch(operation, pending, failures);
  }

  static Future<void> _finishAppDispatch(
    String operation,
    List<Future<void>> pending,
    List<Object> failures,
  ) async {
    await Future.wait(pending);
    if (failures.isNotEmpty) {
      throw PluginLifecycleException(operation, failures);
    }
  }

  PluginSession openSession(PluginHostBindings bindings) {
    if (_closing || _closed) {
      throw StateError('Installed plugins are closed.');
    }
    final contributions = <_OwnedSessionContribution>[];
    final consumerRevocations = <void Function()>[];
    final services = <PluginServiceKey<Object>, Object>{};
    final serviceOwners = <PluginServiceKey<Object>, PluginId>{};
    try {
      for (final registration in _registrations) {
        final dependencies = _PluginDependencies(
          consumer: registration.descriptor.id,
          declared: registration.descriptor.dependencies,
          services: services,
        );
        for (final session in registration.sessions) {
          for (final port in session.requiredPorts) {
            if (!bindings.contains(port)) {
              throw PluginInstallationException(
                '${registration.descriptor.id} requires host port ${port.id}.',
              );
            }
          }
          consumerRevocations.addAll(
            bindings.consumerRevocations(
              session.requiredPorts,
              consumer: registration.descriptor.id,
            ),
          );
          final contribution = _OwnedSessionContribution(
            registration.descriptor.id,
            session.factory(
              bindings.restrictedTo(
                session.requiredPorts,
                consumer: registration.descriptor.id,
              ),
              dependencies,
            ),
          );
          contributions.add(contribution);
          _collectServices(contribution, services, serviceOwners);
        }
      }
      return PluginSession._(contributions, services, consumerRevocations);
    } catch (error) {
      _revokeConsumers(consumerRevocations, <Object>[]);
      unawaited(_rollbackSessionContributions(contributions));
      rethrow;
    }
  }

  static Future<void> _rollbackSessionContributions(
    List<_OwnedSessionContribution> contributions,
  ) async {
    for (final contribution in contributions.reversed) {
      try {
        await contribution.value.lifecycle.close();
      } catch (_) {
        // Preserve the installation error which triggered this rollback.
      }
    }
  }

  static void _collectServices(
    _OwnedSessionContribution contribution,
    Map<PluginServiceKey<Object>, Object> services,
    Map<PluginServiceKey<Object>, PluginId> owners,
  ) {
    for (final service in contribution.value.services) {
      if (service.key.owner != contribution.owner) {
        throw PluginInstallationException(
          '${contribution.owner} contributed service ${service.key.id}, '
          'which is owned by ${service.key.owner}.',
        );
      }
      final previous = owners[service.key];
      if (previous != null) {
        throw PluginInstallationException(
          'Service ${service.key.id} is provided by both $previous and '
          '${contribution.owner}.',
        );
      }
      owners[service.key] = contribution.owner;
      services[service.key] = service.value;
    }
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    final pending = _closeFuture;
    if (pending != null) return pending;
    _closing = true;
    final close = _appLifecycleOperations.run(_close);
    _closeFuture = close;
    return close;
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    final failures = <Object>[];
    await _closeAppLifecycles(failures);
    if (failures.isNotEmpty) {
      throw PluginLifecycleException('close', failures);
    }
  }

  Future<void> _closeAppLifecycles(List<Object> failures) async {
    for (final registration in _registrations.reversed) {
      for (final appLifecycle in registration.appLifecycles.reversed) {
        _revokeConsumers(
          _appLifecycleRevocations.remove(appLifecycle) ?? const [],
          failures,
        );
        if (!_started.remove(appLifecycle)) continue;
        try {
          await appLifecycle.lifecycle.close();
        } catch (error) {
          failures.add(error);
        }
      }
    }
    _completedPhases.clear();
    _appLifecycleBindings.clear();
    _appLifecycleRevocations.clear();
  }
}

final class PluginSession {
  PluginSession._(
    List<_OwnedSessionContribution> contributions,
    Map<PluginServiceKey<Object>, Object> services,
    List<void Function()> consumerRevocations,
  ) : _contributions = List.unmodifiable(contributions),
      _services = Map.unmodifiable(services),
      _consumerRevocations = List.of(consumerRevocations),
      _capabilities = List.unmodifiable([
        for (final contribution in contributions)
          ...contribution.value.capabilities,
      ]) {
    _validateBookmarkTargets(contributions);
  }

  final List<_OwnedSessionContribution> _contributions;
  final Map<PluginServiceKey<Object>, Object> _services;
  final List<void Function()> _consumerRevocations;
  final List<PluginSessionCapability> _capabilities;
  final _lifecycleOperations = _PluginLifecycleOperationQueue();
  bool _closing = false;
  bool _closed = false;
  Future<void>? _closeFuture;

  static void _validateBookmarkTargets(
    List<_OwnedSessionContribution> contributions,
  ) {
    final idOwners = <String, PluginId>{
      BookmarkTargetType.post.id: BookmarkTargetType.post.owner,
      BookmarkTargetType.topic.id: BookmarkTargetType.topic.owner,
    };
    final wireOwners = <String, PluginId>{
      BookmarkTargetType.post.wireName: BookmarkTargetType.post.owner,
      BookmarkTargetType.topic.wireName: BookmarkTargetType.topic.owner,
    };
    for (final contribution in contributions) {
      for (final capability
          in contribution.value.capabilities
              .whereType<PluginBookmarkTargetStrategy>()) {
        final target = capability.pluginBookmarkTarget;
        if (target.owner != contribution.owner ||
            target.name.trim().isEmpty ||
            target.name.contains('/') ||
            target.wireName.trim().isEmpty) {
          throw PluginInstallationException(
            'Bookmark target ${target.id} must be namespaced to '
            '${contribution.owner} and declare a wire type.',
          );
        }
        final previousIdOwner = idOwners[target.id];
        if (previousIdOwner != null) {
          throw PluginInstallationException(
            'Bookmark target ${target.id} is claimed by both '
            '$previousIdOwner and ${contribution.owner}.',
          );
        }
        final previousWireOwner = wireOwners[target.wireName];
        if (previousWireOwner != null) {
          throw PluginInstallationException(
            'Bookmark wire type ${target.wireName} is claimed by both '
            '$previousWireOwner and ${contribution.owner}.',
          );
        }
        idOwners[target.id] = contribution.owner;
        wireOwners[target.wireName] = contribution.owner;
      }
    }
  }

  T? maybeService<T extends Object>(PluginServiceKey<T> key) =>
      _services[key] as T?;

  /// Compatibility alias for callers which used the original nullable API.
  T? service<T extends Object>(PluginServiceKey<T> key) => maybeService(key);

  T require<T extends Object>(PluginServiceKey<T> key) {
    final value = maybeService(key);
    if (value == null) throw StateError('Plugin service ${key.id} is absent.');
    return value;
  }

  /// Every installed session capability implementing [T], in manifest order.
  Iterable<T> capabilities<T extends PluginSessionCapability>() =>
      _capabilities.whereType<T>();

  /// Every installed session capability implementing [T], with its owner.
  ///
  /// Shell adapters use ownership to scope host authority without requiring a
  /// capability to repeat or spoof its module id.
  Iterable<({PluginId owner, T capability})>
  ownedCapabilities<T extends PluginSessionCapability>() sync* {
    for (final contribution in _contributions) {
      for (final capability in contribution.value.capabilities.whereType<T>()) {
        yield (owner: contribution.owner, capability: capability);
      }
    }
  }

  Future<void> setForeground(bool foreground) {
    if (_closing || _closed) return Future<void>.value();
    return _lifecycleOperations.run(
      () => _dispatch('setForeground', (lifecycle) {
        return lifecycle.setForeground(foreground);
      }),
    );
  }

  Future<void> forget(String siteUrl) {
    if (_closing || _closed) return Future<void>.value();
    return _lifecycleOperations.run(
      () => _dispatch('forget', (lifecycle) => lifecycle.forget(siteUrl)),
    );
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    final pending = _closeFuture;
    if (pending != null) return pending;
    _closing = true;
    final failures = <Object>[];
    _revokeConsumers(_consumerRevocations, failures);
    _consumerRevocations.clear();
    final close = _lifecycleOperations.run(() => _close(failures));
    _closeFuture = close;
    return close;
  }

  Future<void> _close(List<Object> failures) async {
    if (_closed) return;
    _closed = true;
    for (final contribution in _contributions.reversed) {
      try {
        await contribution.value.lifecycle.close();
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw PluginLifecycleException('session.close', failures);
    }
  }

  Future<void> _dispatch(
    String operation,
    FutureOr<void> Function(PluginSessionLifecycle lifecycle) invoke,
  ) {
    if (_closed) return Future<void>.value();
    final failures = <Object>[];
    final pending = <Future<void>>[];
    for (final contribution in _contributions) {
      try {
        final result = invoke(contribution.value.lifecycle);
        if (result is Future<void>) {
          pending.add(
            result.onError((error, _) {
              failures.add(error ?? StateError('Unknown plugin failure.'));
            }),
          );
        }
      } catch (error) {
        failures.add(error);
      }
    }
    return _finishDispatch('session.$operation', pending, failures);
  }

  static Future<void> _finishDispatch(
    String operation,
    List<Future<void>> pending,
    List<Object> failures,
  ) async {
    await Future.wait(pending);
    if (failures.isNotEmpty) {
      throw PluginLifecycleException(operation, failures);
    }
  }
}

final class _PluginDependencies implements PluginDependencies {
  factory _PluginDependencies({
    required PluginId consumer,
    required Iterable<PluginDependency> declared,
    required Map<PluginServiceKey<Object>, Object> services,
  }) {
    final declaredOwners = Set<PluginId>.unmodifiable(
      declared.map((dependency) => dependency.id),
    );
    return _PluginDependencies._(
      consumer,
      declaredOwners,
      Map.unmodifiable({
        for (final entry in services.entries)
          if (declaredOwners.contains(entry.key.owner)) entry.key: entry.value,
      }),
    );
  }

  const _PluginDependencies._(
    this.consumer,
    this._declaredOwners,
    this._services,
  );

  final PluginId consumer;
  final Set<PluginId> _declaredOwners;
  final Map<PluginServiceKey<Object>, Object> _services;

  @override
  T? maybe<T extends Object>(PluginServiceKey<T> key) {
    _validateDeclared(key);
    return _services[key] as T?;
  }

  @override
  T require<T extends Object>(PluginServiceKey<T> key) {
    final value = maybe(key);
    if (value == null) {
      throw PluginInstallationException(
        '$consumer requires missing dependency service ${key.id}.',
      );
    }
    return value;
  }

  void _validateDeclared(PluginServiceKey<Object> key) {
    if (_declaredOwners.contains(key.owner)) return;
    throw PluginInstallationException(
      '$consumer attempted to access undeclared dependency service ${key.id}.',
    );
  }
}

final class _PluginRegistrar implements PluginRegistrar {
  _PluginRegistrar(this.descriptor);

  final PluginDescriptor descriptor;
  final List<PluginCapability> _capabilities = [];
  final List<_AppLifecycleRegistration> _appLifecycles = [];
  final List<_SessionRegistration> _sessions = [];
  final Set<String> _routeNamespaces = {};
  final Set<String> _syntaxIds = {};
  final Set<String> _exclusiveClaims = {};
  final Set<PluginLiveChannelScope> _liveChannelScopes = {};

  @override
  void addCapability(PluginCapability capability) {
    if (capability.name != descriptor.id.value) {
      throw PluginInstallationException(
        '${descriptor.id} registered capability ${capability.name}.',
      );
    }
    if (capability case final PluginRecord<Object> recordPlugin
        when recordPlugin.record.owner != descriptor.id.value) {
      throw PluginInstallationException(
        '${descriptor.id} registered record ${recordPlugin.record.id}, '
        'which is owned by ${recordPlugin.record.owner}.',
      );
    }
    _capabilities.add(capability);
  }

  @override
  void addAppLifecycle(
    PluginAppLifecycle lifecycle, {
    Iterable<PluginHostPortKey<Object>> requires = const [],
  }) {
    _appLifecycles.add(
      _AppLifecycleRegistration(lifecycle, List.unmodifiable(requires)),
    );
  }

  @override
  void addRouteNamespace(String namespace) {
    _addClaim(_routeNamespaces, namespace, 'route namespace');
  }

  @override
  void addSyntaxId(String syntaxId) {
    _addClaim(_syntaxIds, syntaxId, 'syntax id');
  }

  @override
  void addExclusiveClaim(String claim) {
    _addClaim(_exclusiveClaims, claim, 'exclusive claim');
  }

  @override
  void addLiveChannelScope(PluginLiveChannelScope scope) {
    if (!_liveChannelScopes.add(scope)) {
      throw PluginInstallationException(
        '${descriptor.id} registered duplicate live-channel scope '
        '${scope.path}.',
      );
    }
  }

  @override
  void addSession(
    PluginSessionFactory factory, {
    Iterable<PluginHostPortKey<Object>> requires = const [],
  }) {
    _sessions.add(_SessionRegistration(factory, List.unmodifiable(requires)));
  }

  _PluginRegistration freeze() {
    _validateClaims(
      kind: 'route namespaces',
      declared: descriptor.routeNamespaces,
      registered: _routeNamespaces,
    );
    _validateClaims(
      kind: 'syntax ids',
      declared: descriptor.syntaxIds,
      registered: _syntaxIds,
    );
    _validateClaims(
      kind: 'exclusive claims',
      declared: descriptor.exclusiveClaims,
      registered: _exclusiveClaims,
    );
    _validateClaims(
      kind: 'live-channel scopes',
      declared: descriptor.liveChannelScopes,
      registered: _liveChannelScopes,
    );

    final capabilitySyntaxIds = <String>{};
    for (final capability in _capabilities.whereType<ComposerSyntaxPlugin>()) {
      _addClaim(capabilitySyntaxIds, capability.syntaxId, 'composer syntax id');
    }
    _validateClaims(
      kind: 'composer syntax ids',
      declared: _syntaxIds,
      registered: capabilitySyntaxIds,
    );

    return _PluginRegistration(
      descriptor,
      List.unmodifiable(_capabilities),
      List.unmodifiable(_appLifecycles),
      List.unmodifiable(_sessions),
    );
  }

  void _addClaim(Set<String> claims, String claim, String kind) {
    if (!claims.add(claim)) {
      throw PluginInstallationException(
        '${descriptor.id} registered duplicate $kind $claim.',
      );
    }
  }

  void _validateClaims<T>({
    required String kind,
    required Set<T> declared,
    required Set<T> registered,
  }) {
    if (declared.length == registered.length &&
        declared.containsAll(registered)) {
      return;
    }
    throw PluginInstallationException(
      '${descriptor.id} declared $kind ${_formatClaims(declared)} but '
      'registered ${_formatClaims(registered)}.',
    );
  }

  static String _formatClaims(Set<Object?> claims) {
    final sorted = claims.map((claim) => claim.toString()).toList()..sort();
    return '{${sorted.join(', ')}}';
  }
}

final class _PluginRegistration {
  const _PluginRegistration(
    this.descriptor,
    this.capabilities,
    this.appLifecycles,
    this.sessions,
  );

  final PluginDescriptor descriptor;
  final List<PluginCapability> capabilities;
  final List<_AppLifecycleRegistration> appLifecycles;
  final List<_SessionRegistration> sessions;
}

final class _ModuleSnapshot {
  const _ModuleSnapshot(this.module, this.descriptor);

  final PluginModule module;
  final PluginDescriptor descriptor;
}

final class _SessionRegistration {
  const _SessionRegistration(this.factory, this.requiredPorts);

  final PluginSessionFactory factory;
  final List<PluginHostPortKey<Object>> requiredPorts;
}

final class _AppLifecycleRegistration {
  const _AppLifecycleRegistration(this.lifecycle, this.requiredPorts);

  final PluginAppLifecycle lifecycle;
  final List<PluginHostPortKey<Object>> requiredPorts;
}

final class _OwnedSessionContribution {
  const _OwnedSessionContribution(this.owner, this.value);

  final PluginId owner;
  final PluginSessionContribution value;
}
