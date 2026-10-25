import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _mobile = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});
final _more = find.byKey(const ValueKey('topic-more-actions'));
final _menu = find.byType(DDropdownMenuContent);
final _menuSheet = find.ancestor(
  of: _menu,
  matching: find.byType(DSheetContent),
);

void main() {
  if (const bool.fromEnvironment('captureTopicMore')) {
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
    tearDownAll(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('org.discourse.native/notification_opens'),
            null,
          ),
    );
  }

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    {
      testWidgets('topic More appearance ${mode.name} flat', (tester) async {
        await _openTopic(tester, mode: mode);
        await _openMore(tester);
        expect(
          Theme.of(tester.element(_menu)).brightness,
          mode == AppThemeMode.dark ? Brightness.dark : Brightness.light,
        );

        final rect = tester.getRect(_menuSheet);
        expect(rect.left, 6);
        expect(rect.right, 384);
        expect(rect.bottom, 838);
        await _capture(
          tester,
          '${Theme.of(tester.element(_more)).platform.name}-${mode.name}-flat',
        );
        expect(rect.height, closeTo(144.04, 1));
        final labels = ['Share topic', 'Flag topic', 'Mark unread'];
        for (final label in labels) {
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.text('Share topic')).label,
          'Share topic',
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }
  }

  testWidgets('topic More opens a compact floating menu over the reader', (
    tester,
  ) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    final (shell, _) = await _openTopic(tester);
    final reader = shell.currentContent;
    await _openMore(tester);

    expect(_menuSheet, findsOneWidget);
    expect(find.text('Share topic'), findsOneWidget);
    expect(find.text('Flag topic'), findsOneWidget);
    expect(find.text('Mark unread'), findsOneWidget);
    expect(
      find.descendant(of: _menuSheet, matching: find.byType(DSheetHeader)),
      findsNothing,
    );
    expect(
      find.descendant(of: _menuSheet, matching: find.byTooltip('Close')),
      findsNothing,
    );
    final bounds = tester.getRect(_menuSheet);
    expect(bounds.left, 6);
    expect(bounds.right, 384);
    expect(bounds.bottom, 804);
    expect(bounds.height, lessThan(200));
    final handle = find.descendant(
      of: _menuSheet,
      matching: find.byKey(const ValueKey('sheet-drag-handle')),
    );
    expect(tester.getSize(handle), const Size(36, 5));
    expect(tester.widget<DButton>(_more).expanded, isTrue);
    expect(shell.currentContent, same(reader));

    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(tester.widget<DButton>(_more).expanded, isFalse);
    expect(shell.currentContent, same(reader));
    expect(find.byType(TopicStatusButton), findsOneWidget);

    await _openMore(tester);
    await tester.drag(
      find.descendant(
        of: _menuSheet,
        matching: find.byKey(const ValueKey('sheet-drag-handle')),
      ),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(shell.currentContent, same(reader));
    expect(tester.takeException(), isNull);
  }, variant: _mobile);

  for (final action in ['Share topic', 'Flag topic', 'Mark unread']) {
    testWidgets('$action closes More and performs its action on mobile', (
      tester,
    ) async {
      final (shell, api) = await _openTopic(tester);
      await _openMore(tester);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(_menu, findsNothing);
      switch (action) {
        case 'Share topic':
          expect(
            find.byKey(const ValueKey('topic-share-copy')),
            findsOneWidget,
          );
        case 'Flag topic':
          expect(find.byType(PostFlagEditor), findsOneWidget);
        default:
          expect(
            api.pluginWrites.any(
              (write) =>
                  write.method == 'DELETE' &&
                  write.path == '/t/7/timings.json?last=1',
            ),
            isTrue,
          );
          expect(shell.currentContent?.topicId, isNot(7));
      }
      expect(tester.takeException(), isNull);
    }, variant: _mobile);
  }

  testWidgets('topic More remains anchored on desktop', (tester) async {
    await _openTopic(tester, size: desktop);
    await _openMore(tester);
    expect(_menu, findsOneWidget);
    expect(_menuSheet, findsNothing);
    expect(tester.getSize(_menu).width, 224);
    expect(
      tester.getRect(_menu).top,
      greaterThan(tester.getRect(_more).bottom),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('mobile More supports large text, reduced motion, and Escape', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final (shell, _) = await _openTopic(tester, size: const Size(320, 740));
    final reader = shell.currentContent;
    final focus = tester.widget<DButton>(_more).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await _openMore(tester);
    expect(find.text('Mark unread').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(focus.hasFocus, isTrue);
    expect(shell.currentContent, same(reader));
    expect(tester.takeException(), isNull);
  }, variant: _mobile);
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureTopicMore')) return;
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    repaint(tester.binding.renderViews.first);
    await tester.pump();
    await tester.runAsync(() async {
      final builder = ui.SceneBuilder();
      tester.binding.renderViews.first.debugLayer!.addToScene(builder);
      final scene = builder.build();
      final image = await scene.toImage(390, 844);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/private/tmp/topic-more-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      scene.dispose();
    });
  } finally {
    debugDisableShadows = previous;
  }
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(_more);
  await tester.pumpAndSettle();
}

Future<(ShellController, FakeDiscourseApi)> _openTopic(
  WidgetTester tester, {
  Size size = phone,
  AppThemeMode? mode,
}) async {
  const user = DiscourseUser(id: 9, username: 'reader');
  final api = FakeDiscourseApi(
    user: user,
    pluginResponses: const {'DELETE /t/7/timings.json?last=1': {}},
    feeds: const {
      '/latest.json': [
        Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
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
        title: 'A real topic',
        canFlagTopic: true,
        topicActions: const [PostActionSummary(id: 3, canAct: true)],
        posts: const [
          Post(
            id: 1,
            postNumber: 1,
            username: 'author',
            cooked: '<p>Topic content</p>',
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
  if (mode != null) {
    final shell = ShellScope.read(tester.element(primaryMainContent));
    await shell.forumSettings.setThemeMode(_site, mode);
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences.preset('dracula'),
    );
    await shell.forumSettings.setShared(
      shell.forumSettings.shared.copyWith(
        font: ForumFont.lato,
        interfaceFont: ForumFont.lato,
      ),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('topic-card-7')));
  await tester.pumpAndSettle();
  return (ShellScope.read(tester.element(_more)), api);
}
