import 'dart:async';

import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('synchronous shell disposal keeps worker timers off widget clock', (
    tester,
  ) async {
    final plugins = PluginInstaller.install(const PluginManifest([]));
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      plugins: plugins,
    );
    var disposed = false;
    var workerStopped = false;
    Future<void> finishDisposal() async {
      if (!disposed) {
        shell.dispose();
        disposed = true;
      }
      unawaited(shell.cooking.dispose().then((_) => workerStopped = true));
      // Let real isolate events arrive, then drain their UI-zone continuations.
      // Never advance virtual widget time to expire or hide a watchdog.
      for (var i = 0; i < 250 && !workerStopped; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        workerStopped,
        isTrue,
        reason: 'Worker shutdown must remain bounded',
      );
    }

    addTearDown(() async {
      await finishDisposal();
      await plugins.close();
    });

    await tester.runAsync(() async {
      expect(await shell.cooking.start(), isTrue);
      final result = await shell.cooking.cook(
        shell.cookingRequest(
          siteUrl: 'https://cold.example',
          raw: '**worker is alive**',
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('<strong>worker is alive</strong>'));
    });

    final widgetTimers = <Duration>[];
    runZoned(
      () {
        shell.dispose();
        disposed = true;
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          widgetTimers.add(duration);
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    await finishDisposal();
    // Do not pump a timeout away: native isolate shutdown cannot depend on
    // virtual frame time advancing, and must not leave widget timers behind.
    expect(widgetTimers, isEmpty);
  });
}
