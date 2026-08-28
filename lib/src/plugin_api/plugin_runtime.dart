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

    final capabilities = <SitePlugin>[
      for (final registration in registrations) ...registration.capabilities,
    ];
    late final PluginRegistry registry;
    try {
      registry = PluginRegistry.validated(capabilities);
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

  final Set<PluginAppLifecycle> _started = {};
  final Map<PluginAppLifecycle, Set<PluginStartupPhase>> _completedPhases = {};
  bool _closed = false;

  Future<void> startPhase(PluginStartupPhase phase) async {
    if (_closed) throw StateError('Installed plugins are closed.');
    try {
      for (final registration in _registrations) {
        for (final lifecycle in registration.appLifecycles) {
          final completed = _completedPhases[lifecycle];
          if (completed?.contains(phase) ?? false) continue;
          await lifecycle.startPhase(phase);
          _started.add(lifecycle);
          (_completedPhases[lifecycle] ??= {}).add(phase);
        }
      }
    } catch (error) {
      final failures = <Object>[error];
      await _closeAppLifecycles(failures);
      _closed = true;
      throw PluginLifecycleException('startPhase(${phase.name})', failures);
    }
  }

  PluginSession openSession(PluginHostBindings bindings) {
    if (_closed) throw StateError('Installed plugins are closed.');
    final contributions = <_OwnedSessionContribution>[];
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
      return PluginSession._(contributions, services, {
        for (final registration in _registrations) registration.descriptor.id,
      });
    } catch (error) {
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

  Future<void> close() async {
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
      for (final lifecycle in registration.appLifecycles.reversed) {
        if (!_started.remove(lifecycle)) continue;
        try {
          await lifecycle.close();
        } catch (error) {
          failures.add(error);
        }
      }
    }
    _completedPhases.clear();
  }
}

final class PluginSession {
  PluginSession._(
    List<_OwnedSessionContribution> contributions,
    Map<PluginServiceKey<Object>, Object> services,
    Set<PluginId> owners,
  ) : _contributions = List.unmodifiable(contributions),
      _services = Map.unmodifiable(services),
      _owners = Set.unmodifiable(owners),
      _capabilities = List.unmodifiable([
        for (final contribution in contributions)
          ...contribution.value.capabilities,
      ]) {
    _ownedServiceViews = Map.unmodifiable({
      for (final owner in _owners)
        owner: PluginOwnedServices._(owner, _services),
    });
    _validateBookmarkTargets(contributions);
  }

  final List<_OwnedSessionContribution> _contributions;
  final Map<PluginServiceKey<Object>, Object> _services;
  final Set<PluginId> _owners;
  late final Map<PluginId, PluginOwnedServices> _ownedServiceViews;
  final List<PluginSessionCapability> _capabilities;
  bool _closed = false;

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

  /// A resolver which can see only services republished by [owner].
  ///
  /// Dependency services are intentionally not transitively visible here. A
  /// module may consume them while constructing its session and republish a
  /// deliberately narrower adapter under one of its own keys for its UI.
  PluginOwnedServices servicesFor(PluginId owner) {
    final services = _ownedServiceViews[owner];
    if (services == null) {
      throw StateError('Plugin $owner is not installed in this session.');
    }
    return services;
  }

  /// Every installed session capability implementing [T], in manifest order.
  Iterable<T> capabilities<T extends PluginSessionCapability>() =>
      _capabilities.whereType<T>();

  Future<void> setForeground(bool foreground) =>
      _dispatch('setForeground', (lifecycle) {
        return lifecycle.setForeground(foreground);
      });

  Future<void> forget(String siteUrl) =>
      _dispatch('forget', (lifecycle) => lifecycle.forget(siteUrl));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final failures = <Object>[];
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

/// The immutable service view carried by one owner-scoped UI contribution.
final class PluginOwnedServices {
  const PluginOwnedServices._(this.owner, this._services);

  const PluginOwnedServices.detached(PluginId owner) : this._(owner, const {});

  final PluginId owner;
  final Map<PluginServiceKey<Object>, Object> _services;

  T? maybe<T extends Object>(PluginServiceKey<T> key) {
    _checkOwner(key);
    return _services[key] as T?;
  }

  T require<T extends Object>(PluginServiceKey<T> key) {
    final value = maybe(key);
    if (value == null) throw StateError('Plugin service ${key.id} is absent.');
    return value;
  }

  void _checkOwner<T extends Object>(PluginServiceKey<T> key) {
    if (key.owner == owner) return;
    throw StateError(
      'Plugin $owner cannot resolve service ${key.id} owned by ${key.owner}.',
    );
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
  final List<SitePlugin> _capabilities = [];
  final List<PluginAppLifecycle> _appLifecycles = [];
  final List<_SessionRegistration> _sessions = [];
  final Set<String> _routeNamespaces = {};
  final Set<String> _syntaxIds = {};
  final Set<String> _exclusiveClaims = {};

  @override
  void addCapability(PluginCapability capability) {
    if (capability is! SitePlugin) {
      throw PluginInstallationException(
        '${descriptor.id} registered a capability outside the app API.',
      );
    }
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
  void addAppLifecycle(PluginAppLifecycle lifecycle) {
    _appLifecycles.add(lifecycle);
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

  void _validateClaims({
    required String kind,
    required Set<String> declared,
    required Set<String> registered,
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

  static String _formatClaims(Set<String> claims) {
    final sorted = claims.toList()..sort();
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
  final List<SitePlugin> capabilities;
  final List<PluginAppLifecycle> appLifecycles;
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

final class _OwnedSessionContribution {
  const _OwnedSessionContribution(this.owner, this.value);

  final PluginId owner;
  final PluginSessionContribution value;
}
