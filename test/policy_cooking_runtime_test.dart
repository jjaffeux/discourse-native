import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native worker loads the trusted Policy parser and isolates enablement',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final configuration = CookingConfiguration(
        modules: [
          CookingModule(
            id: 'discourse-policy',
            owner: 'discourse-policy',
            version: '1',
            enabledSetting: 'policy_enabled',
          ),
        ],
        installedOwners: {'discourse-policy'},
      );
      Future<CookingResult> cook(bool enabled) => service.cook(
        CookingRequest(
          raw:
              '[policy groups="staff" renew="monthly"]\n**Read this**\n[/policy]',
          configuration: configuration,
          snapshot: CookingSnapshot(
            siteId: 'fixture',
            accountId: 'member',
            pluginContext: {
              'discourse-policy': {
                'settings': {'policy_enabled': enabled},
              },
            },
          ),
        ),
      );
      final enabled = await cook(true);
      expect(enabled.failure, isNull);
      expect(enabled.html, contains('class="policy"'));
      expect(enabled.html, contains('data-version="1"'));
      expect(enabled.html, contains('data-renew="monthly"'));
      expect(enabled.html, contains('<strong>Read this</strong>'));
      final disabled = await cook(false);
      expect(disabled.failure, isNull);
      expect(disabled.html, isNot(contains('class="policy"')));
      expect((await cook(true)).html, enabled.html);
    },
  );
}
