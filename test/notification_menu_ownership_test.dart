import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/category_notifications.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteA = 'https://meta.example';
const _siteB = 'https://team.example';
const _categories = [
  TopicCategory(id: 5, name: 'Support', slug: 'support', color: '0088CC'),
  TopicCategory(id: 6, name: 'Design', slug: 'design', color: '0088CC'),
];

Finder _menuOption(String title) => find.descendant(
  of: find.byType(DDropdownMenuContent),
  matching: find.text(title),
);

void main() {
  for (final category in [true, false]) {
    final kind = category ? 'category' : 'topic';

    testWidgets('$kind menu cannot write after navigation to another target', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester);
      final owner = tester.element(harness.wrapper);
      final reader = category ? null : tester.state(find.byType(TopicView));
      await harness.open(tester);

      harness.navigate(id: category ? 6 : 9);
      await tester.pumpAndSettle();
      if (category) {
        // The production inbox heading reuses the same wrapper slot.
        expect(tester.element(harness.wrapper), same(owner));
      } else {
        // MainContent's inbox reader already has a per-topic parent key.
        expect(reader!.mounted, isFalse);
      }
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(harness.api.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$kind menu cannot write to the same ID on another site', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester);
      await harness.open(tester);
      harness.navigate(siteUrl: _siteB);
      await tester.pumpAndSettle();
      expect(harness.shell.currentInstance!.url, _siteB);
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(harness.api.writes, isEmpty);

      await harness.open(tester);
      await tester.tap(_menuOption('Watching'));
      await tester.pumpAndSettle();
      expect(harness.api.writes, [
        (siteUrl: _siteB, id: harness.id, apiKey: 'key-b', level: 3),
      ]);
    });

    testWidgets('$kind menu cannot write after reconnecting the same URL', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester);
      await harness.open(tester);
      final lease = harness.shell.lifecycle.capture(_siteA);
      await harness.shell.connectCurrentInstance();
      expect(lease.isCurrent, isFalse);
      harness.navigate();
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(harness.api.writes, isEmpty);

      await harness.open(tester);
      await tester.tap(_menuOption('Muted'));
      await tester.pumpAndSettle();
      expect(harness.api.writes, [
        (siteUrl: _siteA, id: harness.id, apiKey: 'api-key', level: 0),
      ]);
    });

    testWidgets(
      '$kind selection rejects an expired account before rebuilding',
      (tester) async {
        final harness = await _Harness.create(tester, category: category);
        await harness.pump(tester);
        await harness.open(tester);
        // A session can expire before the next frame rebuilds its anchor.
        harness.shell.lifecycle.invalidate(_siteA);
        harness.authenticator.keys[_siteA] = 'replacement-key';
        await tester.tap(_menuOption('Watching'));
        await tester.pumpAndSettle();
        expect(harness.api.writes, isEmpty);
      },
    );

    testWidgets('$kind same-target updates keep the open menu usable', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester);
      final state = tester.state(harness.anchor);
      await harness.open(tester);
      harness.setLevel(tracking: true);
      await tester.pumpAndSettle();
      expect(tester.state(harness.anchor), same(state));
      await tester.tap(_menuOption('Watching'));
      await tester.pumpAndSettle();
      expect(harness.api.writes, [
        (siteUrl: _siteA, id: harness.id, apiKey: 'key-a', level: 3),
      ]);

      await harness.open(tester);
      harness.setLevel(tracking: false);
      await tester.pumpAndSettle();
      await tester.tap(_menuOption('Muted'));
      await tester.pumpAndSettle();
      expect(
        harness.api.writes,
        hasLength(1),
        reason: 'Current value is a no-op',
      );
    });

    testWidgets('$kind menu cannot write after its production view unmounts', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester);
      final state = tester.state(harness.anchor);
      await harness.open(tester);
      harness.shell.pushContent(ContentRoute.userActivity());
      await tester.pumpAndSettle();
      expect(state.mounted, isFalse);
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(harness.api.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$kind anchor retires an account even when its slot survives', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester, buttonOnly: true);
      final owner = tester.element(harness.wrapper);
      await harness.open(tester);
      await harness.shell.connectCurrentInstance();
      harness.navigate();
      await harness.pump(tester, buttonOnly: true);
      expect(tester.element(harness.wrapper), same(owner));
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(harness.api.writes, isEmpty);
      await harness.open(tester);
      await tester.tap(_menuOption('Muted'));
      await tester.pumpAndSettle();
      expect(harness.api.writes.single.apiKey, 'api-key');
    });

    testWidgets('$kind anchor retires when only its controller changes', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, category: category);
      await harness.pump(tester, buttonOnly: true);
      final owner = tester.element(harness.wrapper);
      await harness.open(tester);
      final replacement = await _Harness.create(
        tester,
        category: category,
        lifecycle: harness.shell.lifecycle,
      );
      await replacement.pump(tester, buttonOnly: true);
      expect(tester.element(harness.wrapper), same(owner));
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(harness.api.writes, isEmpty);
      expect(replacement.api.writes, isEmpty);
      await replacement.open(tester);
      await tester.tap(_menuOption('Muted'));
      await tester.pumpAndSettle();
      expect(replacement.api.writes, hasLength(1));
      expect(harness.api.writes, isEmpty);
    });

    for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
      testWidgets('$kind menu preserves selection on $platform', (
        tester,
      ) async {
        final harness = await _Harness.create(tester, category: category);
        await harness.pump(tester, platform: platform);
        await harness.open(tester);
        harness.setLevel(tracking: true);
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.macOS) {
          await tester.sendKeyEvent(LogicalKeyboardKey.home);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          expect(find.byType(DDropdownMenuContent), findsOneWidget);
          await tester.tap(_menuOption('Watching'));
        }
        await tester.pumpAndSettle();
        expect(harness.api.writes, [
          (siteUrl: _siteA, id: harness.id, apiKey: 'key-a', level: 3),
        ]);
      });
    }
  }

  testWidgets('standalone topic parent key retires an old menu on navigation', (
    tester,
  ) async {
    final harness = await _Harness.create(tester, category: false);
    harness.shell.pushContent(ContentRoute.userActivity());
    harness.navigate();
    await harness.pump(tester);
    expect(harness.shell.topicListContent, isNull);
    final state = tester.state(find.byType(TopicView));
    await harness.open(tester);
    harness.navigate(id: 9);
    await tester.pumpAndSettle();
    expect(state.mounted, isFalse);
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(harness.api.writes, isEmpty);
  });
}

final class _Harness {
  _Harness(this.category, this.shell, this.api, this.authenticator);

  final bool category;
  final ShellController shell;
  final _NotificationApi api;
  final FakeAuthenticator authenticator;

  int get id => category ? 5 : 7;
  Finder get wrapper => find.byType(
    category ? CategoryNotificationLevelButton : TopicNotificationLevelButton,
  );
  Finder get anchor =>
      find.descendant(of: wrapper, matching: find.byType(DPopover));

  static Future<_Harness> create(
    WidgetTester tester, {
    required bool category,
    SiteLifecycle? lifecycle,
  }) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _NotificationApi();
    final authenticator = FakeAuthenticator()
      ..keys[_siteA] = 'key-a'
      ..keys[_siteB] = 'key-b';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        for (final host in ['meta.example', 'team.example'])
          instance(
            host,
          ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
      ]),
      api: api,
      lifecycle: lifecycle,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabsEnabled: false,
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    final harness = _Harness(category, shell, api, authenticator);
    harness.navigate();
    return harness;
  }

  void navigate({int? id, String siteUrl = _siteA}) {
    final targetId = id ?? this.id;
    final opened = category
        ? shell.openListUrl(
            '$siteUrl/c/${targetId == 5 ? 'support' : 'design'}/$targetId',
          )
        : shell.openTopicUrl('$siteUrl/t/topic-$targetId/$targetId');
    expect(opened, isTrue);
  }

  Future<void> pump(
    WidgetTester tester, {
    bool buttonOnly = false,
    TargetPlatform platform = TargetPlatform.macOS,
  }) async {
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: buttonOnly
                ? Align(
                    alignment: Alignment.topLeft,
                    child: category
                        ? const CategoryNotificationLevelButton(
                            siteUrl: _siteA,
                            categoryId: 5,
                          )
                        : const TopicNotificationLevelButton(
                            siteUrl: _siteA,
                            topic: TopicDetail(
                              id: 7,
                              title: 'Topic 7',
                              stream: [],
                            ),
                          ),
                  )
                : const MainContent(layout: ShellLayout.expanded),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(
      find.byKey(
        ValueKey(
          '${category ? 'category' : 'topic'}-notification-level-button',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_menuOption('Watching'), findsOneWidget);
  }

  void setLevel({required bool tracking}) {
    if (category) {
      shell.store.update<TopicCategory>(
        _siteA,
        id,
        (value) => value.withNotificationLevel(
          tracking
              ? CategoryNotificationLevel.tracking
              : CategoryNotificationLevel.muted,
        ),
      );
    } else {
      shell.store.update<TopicDetail>(
        _siteA,
        id,
        (value) => value.withNotificationLevel(
          tracking
              ? TopicNotificationLevel.tracking
              : TopicNotificationLevel.muted,
        ),
      );
    }
  }
}

typedef _Write = ({String siteUrl, int id, String apiKey, int level});

final class _NotificationApi extends FakeDiscourseApi {
  _NotificationApi()
    : super(
        feeds: const {
          '/latest.json': [],
          '/c/support/5.json': [],
          '/c/design/6.json': [],
        },
        categoryList: _categories,
        topics: {
          for (final id in [7, 9])
            id: topicPayload(id: id, title: 'Topic $id', stream: const []),
        },
      );

  final writes = <_Write>[];

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    writes.add((
      siteUrl: siteUrl,
      id: topicId,
      apiKey: apiKey,
      level: notificationLevel.index,
    ));
  }

  @override
  Future<List<int>?> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    writes.add((
      siteUrl: siteUrl,
      id: categoryId,
      apiKey: apiKey,
      level: notificationLevel.index,
    ));
    return const [];
  }
}
