import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/shell/topic_list_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_filter_parity_test.dart' as fixture;
import 'support/shell_test_harness.dart' show desktop, phone;

Finder get _list => find.byType(DCommandList<String>);
Finder _choice(String text) =>
    find.descendant(of: _list, matching: find.text(text));
String _query(WidgetTester tester) => tester
    .widget<DInput>(
      find.descendant(of: fixture.field, matching: find.byType(DInput)),
    )
    .controller!
    .text;

Future<void> _open(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  test('tag pill describes every supported scope', () {
    expect(topicListTagFilterLabel('', 'Tags'), 'Tags');
    expect(
      topicListTagFilterLabel('tag:"User experience"', 'Tags'),
      'User experience',
    );
    expect(topicListTagFilterLabel('-tag:Alpha+Beta', 'Tags'), '2 tags');
    expect(topicListTagFilterLabel('tag:Alpha,Beta', 'Tags'), '2 tags');
    expect(
      topicListTagFilterLabel('tag-group:"Design team"', 'Tags'),
      'group Design team',
    );
    expect(topicListTagFilterLabel('in:untagged', 'Tags'), 'no tags');
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('category levels and live tags on $platform flat', (
      tester,
    ) async {
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      final data = await fixture.fixture(
        tester,
        size: platform == TargetPlatform.macOS ? desktop : phone,
        filterOptions: fixture.filterMenuOptions,
      );
      await data.shell.forumSettings.setShared(
        const SharedAppearance(
          font: ForumFont.openSans,
          interfaceFont: ForumFont.openSans,
        ),
      );
      await data.shell.forumSettings.setThemeMode(
        fixture.site,
        platform == TargetPlatform.iOS ? AppThemeMode.dark : AppThemeMode.light,
      );
      await data.shell.applyTopicListFilterQuery(
        'status:open category:1 tag:Alpha',
      );
      await tester.pumpAndSettle();
      await _open(tester, 'topic-list-subcategory-filter-1');
      expect(_query(tester), isEmpty);
      expect(
        fixture.textField(tester).focusNode!.hasFocus,
        platform == TargetPlatform.macOS,
      );
      expect(_choice('Design'), findsOneWidget);
      expect(_choice('Support'), findsNothing);
      expect(find.text('Status: open'), findsNothing);
      expect(find.text('Tags: Alpha'), findsNothing);
      expect(find.widgetWithText(DButton, 'Done'), findsNothing);
      await fixture.capture(tester, 'taxonomy-category-$platform-flat');
      await tester.tap(_choice('Design'));
      await tester.pumpAndSettle();
      expect(data.shell.topicListContent!.categoryId, 2);
      expect(data.shell.topicListContent!.topicFilterQuery, 'status:open');
      expect(data.shell.topicListContent!.tagNames, ['Alpha']);
      expect(_list, findsNothing);

      await _open(tester, 'topic-list-category-filter');
      expect(_choice('Support'), findsOneWidget);
      expect(_choice('Design'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      if (platform == TargetPlatform.iOS) {
        await tester.tapAt(const Offset(8, 20));
      }
      await tester.pumpAndSettle();
      await _open(tester, 'topic-list-tag-filter');
      expect(_query(tester), isEmpty);
      expect(find.text('Category: Design'), findsNothing);
      await fixture.capture(tester, 'taxonomy-tags-$platform-flat');
      // Removing the last tag publishes an empty scope without discarding
      // the category or status, and the same menu stays available.
      await tester.tap(
        find.byKey(const ValueKey('topic-filter-token-remove-0')),
      );
      await tester.pumpAndSettle();
      expect(data.shell.topicListContent!.tagNames, isEmpty);
      expect(_list, findsOneWidget);
      await tester.tap(_choice('Alpha'));
      await tester.pumpAndSettle();
      expect(data.shell.topicListContent!.tagNames, ['Alpha']);
      expect(_list, findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(
        data.shell.topicListContent!.topicFilterQuery,
        contains('-tag:Alpha'),
      );
      expect(
        data.shell.topicListContent!.topicFilterQuery,
        contains('status:open'),
      );
      await tester.tap(find.byKey(const ValueKey('topic-filter-done-tags')));
      await tester.pumpAndSettle();
      expect(_list, findsNothing);
      expect(tester.takeException(), isNull);
      debugDisableShadows = true;
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('exact category is explicit and does not carry into a child', (
    tester,
  ) async {
    final data = await fixture.fixture(
      tester,
      filterOptions: fixture.filterMenuOptions,
    );
    data.shell.selectTopicListCategory(fixture.parent);
    await tester.pumpAndSettle();
    await _open(tester, 'topic-list-subcategory-filter-1');
    await tester.tap(_choice('Product only, not its subcategories'));
    await tester.pumpAndSettle();
    expect(find.text('No subcategories'), findsOneWidget);
    expect(data.shell.topicListContent!.topicFilterQuery, '=category:1');
    await _open(tester, 'topic-list-subcategory-filter-1');
    await tester.tap(_choice('Design'));
    await tester.pumpAndSettle();
    expect(data.shell.topicListContent!.categoryId, 2);
    expect(data.shell.topicListContent!.topicFilterQuery, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('scoped search keeps its key through Escape and Backspace', (
    tester,
  ) async {
    final data = await fixture.fixture(
      tester,
      filterOptions: fixture.filterMenuOptions,
    );
    await data.shell.applyTopicListFilterQuery('tag:Alpha+Beta category:1');
    await tester.pumpAndSettle();
    expect(find.text('2 tags'), findsOneWidget);
    await _open(tester, 'topic-list-tag-filter');
    await tester.enterText(fixture.field, 'nothing');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_query(tester), isEmpty);
    expect(_list, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(data.shell.topicListContent!.tagNames, ['Alpha']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_list, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a shortened category path hands its open menu to the root', (
    tester,
  ) async {
    final data = await fixture.fixture(
      tester,
      filterOptions: fixture.filterMenuOptions,
    );
    data.shell.selectTopicListCategory(fixture.parent);
    await tester.pumpAndSettle();
    await _open(tester, 'topic-list-subcategory-filter-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(data.shell.topicListContent!.categoryId, isNull);
    expect(_list, findsOneWidget);
    expect(_choice('Support'), findsOneWidget);
    expect(_choice('Design'), findsNothing);
    await tester.tap(_choice('Support'));
    await tester.pumpAndSettle();
    expect(data.shell.topicListContent!.categoryId, 4);
    expect(_list, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('scoped tag searches accept spaces without exposing syntax', (
    tester,
  ) async {
    final data = await fixture.fixture(
      tester,
      knownTags: const [
        SidebarTag(id: 12, name: 'User experience', slug: 'ux'),
      ],
      filterOptions: fixture.filterMenuOptions,
    );
    await _open(tester, 'topic-list-tag-filter');
    await tester.enterText(fixture.field, 'User experience');
    await tester.pumpAndSettle();
    expect(fixture.textField(tester).controller!.text, 'User experience');
    await tester.tap(_choice('User experience'));
    await tester.pumpAndSettle();
    expect(data.shell.topicListContent!.tagNames, ['User experience']);
    expect(_list, findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('live tag modes keep usage order and one selection mark', (
    tester,
  ) async {
    final data = await fixture.fixture(
      tester,
      filterOptions: fixture.filterMenuOptions,
    );
    await _open(tester, 'topic-list-tag-filter');
    final groups = tester
        .widget<DCommandList<String>>(_list)
        .children
        .whereType<DCommandGroup<String>>();
    expect(
      groups
          .expand((group) => group.items)
          .where((item) => item.value.startsWith('tag:'))
          .map((item) => item.value),
      ['tag:Beta', 'tag:Alpha'],
    );
    for (final tag in ['Beta', 'Alpha']) {
      await tester.tap(_choice(tag));
      await tester.pumpAndSettle();
    }
    for (final (label, clause) in [
      ('All', 'tag:Beta+Alpha'),
      ('None', '-tag:Beta,Alpha'),
      ('Not all', '-tag:Beta+Alpha'),
      ('Any', 'tag:Beta,Alpha'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      final serialized = data.shell.topicListFilterEditorQuery(
        data.shell.topicListContent!,
      );
      final tagClause = RegExp(r'(-?tag:)([^ ]+)').firstMatch(serialized)!;
      expect(tagClause[1], clause.startsWith('-') ? '-tag:' : 'tag:');
      expect(tagClause[2]!.contains('+'), clause.contains('+'));
      expect(
        tagClause[2]!.split(RegExp('[,+]')),
        unorderedEquals(['Beta', 'Alpha']),
      );
      expect(find.text('2 tags'), findsOneWidget);
      expect(_list, findsOneWidget);
      expect(
        tester
            .widgetList<DCheckbox>(find.byType(DCheckbox))
            .where((checkbox) => checkbox.value == true),
        hasLength(2),
      );
      for (final checkbox in find.byType(DCheckbox).evaluate()) {
        expect(
          tester.getSize(find.byWidget(checkbox.widget)),
          const Size(14, 14),
        );
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'Backspace clears a special tag scope and preserves the category',
    (tester) async {
      final data = await fixture.fixture(
        tester,
        filterOptions: fixture.filterMenuOptions,
      );
      await data.shell.applyTopicListFilterQuery('in:untagged category:1');
      await tester.pumpAndSettle();
      expect(find.text('no tags'), findsOneWidget);
      await _open(tester, 'topic-list-tag-filter');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(data.shell.topicListContent!.topicFilterQuery, isEmpty);
      expect(data.shell.topicListContent!.categoryId, 1);
      expect(_list, findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'scoped menus remain reachable at 200 percent text on $platform',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final data = await fixture.fixture(
          tester,
          size: platform == TargetPlatform.macOS ? desktop : phone,
          filterOptions: fixture.filterMenuOptions,
        );
        await _open(tester, 'topic-list-category-filter');
        await fixture.capture(tester, 'taxonomy-large-category-$platform');
        await tester.tap(_choice('Product'));
        await tester.pumpAndSettle();
        expect(data.shell.topicListContent!.categoryId, 1);
        await _open(tester, 'topic-list-tag-filter');
        await fixture.capture(tester, 'taxonomy-large-tags-$platform');
        expect(
          tester.getRect(_list).width,
          lessThanOrEqualTo(
            platform == TargetPlatform.macOS ? desktop.width : phone.width,
          ),
        );
        final toggles = find.descendant(
          of: _list,
          matching: find.byType(DToggle),
        );
        final rects = [
          for (var i = 0; i < 4; i++) tester.getRect(toggles.at(i)),
        ];
        expect(rects.map((rect) => rect.top).toSet().length, greaterThan(1));
        final modes = tester.getRect(find.byType(DToggleGroup<String>));
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(modes.left));
          expect(rect.right, lessThanOrEqualTo(modes.right));
        }
        await tester.ensureVisible(_choice('Alpha'));
        await tester.tap(_choice('Alpha'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Not all'));
        await tester.tap(find.text('Not all'));
        await tester.pumpAndSettle();
        expect(
          data.shell.topicListContent!.topicFilterQuery,
          contains('-tag:Alpha'),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('topic-filter-done-tags')),
        );
        await tester.tap(find.byKey(const ValueKey('topic-filter-done-tags')));
        await tester.pumpAndSettle();
        expect(_list, findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
