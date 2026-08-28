import 'dart:async';

abstract interface class PluginCapability {
  String get name;
}

final class PluginId {
  const PluginId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is PluginId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class PluginVersion implements Comparable<PluginVersion> {
  const PluginVersion(this.major, [this.minor = 0, this.patch = 0]);

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(PluginVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is PluginVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

final class PluginVersionRange {
  const PluginVersionRange({required this.minimum, this.maximumExclusive});

  const PluginVersionRange.any()
    : minimum = const PluginVersion(0),
      maximumExclusive = null;

  final PluginVersion minimum;
  final PluginVersion? maximumExclusive;

  bool allows(PluginVersion version) =>
      version.compareTo(minimum) >= 0 &&
      (maximumExclusive == null || version.compareTo(maximumExclusive!) < 0);

  @override
  String toString() => maximumExclusive == null
      ? '>=$minimum'
      : '>=$minimum <${maximumExclusive!}';
}

final class PluginDependency {
  const PluginDependency(
    this.id, {
    this.versions = const PluginVersionRange.any(),
    this.optional = false,
  });

  final PluginId id;
  final PluginVersionRange versions;
  final bool optional;
}

/// Authority to contribute immutable installation-time behavior to a point
/// owned by another plugin.
///
/// Unlike [PluginDependency], this does not impose session startup order and
/// exposes no runtime service. It is deliberately a separate edge: an
/// extension may be consumed by its owner before the contributing plugin's
/// session is created.
final class PluginStaticContributionTarget {
  const PluginStaticContributionTarget(
    this.id, {
    this.versions = const PluginVersionRange.any(),
    this.optional = false,
  });

  final PluginId id;
  final PluginVersionRange versions;
  final bool optional;
}

enum PluginStaticContributionCardinality { many, atMostOne, exactlyOne }

/// A typed, namespaced point for immutable installation-time contributions.
///
/// The owning module declares the point. Other modules may contribute only
/// when their descriptor declares a [PluginStaticContributionTarget] for the
/// owner.
final class PluginStaticContributionPoint<T extends Object> {
  const PluginStaticContributionPoint({
    required this.owner,
    required this.name,
    this.cardinality = PluginStaticContributionCardinality.many,
  });

  final PluginId owner;
  final String name;
  final PluginStaticContributionCardinality cardinality;

  String get id => '${owner.value}/$name';

  Type get valueType => T;

  @override
  bool operator ==(Object other) =>
      other is PluginStaticContributionPoint<Object> &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

/// An owner-scoped immutable view of static contributions.
abstract interface class PluginStaticContributionCatalog {
  /// Contributions in deterministic manifest order.
  List<T> contributions<T extends Object>(
    PluginStaticContributionPoint<T> point,
  );

  /// The contribution to a singleton point, or null when an at-most-one point
  /// has no provider.
  T? single<T extends Object>(PluginStaticContributionPoint<T> point);
}

/// One message-bus namespace a plugin may subscribe to at runtime.
///
/// Prefixes are path-segment aware: `/chat` permits `/chat` and
/// `/chat/42`, but never `/chatty`. The runtime validates declarations before
/// installation, including rejecting namespaces reserved for core.
final class PluginLiveChannelScope {
  const PluginLiveChannelScope.prefix(this.path);

  final String path;

  bool allows(String channel) =>
      channel == path || channel.startsWith('$path/');

  @override
  bool operator ==(Object other) =>
      other is PluginLiveChannelScope && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => path;
}

final class PluginDescriptor {
  const PluginDescriptor({
    required this.id,
    this.version = const PluginVersion(1),
    this.dependencies = const [],
    this.staticContributionTargets = const [],
    this.routeNamespaces = const {},
    this.syntaxIds = const {},
    this.exclusiveClaims = const {},
    this.liveChannelScopes = const {},
  });

  final PluginId id;
  final PluginVersion version;
  final List<PluginDependency> dependencies;
  final List<PluginStaticContributionTarget> staticContributionTargets;
  final Set<String> routeNamespaces;
  final Set<String> syntaxIds;
  final Set<String> exclusiveClaims;
  final Set<PluginLiveChannelScope> liveChannelScopes;
}

final class PluginManifest {
  const PluginManifest(this.modules);

  final List<PluginModule> modules;
}

enum PluginStartupPhase { bootstrap, appReady }

abstract interface class PluginModule {
  PluginDescriptor get descriptor;

  void register(PluginRegistrar registrar);
}

abstract interface class PluginRegistrar {
  void addCapability(PluginCapability capability);

  void addAppLifecycle(
    PluginAppLifecycle lifecycle, {
    Iterable<PluginHostPortKey<Object>> requires,
  });

  void addRouteNamespace(String namespace);

  void addSyntaxId(String syntaxId);

  void addExclusiveClaim(String claim);

  /// Declares a static contribution point owned by this module.
  void addStaticContributionPoint<T extends Object>(
    PluginStaticContributionPoint<T> point,
  );

  /// Contributes one immutable value to [point].
  ///
  /// [name] is local to the contributing module; the runtime namespaces it to
  /// the registrar's module id.
  void addStaticContribution<T extends Object>(
    PluginStaticContributionPoint<T> point, {
    required String name,
    required T value,
  });

  void addLiveChannelScope(PluginLiveChannelScope scope);

  void addSession(
    PluginSessionFactory factory, {
    Iterable<PluginHostPortKey<Object>> requires,
  });
}

abstract base class PluginAppLifecycle {
  FutureOr<void> startPhase(
    PluginStartupPhase phase,
    PluginHostBindings bindings,
  ) {}

  FutureOr<void> observeAppState(String state, {required bool foreground}) {}

  FutureOr<void> flush() {}

  FutureOr<void> close() {}
}

abstract base class PluginSessionLifecycle {
  FutureOr<void> setForeground(bool foreground) {}

  FutureOr<void> forget(String siteUrl) {}

  FutureOr<void> close() {}
}

/// Behavior a plugin exposes to its host for one installed session.
///
/// Capabilities are intentionally discovered by interface type. The host can
/// dispatch a stable extension point without knowing which plugin implements
/// it, while plugin-private controllers remain behind the contribution.
abstract interface class PluginSessionCapability {}

final class PluginHostPortKey<T extends Object> {
  const PluginHostPortKey({required this.owner, required this.name});

  final PluginId owner;
  final String name;

  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginHostPortKey<Object> &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);
}

final class PluginServiceKey<T extends Object> {
  const PluginServiceKey({required this.owner, required this.name});

  final PluginId owner;
  final String name;

  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginServiceKey<Object> &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);
}

final class PluginHostBindings {
  PluginHostBindings(Iterable<PluginHostPort<Object>> ports)
    : _ports = Map.unmodifiable({for (final port in ports) port.key: port});

  const PluginHostBindings.empty()
    : _ports = const <PluginHostPortKey<Object>, PluginHostPort<Object>>{};

  final Map<PluginHostPortKey<Object>, PluginHostPort<Object>> _ports;

  bool contains(PluginHostPortKey<Object> key) => _ports.containsKey(key);

  /// A view containing only the ports a session explicitly declared.
  ///
  /// The application supplies one complete binding set at its composition
  /// root. Restricting it before invoking a session factory makes `requires`
  /// an authority boundary rather than only a startup validation list.
  ///
  /// A host may attach a [PluginHostPort.scopeToConsumer] materializer to a
  /// root binding. The runtime supplies the consuming module id here, and the
  /// restricted view receives only the resulting value. The materializer is
  /// deliberately not copied, so a plugin cannot re-scope its view to another
  /// consumer after construction.
  PluginHostBindings restrictedTo(
    Iterable<PluginHostPortKey<Object>> keys, {
    PluginId? consumer,
  }) => PluginHostBindings([
    for (final key in keys) _restrictedPort(key, consumer: consumer),
  ]);

  /// Revocations attached to root ports for one materialized consumer.
  ///
  /// Restricted bindings never carry revocation callbacks, so a plugin cannot
  /// revoke another consumer or retain a callback to its root binding. The
  /// runtime collects these closures before invoking a lifecycle or factory
  /// and owns their execution during rollback and teardown.
  Iterable<void Function()> consumerRevocations(
    Iterable<PluginHostPortKey<Object>> keys, {
    required PluginId consumer,
  }) sync* {
    for (final key in keys) {
      final revoke = _ports[key]?.revokeConsumer;
      if (revoke != null) yield () => revoke(consumer);
    }
  }

  PluginHostPort<Object> _restrictedPort(
    PluginHostPortKey<Object> key, {
    required PluginId? consumer,
  }) {
    final port = _ports[key];
    if (port == null) {
      throw PluginInstallationException('Missing host port ${key.id}.');
    }
    final scope = port.scopeToConsumer;
    if (scope == null) return PluginHostPort<Object>(key, port.value);
    if (consumer == null) {
      throw PluginInstallationException(
        'Host port ${key.id} requires a plugin consumer.',
      );
    }
    return PluginHostPort<Object>(key, scope(consumer));
  }

  T require<T extends Object>(PluginHostPortKey<T> key) {
    final port = _ports[key];
    if (port == null) {
      throw PluginInstallationException('Missing host port ${key.id}.');
    }
    return port.value as T;
  }
}

final class PluginHostPort<T extends Object> {
  const PluginHostPort(
    this.key,
    this.value, {
    this.scopeToConsumer,
    this.revokeConsumer,
  });

  final PluginHostPortKey<T> key;
  final T value;

  /// Produces the authority this port grants to one consuming plugin module.
  ///
  /// Leave this null for ordinary ports whose value is already least-privilege.
  /// Scoped ports are materialized by [PluginHostBindings.restrictedTo] before
  /// a plugin session factory can observe them.
  final T Function(PluginId consumer)? scopeToConsumer;

  /// Revokes stateful authority previously materialized for one consumer.
  ///
  /// This callback exists only on a root binding. Restricted plugin bindings
  /// strip it alongside [scopeToConsumer]. It must synchronously make retained
  /// handles unusable; asynchronous cleanup belongs to plugin lifecycle close.
  final void Function(PluginId consumer)? revokeConsumer;
}

/// Services exposed by modules this module explicitly depends on.
///
/// The runtime supplies an immutable snapshot containing only services that
/// were created before the consumer's session factory ran. Both lookup methods
/// reject keys owned by modules absent from the consumer's descriptor.
abstract interface class PluginDependencies {
  T require<T extends Object>(PluginServiceKey<T> key);

  T? maybe<T extends Object>(PluginServiceKey<T> key);
}

typedef PluginSessionFactory =
    PluginSessionContribution Function(
      PluginHostBindings bindings,
      PluginDependencies dependencies,
    );

final class PluginSessionContribution {
  PluginSessionContribution({
    required this.lifecycle,
    Iterable<PluginService<Object>> services = const [],
    Iterable<PluginSessionCapability> capabilities = const [],
  }) : services = List.unmodifiable(services),
       capabilities = List.unmodifiable(capabilities);

  final PluginSessionLifecycle lifecycle;
  final List<PluginService<Object>> services;
  final List<PluginSessionCapability> capabilities;
}

final class PluginService<T extends Object> {
  const PluginService(this.key, this.value);

  final PluginServiceKey<T> key;
  final T value;
}

final class PluginInstallationException implements Exception {
  const PluginInstallationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'Plugin installation failed: $message'
      : 'Plugin installation failed: $message ($cause)';
}
