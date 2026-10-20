import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _mobile = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});
final _compact = find.byKey(const ValueKey('topic-header-compact-layout'));
final _more = find.byKey(const ValueKey('topic-more-actions'));
final _menu = find.byType(DDropdownMenuContent);
Finder get _menuSheet =>
    find.ancestor(of: _menu, matching: find.byType(DSheetContent)).first;

void main() => topicCompactActionsSheetTests();

void topicCompactActionsSheetTests({
  bool native = false,
  Future<void> Function(WidgetTester tester, String name)? onCapture,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(320, 740), 2.0),
  ]) {
    testWidgets(
      'topic bookmark, bell and assignment menus use mobile sheets at ${size.width} $scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (shell, api) = await _openCompact(
          tester,
          size: size,
          assigned: true,
        );
        final reader = shell.currentContent;
        final bookmark = find.byKey(
          const ValueKey('topic-header-bookmark-button'),
        );
        await tester.tap(bookmark);
        await tester.pumpAndSettle();
        final sheet = find.byType(DSheetContent).last;
        expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
        expect(
          tester.widget<DSheetContent>(sheet).variant,
          DSheetVariant.adaptiveMenu,
        );
        await tester.drag(
          find.byType(DSheetContent).last,
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('More options'));
        await tester.pumpAndSettle();
        await _capture(tester, 'bookmark-${size.width.toInt()}-$scale', size);
        expect(find.text('More options').hitTestable(), findsOneWidget);
        expect(api.createdBookmarks, hasLength(1));
        await tester.tap(find.text('More options'));
        await tester.pumpAndSettle();
        expect(find.text('Edit bookmark'), findsOneWidget);
        await tester.tap(find.byTooltip('Close').last);
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsOneWidget);

        final bell = find.byKey(
          const ValueKey('topic-header-notification-button'),
        );
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
        expect(
          tester.widget<DSheetContent>(sheet).variant,
          DSheetVariant.adaptiveMenu,
        );
        expect(find.text('Watching').hitTestable(), findsOneWidget);
        await _capture(tester, 'bell-${size.width.toInt()}-$scale', size);
        await tester.tap(find.text('Watching'));
        await tester.pumpAndSettle();
        expect(api.topicNotificationLevelsUpdated, [
          (topicId: 7, notificationLevel: TopicNotificationLevel.watching),
        ]);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(find.byType(DSheetContent), findsOneWidget);
        await tester.tap(bell);
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);

        await tester.tap(find.byKey(const Key('assign-topic-header')));
        await tester.pumpAndSettle();
        expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
        expect(
          tester.widget<DSheetContent>(sheet).variant,
          DSheetVariant.adaptiveMenu,
        );
        expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
        expect(find.text('@sam').hitTestable(), findsOneWidget);
        await _capture(tester, 'assign-${size.width.toInt()}-$scale', size);
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(shell.currentContent, reader);

        // The same trigger can reopen, and its sheet belongs to the reader.
        await tester.tap(find.byKey(const Key('assign-topic-header')));
        await tester.pumpAndSettle();
        shell.closeTopic();
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: native
          ? TargetPlatformVariant.only(TargetPlatform.iOS)
          : _mobile,
    );
  }
  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 740), 2.0),
    ]) {
      testWidgets(
        'compact topic actions match mobile menu layout ${mode.name} ${size.width} $scale',
        (tester) async {
          if (native) {
            expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
            await tester.runAsync(LiquidGlass.precache);
          }
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final (shell, _) = await _openCompact(tester, size: size, mode: mode);
          final reader = shell.currentContent;
          final scroll = tester
              .widget<CustomScrollView>(
                find
                    .descendant(
                      of: find.byType(TopicView),
                      matching: find.byType(CustomScrollView),
                    )
                    .first,
              )
              .controller!;
          final offset = scroll.offset;
          expect(
            find.byKey(const ValueKey('topic-compact-more')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('topic-header-taxonomy')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: _compact,
              matching: find.byType(TopicBookmarkButton),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: _compact,
              matching: find.byType(TopicNotificationLevelButton),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('assign-topic-header')).hitTestable(),
            findsOneWidget,
          );
          for (final button in [
            _more,
            find.byKey(const ValueKey('topic-status-button')),
          ]) {
            expect(button.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(button).right,
              lessThanOrEqualTo(size.width - 16),
            );
          }
          tester.widget<DButton>(_more).focusNode!.requestFocus();
          await tester.pump();
          await tester.tap(_more);
          await tester.pumpAndSettle();
          expect(
            tester.widget<DSheetContent>(_menuSheet).variant,
            DSheetVariant.adaptiveMenu,
          );
          expect(
            tester.widget<DDropdownMenuContent>(_menu).padding,
            const EdgeInsets.fromLTRB(8, 0, 8, 8),
          );
          final bounds = tester.getRect(_menuSheet);
          expect(bounds.left, 6);
          expect(bounds.right, size.width - 6);
          expect(bounds.bottom, size.height - 40);
          expect(
            find.descendant(
              of: _menuSheet,
              matching: find.byType(DSheetHeader),
            ),
            findsNothing,
          );
          final labels = ['Share topic', 'Flag topic', 'Mark unread'];
          final rows = find.descendant(
            of: _menu,
            matching: find.byType(DDropdownMenuItem),
          );
          expect(rows, findsNWidgets(3));
          double? previousBottom;
          for (var index = 0; index < labels.length; index++) {
            expect(find.text(labels[index]).hitTestable(), findsOneWidget);
            final row = tester.getRect(rows.at(index));
            expect(row.left, bounds.left + 8);
            expect(row.right, bounds.right - 8);
            if (previousBottom != null) {
              expect(row.top, closeTo(previousBottom, .01));
            }
            previousBottom = row.bottom;
          }
          expect(
            find.descendant(of: _menu, matching: find.byType(DButtonGroup)),
            findsNothing,
          );
          final semantics = tester.ensureSemantics();
          expect(
            tester.getSemantics(find.text('Share topic')).label,
            'Share topic',
          );
          semantics.dispose();
          final platform = Theme.of(tester.element(_menu)).platform;
          await _capture(
            tester,
            '${platform.name}-${mode.name}-${size.width.toInt()}-${scale.toInt()}x',
            size,
          );
          await onCapture?.call(
            tester,
            '${platform.name}-${mode.name}-${size.width.toInt()}-${scale.toInt()}x',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_menu, findsNothing);
          expect(shell.currentContent, same(reader));
          expect(scroll.offset, offset);
          expect(tester.widget<DButton>(_more).focusNode!.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        },
        variant: native
            ? TargetPlatformVariant.only(TargetPlatform.iOS)
            : _mobile,
      );
    }
  }
  testWidgets(
    'compact moderation opens its own sheet and applies the selected command',
    (tester) async {
      final (shell, api) = await _openCompact(tester);
      final reader = shell.currentContent;
      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DSheetContent>(_menuSheet).variant,
        DSheetVariant.adaptiveMenu,
      );
      expect(find.text('Share topic'), findsNothing);
      expect(find.text('Close topic').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Close topic'));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
      expect(shell.currentContent, same(reader));
      expect(shell.currentTopic!.closed, isTrue);
      expect(api.topicStatusesUpdated, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: native ? TargetPlatformVariant.only(TargetPlatform.iOS) : _mobile,
  );
}

Future<(ShellController, FakeDiscourseApi)> _openCompact(
  WidgetTester tester, {
  Size size = phone,
  AppThemeMode mode = AppThemeMode.dark,
  bool assigned = false,
}) async {
  const user = DiscourseUser(id: 9, username: 'moderator', staff: true);
  final api = FakeDiscourseApi(
    user: user,
    feeds: const {
      '/latest.json': [
        Topic(id: 7, title: 'A long community discussion', slug: 'discussion'),
      ],
    },
    categoryPostActionCatalog: const SitePostActionCatalog(
      topicFlags: [
        PostFlagType(
          id: 3,
          nameKey: 'off_topic',
          name: 'Off-Topic',
          description: '',
          appliesTo: ['Topic'],
        ),
      ],
    ),
    topics: {
      7: topicPayload(
        id: 7,
        title: 'A long community discussion',
        canCreatePost: true,
        canCloseTopic: true,
        canArchiveTopic: true,
        canFlagTopic: true,
        topicActions: const [PostActionSummary(id: 3, canAct: true)],
        tags: const [
          TopicTag(id: 1, name: 'design'),
          TopicTag(id: 2, name: 'mobile'),
        ],
        plugins: PluginData.none.withValue(
          assignmentsDataKey,
          Assignments(
            canAssign: true,
            direct: assigned
                ? const Assignment(
                    assignee: AssignmentUser(username: 'sam', name: 'Sam'),
                  )
                : null,
          ),
        ),
        posts: [
          for (var id = 1; id <= 50; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'reader',
              createdAt: DateTime.utc(2026, 9, 1, 0, id),
              cooked:
                  '<p>Post $id discusses mobile navigation, reading and the community.</p>',
            ),
        ],
      ),
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [instance('meta.discourse.org').copyWith(user: user)],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
  );
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
  final shell = ShellScope.read(
    tester.element(find.byKey(const ValueKey('topic-card-7'))),
  );
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 4);
  await tester.pumpAndSettle();
  await shell.forumSettings.setThemeMode(_site, mode);
  await shell.forumSettings.setShared(
    shell.forumSettings.shared.copyWith(
      font: ForumFont.lato,
      interfaceFont: ForumFont.lato,
      material: DAppearanceMaterial.standard,
    ),
  );
  await tester.pumpAndSettle();
  expect(_compact, findsOneWidget);
  return (shell, api);
}

Future<void> _capture(WidgetTester tester, String name, Size size) async {
  const directory = String.fromEnvironment('TOPIC_COMPACT_CAPTURE_DIR');
  if (directory.isEmpty) return;
  final bytes = await captureTopicCompactSheet(tester, size);
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes);
  });
}

Future<List<int>> captureTopicCompactSheet(
  WidgetTester tester,
  Size size,
) async {
  return (await tester.runAsync(() async {
    RenderObject root = tester.renderObject(find.byType(DSheetContent).last);
    while (root.parent != null) {
      root = root.parent!;
    }
    final builder = ui.SceneBuilder();
    (root as RenderView).debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(size.width.toInt(), size.height.toInt());
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return bytes.buffer.asUint8List().toList();
    } finally {
      image.dispose();
      scene.dispose();
    }
  }))!;
}
