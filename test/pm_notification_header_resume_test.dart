import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_module.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/notifications_menu.dart';
import 'support/shell_test_harness.dart';
import 'support/topic_post_list.dart';

const _site = 'https://meta.discourse.org';
const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

double _paintedTitleOpacity(WidgetTester tester) {
  final title = find.byKey(const ValueKey('topic-header-compact-title'));
  final placeholder = find.byKey(
    const ValueKey('topic-header-title-placeholder'),
  );
  final element = tester.element(
    title.evaluate().isEmpty ? placeholder : title,
  );
  double? opacity;
  element.visitAncestorElements((ancestor) {
    if (ancestor.renderObject case final RenderOpacity render) {
      opacity = render.opacity;
      return false;
    }
    return true;
  });
  return opacity!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final source in ['explicit', 'metadata', 'cached', 'cached_posts']) {
    testWidgets('PM notification never paints an expanded header source=$source', (
      tester,
    ) async {
      final gate = Completer<void>();
      final posts = [
        for (var number = 1; number <= 30; number++)
          Post(
            id: number,
            postNumber: number,
            username: 'reader',
            cooked:
                '<p>${List.filled(25, 'A private discussion post.').join(' ')}</p>',
          ),
      ];
      final detail = TopicDetail(
        id: 7,
        title: 'Returning to a private conversation',
        privateMessage: true,
        stream: [for (final post in posts) post.id],
        postsCount: posts.length,
        lastReadPostNumber: 12,
      );
      final shell = await pumpMobileShellFixture(
        tester,
        topicGate: gate,
        topic: (detail: detail, posts: posts),
      );
      if (source.startsWith('cached')) shell.store.put(_site, detail);
      if (source == 'cached_posts') shell.store.putAll(_site, posts);
      expect(
        await shell.openNotificationUrl(
          '$_site/t/private/7${source.endsWith('explicit') ? '/12' : ''}',
        ),
        isTrue,
      );
      final painted = <double>[];
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const ValueKey('topic-header-morph'))
            .evaluate()
            .isNotEmpty) {
          painted.add(_paintedTitleOpacity(tester));
        }
      }
      gate.complete();
      for (var frame = 0; frame < 48; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const ValueKey('topic-header-morph'))
            .evaluate()
            .isNotEmpty) {
          painted.add(_paintedTitleOpacity(tester));
        }
      }
      final page = DPageHeaderScope.maybeOf(
        tester.element(find.byKey(const ValueKey('topic-header-morph'))),
      )!;
      expect(page.barOpacity, 1);
      expect(topicPostList(tester).controller!.offset, greaterThan(0));
      expect(painted, isNotEmpty);
      expect(
        painted,
        everyElement(0.0),
        reason:
            'The resumed header must remain hidden in every painted opening frame.',
      );
      topicPostList(tester).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_paintedTitleOpacity(tester), 1);
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }
  testWidgets('unread PM reveals its expanded header after metadata resolves', (
    tester,
  ) async {
    final gate = Completer<void>();
    final shell = await pumpMobileShellFixture(
      tester,
      topicGate: gate,
      topic: topicPayload(
        id: 7,
        title: 'Unread private conversation',
        privateMessage: true,
        posts: const [
          Post(
            id: 1,
            postNumber: 1,
            username: 'reader',
            cooked: '<p>A new private message.</p>',
          ),
        ],
      ),
    );
    expect(await shell.openNotificationUrl('$_site/t/private/7'), isTrue);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_paintedTitleOpacity(tester), 0);
    }
    gate.complete();
    await tester.pumpAndSettle();
    expect(_paintedTitleOpacity(tester), 1);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets(
    'discovered PM never paints its first window before the notification target',
    (tester) async {
      final gate = Completer<void>();
      final posts = [
        for (var number = 1; number <= 100; number++)
          Post(
            id: number,
            postNumber: number,
            username: 'reader',
            cooked:
                '<p>${List.filled(25, 'A private discussion post.').join(' ')}</p>',
          ),
      ];
      final api = _WindowedPmApi(posts, gate);
      await pumpShell(
        tester,
        phone,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
        ],
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        api: api,
        pluginManifest: PluginManifest([
          ...bundledWidgetTestManifest.modules,
          nestedRepliesModule,
        ]),
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MobileForumRoot)),
      );
      await tester.tap(dockNotifications);
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Private conversation notification').last,
      );
      final painted = <double>[];
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const ValueKey('topic-header-morph'))
            .evaluate()
            .isNotEmpty) {
          painted.add(_paintedTitleOpacity(tester));
        }
      }
      gate.complete();
      for (var frame = 0; frame < 48; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const ValueKey('topic-header-morph'))
            .evaluate()
            .isNotEmpty) {
          painted.add(_paintedTitleOpacity(tester));
        }
      }
      expect(shell.currentContent?.postNumber, 100);
      expect(find.byKey(const ValueKey(100)), findsOneWidget);
      expect(painted, isNotEmpty);
      expect(
        painted,
        everyElement(0.0),
        reason:
            'Discovery must not flash the first window before the requested post window.',
      );
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );
}

class _WindowedPmApi extends FakeDiscourseApi {
  _WindowedPmApi(this.allPosts, this.positionGate)
    : super(
        notificationList: const [
          DiscourseNotification.test(
            id: 80,
            typeId: NotificationTypeId(6),
            topicId: 7,
            postNumber: 100,
            slug: 'private',
            title: 'Private conversation notification',
            data: {'display_username': 'sender'},
          ),
        ],
        feeds: {
          '/latest.json': const [
            Topic(id: 7, title: 'Private conversation', slug: 'private'),
          ],
        },
        postsById: {for (final post in allPosts) post.id: post},
      );
  final List<Post> allPosts;
  final Completer<void> positionGate;
  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    topicsOpened.add(id);
    topicPostNumbersOpened.add(postNumber);
    if (postNumber != null) await positionGate.future;
    return (
      detail: TopicDetail(
        id: id,
        title: 'Private conversation',
        privateMessage: true,
        stream: [for (final post in allPosts) post.id],
        postsCount: allPosts.length,
        lastReadPostNumber: 99,
      ),
      posts: postNumber == null
          ? allPosts.take(20).toList()
          : allPosts.skip(80).toList(),
    );
  }
}
