import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_category_path.dart';
import 'package:discourse_native/src/shell/topic_category_picker.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  Future<ShellController> pumpComposer(
    WidgetTester tester, {
    required TargetPlatform platform,
    List<TopicCategory> categories = const [
      TopicCategory(id: 5, name: 'Support', color: '0088CC', permission: 1),
    ],
    Map<String, List<TopicCategory>> categorySearches = const {
      '': [
        TopicCategory(id: 5, name: 'Support', color: '0088CC', permission: 1),
      ],
    },
  }) async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': <Topic>[]},
        creatableFeedPaths: const {'/latest.json'},
        categoryList: categories,
        categorySearches: categorySearches,
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
        topicTagSearches: const {
          '': TopicTagSearch(
            tags: [
              TopicTag(id: 7, name: 'design'),
              TopicTag(id: 8, name: 'mobile'),
            ],
          ),
        },
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    // Real async: the composer opens off several awaited reads, which the
    // test's fake clock would never let finish.
    await tester.runAsync(() async {
      await shell.load();
      await pumpEventQueue();
      await shell.openNewTopic();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: ComposerPanel(composer: shell.visibleComposer!),
          ),
        ),
      ),
    );
    // Never pumpAndSettle here: the composer's caret keeps blinking.
    await tester.pump();
    return shell;
  }

  Future<void> open(WidgetTester tester, Key actionKey) async {
    await tester.tap(find.byKey(actionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('shows compact taxonomy controls beneath the title', (
    tester,
  ) async {
    final shell = await pumpComposer(tester, platform: TargetPlatform.macOS);

    expect(find.text('Choose a category'), findsOneWidget);
    expect(find.text('Add tags'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Tags'), findsNothing);
    final title = find.widgetWithText(TextField, 'Give your topic a title');
    final category = tester.getRect(
      find.byKey(const ValueKey('composer-category-action')),
    );
    final tags = tester.getRect(find.byKey(const ValueKey('composer-add-tag')));
    expect(category.top, greaterThan(tester.getRect(title).bottom));
    expect(tags.center.dy, category.center.dy);
    expect(tags.left, greaterThan(category.right));
    expect(
      tester.getSize(find.byKey(const ValueKey('composer-category-color'))),
      const Size.square(9),
    );

    shell.visibleComposer!
      ..setCategory(5)
      ..setTags(const [TopicTag(name: 'design'), TopicTag(name: 'mobile')]);
    await tester.pump();

    expect(shell.visibleComposer!.categoryId, 5);
    expect(find.text('Support'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-tags')),
        matching: find.text('design, mobile'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('composer-add-tag')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('long taxonomy values wrap into reachable controls at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const category = TopicCategory(
      id: 5,
      name: 'Discourse Native App Development and Support',
      color: '0088CC',
      permission: 1,
    );
    final shell = await pumpComposer(
      tester,
      platform: TargetPlatform.iOS,
      categories: const [category],
    );
    shell.visibleComposer!
      ..setCategory(category.id)
      ..setTags(const [
        TopicTag(name: 'user-interface-improvements'),
        TopicTag(name: 'mobile-accessibility'),
      ]);
    await tester.pump();

    final categoryBounds = tester.getRect(
      find.byKey(const ValueKey('composer-category-action')),
    );
    final tagsBounds = tester.getRect(
      find.byKey(const ValueKey('composer-add-tag')),
    );
    expect(tagsBounds.top, greaterThan(categoryBounds.bottom));
    expect(categoryBounds.right, lessThanOrEqualTo(304));
    expect(tagsBounds.right, lessThanOrEqualTo(304));
    expect(categoryBounds.height, greaterThanOrEqualTo(44));
    expect(tagsBounds.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);

    await open(tester, const ValueKey('composer-add-tag'));
    expect(find.byType(TopicTagPicker), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the category picker is the sidebar popover on desktop', (
    tester,
  ) async {
    final shell = await pumpComposer(tester, platform: TargetPlatform.macOS);

    await open(tester, const ValueKey('composer-category-action'));

    expect(
      find.byKey(const ValueKey('topic-category-picker-popover')),
      findsOneWidget,
    );
    expect(find.byType(TopicCategoryPicker), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byKey(const ValueKey('topic-category-option-5')));
    await tester.pump();
    expect(shell.visibleComposer!.categoryId, 5);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the category value and picker include a subcategory parent', (
    tester,
  ) async {
    const parent = TopicCategory(
      id: 5,
      name: 'Support',
      color: '0088CC',
      permission: 1,
    );
    const child = TopicCategory(
      id: 6,
      name: 'Bugs',
      color: 'FF6600',
      parentCategoryId: 5,
      permission: 1,
    );
    final shell = await pumpComposer(
      tester,
      platform: TargetPlatform.macOS,
      categories: const [parent, child],
      categorySearches: const {
        '': [parent, child],
      },
    );
    final categoryPath = topicCategoryPathLabel(child, parent: parent);

    shell.visibleComposer!.setCategory(child.id);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-category')),
        matching: find.text(categoryPath),
      ),
      findsOneWidget,
    );

    await open(tester, const ValueKey('composer-category-action'));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-category-option-6')),
        matching: find.text(categoryPath),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the tag picker is the sidebar popover on desktop', (
    tester,
  ) async {
    final shell = await pumpComposer(tester, platform: TargetPlatform.macOS);

    await open(tester, const ValueKey('composer-add-tag'));

    expect(
      find.byKey(const ValueKey('topic-tag-picker-popover')),
      findsOneWidget,
    );
    expect(find.byType(TopicTagPicker), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey(('topic-tag-picker-option', 'design'))),
    );
    await tester.pump();
    expect(shell.visibleComposer!.tags, const [
      TopicTag(id: 7, name: 'design'),
    ]);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the composer keeps multiple tag removals when dismissed', (
    tester,
  ) async {
    final shell = await pumpComposer(tester, platform: TargetPlatform.macOS);
    const support = TopicTag(id: 9, name: 'support');
    shell.visibleComposer!.setTags(const [
      TopicTag(id: 7, name: 'design'),
      TopicTag(id: 8, name: 'mobile'),
      support,
    ]);
    await tester.pump();

    await open(tester, const ValueKey('composer-add-tag'));
    for (final name in ['design', 'mobile']) {
      await tester.tap(find.byKey(ValueKey(('topic-tag-picker-option', name))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TopicTagPicker), findsOneWidget);
    }

    await tester.tapAt(const Offset(790, 10));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(TopicTagPicker), findsNothing);
    expect(shell.visibleComposer!.tags, const [support]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-tags')),
        matching: find.text('support'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the category picker stays a sheet on touch', (tester) async {
    await pumpComposer(tester, platform: TargetPlatform.iOS);

    await open(tester, const ValueKey('composer-category-action'));

    expect(find.byType(TopicCategoryPicker), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the tag picker stays a sheet on touch', (tester) async {
    await pumpComposer(tester, platform: TargetPlatform.iOS);

    await open(tester, const ValueKey('composer-add-tag'));

    expect(find.byType(TopicTagPicker), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
