import 'package:discourse_native/src/app_runtime.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'shell shutdown retires every forum and closes transport before rethrowing',
    () async {
      final sites = [instance('one.example'), instance('two.example')];
      final api = FakeDiscourseApi();
      final plugins = PluginInstaller.install(const PluginManifest([]));
      addTearDown(plugins.close);
      final shell = ShellController(
        instanceStore: FakeInstanceStore(sites),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: plugins,
      );
      await shell.load();
      await pumpEventQueue();
      final failure = StateError('broken retirement observer');
      final observed = <String>[];
      for (final site in sites) {
        shell.lifecycle.capture(site.url).onRetire(() {
          observed.add(site.url);
          throw site == sites.first ? failure : StateError('later failure');
        });
      }
      expect(shell.dispose, throwsA(same(failure)));
      expect(observed, sites.map((site) => site.url));
      expect(api.closeCalls, 1);
      expect(() => shell.addListener(() {}), throwsA(isA<FlutterError>()));
      await shell.pluginTeardown;
    },
  );

  test(
    'runtime shutdown releases owned transport after controller retirement fails',
    () async {
      final DiscourseInstance site = instance('one.example');
      final api = FakeDiscourseApi();
      final runtime = AppRuntime(
        dependencies: AppRuntimeDependencies(
          store: FakeInstanceStore([site]),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
          pluginManifest: const PluginManifest([]),
        ),
        foreground: false,
        lifecycleState: 'paused',
      );
      await runtime.start(runtime.controller);
      await pumpEventQueue();
      final failure = StateError('broken runtime retirement');
      runtime.controller.lifecycle
          .capture(site.url)
          .onRetire(() => throw failure);
      expect(runtime.dispose, throwsA(same(failure)));
      await pumpEventQueue();
      expect(api.closeCalls, 1);
      expect(
        () => runtime.controller.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
      runtime.dispose();
      expect(api.closeCalls, 1);
    },
  );
}
