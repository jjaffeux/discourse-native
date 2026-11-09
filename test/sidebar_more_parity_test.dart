import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/finders.dart';
import 'support/shell_test_harness.dart';

final _more = sidebarMoreToggle;
final _less = find.descendant(of: _more, matching: find.text('Less'));
final _chevron = find.descendant(
  of: _more,
  matching: find.dIcon(DIcons.chevronDown),
);

Finder _button(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.widgetWithText(DSidebarMenuButton, label),
);

DSidebarMenuButton _row(WidgetTester tester, Finder finder) =>
    tester.widget<DSidebarMenuButton>(finder);

FocusNode _focusOf(WidgetTester tester, Finder row) => Focus.of(
  tester.element(find.descendant(of: row, matching: find.byType(DTouchTarget))),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final connected in [false, true]) {
    testWidgets('More gives way to flush rows, connected=$connected', (
      tester,
    ) async {
      const site = 'https://meta.discourse.org';
      const user = DiscourseUser(id: 7, username: 'reader');
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: connected ? user : null),
        ],
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        api: FakeDiscourseApi(user: connected ? user : null),
      );
      final semantics = tester.ensureSemantics();
      try {
        final moreRow = tester.getRect(_more);
        expect(sidebarMoreLabels(tester), isEmpty);
        expect(_less, findsNothing);
        expect(_chevron, findsNothing);
        expect(
          tester.getSemantics(_more),
          isSemantics(isButton: true, isExpanded: false),
        );
        final topics = tester.getRect(_button('Topics'));

        await tester.tap(_more);
        await tester.pumpAndSettle();

        expect(sidebarMoreLabels(tester), [
          'Categories',
          'Groups',
          'Badges',
          if (connected) 'Bookmarks',
          'Interface',
          if (connected) 'Preferences',
        ]);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(
          find.descendant(of: _more, matching: find.text('More')),
          findsNothing,
        );
        expect(tester.getRect(_button('Topics')), topics);
        final first = tester.getRect(_button('Categories'));
        expect(first.top, moreRow.top);
        for (final label in ['Categories', 'Groups', 'Badges', 'Interface']) {
          final row = tester.getRect(_button(label));
          expect(row.left, closeTo(topics.left, .01));
          expect(row.right, closeTo(topics.right, .01));
          expect(row.height, closeTo(topics.height, .01));
        }
        final foot = tester.getRect(_more);
        expect(foot.left, closeTo(topics.left, .01));
        expect(foot.height, closeTo(topics.height, .01));
        expect(
          foot.top,
          greaterThan(tester.getRect(_button('Interface')).bottom),
        );
        expect(tester.widget<Text>(_less).style?.fontSize, 12);
        expect(tester.widget<DIcon>(_chevron).size, 11);
        expect(
          tester
              .widget<RotatedBox>(
                find.descendant(of: _more, matching: find.byType(RotatedBox)),
              )
              .quarterTurns,
          2,
        );
        expect(
          tester.getSemantics(_more),
          isSemantics(isButton: true, isExpanded: true),
        );

        await tester.tap(_less);
        await tester.pumpAndSettle();

        expect(sidebarMoreLabels(tester), isEmpty);
        expect(_less, findsNothing);
        expect(_button('Groups'), findsNothing);
        expect(tester.getRect(_more), moreRow);
        expect(tester.getRect(_button('Topics')), topics);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('the row you are on stands above More once folded', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.tap(_button('Groups'));
    await tester.pumpAndSettle();
    expect(_row(tester, _button('Groups')).isActive, isTrue);
    expect(_row(tester, _button('Topics')).isActive, isFalse);
    expect(_row(tester, _more).isActive, isFalse);

    await tester.tap(_less);
    await tester.pumpAndSettle();

    expect(_row(tester, _button('Groups')).isActive, isTrue);
    expect(_row(tester, _more).isActive, isFalse);
    expect(_row(tester, _more).expanded, isFalse);
    expect(
      tester.getRect(_button('Groups')).bottom,
      lessThanOrEqualTo(tester.getRect(_more).top),
    );
    expect(
      tester.getRect(_button('Groups')).left,
      closeTo(tester.getRect(_more).left, .01),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on a phone More and Less use the drawer sizes', (tester) async {
    await pumpShell(tester, phone, revealMobileNavigation: true);
    final topics = tester.getRect(_button('Topics'));
    await tester.ensureVisible(_more);
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();

    await tester.ensureVisible(_more);
    await tester.pumpAndSettle();
    expect(_less, findsOneWidget);
    expect(tester.widget<Text>(_less).style?.fontSize, 14);
    expect(tester.widget<DIcon>(_chevron).size, 13);
    expect(tester.getRect(_more).left, closeTo(topics.left, .01));
    expect(tester.getRect(_button('Groups')).left, closeTo(topics.left, .01));

    await tester.tap(_less);
    await tester.pumpAndSettle();
    expect(_less, findsNothing);
    expect(_button('Groups'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('keyboard focus follows the row that replaces the one it held', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    _focusOf(tester, _more).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_less, findsOneWidget);
    expect(_focusOf(tester, _button('Categories')).hasPrimaryFocus, isTrue);

    for (final label in ['Groups', 'Badges', 'Interface']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        _focusOf(tester, _button(label)).hasPrimaryFocus,
        isTrue,
        reason: label,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, _more).hasPrimaryFocus, isTrue);
    expect(_row(tester, _more).expanded, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_less, findsNothing);
    expect(_focusOf(tester, _more).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, _button('Categories')).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final shell = ShellScope.read(tester.element(_more));
    expect(shell.currentContent?.id, 'all-categories');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a press does not hand focus to the next row', (tester) async {
    await pumpShell(tester, desktop);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, _button('Categories')).hasFocus, isFalse);
    await tester.tap(_less);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, _more).hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('folding from the keyboard keeps More in view', (tester) async {
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(id: 7, username: 'reader');
    final ids = [for (var id = 1; id <= 5; id++) id];
    final tags = [
      for (final id in ids)
        SidebarTag(id: id, name: 'tag-$id', slug: 'tag-$id'),
    ];
    await pumpShell(
      tester,
      desktop,
      instances: [instance('meta.discourse.org').copyWith(user: user)],
      authenticator: FakeAuthenticator()..keys[site] = 'key',
      api:
          FakeDiscourseApi(
              user: user,
              tagList: tags,
              categoryList: [
                for (final id in ids)
                  TopicCategory(
                    id: id,
                    name: 'Category $id',
                    slug: 'category-$id',
                    color: '7755AA',
                    position: id,
                  ),
              ],
            )
            ..userPreferences = UserPreferences(
              username: 'reader',
              canEdit: true,
              sidebarCategoryIds: ids,
              sidebarTags: tags,
            ),
    );
    await tester.runAsync(
      () => ShellScope.read(tester.element(_more)).loadCategories(site),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1440, 420);
    await tester.pumpAndSettle();
    // A row built past the viewport's edge is offstage to the default finder.
    final toggle = find.byKey(
      const ValueKey('sidebar-more-toggle'),
      skipOffstage: false,
    );
    final list = Scrollable.of(tester.element(_button('Topics')));
    final viewport = list.context.findRenderObject()! as RenderBox;
    final top = viewport.localToGlobal(Offset.zero).dy;
    list.position.jumpTo(
      list.position.pixels + tester.getTopLeft(toggle).dy - top,
    );
    await tester.pumpAndSettle();
    expect(list.position.pixels, greaterThan(0));
    _focusOf(tester, _more).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Less', skipOffstage: false), findsNothing);
    expect(tester.getTopLeft(toggle).dy, greaterThanOrEqualTo(top));
    expect(_focusOf(tester, toggle).hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('More rows are ordinary targets with visible hit bounds', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.tap(_button('Categories'));
    await tester.pumpAndSettle();
    final shell = ShellScope.read(tester.element(_more));
    expect(shell.currentContent?.id, 'all-categories');
    expect(_row(tester, _more).expanded, isTrue);
    final groups = tester.getRect(_button('Groups'));
    await tester.tapAt(Offset(groups.left - 5, groups.center.dy));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
    await tester.tapAt(Offset(groups.right + 2, groups.center.dy));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
    await tester.tap(_button('Topics'));
    await tester.pumpAndSettle();
    expect(_row(tester, _more).expanded, isTrue);
    expect(_row(tester, _more).isActive, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'direct routes reveal the rows, and each destination opens its page',
    (tester) async {
      const site = 'https://meta.discourse.org';
      const user = DiscourseUser(id: 7, username: 'reader');
      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        api: FakeDiscourseApi(user: user),
      );
      final shell = ShellScope.read(tester.element(_more));
      shell.pushContent(ContentRoute.group(GroupRoute.detail('staff')));
      await tester.pumpAndSettle();
      expect(_less, findsOneWidget);
      expect(_row(tester, _button('Groups')).isActive, isTrue);
      for (final (label, id) in [
        ('Categories', 'all-categories'),
        ('Badges', 'badges'),
        ('Bookmarks', 'user-bookmarks'),
        ('Interface', 'appearance'),
        ('Preferences', 'preferences'),
      ]) {
        await tester.tap(_button(label));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, id);
        expect(_row(tester, _button(label)).isActive, isTrue);
        expect(_less, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'expansion belongs to the forum and restores on an active More route',
    (tester) async {
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(tester.element(_more));
      await tester.tap(_more);
      await tester.pumpAndSettle();
      await tester.tap(_button('Groups'));
      await tester.pumpAndSettle();
      shell.selectInstance(1);
      await tester.pumpAndSettle();
      expect(tester.widget<DSidebarMenuButton>(_more).expanded, isFalse);
      shell.selectInstance(0);
      await tester.pumpAndSettle();
      expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
      expect(
        tester.widget<DSidebarMenuButton>(_button('Groups')).isActive,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('inline More grows without overflow at 200% text', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    final shell = ShellScope.read(tester.element(_more));
    await shell.appSettings.setTextScale(AppTextScale.percent200);
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(sidebarMoreLabels(tester), [
      'Categories',
      'Groups',
      'Badges',
      'Interface',
    ]);
    expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
