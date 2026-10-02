import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show renderedText, replaceEmojiCache;

const _siteA = 'https://meta.discourse.org';
const _siteB = 'https://team.discourse.org';
const _user = DiscourseUser(id: 7, username: 'author');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final action in ['Delete', 'Make wiki', 'Reply']) {
    for (final change in [
      'forum',
      'topic',
      'tab',
      'connect rollback',
      'disconnect rollback',
      'unchanged',
      'counts',
    ]) {
      final valid = change == 'unchanged' || change == 'counts';
      for (final repaint in valid ? [true] : [false, true]) {
        testWidgets(
          'mobile post sheet $action keeps its owner across $change ${repaint ? 'after repaint' : 'before repaint'}',
          (tester) async {
            final fixture = await _Fixture.open(tester);
            final shell = fixture.shell;
            final post = find.ancestor(
              of: renderedText('Original reply'),
              matching: find.byType(PostActions),
            );
            await tester.longPress(
              find.descendant(of: post, matching: find.text('author')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(DSheetContent), findsOneWidget);
            expect(
              find.widgetWithText(DItem, action).hitTestable(),
              findsOneWidget,
            );
            final sheet = tester.element(find.byType(DSheetContent));
            final opening = shell.lifecycle.capture(_siteA);
            final originalTab = shell.activeTabId;
            final originalRoute = shell.currentContent?.id;
            switch (change) {
              case 'forum':
                shell.openTopicPost(siteUrl: _siteB, topicId: 7, postNumber: 2);
              case 'topic':
                shell.openTopicPost(siteUrl: _siteA, topicId: 8, postNumber: 1);
              case 'tab':
                shell.createTab();
                shell.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 2);
                expect(shell.activeTabId, isNot(originalTab));
                expect(shell.currentContent?.id, originalRoute);
              case 'connect rollback':
                fixture.store.failSignedOut = true;
                await tester.runAsync(shell.connectCurrentInstance);
                expect(opening.isCurrent, isFalse);
                expect(shell.activeTabId, originalTab);
                expect(shell.currentContent?.id, originalRoute);
              case 'disconnect rollback':
                fixture.store.failSignedOut = true;
                expect(
                  await tester.runAsync(() => shell.disconnectInstance(_siteA)),
                  isFalse,
                );
                expect(opening.isCurrent, isFalse);
                expect(shell.activeTabId, originalTab);
                expect(shell.currentContent?.id, originalRoute);
              case 'counts':
                FakeSiteTracker.built.last.deliverNotification(const {
                  'all_unread_notifications_count': 4,
                });
                expect(opening.isCurrent, isTrue);
              case 'unchanged':
                break;
            }
            if (repaint) await _settle(tester);
            expect(tester.element(find.byType(DSheetContent)), same(sheet));
            // The route-owned sheet remains available even if the reader below it
            // has moved or rolled its account session back.
            expect(find.text(action).hitTestable(), findsOneWidget);
            await tester.runAsync(() async {
              await tester.tap(find.text(action).hitTestable());
              await pumpEventQueue();
            });
            await _settle(tester);
            if (action == 'Reply') {
              expect(shell.visibleComposer, valid ? isNotNull : isNull);
              if (valid) {
                expect(shell.visibleComposer!.target.topicId, 7);
                expect(shell.visibleComposer!.target.replyToPostNumber, 2);
              }
              expect(fixture.api.writes, isEmpty);
            } else {
              expect(fixture.api.writes, hasLength(valid ? 1 : 0));
              if (valid) {
                final request = fixture.api.writes.single;
                expect(request.url.origin, _siteA);
                expect(request.headers['User-Api-Key'], 'a-key');
                expect(
                  request.url.path,
                  '/posts/2${action == 'Delete' ? '' : '/wiki'}.json',
                );
                expect(request.method, action == 'Delete' ? 'DELETE' : 'PUT');
              }
              expect(shell.visibleComposer, isNull);
            }
            expect(tester.takeException(), isNull);
          },
          variant: const TargetPlatformVariant({
            TargetPlatform.iOS,
            TargetPlatform.android,
          }),
        );
      }
    }
  }
  testWidgets(
    'mobile post sheet scrolls at large text and dismisses without an action',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _Fixture.open(tester, size: const Size(320, 650));
      final post = find.ancestor(
        of: renderedText('Original reply'),
        matching: find.byType(PostActions),
      );
      final header = find.descendant(of: post, matching: find.text('author'));
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.longPress(header);
      await tester.pumpAndSettle();
      final delete = find.widgetWithText(DItem, 'Delete');
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      expect(delete.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(fixture.api.writes, isEmpty);
      expect(fixture.shell.visibleComposer, isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump(const Duration(milliseconds: 300));
}

class _Fixture {
  _Fixture(this.shell, this.api, this.store);
  final ShellController shell;
  final _Api api;
  final _FailingStore store;

  static Future<_Fixture> open(
    WidgetTester tester, {
    Size size = const Size(390, 1000),
  }) async {
    final api = _Api();
    final store = _FailingStore();
    final shell = ShellController(
      api: api,
      instanceStore: store,
      authenticator: FakeAuthenticator()
        ..keys[_siteA] = 'a-key'
        ..keys[_siteB] = 'b-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    addTearDown(api.httpApi.close);
    await tester.runAsync(shell.load);
    shell.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 2);
    await tester.runAsync(() => pumpEventQueue());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    replaceEmojiCache(MockClient((_) async => http.Response('', 404)));
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: defaultTargetPlatform),
          builder: (_, child) => DToaster(child: child!),
          home: const Scaffold(body: MainContent(layout: ShellLayout.compact)),
        ),
      ),
    );
    await _settle(tester);
    expect(find.byType(PostActions), findsWidgets);
    expect(renderedText('Original reply'), findsOneWidget);
    return _Fixture(shell, api, store);
  }
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore()
    : super([
        instance('meta.discourse.org').copyWith(user: _user),
        instance('team.discourse.org').copyWith(user: _user),
      ]);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}

class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        user: _user,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Original topic',
            canCreatePost: true,
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'author',
                cooked: '<p>Original first</p>',
              ),
              Post(
                id: 2,
                postNumber: 2,
                username: 'author',
                cooked: '<p>Original reply</p>',
                canDelete: true,
                canWiki: true,
              ),
            ],
          ),
          8: topicPayload(
            id: 8,
            title: 'Other topic',
            canCreatePost: true,
            posts: const [
              Post(
                id: 3,
                postNumber: 1,
                username: 'other',
                cooked: '<p>Other first</p>',
              ),
            ],
          ),
        },
      );
  final writes = <http.Request>[];
  late final httpApi = DiscourseApi(
    client: MockClient((request) async {
      writes.add(request);
      return http.Response(jsonEncode(<String, Object?>{}), 200);
    }),
  );

  @override
  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => httpApi.deletePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<void> updatePostWiki({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool wiki,
    String? clientId,
  }) => httpApi.updatePostWiki(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    wiki: wiki,
    clientId: clientId,
  );
}
