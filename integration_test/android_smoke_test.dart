import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android starts the bundled app and opens the add-site form', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    await tester.pumpWidget(
      DiscourseApp(pluginManifest: bundledPluginManifest),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DInput), findsWidgets);
    final voiceContext = PluginUiScope.contextFor(
      tester.element(find.byType(DInput).first),
      voicePluginId,
    );
    expect(
      PluginUiScope.require(
        voiceContext,
        voiceControllerService,
      ).supportedPlatform,
      isTrue,
    );
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) => widget is DButton && widget.tooltip == 'Close',
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'Add a site').first);
    await tester.pumpAndSettle();
    expect(find.byType(DInput), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('Android persists and deletes credentials through Keystore', () async {
    const site = 'https://android-smoke.invalid';
    addTearDown(() => SecureStore().deleteApiKey(site));
    await SecureStore().writeApiKey(site, 'first-key');
    expect(
      await const AndroidCredentialStorage().read('api_key::$site'),
      'first-key',
    );
    await SecureStore().writeApiKey(site, 'replacement-key');
    expect(
      await const AndroidCredentialStorage().read('api_key::$site'),
      'replacement-key',
    );
    await SecureStore().deleteApiKey(site);
    expect(
      await const AndroidCredentialStorage().read('api_key::$site'),
      isNull,
    );
  });

  test('Android persists drafts and clears only the requested site', () async {
    const site = 'https://android-smoke.invalid';
    const otherSite = 'https://android-other-smoke.invalid';
    addTearDown(() async {
      await DraftStore().clearSite(site);
      await DraftStore().clearSite(otherSite);
    });
    await DraftStore().write(site, 'topic_1', 'unfinished draft');
    await DraftStore().write(otherSite, 'topic_1', 'other draft');
    expect(await DraftStore().read(site, 'topic_1'), 'unfinished draft');
    await DraftStore().clearSite(site);
    expect(await DraftStore().read(site, 'topic_1'), isNull);
    expect(await DraftStore().read(otherSite, 'topic_1'), 'other draft');
  });

  test('Android loads and cooks with the packaged native runtime', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    final result = await service.cook(
      CookingRequest(
        raw: 'An **Android** offline cook',
        snapshot: CookingSnapshot(siteId: 'android-test', accountId: 'test'),
      ),
    );
    expect(result.failure, isNull);
    expect(result.html, '<p>An <strong>Android</strong> offline cook</p>');
  });
}
