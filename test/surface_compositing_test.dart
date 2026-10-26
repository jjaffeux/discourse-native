import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_more_topics_panel.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _control = ValueKey('surface-control');

List<double> _fractionalOpacityAbove(WidgetTester tester, Finder target) {
  final values = <double>[];
  RenderObject? ancestor = tester.renderObject(target).parent;
  while (ancestor != null) {
    final opacity = switch (ancestor) {
      RenderOpacity(:final opacity) => opacity,
      RenderAnimatedOpacity(:final opacity) => opacity.value,
      // Popovers fade while painting, through the opacity layer they retain.
      RenderObject(debugLayer: OpacityLayer(:final alpha?)) => alpha / 255,
      _ => 1.0,
    };
    if (opacity > 0 && opacity < 1) values.add(opacity);
    ancestor = ancestor.parent;
  }
  return values;
}

void _expectFading(WidgetTester tester, Finder content) {
  expect(content, findsOneWidget);
  expect(_fractionalOpacityAbove(tester, content), isNotEmpty);
}

Future<void> _host(WidgetTester tester, Widget child, ThemeData theme) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform: TargetPlatform.macOS,
    );
    final suffix = dark ? 'dark' : 'light';
    void check(String name, Future<void> Function(WidgetTester) body) {
      testWidgets('$name ($suffix)', (tester) async {
        await body(tester);
        expect(tester.takeException(), isNull);
      });
    }

    check('dialog fades during entrance and exit', (tester) async {
      final controller = DDialogController<void>();
      addTearDown(controller.dispose);
      await _host(
        tester,
        Center(
          child: DDialog<void>(
            controller: controller,
            transitionDuration: const Duration(seconds: 1),
            reverseTransitionDuration: const Duration(seconds: 1),
            trigger: DDialogTrigger(
              builder: (_, open) =>
                  DButton(onPressed: open, label: const Text('Open')),
            ),
            content: const DDialogContent(children: [Text('Dialog content')]),
          ),
        ),
        theme,
      );
      controller.open();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final surface = find.byType(DDialogContent);
      _expectFading(tester, surface);
      await tester.pumpAndSettle();
      controller.close();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      _expectFading(tester, surface);
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
    });

    check('desktop emoji popup fades during entrance and exit', (tester) async {
      final store = EmojiPickerStore(persistence: _MemoryEmojiPersistence());
      Future<String?>? result;
      await _host(
        tester,
        Center(
          child: Builder(
            builder: (context) => DButton(
              label: const Text('Open emoji'),
              onPressed: () => result = showEmojiPicker(
                context: context,
                siteUrl: 'https://emoji.example',
                pickerContext: CoreEmojiUsageContexts.topic,
                store: store,
                loadCatalog: ({refresh = false}) async =>
                    SiteEmojiCatalog(groups: const []),
                loadSearchAliases: ({refresh = false}) async => const {},
              ),
            ),
          ),
        ),
        theme,
      );
      await tester.tap(find.text('Open emoji'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final surface = find.byKey(
        const ValueKey('emoji-picker-desktop-popover'),
      );
      _expectFading(tester, surface);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emoji-picker-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      _expectFading(tester, surface);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(surface, findsNothing);
    });

    check('tab switches fade and clean up snapshots', (tester) async {
      final tab = ValueNotifier(0);
      addTearDown(tab.dispose);
      await _host(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (_, value, _) => DHistoryTransition(
            history: value,
            tab: (id: value, index: value),
            tabOwner: 'audit',
            entry: value,
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: Center(
                child: DButton(
                  key: _control,
                  label: Text('Tab $value'),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
        theme,
      );
      tab.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.byType(RawImage), findsOneWidget);
      final snapshot = find.byType(RawImage);
      expect(_fractionalOpacityAbove(tester, snapshot), isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.text('Tab 1'), findsOneWidget);
    });

    check('covered topic chrome fades while preserving its state', (
      tester,
    ) async {
      final covered = ValueNotifier(false);
      addTearDown(covered.dispose);
      await _host(
        tester,
        Center(
          child: TopicChromeVisibility(
            covered: covered,
            child: TopicProgressButton(
              position: 2,
              total: 8,
              floating: true,
              onPressed: () {},
            ),
          ),
        ),
        theme,
      );
      final button = find.byType(TopicProgressButton);
      final state = tester.element(button);
      covered.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final animation = tester.widget<AnimatedOpacity>(
        find.ancestor(of: button, matching: find.byType(AnimatedOpacity)),
      );
      expect(animation.duration, const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      covered.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(_fractionalOpacityAbove(tester, button), isNotEmpty);

      expect(tester.element(button), same(state));
      await tester.pumpAndSettle();
    });

    check('disabled controls dim without changing targets', (tester) async {
      var presses = 0;
      var enabled = true;
      late StateSetter rebuild;
      await _host(
        tester,
        Center(
          child: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DButton(
                    key: _control,
                    label: const Text('Save'),
                    onPressed: enabled ? () => presses++ : null,
                  ),
                  DToggle(
                    pressed: true,
                    enabled: enabled,
                    variant: DToggleVariant.outline,
                    onPressedChanged: (_) => presses++,
                    child: const Text('Pinned'),
                  ),
                ],
              );
            },
          ),
        ),
        theme,
      );
      final button = find.byKey(_control);
      final toggle = find.byType(DToggle);
      final buttonBounds = tester.getRect(button);
      final toggleBounds = tester.getRect(toggle);
      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(_fractionalOpacityAbove(tester, find.text('Save')), contains(.6));
      expect(
        _fractionalOpacityAbove(tester, find.text('Pinned')),
        contains(.6),
      );
      expect(tester.getRect(button), buttonBounds);
      expect(tester.getRect(toggle), toggleBounds);
      await tester.tap(button);
      await tester.tap(toggle);
      expect(presses, 0);
    });

    check('desktop folding preserves the live document and its paint', (
      tester,
    ) async {
      final shell = await _panelShell();
      addTearDown(shell.dispose);
      final layout = DesktopPanelsLayout();
      addTearDown(layout.dispose);
      await _host(
        tester,
        ShellScope(
          controller: shell,
          child: TopicPresentationPreferences(
            child: DToaster(child: DesktopPanels(layout: layout)),
          ),
        ),
        theme,
      );
      final document = find.byType(MainContent).first;
      final element = tester.element(document);
      layout.toggleSplit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 32));
      final values = find
          .byType(MainContent)
          .evaluate()
          .map(
            (element) => _fractionalOpacityAbove(
              tester,
              find.byElementPredicate((e) => e == element),
            ),
          )
          .expand((values) => values);
      expect(values, isNotEmpty);
      await tester.pumpAndSettle();
      layout.toggleSplit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 32));
      final fades = find
          .byType(FadeTransition)
          .evaluate()
          .map((element) => (element.widget as FadeTransition).opacity.value)
          .where((value) => value > 0 && value < 1);
      expect(fades, isNotEmpty);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(MainContent).first), same(element));
    });
  }
}

Future<ShellController> _panelShell() async {
  const user = DiscourseUser(id: 1, username: 'auditor', canCreateTopic: true);
  const topic = Topic(id: 42, title: 'Audit topic', slug: 'audit-topic');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('panels.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      creatableFeedPaths: const {'/latest.json'},
      feeds: const {
        '/latest.json': [topic],
      },
      topics: {
        42: (
          detail: const TopicDetail(
            id: 42,
            title: 'Audit topic',
            stream: [42],
            postsCount: 1,
          ),
          posts: const [
            Post(
              id: 42,
              postNumber: 1,
              username: 'auditor',
              cooked: '<p>Audit content</p>',
            ),
          ],
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys['https://panels.example'] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.loadFeed('latest');
  shell.desktopTopicTabs = true;
  shell.openLinkInNewTab(
    '/t/audit-topic/42',
    title: 'Audit topic',
    panel: ForumPanel.secondary,
  );
  return shell;
}

final class _MemoryEmojiPersistence implements EmojiPickerPersistence {
  @override
  Future<String?> readPreferences({required String siteUrl}) async => null;
  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async => true;
}
