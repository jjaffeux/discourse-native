import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'plugin_registry.dart';
import 'plugin_runtime.dart';

/// Carries render-only plugin contributions through nested content.
///
/// A full application uses [PluginScope]. Standalone cooked fragments can use
/// this narrower scope without fabricating a plugin session merely to make a
/// nested quote inherit the same renderers.
class PluginRegistryScope extends InheritedWidget {
  const PluginRegistryScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final PluginRegistry registry;

  static PluginRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PluginRegistryScope>()
      ?.registry;

  @override
  bool updateShouldNotify(PluginRegistryScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// The installed plugin graph available to extension widgets.
///
/// Core keeps the complete runtime graph private; plugin-owned UI state is
/// projected through [PluginUiScope] so a feature never receives the shell's
/// public surface merely to reach its own controller.
class PluginScope extends InheritedWidget {
  const PluginScope({
    super.key,
    required PluginSession session,
    required this.registry,
    required super.child,
    // Keep the public constructor name `session` while the capability-bearing
    // value itself remains inaccessible to descendants.
    // ignore: prefer_initializing_formals
  }) : _session = session;

  final PluginSession _session;
  final PluginRegistry registry;

  PluginOwnedServices _servicesFor(PluginId owner) =>
      _session.servicesFor(owner);

  static PluginScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PluginScope>();
    assert(scope != null, 'No PluginScope found above this widget');
    return scope!;
  }

  static PluginScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PluginScope>();

  @override
  bool updateShouldNotify(PluginScope oldWidget) =>
      !identical(_session, oldWidget._session) ||
      !identical(registry, oldWidget.registry);
}

/// The owner-stamped context supplied to one plugin's UI contribution.
///
/// The application-wide [PluginScope] contains every installed service because
/// core must dispatch all contributions. Plugin widgets do not receive that
/// authority directly: the registry invokes their builders with this context
/// and wraps returned widgets in a [PluginUiScope]. Service lookup therefore
/// remains tied to the module that registered the contribution, including in
/// callbacks which retain the build context after registration returns.
class PluginUiScope extends InheritedWidget {
  const PluginUiScope._({required this.services, required super.child});

  final PluginOwnedServices services;
  PluginId get owner => services.owner;

  /// Stamps a synchronous contribution callback with [owner].
  static BuildContext contextFor(BuildContext context, PluginId owner) =>
      _PluginUiBuildContext(context, _rootServices(context, owner));

  /// Keeps [owner] available to widgets built below a returned contribution.
  static Widget own(PluginId owner, Widget child) =>
      _PluginUiOwnerBoundary(owner: owner, child: child);

  static PluginOwnedServices _rootServices(
    BuildContext context,
    PluginId owner,
  ) =>
      PluginScope.maybeOf(context)?._servicesFor(owner) ??
      PluginOwnedServices.detached(owner);

  static PluginId? maybeOwnerOf(BuildContext context) {
    if (context case _PluginUiBuildContext(:final services)) {
      return services.owner;
    }
    return context.dependOnInheritedWidgetOfExactType<PluginUiScope>()?.owner;
  }

  static PluginId ownerOf(BuildContext context) {
    final owner = maybeOwnerOf(context);
    assert(owner != null, 'No PluginUiScope found above this widget');
    return owner!;
  }

  static T require<T extends Object>(
    BuildContext context,
    PluginServiceKey<T> key,
  ) {
    return _servicesOf(context).require(key);
  }

  static T? optional<T extends Object>(
    BuildContext context,
    PluginServiceKey<T> key,
  ) {
    return _servicesOf(context).maybe(key);
  }

  /// An optional owner service for widgets which also support standalone use.
  /// A mounted plugin contribution still enforces the stamped owner.
  static T? maybe<T extends Object>(
    BuildContext context,
    PluginServiceKey<T> key,
  ) {
    if (maybeOwnerOf(context) == null) return null;
    return _servicesOf(context).maybe(key);
  }

  static PluginOwnedServices _servicesOf(BuildContext context) {
    if (context case _PluginUiBuildContext(:final services)) return services;
    final scope = context.dependOnInheritedWidgetOfExactType<PluginUiScope>();
    if (scope != null) return scope.services;
    throw StateError('Plugin service requested outside a PluginUiScope.');
  }

  @override
  bool updateShouldNotify(PluginUiScope oldWidget) =>
      !identical(services, oldWidget.services);
}

final class _PluginUiOwnerBoundary extends StatelessWidget {
  const _PluginUiOwnerBoundary({required this.owner, required this.child});

  final PluginId owner;
  final Widget child;

  @override
  Widget build(BuildContext context) => PluginUiScope._(
    services:
        PluginScope.maybeOf(context)?._servicesFor(owner) ??
        PluginOwnedServices.detached(owner),
    child: child,
  );
}

/// A short-lived owner stamp which otherwise behaves exactly like the real
/// element context supplied by Flutter.
final class _PluginUiBuildContext implements BuildContext {
  const _PluginUiBuildContext(this._delegate, this.services);

  final BuildContext _delegate;
  final PluginOwnedServices services;

  @override
  Widget get widget => _delegate.widget;

  @override
  BuildOwner? get owner => _delegate.owner;

  @override
  bool get mounted => _delegate.mounted;

  @override
  bool get debugDoingBuild => _delegate.debugDoingBuild;

  @override
  RenderObject? findRenderObject() => _delegate.findRenderObject();

  @override
  Size? get size => _delegate.size;

  @override
  InheritedWidget dependOnInheritedElement(
    InheritedElement ancestor, {
    Object? aspect,
  }) => _delegate.dependOnInheritedElement(ancestor, aspect: aspect);

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({
    Object? aspect,
  }) => _delegate.dependOnInheritedWidgetOfExactType<T>(aspect: aspect);

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _delegate.getInheritedWidgetOfExactType<T>();

  @override
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _delegate.getElementForInheritedWidgetOfExactType<T>();

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() =>
      _delegate.findAncestorWidgetOfExactType<T>();

  @override
  T? findAncestorStateOfType<T extends State>() =>
      _delegate.findAncestorStateOfType<T>();

  @override
  T? findRootAncestorStateOfType<T extends State>() =>
      _delegate.findRootAncestorStateOfType<T>();

  @override
  T? findAncestorRenderObjectOfType<T extends RenderObject>() =>
      _delegate.findAncestorRenderObjectOfType<T>();

  @override
  void visitAncestorElements(ConditionalElementVisitor visitor) =>
      _delegate.visitAncestorElements(visitor);

  @override
  void visitChildElements(ElementVisitor visitor) =>
      _delegate.visitChildElements(visitor);

  @override
  void dispatchNotification(Notification notification) =>
      _delegate.dispatchNotification(notification);

  @override
  DiagnosticsNode describeElement(
    String name, {
    DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty,
  }) => _delegate.describeElement(name, style: style);

  @override
  DiagnosticsNode describeWidget(
    String name, {
    DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty,
  }) => _delegate.describeWidget(name, style: style);

  @override
  List<DiagnosticsNode> describeMissingAncestor({
    required Type expectedAncestorType,
  }) => _delegate.describeMissingAncestor(
    expectedAncestorType: expectedAncestorType,
  );

  @override
  DiagnosticsNode describeOwnershipChain(String name) =>
      _delegate.describeOwnershipChain(name);
}

/// Rebuilds only when a selected value from one plugin service changes.
class PluginServiceSelector<S extends Listenable, T> extends StatefulWidget {
  const PluginServiceSelector({
    super.key,
    required this.service,
    required this.select,
    required this.builder,
    this.child,
  });

  final PluginServiceKey<S> service;
  final T Function(S value) select;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<PluginServiceSelector<S, T>> createState() =>
      _PluginServiceSelectorState<S, T>();
}

class _PluginServiceSelectorState<S extends Listenable, T>
    extends State<PluginServiceSelector<S, T>> {
  S? _service;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = PluginUiScope.require(context, widget.service);
    if (identical(service, _service)) return;

    _service?.removeListener(_select);
    _service = service..addListener(_select);
    _value = widget.select(service);
  }

  @override
  void didUpdateWidget(PluginServiceSelector<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _service?.removeListener(_select);
      _service = PluginUiScope.require(context, widget.service)
        ..addListener(_select);
    }
    _value = widget.select(_service!);
  }

  void _select() {
    final next = widget.select(_service!);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);

  @override
  void dispose() {
    _service?.removeListener(_select);
    super.dispose();
  }
}
