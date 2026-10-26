import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/preference_storage_scope.dart';
import '../data/scalar_preference_repository.dart';
import '../data/site_preference_keys.dart';
import '../foundation/frame_safe_notifier.dart';
import 'shell_scope.dart';

@PreferenceStorage.adapter(
  'MobilePlaceOrderController.keys owns the account-scoped place order.',
)
final class MobilePlaceOrderPersistence
    extends SharedPreferencesScalarPreferencePersistence<List<String>> {
  const MobilePlaceOrderPersistence();
  @override
  List<String>? readValue(SharedPreferences preferences, String key) =>
      preferences.getStringList(key);
  @override
  Future<bool> writeValue(
    SharedPreferences preferences,
    String key,
    List<String> value,
  ) => preferences.setStringList(key, value);
}

/// The order a person has put a phone's places in, as a list of the places'
/// names. It belongs to the forum account, as the other local interaction
/// settings do, and the places it does not name keep their default order
/// after the ones it does.
class MobilePlaceOrderController extends FrameSafeNotifier {
  MobilePlaceOrderController(
    String siteUrl,
    String accountIdentity, {
    ScalarPreferencePersistence<List<String>> persistence =
        const MobilePlaceOrderPersistence(),
  }) : _siteUrl = siteUrl {
    _store = ScalarPreferenceRepository(
      persistence: persistence,
      key: '${keys.of(siteUrl)}.${Uri.encodeComponent(accountIdentity)}',
      isCurrent: () => !isDisposed && !_retired,
    );
    keys.track(this, (controller, sites) => controller.forgetSites(sites));
  }
  static const keys = SitePreferenceKey(
    'discourse_native.mobile_place_order',
    tail: SitePreferenceTail.name,
    retirement: SitePreferenceRetirement.tracked,
  );
  final String _siteUrl;
  late final ScalarPreferenceRepository<List<String>> _store;
  bool _retired = false;
  List<String> order = const [];
  bool _edited = false;

  /// [places] as [order] puts them: the ones it names first, in its sequence,
  /// then the rest in the order given. A name with no place among [places]
  /// is dropped, so a place the forum no longer offers leaves no gap and
  /// one it offers anew takes its default position among the unplaced.
  static List<T> apply<T>(
    List<T> places,
    List<String> order,
    String Function(T place) nameOf,
  ) {
    if (order.isEmpty) return places;
    final unplaced = {for (final place in places) nameOf(place): place};
    return [
      for (final name in order) ?unplaced.remove(name),
      ...unplaced.values,
    ];
  }

  /// [stored] with [shown], the places as they stand now, placed in that
  /// order. A stored name not among them, a place hidden for now, keeps its
  /// place after the one before it in [stored], or first, so [apply] brings
  /// it back where it was.
  static List<String> placed(List<String> stored, List<String> shown) {
    final showing = shown.toSet();
    final out = [...shown];
    String? before;
    for (final name in stored) {
      if (!showing.contains(name)) {
        out.insert(before == null ? 0 : out.indexOf(before) + 1, name);
      }
      before = name;
    }
    return out;
  }

  /// The shown places stand in the order [shown] now, written as [placed]
  /// says.
  Future<void> place(List<String> shown) => set(placed(order, shown));

  void forgetSites(ForgottenSites sites) {
    if (!sites.includes(_siteUrl, keys)) return;
    _retired = true;
    order = const [];
    notifySafely();
  }

  Future<void> load() async {
    final stored = await _store.read();
    if (isDisposed || _retired || _edited || stored == null) return;
    order = List.unmodifiable(stored);
    notifySafely();
  }

  Future<void> set(List<String> value) {
    if (isDisposed || _retired || listEquals(value, order)) {
      return Future.value();
    }
    _edited = true;
    order = List.unmodifiable(value);
    notifySafely();
    return _store.write(order);
  }
}

/// Holds the current account's [MobilePlaceOrderController] for the shell
/// under it, replacing it as the account changes.
class MobilePlaceOrderHost extends StatefulWidget {
  const MobilePlaceOrderHost({super.key, required this.child});
  final Widget child;
  static MobilePlaceOrderController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_MobilePlaceOrderScope>()
      ?.controller;
  @override
  State<MobilePlaceOrderHost> createState() => _MobilePlaceOrderHostState();
}

class _MobilePlaceOrderHostState extends State<MobilePlaceOrderHost> {
  (String, String)? _account;
  MobilePlaceOrderController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.of(context);
    final instance = shell.currentInstance;
    final account = instance == null
        ? null
        : (instance.url, shell.currentAccountIdentity!);
    if (_account == account) return;
    _account = account;
    _controller?.dispose();
    _controller = account == null
        ? null
        : MobilePlaceOrderController(account.$1, account.$2);
    if (_controller case final controller?) unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) =>
      _MobilePlaceOrderScope(controller: _controller, child: widget.child);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _MobilePlaceOrderScope extends InheritedWidget {
  const _MobilePlaceOrderScope({
    required this.controller,
    required super.child,
  });
  final MobilePlaceOrderController? controller;
  @override
  bool updateShouldNotify(_MobilePlaceOrderScope oldWidget) =>
      controller != oldWidget.controller;
}
