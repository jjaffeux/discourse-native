import 'dart:async';

import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _route = ContentRoute(
  title: 'Probe',
  destination: ExtensionDestination('retry-probe-route'),
  icon: DIcons.comments,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a retired retry leaves its successor gate and retry alone', () async {
    final probe = _RetryProbe('first');
    final controller = await _signedIn(probe);
    controller.pushContent(_route);
    probe.events.markSiteUnreachable(_site);
    final retired = probe.hold();
    final retiredRetry = controller.retryCurrentForum();
    await pumpEventQueue();
    expect(probe.asked, 1);
    expect(controller.retryingCurrentForum, isTrue);

    await controller.disconnectCurrentInstance();
    expect(controller.currentForumUnavailable, isFalse);
    expect(controller.retryingCurrentForum, isFalse);

    controller.pushContent(_route);
    probe.events.markSiteUnreachable(_site);
    final successor = probe.hold();
    final successorRetry = controller.retryCurrentForum();
    await pumpEventQueue();
    expect(probe.asked, 2);
    expect(controller.retryingCurrentForum, isTrue);

    retired.complete(PluginRouteRetryResult.succeeded);
    await retiredRetry;

    // ignore: avoid_print
    print(
      'PERF_PROOF forum-access-owner stale_cleared_successor='
      '${controller.currentForumUnavailable ? 0 : 1}',
    );
    // ignore: avoid_print
    print(
      'PERF_PROOF forum-access-owner stale_ended_successor_retry='
      '${controller.retryingCurrentForum ? 0 : 1}',
    );
    expect(controller.currentForumUnavailable, isTrue);
    expect(controller.retryingCurrentForum, isTrue);

    successor.complete(PluginRouteRetryResult.succeeded);
    await successorRetry;
    expect(controller.currentForumUnavailable, isFalse);
    expect(controller.retryingCurrentForum, isFalse);
  });

  test('a retired retry does not ask the next plugin', () async {
    final first = _RetryProbe('first');
    final second = _RetryProbe('second');
    final controller = await _signedIn(first, second);
    controller.pushContent(_route);
    first.events.markSiteUnreachable(_site);
    final retired = first.hold();
    final retry = controller.retryCurrentForum();
    await pumpEventQueue();
    expect(first.asked, 1);

    await controller.disconnectCurrentInstance();
    retired.complete(PluginRouteRetryResult.notHandled);
    await retry;

    expect(second.asked, 0);
  });

  test(
    'removing a forum leaves no access state for its next arrival',
    () async {
      final probe = _RetryProbe('first');
      final authenticator = FakeAuthenticator(
        failure: UserApiAuthFailure.launchFailed,
      );
      final controller = await _shell(authenticator, [probe], signedIn: false);
      final added = controller.currentInstance!;

      await controller.connectCurrentInstance();
      expect(controller.connectError, isNotNull);
      controller.pushContent(_route);
      probe.events.markSiteUnreachable(_site);
      final retired = probe.hold();
      final retiredRetry = controller.retryCurrentForum();
      await pumpEventQueue();
      expect(probe.asked, 1);
      expect(controller.currentForumUnavailable, isTrue);
      expect(controller.retryingCurrentForum, isTrue);

      expect(await controller.removeInstance(added), isTrue);
      expect(
        await controller.addInstance(instance('meta.discourse.org')),
        isTrue,
      );

      expect(controller.connectError, isNull);
      expect(controller.currentForumUnavailable, isFalse);
      expect(controller.retryingCurrentForum, isFalse);

      controller.pushContent(_route);
      probe.events.markSiteUnreachable(_site);
      retired.complete(PluginRouteRetryResult.succeeded);
      await retiredRetry;
      expect(controller.currentForumUnavailable, isTrue);
    },
  );

  for (final failure in UserApiAuthFailure.values) {
    test('a connection overtaken by sign-out publishes no ${failure.name} '
        'error', () async {
      final authenticator = _HeldAuthenticator();
      final controller = await _shell(authenticator, const [], signedIn: false);

      final connection = controller.connectCurrentInstance();
      await pumpEventQueue();
      expect(controller.connecting, isTrue);

      await controller.disconnectCurrentInstance();
      authenticator.authorization.completeError(UserApiAuthException(failure));
      await connection;

      expect(controller.connectError, isNull);
      expect(controller.connecting, isFalse);
    });
  }

  test(
    'a failed sign-in publishes its error while it still owns the forum',
    () async {
      final authenticator = _HeldAuthenticator();
      final controller = await _shell(authenticator, const [], signedIn: false);

      final connection = controller.connectCurrentInstance();
      await pumpEventQueue();
      authenticator.authorization.completeError(
        const UserApiAuthException(UserApiAuthFailure.launchFailed),
      );
      await connection;

      expect(controller.connectError, isNotNull);
      expect(controller.connecting, isFalse);
    },
  );

  test(
    'a connection stays underway through its own account rotation',
    () async {
      final authenticator = _HeldAuthenticator()
        ..authorization.complete(
          const UserApiCredentials(key: 'api-key', apiVersion: 4, push: false),
        );
      final hold = authenticator.holdPersistence();
      final controller = await _shell(authenticator, const [], signedIn: false);

      final connection = controller.connectCurrentInstance();
      await pumpEventQueue();
      expect(authenticator.persisting, isTrue);
      expect(controller.connecting, isTrue);

      final second = controller.connectCurrentInstance();
      await second;
      expect(authenticator.authorizations, 1);

      hold.complete();
      await connection;
      expect(controller.connecting, isFalse);
    },
  );
}

Future<ShellController> _signedIn(PluginModule first, [PluginModule? second]) =>
    _shell(FakeAuthenticator()..keys[_site] = 'key', [
      first,
      ?second,
    ], signedIn: true);

Future<ShellController> _shell(
  FakeAuthenticator authenticator,
  List<PluginModule> probes, {
  required bool signedIn,
}) async {
  final held = instance('meta.discourse.org');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      signedIn ? held.copyWith(user: _user) : held,
    ]),
    api: FakeDiscourseApi(user: _user, results: {'meta.discourse.org': held}),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    plugins: PluginInstaller.install(
      PluginManifest([...bundledWidgetTestManifest.modules, ...probes]),
    ),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.pluginSession;
  return controller;
}

final class _RetryProbe implements PluginModule, PluginRouteRetry {
  _RetryProbe(this.name);

  final String name;
  late PluginAccountEventsHost events;
  Completer<PluginRouteRetryResult>? _held;
  int asked = 0;

  Completer<PluginRouteRetryResult> hold() =>
      _held = Completer<PluginRouteRetryResult>();

  @override
  PluginDescriptor get descriptor =>
      PluginDescriptor(id: PluginId('retry-probe-$name'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession((bindings, _) {
      events = bindings.require(corePluginAccountEventsPort);
      return PluginSessionContribution(
        lifecycle: _ProbeLifecycle(),
        capabilities: [this],
      );
    }, requires: const [corePluginAccountEventsPort]);
  }

  @override
  Future<PluginRouteRetryResult> retryPluginRoute(
    String siteUrl,
    String routeId,
  ) {
    asked += 1;
    return _held?.future ?? Future.value(PluginRouteRetryResult.notHandled);
  }
}

final class _ProbeLifecycle extends PluginSessionLifecycle {}

final class _HeldAuthenticator extends FakeAuthenticator {
  final authorization = Completer<UserApiCredentials>();
  Completer<void>? _persistence;
  int authorizations = 0;
  bool persisting = false;

  Completer<void> holdPersistence() => _persistence = Completer<void>();

  @override
  Future<UserApiCredentials> authorize(String siteUrl) {
    authorizations += 1;
    return authorization.future;
  }

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    persisting = true;
    await _persistence?.future;
    await super.persistCredentials(siteUrl, credentials);
  }
}
