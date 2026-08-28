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
        module.register(registrar);
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

  static List<PluginModule> _validateAndOrder(List<PluginModule> modules) {
    final byId = <PluginId, PluginModule>{};
    final manifestIndex = <PluginId, int>{};
    final routeOwners = <String, PluginId>{};
    final syntaxOwners = <String, PluginId>{};
    final exclusiveOwners = <String, PluginId>{};

    for (var index = 0; index < modules.length; index++) {
      final module = modules[index];
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

    for (final module in modules) {
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
    final ordered = <PluginModule>[];
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
    if (ordered.length != modules.length) {
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
    try {
      for (final registration in _registrations) {
        for (final session in registration.sessions) {
          for (final port in session.requiredPorts) {
            if (!bindings.contains(port)) {
              throw PluginInstallationException(
                '${registration.descriptor.id} requires host port ${port.id}.',
              );
            }
          }
          contributions.add(
            _OwnedSessionContribution(
              registration.descriptor.id,
              session.factory(
                bindings.restrictedTo(
                  session.requiredPorts,
                  consumer: registration.descriptor.id,
                ),
              ),
            ),
          );
        }
      }
      return PluginSession._(contributions);
    } catch (error) {
      for (final contribution in contributions.reversed) {
        unawaited(Future.sync(contribution.value.lifecycle.close));
      }
      rethrow;
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
  PluginSession._(List<_OwnedSessionContribution> contributions)
    : _contributions = List.unmodifiable(contributions),
      _services = _collectServices(contributions),
      _capabilities = List.unmodifiable([
        for (final contribution in contributions)
          ...contribution.value.capabilities,
      ]) {
    _validateBookmarkTargets(contributions);
  }

  final List<_OwnedSessionContribution> _contributions;
  final Map<PluginServiceKey<Object>, Object> _services;
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

  T? service<T extends Object>(PluginServiceKey<T> key) => _services[key] as T?;

  T require<T extends Object>(PluginServiceKey<T> key) {
    final value = service(key);
    if (value == null) throw StateError('Plugin service ${key.id} is absent.');
    return value;
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

  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    final failures = <Object>[];
    final pending = <Future<void>>[];
    for (final contribution in _contributions.reversed) {
      try {
        final result = contribution.value.lifecycle.close();
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
    return _finishDispatch('session.close', pending, failures);
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

  static Map<PluginServiceKey<Object>, Object> _collectServices(
    List<_OwnedSessionContribution> contributions,
  ) {
    final services = <PluginServiceKey<Object>, Object>{};
    final owners = <PluginServiceKey<Object>, PluginId>{};
    for (final contribution in contributions) {
      for (final service in contribution.value.services) {
        if (service.key.owner != contribution.owner) {
          throw PluginInstallationException(
            'Service ${service.key.id} provided by ${contribution.owner} '
            'must be owned by ${contribution.owner}.',
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
    return Map.unmodifiable(services);
  }
}

final class _PluginRegistrar implements PluginRegistrar {
  _PluginRegistrar(this.descriptor);

  final PluginDescriptor descriptor;
  final List<SitePlugin> _capabilities = [];
  final List<PluginAppLifecycle> _appLifecycles = [];
  final List<_SessionRegistration> _sessions = [];

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
    _capabilities.add(capability);
  }

  @override
  void addAppLifecycle(PluginAppLifecycle lifecycle) {
    _appLifecycles.add(lifecycle);
  }

  @override
  void addSession(
    PluginSessionFactory factory, {
    Iterable<PluginHostPortKey<Object>> requires = const [],
  }) {
    _sessions.add(_SessionRegistration(factory, List.unmodifiable(requires)));
  }

  _PluginRegistration freeze() => _PluginRegistration(
    descriptor,
    List.unmodifiable(_capabilities),
    List.unmodifiable(_appLifecycles),
    List.unmodifiable(_sessions),
  );
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
