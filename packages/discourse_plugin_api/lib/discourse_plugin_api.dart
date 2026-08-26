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

final class PluginDescriptor {
  const PluginDescriptor({
    required this.id,
    this.version = const PluginVersion(1),
    this.dependencies = const [],
    this.routeNamespaces = const {},
    this.syntaxIds = const {},
    this.exclusiveClaims = const {},
  });

  final PluginId id;
  final PluginVersion version;
  final List<PluginDependency> dependencies;
  final Set<String> routeNamespaces;
  final Set<String> syntaxIds;
  final Set<String> exclusiveClaims;
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

  void addAppLifecycle(PluginAppLifecycle lifecycle);

  void addSession(
    PluginSessionFactory factory, {
    Iterable<PluginHostPortKey<Object>> requires,
  });
}

abstract base class PluginAppLifecycle {
  FutureOr<void> startPhase(PluginStartupPhase phase) {}

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
    : _ports = Map.unmodifiable({
        for (final port in ports) port.key: port.value,
      });

  const PluginHostBindings.empty()
    : _ports = const <PluginHostPortKey<Object>, Object>{};

  final Map<PluginHostPortKey<Object>, Object> _ports;

  bool contains(PluginHostPortKey<Object> key) => _ports.containsKey(key);

  T require<T extends Object>(PluginHostPortKey<T> key) {
    final value = _ports[key];
    if (value == null) {
      throw PluginInstallationException('Missing host port ${key.id}.');
    }
    return value as T;
  }
}

final class PluginHostPort<T extends Object> {
  const PluginHostPort(this.key, this.value);

  final PluginHostPortKey<T> key;
  final T value;
}

typedef PluginSessionFactory =
    PluginSessionContribution Function(PluginHostBindings bindings);

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
