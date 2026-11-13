import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/preference_storage_scope.dart';
import '../data/scalar_preference_repository.dart';
import '../data/site_preference_keys.dart';
import '../foundation/d_header_tuning.dart';
import '../foundation/frame_safe_notifier.dart';

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
    // Listeners can accept another choice before this call returns.
    final saving = _store.write(jsonEncode(value.toJson()));
    notifySafely();
    return saving;
  }
}
