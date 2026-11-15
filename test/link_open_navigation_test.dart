import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/link_open_request.dart';
import 'package:discourse_native/src/data/link_opens.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

String _request(String target) =>
    'discourse://open?url=${Uri.encodeQueryComponent(target)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a request opens its page on the forum that serves it', () async {
    final controller = await _shell([
      _connected('one.example'),
      _connected('two.example'),
    ]);

    expect(
      await controller.openRequestedLink(
        _request('https://two.example/t/from-mail/42/3'),
      ),
      isA<RequestedLinkOpened>(),
    );
    expect(controller.currentInstance?.url, 'https://two.example');
    expect(controller.currentContent?.topicId, 42);
    expect(controller.currentContent?.postNumber, 3);
  });

  test('a public page opens on a forum added without signing in', () async {
    final controller = await _shell([instance('one.example')]);

    expect(
      await controller.openRequestedLink(
        _request('https://one.example/t/public/42'),
      ),
      isA<RequestedLinkOpened>(),
    );
    expect(controller.currentContent?.topicId, 42);
  });

  test('a request for a forum that was never added changes nothing', () async {
    final controller = await _shell([_connected('one.example')]);
    final before = controller.currentContent;

    final outcome = await controller.openRequestedLink(
      _request('https://evil.example/t/phish/42'),
    );

    expect(
      outcome,
      isA<RequestedLinkUnknownSite>().having(
        (unknown) => unknown.target.host,
        'host',
        'evil.example',
      ),
    );
    expect(controller.instances.map((site) => site.url), [
      'https://one.example',
    ]);
    expect(controller.currentContent, same(before));
  });

  test('a lookalike host is not the forum it imitates', () async {
    final controller = await _shell([_connected('one.example')]);

    for (final target in const [
      'https://one.example.evil.example/t/42',
      'https://evil-one.example/t/42',
      'https://one.example:8443/t/42',
    ]) {
      expect(
        await controller.openRequestedLink(_request(target)),
        isA<RequestedLinkUnknownSite>(),
        reason: target,
      );
    }
  });

  test(
    'a malformed request is refused before any forum is consulted',
    () async {
      final asked = <String>[];
      final controller = await _shell(
        [_connected('one.example')],
        plugin: (url) async {
          asked.add(url);
          return false;
        },
      );

      for (final request in [
        'discourse://open?url=javascript%3Aalert(1)',
        _request('https://reader:secret@one.example/t/42'),
        _request(_request('https://one.example/t/42')),
        'https://one.example/t/42',
      ]) {
        expect(
          await controller.openRequestedLink(request),
          isA<RequestedLinkMalformed>(),
          reason: request,
        );
      }
      expect(asked, isEmpty);
    },
  );

  test(
    'a page the app has no screen for is handed back for the browser',
    () async {
      final controller = await _shell([_connected('one.example')]);
      final before = controller.currentContent;

      final outcome = await controller.openRequestedLink(
        _request('https://one.example/admin/customize/themes'),
      );

      expect(
        outcome,
        isA<RequestedLinkUndecodable>().having(
          (undecodable) => undecodable.target.toString(),
          'target',
          'https://one.example/admin/customize/themes',
        ),
      );
      expect(controller.currentContent, same(before));
    },
  );

  test('a later request wins over an earlier one still resolving', () async {
    final earlierGate = Completer<bool>();
    final controller = await _shell(
      [_connected('one.example')],
      plugin: (url) =>
          url.contains('/earlier/') ? earlierGate.future : Future.value(false),
    );

    final earlier = controller.openRequestedLink(
      _request('https://one.example/t/earlier/41'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentContent?.topicId, isNot(41));

    expect(
      await controller.openRequestedLink(
        _request('https://one.example/t/later/42'),
      ),
      isA<RequestedLinkOpened>(),
    );
    expect(controller.currentContent?.topicId, 42);

    earlierGate.complete(false);
    expect(await earlier, isA<RequestedLinkSuperseded>());
    expect(controller.currentContent?.topicId, 42);
  });

  test('a notification tap wins over a request still resolving', () async {
    final requestGate = Completer<bool>();
    final controller = await _shell(
      [_connected('one.example')],
      plugin: (url) =>
          url.contains('/request/') ? requestGate.future : Future.value(false),
    );

    final request = controller.openRequestedLink(
      _request('https://one.example/t/request/41'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      await controller.openNotificationUrl('https://one.example/t/tapped/42'),
      isTrue,
    );

    requestGate.complete(false);
    expect(await request, isA<RequestedLinkSuperseded>());
    expect(controller.currentContent?.topicId, 42);
  });

  test('a request that outlives its forum opens nothing', () async {
    final gate = Completer<bool>();
    final controller = await _shell([
      _connected('one.example'),
      _connected('two.example'),
    ], plugin: (_) => gate.future);

    final request = controller.openRequestedLink(
      _request('https://two.example/t/removed/42'),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.removeInstance(controller.instances[1]);
    gate.complete(false);

    expect(await request, isA<RequestedLinkSuperseded>());
    expect(controller.currentContent?.topicId, isNot(42));
  });

  testWidgets(
    'a refused request is explained, and an unknown forum only offered',
    (tester) async {
      final requests = StreamController<String>.broadcast(sync: true);
      addTearDown(requests.close);
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final store = FakeInstanceStore([_connected('one.example')]);
      await tester.pumpWidget(
        DiscourseApp(
          store: store,
          api: api,
          authenticator: FakeAuthenticator.signedIn([
            _connected('one.example'),
          ], site: api),
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
          initialRootMode: ShellRootMode.forum,
          notificationOpenUrls: const Stream.empty(),
          linkOpenRequests: requests.stream,
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ShellScope>(find.byType(ShellScope))
          .notifier!;

      requests.add('discourse://open?url=javascript%3Aalert(1)');
      await tester.pump();
      await tester.pump();
      expect(find.text('That link can’t be opened here.'), findsOneWidget);

      requests.add(_request('https://evil.example/t/phish/42?token=secret'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('evil.example isn’t one of your sites.'),
        findsOneWidget,
      );
      expect(controller.instances, hasLength(1));

      await tester.tap(find.text('Add a site'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((field) => field.controller.text),
        contains('https://evil.example'),
      );
      expect(controller.instances, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final platform in const [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.linux,
  ]) {
    test('${platform.name} hands over requests unparsed', () async {
      const channel = MethodChannel('test.discourse.native/link_opens');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> native(String method, Object? argument) =>
          messenger.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, argument)),
            (_) {},
          );
      final listened = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'listen');
        listened.complete();
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final received = <String>[];
      final subscription = PlatformLinkOpens(
        channel: channel,
        platform: platform,
      ).requests.listen(received.add);
      await listened.future;
      await native('open', _request('https://one.example/t/42'));
      await native('open', '');
      await native('open', 42);
      await native('close', _request('https://one.example/t/43'));
      expect(received, [_request('https://one.example/t/42')]);

      await subscription.cancel();
      await native('open', _request('https://one.example/t/44'));
      expect(received, hasLength(1));
    });
  }

  test(
    'a runner without the forwarder is a platform with no requests',
    () async {
      final received = <String>[];
      final subscription = PlatformLinkOpens(
        channel: const MethodChannel('test.discourse.native/absent_link_opens'),
        platform: TargetPlatform.linux,
      ).requests.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(received, isEmpty);
    },
  );

  test('platforms without the scheme expose no requests', () async {
    expect(
      await PlatformLinkOpens(
        platform: TargetPlatform.windows,
      ).requests.toList(),
      isEmpty,
    );
  });
}

DiscourseInstance _connected(String host) => instance(
  host,
).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));

Future<ShellController> _shell(
  List<DiscourseInstance> instances, {
  Future<bool> Function(String url)? plugin,
}) async {
  final plugins = PluginInstaller.install(
    PluginManifest([if (plugin != null) _LinkModule(plugin)]),
  );
  addTearDown(plugins.close);
  final api = FakeDiscourseApi(
    feeds: const {'/latest.json': []},
    topics: {
      for (final id in [41, 42]) id: topicPayload(id: id, title: 'Topic $id'),
    },
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore(instances),
    api: api,
    authenticator: FakeAuthenticator.signedIn([
      for (final instance in instances)
        if (instance.isConnected) instance,
    ], site: api),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins,
  );
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

final class _LinkModule implements PluginModule {
  const _LinkModule(this.open);

  final Future<bool> Function(String url) open;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('link-open-test'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _LinkLifecycle(),
        capabilities: [_LinkHandler(open)],
      ),
    );
  }
}

final class _LinkLifecycle extends PluginSessionLifecycle {}

final class _LinkHandler implements PluginLinkHandler {
  const _LinkHandler(this.open);

  final Future<bool> Function(String url) open;

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) => open(url);
}
