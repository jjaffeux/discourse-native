import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/dsa_notice.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reporting and confirmed-email capabilities survive storage and account updates',
    () {
      final config = SiteConfig.fromSettings(const {
        'dsa_reporting_enabled': true,
      });
      expect(SiteConfig.fromJson(config.toJson()).dsaReportingEnabled, isTrue);
      expect(config.withPlugins(PluginData.none).dsaReportingEnabled, isTrue);
      final user = const DiscourseModelCodec.core().currentUser({
        'id': 4,
        'username': 'member',
        'can_use_dsa_account_email': true,
      }, 'https://forum.example');
      expect(user.canUseDsaAccountEmail, isTrue);
      expect(
        DiscourseUser.fromJson(user.toJson()).canUseDsaAccountEmail,
        isTrue,
      );
      expect(user.withDraftCount(2).canUseDsaAccountEmail, isTrue);
      expect(user.withPlugins(PluginData.none).canUseDsaAccountEmail, isTrue);
      expect(
        const DiscourseUser(username: 'old snapshot').canUseDsaAccountEmail,
        isFalse,
      );
    },
  );

  test('notice requires a declaration and the server explanation minimum', () {
    DsaNoticeDraft draft({
      bool declaration = true,
      String explanation = 'short',
    }) => DsaNoticeDraft(
      contentUrl: 'https://forum.example/t/example/10/2',
      explanation: explanation,
      name: 'Reporter',
      email: 'guest@example.com',
      declaration: declaration,
    );
    const explanation =
        'This content contains an illegal threat against a named person.';
    expect(draft().valid(useAccountEmail: false), isFalse);
    expect(
      draft(
        explanation: explanation,
        declaration: false,
      ).valid(useAccountEmail: false),
      isFalse,
    );
    expect(
      draft(explanation: explanation).valid(useAccountEmail: false),
      isTrue,
    );
  });
}
