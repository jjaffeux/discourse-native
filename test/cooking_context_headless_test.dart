import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test(
    'cooking snapshots and consumer lifetime work without a binding',
    () async {
      final plugins = PluginInstaller.install(const PluginManifest([]));
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: plugins,
        cookingService: _Service(),
      );
      addTearDown(() async {
        shell.dispose();
        await shell.cooking.dispose();
        await plugins.close();
      });
      const site = 'https://a.test';
      final request = shell.cookingRequest(siteUrl: site, raw: '@Alice');
      expect(shell.cookingRequestIsCurrent(request), isTrue);
      var calls = 0;
      final stop = shell.watchCooking(
        siteUrl: site,
        raw: request.raw,
        onChanged: () => calls++,
      );
      shell.store.put(site, const UserCard(username: 'Alice'));
      expect(shell.cookingRequestIsCurrent(request), isFalse);
      expect(calls, 0);
      await pumpEventQueue();
      expect(calls, 1);
      stop();
      stop();
      shell.cooking.contextChanged(site);
      await pumpEventQueue();
      expect(calls, 1);
    },
  );
}

final class _Service implements CookingServicePort {
  @override
  Future<bool> start() async => true;
  @override
  Future<CookingResult> cook(CookingRequest request) async =>
      CookingResult(html: request.raw).forRequest(request);
  @override
  void invalidate() {}
  @override
  Future<void> dispose() async {}
}
