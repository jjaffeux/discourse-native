import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/shell/preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const account = DiscourseInstance(
  url: 'https://forum.example',
  title: 'Forum',
  user: DiscourseUser(id: 7, username: 'reader'),
);

class PreferenceApi implements UserPreferencesApi {
  final writes = <Map<String, Object?>>[];
  bool fail = false;
  @override
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => UserPreferences(
    username: 'reader',
    canEdit: true,
    pluginValues: {
      cakedayPreferenceSection.id: CakedayPreferences(
        CakedayBirthday.create(1, 30),
      ),
    },
  );
  @override
  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  }) async {
    writes.add(values);
    if (fail) {
      throw const WriteException(
        WriteFailure.validation,
        errors: ['Rejected birthday'],
      );
    }
    return fallback;
  }
}

class Credentials implements ApiCredentialReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'key';
  @override
  Future<String> clientId() async => 'client';
}

void main() {
  test(
    'host save excludes invalid draft, preserves rejected draft, and sends explicit clear',
    () async {
      final api = PreferenceApi();
      final controller = PreferencesController(
        api: api,
        credentials: Credentials(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      await controller.load(account);
      void edit(CakedayPreferences value) => controller.edit(
        account.url,
        cakedayPreferenceSection,
        (current) => current.copyWith(
          pluginValues: {
            ...current.pluginValues,
            cakedayPreferenceSection.id: value,
          },
        ),
      );
      edit(CakedayPreferences.invalid(CakedayBirthday.create(1, 31)));
      expect(await controller.save(account, cakedayPreferenceSection), isFalse);
      expect(api.writes, isEmpty);
      edit(CakedayPreferences(CakedayBirthday.create(2, 29)));
      api.fail = true;
      expect(await controller.save(account, cakedayPreferenceSection), isFalse);
      expect(api.writes.single, {'date_of_birth': '1904-2-29'});
      expect(
        controller
            .stateFor(account.url)!
            .draft!
            .pluginValues[cakedayPreferenceSection.id],
        CakedayPreferences(CakedayBirthday.create(2, 29)),
      );
      api.fail = false;
      edit(const CakedayPreferences(null));
      expect(await controller.save(account, cakedayPreferenceSection), isTrue);
      expect(api.writes.last, {'date_of_birth': ''});
    },
  );
}
