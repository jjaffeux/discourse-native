import 'dart:async';

import 'package:discourse_native/discourse_ui.dart'
    show DButton, DButtonVariant, DPopoverContent;
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('compact navigation fits narrow and enlarged layouts', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
          tester.view.physicalSize = const Size(320, 640);
          final shell = await _loadShell(FakeDiscourseApi(user: _user));
          await _openProgress(
            tester,
            shell,
            TargetPlatform.macOS,
            dark: dark,
            scale: scale,
            direction: direction,
          );
          expect(find.text('Topic progress'), findsNothing);
          final panel = tester.getRect(find.byType(DPopoverContent));
          for (final label in ['First post', 'Latest post', 'Jump']) {
            final button = find.widgetWithText(DButton, label);
            final bounds = tester.getRect(button);
            expect(panel.contains(bounds.topLeft), isTrue);
            expect(panel.contains(bounds.bottomRight), isTrue);
          }
          final jump = tester.widget<DButton>(find.byKey(_jumpKey));
          expect(jump.variant, DButtonVariant.primary);
          for (final label in ['First post', 'Latest post']) {
            expect(
              tester
                  .widget<DButton>(find.widgetWithText(DButton, label))
                  .variant,
              DButtonVariant.ghost,
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(DPopoverContent), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    group(platform.name, () {
      for (final change in [
        'site',
        'topic',
        'tab',
        'account',
        'account session',
        'topic round trip',
        'root mode',
      ]) {
        testWidgets('an open progress route rejects a changed $change', (
          tester,
        ) async {
          final shell = await _loadShell(FakeDiscourseApi(user: _user));
          await _openProgress(tester, shell, platform);
          final openingTab = shell.activeTabId;
          switch (change) {
            case 'site':
              shell.selectInstance(1);
              _openTopic(shell);
            case 'topic':
              _openTopic(shell, topicId: 2);
            case 'tab':
              shell.createTab();
              _openTopic(shell);
            case 'account':
              await shell.disconnectCurrentInstance();
              _storeTopics(shell, _siteUrl);
              _openTopic(shell);
            case 'account session':
              // Retire the account lease while retaining the same site, topic,
              // tab and visible account identity, as a same-account reconnect can.
              shell.lifecycle.invalidate(_siteUrl);
              expect(shell.activeTabId, openingTab);
            case 'topic round trip':
              _openTopic(shell, topicId: 2);
              expect(shell.handleBack(), isTrue);
            case 'root mode':
              shell.selectAggregate();
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsOneWidget,
          );
          final source = shell.currentContent;
          final revision = shell.topicNavigationRevision;

          await tester.tap(find.byKey(_jumpKey));
          await tester.pumpAndSettle();

          expect(shell.currentContent, same(source));
          expect(shell.topicNavigationRevision, revision);
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsOneWidget,
          );
          expect(
            find.text(
              'Close and reopen topic progress to jump in the current topic.',
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('topic-progress-button')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }

      for (final dismissal in ['Escape', 'barrier']) {
        testWidgets('late success after $dismissal preserves a new route', (
          tester,
        ) async {
          final gate = Completer<void>();
          final api = FakeDiscourseApi(
            user: _user,
            postGate: gate,
            postsById: const {200: _target},
          );
          final shell = await _loadShell(api, cacheTarget: false);
          final navigator = await _openProgress(tester, shell, platform);

          await tester.tap(find.byKey(_jumpKey));
          await tester.pump();
          expect(api.postFetches, [
            [200],
          ]);
          expect(shell.currentContent?.postNumber, 1);

          if (dismissal == 'Escape') {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tapAt(const Offset(5, 5));
          }
          await tester.pump();

          unawaited(
            navigator.push<void>(
              DialogRoute<void>(
                context: navigator.context,
                builder: (_) =>
                    const AlertDialog(content: Text('Replacement route')),
              ),
            ),
          );
          await tester.pump();

          expect(find.text('Replacement route'), findsOneWidget);

          gate.complete();
          await tester.pumpAndSettle();

          // The real controller successfully resolves the unloaded stream ID;
          // only the dismissed editor's completion must be inert.
          expect(shell.currentContent?.postNumber, _target.postNumber);
          expect(find.text('Replacement route'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('late completion cannot close a reopened popover', (
        tester,
      ) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: _user,
          postGate: gate,
          postsById: const {200: _target},
        );
        final shell = await _loadShell(api, cacheTarget: false);
        await _openProgress(tester, shell, platform);
        await tester.tap(find.byKey(_jumpKey));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-progress-selection')),
          findsOneWidget,
        );
        expect(find.text('Post 2 of 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final action in ['First post', 'Latest post']) {
        testWidgets('$action jumps and closes the popover', (tester) async {
          final api = FakeDiscourseApi(
            user: _user,
            postsById: const {
              300: Post(
                id: 300,
                postNumber: 12,
                username: 'sam',
                cooked: '<p>Last</p>',
              ),
            },
          );
          final shell = await _loadShell(api);
          await _openProgress(tester, shell, platform);
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(
            shell.currentContent?.postNumber,
            action == 'First post' ? 1 : 12,
          );
          expect(
            find.byKey(const ValueKey('topic-progress-selection')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('an unchanged source can retry a failed lookup and jump', (
        tester,
      ) async {
        final responses = <int, Post>{};
        final api = FakeDiscourseApi(user: _user, postsById: responses);
        final shell = await _loadShell(api, cacheTarget: false);
        await _openProgress(tester, shell, platform);

        await tester.tap(find.byKey(_jumpKey));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not open that post. Try again.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-progress-selection')),
          findsOneWidget,
        );
        expect(shell.currentContent?.postNumber, 1);

        responses[200] = _target;
        await tester.tap(find.byKey(_jumpKey));
        await tester.pumpAndSettle();

        expect(api.postFetches, [
          [200],
          [200],
        ]);
        expect(shell.currentContent?.postNumber, _target.postNumber);
        expect(
          find.byKey(const ValueKey('topic-progress-selection')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('topic-progress-button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}

const _siteUrl = 'https://meta.example';
const _jumpKey = ValueKey('topic-progress-jump');
const _user = DiscourseUser(id: 1, username: 'sam');
const _target = Post(
  id: 200,
  postNumber: 7,
  username: 'sam',
  cooked: '<p>Target</p>',
);

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  bool cacheTarget = true,
}) async {
  final sites = [
    instance('meta.example').copyWith(user: _user),
    instance('other.example').copyWith(user: _user),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore(sites),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys.addAll({for (final site in sites) site.url: 'key'}),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  for (final site in sites) {
    _storeTopics(shell, site.url, cacheTarget: cacheTarget);
  }
  _openTopic(shell);
  return shell;
}

void _storeTopics(
  ShellController shell,
  String siteUrl, {
  bool cacheTarget = true,
}) {
  for (final topicId in [1, 2]) {
    final firstId = topicId == 1 ? 100 : 400;
    shell.store
      ..put(
        siteUrl,
        TopicDetail(
          id: topicId,
          title: 'Topic $topicId',
          stream: [firstId, firstId + 100, firstId + 200],
          postsCount: 3,
        ),
      )
      ..put(
        siteUrl,
        Post(
          id: firstId,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First</p>',
        ),
      );
    if (cacheTarget) {
      shell.store.put(
        siteUrl,
        Post(
          id: firstId + 100,
          postNumber: _target.postNumber,
          username: 'sam',
          cooked: '<p>Target</p>',
        ),
      );
    }
  }
}

void _openTopic(ShellController shell, {int topicId = 1}) => shell.pushContent(
  ContentRoute.topic(
    topicId: topicId,
    slug: 'topic-$topicId',
    title: 'Topic $topicId',
    postNumber: 1,
  ),
);

Future<NavigatorState> _openProgress(
  WidgetTester tester,
  ShellController shell,
  TargetPlatform platform, {
  bool dark = false,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
        platform: platform,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: TopicProgressPopover(controller: shell, position: 2, total: 3),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
  await tester.pumpAndSettle();
  expect(find.text('Post 2 of 3'), findsOneWidget);
  expect(find.byType(DPopoverContent), findsOneWidget);
  expect(find.byType(Dialog), findsNothing);
  expect(find.byType(BottomSheet), findsNothing);
  expect(
    tester.getRect(find.byType(DPopoverContent)).bottom,
    lessThanOrEqualTo(
      tester.getRect(find.byKey(const ValueKey('topic-progress-button'))).top,
    ),
  );
  return navigatorKey.currentState!;
}
