import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/preference_storage_scope.dart';
import '../data/scalar_preference_repository.dart';
import '../data/site_preference_keys.dart';
import '../foundation/frame_safe_notifier.dart';
import 'shell_scope.dart';

@PreferenceStorage.adapter(
  'HeaderPreferencesController.keys owns the account-scoped header document.',
)
final class HeaderTuningPersistence
    extends SharedPreferencesScalarPreferencePersistence<String> {
  const HeaderTuningPersistence();
  @override
  String? readValue(SharedPreferences preferences, String key) =>
      preferences.getString(key);
  @override
  Future<bool> writeValue(
    SharedPreferences preferences,
    String key,
    String value,
  ) => preferences.setString(key, value);
}

/// Local interaction settings belong to the forum account, not server options.
class HeaderPreferencesController extends FrameSafeNotifier {
  HeaderPreferencesController(
    String siteUrl,
    String accountIdentity, {
    ScalarPreferencePersistence<String> persistence =
        const HeaderTuningPersistence(),
  }) : _siteUrl = siteUrl {
    _store = ScalarPreferenceRepository(
      persistence: persistence,
      key: '${keys.of(siteUrl)}.${Uri.encodeComponent(accountIdentity)}',

      isCurrent: () => !isDisposed && !_retired,
    );
    keys.track(this, (controller, sites) => controller.forgetSites(sites));
  }
  static const keys = SitePreferenceKey(
    'discourse_native.header_tuning',
    tail: SitePreferenceTail.name,
    retirement: SitePreferenceRetirement.tracked,
  );
  final String _siteUrl;
  late final ScalarPreferenceRepository<String> _store;
  bool _retired = false;
  DHeaderTuning tuning = const DHeaderTuning();
  bool _edited = false;
  void forgetSites(ForgottenSites sites) {
    if (!sites.includes(_siteUrl, keys)) return;
    _retired = true;
    tuning = const DHeaderTuning();
    notifySafely();
  }

  Future<void> load() async {
    final stored = await _store.read();
    if (isDisposed || _retired || _edited || stored == null) return;
    try {
      final json = jsonDecode(stored);
      if (json is! Map<String, dynamic>) return;
      tuning = DHeaderTuning.fromJson(json);
      notifySafely();
    } on FormatException {
      return;
    }
  }

  Future<void> set(DHeaderTuning value) {
    if (isDisposed || _retired || value == tuning) return Future.value();
    _edited = true;
    tuning = value;
    notifySafely();
    return _store.write(jsonEncode(value.toJson()));
  }
}

class HeaderPreferencesHost extends StatefulWidget {
  const HeaderPreferencesHost({super.key, required this.child});
  final Widget child;
  static HeaderPreferencesController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_HeaderPreferencesScope>()
      ?.controller;
  @override
  State<HeaderPreferencesHost> createState() => _HeaderPreferencesHostState();
}

class _HeaderPreferencesHostState extends State<HeaderPreferencesHost> {
  (String, String)? _account;
  HeaderPreferencesController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final instance = ShellScope.of(context).currentInstance;
    final account = instance?.user == null
        ? null
        : (
            instance!.url,
            '${instance.user!.id ?? ''}:${instance.user!.username.toLowerCase()}',
          );
    if (_account == account) return;
    _account = account;
    _controller?.dispose();
    _controller = account == null
        ? null
        : HeaderPreferencesController(account.$1, account.$2);
    if (_controller case final controller?) unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ListenableBuilder(
      listenable: controller ?? Listenable.merge(const []),
      builder: (context, _) => _HeaderPreferencesScope(
        controller: controller,
        child: DHeaderMotionSettings(
          tuning: controller?.tuning ?? const DHeaderTuning(),
          child: widget.child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _HeaderPreferencesScope extends InheritedWidget {
  const _HeaderPreferencesScope({
    required this.controller,
    required super.child,
  });
  final HeaderPreferencesController? controller;
  @override
  bool updateShouldNotify(_HeaderPreferencesScope oldWidget) =>
      controller != oldWidget.controller;
}

class HeaderTuningPreferences extends StatelessWidget {
  const HeaderTuningPreferences({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = HeaderPreferencesHost.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tuning = controller.tuning;
        final l10n = context.l10n;
        Widget select<T>(
          String id,
          String label,
          T value,
          List<T> options,
          String Function(T) name,
          DHeaderTuning Function(T) update,
        ) => DField(
          orientation: DFieldOrientation.vertical,
          children: [
            DFieldLabel(child: Text(label)),
            DSelect<T>.controlled(
              key: ValueKey('header-tuning-$id'),
              value: value,
              semanticLabel: label,
              entries: [
                for (final option in options)
                  DSelectOption(
                    value: option,
                    label: name(option),
                    child: Text(name(option)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) unawaited(controller.set(update(value)));
              },
            ),
          ],
        );
        return DFieldGroup(
          children: [
            DFieldTitle(child: Text(l10n.scrollHeaders)),
            select(
              'settle',
              l10n.headerSettleLabel,
              tuning.settle,
              DHeaderSettle.values,
              (v) => switch (v) {
                DHeaderSettle.direction => l10n.headerSettleDirection,
                DHeaderSettle.halfway => l10n.headerSettleHalfway,
                DHeaderSettle.stay => l10n.headerSettleStay,
              },
              (v) => tuning.copyWith(settle: v),
            ),
            select(
              'point',
              l10n.headerHalfwayLabel,
              tuning.point,
              [.3, .4, .5, .6, .7],
              (v) => l10n.headerPercentage((v * 100).round()),
              (v) => tuning.copyWith(point: v),
            ),
            select(
              'pause',
              l10n.headerPauseLabel,
              tuning.pause,
              [80, 120, 180, 250],
              l10n.headerMilliseconds,
              (v) => tuning.copyWith(pause: v),
            ),
            select(
              'slack',
              l10n.headerSlackLabel,
              tuning.slack,
              [0.0, 24.0, 40.0, 64.0],
              (v) => l10n.headerPixels(v.round()),
              (v) => tuning.copyWith(slack: v),
            ),
            select(
              'hold',
              l10n.headerHoldLabel,
              tuning.hold,
              [0, 250, 400, 600, 800],
              l10n.headerMilliseconds,
              (v) => tuning.copyWith(hold: v),
            ),
            select(
              'smoothing',
              l10n.headerSmoothingLabel,
              tuning.smoothing,
              [0, 25, 40, 60, 90],
              l10n.headerMilliseconds,
              (v) => tuning.copyWith(smoothing: v),
            ),
          ],
        );
      },
    );
  }
}
