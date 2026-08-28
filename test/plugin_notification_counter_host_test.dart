import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _owner = PluginId('counter-owner');
const _counter = PluginNotificationCounter(
  id: PluginNotificationCounterId(owner: _owner, name: 'alerts'),
  wireName: 'owner_alerts',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'account events are scoped to registered counters owned by the caller',
    () {
      PluginAccountEventsHost? accountEvents;
      final installed = PluginInstaller.install(
        PluginManifest([_CounterModule((host) => accountEvents = host)]),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installed,
      );
      addTearDown(shell.dispose);
      addTearDown(installed.close);

      shell.pluginSession;
      final host = accountEvents!;
      host.updateNotificationCounter(
        'https://example.com',
        _counter.id,
        (current) => current + 3,
      );

      expect(
        shell.accountActivity
            .totalsFor('https://example.com')
            ?.pluginCounter(_counter.id),
        3,
      );
      expect(
        () => host.updateNotificationCounter(
          'https://example.com',
          const PluginNotificationCounterId(
            owner: PluginId('other'),
            name: 'alerts',
          ),
          (current) => current + 1,
        ),
        throwsA(isA<PluginInstallationException>()),
      );
      expect(
        () => host.updateNotificationCounter(
          'https://example.com',
          const PluginNotificationCounterId(
            owner: _owner,
            name: 'unregistered',
          ),
          (current) => current + 1,
        ),
        throwsA(isA<PluginInstallationException>()),
      );
    },
  );
}

final class _CounterModule implements PluginModule {
  const _CounterModule(this.capture);

  final void Function(PluginAccountEventsHost host) capture;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _owner);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _CounterCapability());
    registrar.addSession((bindings, _) {
      capture(bindings.require(corePluginAccountEventsPort));
      return PluginSessionContribution(lifecycle: _CounterLifecycle());
    }, requires: const [corePluginAccountEventsPort]);
  }
}

final class _CounterCapability
    implements SitePlugin, NotificationCounterPlugin {
  const _CounterCapability();

  @override
  String get name => _owner.value;

  @override
  List<PluginNotificationCounter> get notificationCounters => const [_counter];
}

final class _CounterLifecycle extends PluginSessionLifecycle {}
