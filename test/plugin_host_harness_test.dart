import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:flutter_test/flutter_test.dart';

const _pluginId = PluginId('host-harness-test');
const _navigationService = PluginServiceKey<_TestNavigationService>(
  owner: _pluginId,
  name: 'navigation',
);
const _testNotificationType = NotificationWireType(901, 'test_notification');

String _dismissNotifications(int count) => 'Dismiss $count notifications?';

ResolvedNotification? _ignoreNotification(DiscourseNotification notification) =>
    null;

void main() {
  test('public SDK exposes complete notification feed declarations', () {
    const definition = PluginNotificationType(
      id: PluginNotificationTypeId(owner: _pluginId, name: 'test-notification'),
      wireType: _testNotificationType,
      decode: _ignoreNotification,
    );
    const source = PluginNotificationFeedSource(
      id: PluginNotificationFeedId(owner: _pluginId, name: 'notifications'),
      filterByTypes: [NotificationTypeName('test_notification')],
      reconnectMessage: 'Reconnect.',
      failureMessage: 'Failed.',
      emptyMessage: 'Empty.',
      dismissal: PluginNotificationFeedDismissal(
        notificationTypes: [_testNotificationType],
        buttonLabel: 'Dismiss',
        buttonTooltip: 'Mark notifications as read',
        confirmationMessage: _dismissNotifications,
      ),
    );

    expect(definition.wireType, _testNotificationType);
    expect(source.filterByTypes.single.value, 'test_notification');
  });

  test('provides typed plugin services over real shell navigation', () async {
    final host = await PluginHostHarness.open(
      transport: RecordingPluginTransport(),
      manifest: const PluginManifest([_TestNavigationModule()]),
      sites: const [
        PluginHostSite(url: 'https://forum.example', apiKey: 'key'),
      ],
    );
    addTearDown(host.close);
    final destination = host.currentContent;

    host.require(_navigationService).open();

    expect(host.currentContent?.id, 'host-harness-test-route');
    expect(host.contentStack, hasLength(2));
    expect(host.popContent(), isTrue);
    expect(host.currentContent?.id, destination?.id);
  });
}

final class _TestNavigationModule implements PluginModule {
  const _TestNavigationModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _pluginId);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _TestSessionLifecycle(),
        services: [
          PluginService<Object>(
            _navigationService,
            _TestNavigationService(
              bindings.require(corePluginRouteNavigationPort),
            ),
          ),
        ],
      ),
      requires: const [corePluginRouteNavigationPort],
    );
  }
}

final class _TestSessionLifecycle extends PluginSessionLifecycle {}

final class _TestNavigationService {
  const _TestNavigationService(this._navigation);

  final PluginRouteNavigationHost _navigation;

  void open() {
    _navigation.pushContent(
      const ContentRoute(
        id: 'host-harness-test-route',
        title: 'Plugin route',
        icon: DIcons.microphoneLines,
      ),
    );
  }
}
