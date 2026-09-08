import 'dart:async';

import 'package:discourse_native/discourse_ui.dart' show DSpinner;
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
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
          expect(find.text('Topic progress'), findsOneWidget);
          final source = shell.currentContent;
          final revision = shell.topicNavigationRevision;

          await tester.tap(find.byKey(_jumpKey));
          await tester.pumpAndSettle();

          expect(shell.currentContent, same(source));
          expect(shell.topicNavigationRevision, revision);
          expect(find.text('Topic progress'), findsOneWidget);
          expect(
            find.text(
              'Close and reopen topic progress to jump in the current topic.',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(find.text('Open progress'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      for (final dismissal in [
        'Close',
        'back',
        if (platform == TargetPlatform.iOS) 'drag' else 'barrier',
      ]) {
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
          final editorContext = tester.element(find.byKey(_jumpKey));
          final progressRoute = ModalRoute.of(editorContext)!;

          await tester.tap(find.byKey(_jumpKey));
          await tester.pump();
          expect(api.postFetches, [
            [200],
          ]);
          expect(shell.currentContent?.postNumber, 1);

          switch (dismissal) {
            case 'Close':
              await tester.tap(find.byTooltip('Close'));
            case 'back':
              await tester.binding.handlePopRoute();
            case 'drag':
              await tester.fling(
                find.byType(BottomSheet),
                const Offset(0, 80),
                1500,
              );
            case 'barrier':
              await tester.tapAt(const Offset(5, 5));
          }
          await tester.pump();
          expect(progressRoute.isActive, isFalse);
          expect(editorContext.mounted, isTrue);

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
          expect(editorContext.mounted, isTrue);
          expect(find.text('Replacement route'), findsOneWidget);

          gate.complete();
          await tester.pumpAndSettle();

          // The real controller successfully resolves the unloaded stream ID;
          // only the dismissed editor's completion must be inert.
          expect(shell.currentContent?.postNumber, _target.postNumber);
          expect(find.text('Replacement route'), findsOneWidget);
          expect(find.text('Topic progress'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }

      for (final succeeds in [false, true]) {
        testWidgets(
          'a covered progress route handles lookup ${succeeds ? 'success' : 'failure'} without popping its cover',
          (tester) async {
            final gate = Completer<void>();
            final responses = <int, Post>{if (succeeds) 200: _target};
            final api = FakeDiscourseApi(
              user: _user,
              postGate: gate,
              postsById: responses,
            );
            final shell = await _loadShell(api, cacheTarget: false);
            final navigator = await _openProgress(tester, shell, platform);
            final progressRoute = ModalRoute.of(
              tester.element(find.byKey(_jumpKey)),
            )!;
            await tester.tap(find.byKey(_jumpKey));
            await tester.pump();
            expect(api.postFetches, [
              [200],
            ]);

            unawaited(
              navigator.push<void>(
                DialogRoute<void>(
                  context: navigator.context,
                  builder: (_) => const AlertDialog(content: Text('Cover')),
                ),
              ),
            );
            await tester.pump();
            expect(progressRoute.isActive, isTrue);
            expect(progressRoute.isCurrent, isFalse);
            gate.complete();
            await tester.pumpAndSettle();

            expect(find.text('Cover'), findsOneWidget);
            navigator.pop();
            await tester.pumpAndSettle();
            expect(find.text('Topic progress'), findsOneWidget);
            expect(find.byType(DSpinner), findsNothing);
            expect(
              find.text('Could not open that post. Try again.'),
              succeeds ? findsNothing : findsOneWidget,
            );

            responses[200] = _target;
            await tester.tap(find.byKey(_jumpKey));
            await tester.pumpAndSettle();
            expect(shell.currentContent?.postNumber, _target.postNumber);
            expect(find.text('Topic progress'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
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
        expect(find.text('Topic progress'), findsOneWidget);
        expect(shell.currentContent?.postNumber, 1);

        responses[200] = _target;
        await tester.tap(find.byKey(_jumpKey));
        await tester.pumpAndSettle();

        expect(api.postFetches, [
          [200],
          [200],
        ]);
        expect(shell.currentContent?.postNumber, _target.postNumber);
        expect(find.text('Topic progress'), findsNothing);
        expect(find.text('Open progress'), findsOneWidget);
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
  TargetPlatform platform,
) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.light.copyWith(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showTopicProgress(
                context: context,
                controller: shell,
                position: 2,
                total: 3,
              ),
            ),
            child: const Text('Open progress'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open progress'));
  await tester.pumpAndSettle();
  expect(find.text('Post 2 of 3'), findsOneWidget);
  expect(
    find.byType(platform == TargetPlatform.iOS ? BottomSheet : Dialog),
    findsOneWidget,
  );
  return navigatorKey.currentState!;
}
