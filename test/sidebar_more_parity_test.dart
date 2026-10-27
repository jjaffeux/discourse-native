import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/finders.dart';
import 'support/shell_test_harness.dart';

final _more = find.byKey(const ValueKey('sidebar-more-toggle'));
final _content = find.byKey(const ValueKey('sidebar-more-content'));

Finder _button(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.widgetWithText(DSidebarMenuButton, label),
);

List<String> _labels(WidgetTester tester) => tester
    .widgetList<SidebarDestinationTile>(
      find.descendant(
        of: _content,
        matching: find.byType(SidebarDestinationTile),
      ),
    )
    .map((row) => row.destination.label)
    .toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final connected in [false, true]) {
    testWidgets('More shows inline destinations, connected=$connected', (
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
        expect(tester.widget<DSidebarMenuButton>(_more).expanded, isFalse);
        expect(_labels(tester), isEmpty);
        final before = tester.getRect(_button('Topics'));
        await tester.tap(_more);
        await tester.pumpAndSettle();
        expect(_labels(tester), [
          'Categories',
          'Groups',
          'Badges',
          if (connected) 'Bookmarks',
          'Interface',
          if (connected) 'Preferences',
        ]);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(tester.getRect(_button('Topics')), before);
        final moreRect = tester.getRect(_more);
        final groupsRect = tester.getRect(_button('Groups'));
        expect(groupsRect.left - moreRect.left, closeTo(20, .01));
        expect(groupsRect.right, closeTo(moreRect.right, .01));
        expect(groupsRect.top, greaterThan(moreRect.bottom));
        expect(
          tester.getSemantics(_more),
          isSemantics(isButton: true, isExpanded: true),
        );
        expect(
          find.descendant(of: _more, matching: find.dIcon(DIcons.chevronDown)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<RotatedBox>(
                find.descendant(of: _more, matching: find.byType(RotatedBox)),
              )
              .quarterTurns,
          2,
        );

        await tester.tap(_button('Groups'));
        await tester.pumpAndSettle();
        expect(tester.widget<DSidebarMenuButton>(_more).isActive, isTrue);
        expect(
          tester.widget<DSidebarMenuButton>(_button('Groups')).isActive,
          isTrue,
        );
        expect(
          tester.widget<DSidebarMenuButton>(_button('Topics')).isActive,
          isFalse,
        );
        expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
        expect(_button('Groups'), findsOneWidget);
        await tester.tap(_more);
        await tester.pumpAndSettle();
        expect(_button('Groups'), findsNothing);
        expect(tester.widget<DSidebarMenuButton>(_more).isActive, isTrue);
        expect(tester.widget<DSidebarMenuButton>(_more).expanded, isFalse);
        expect(
          tester
              .widget<RotatedBox>(
                find.descendant(of: _more, matching: find.byType(RotatedBox)),
              )
              .quarterTurns,
          0,
        );
        expect(
          find.descendant(of: _more, matching: find.dIcon(DIcons.chevronDown)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('More uses keyboard activation and visible hit bounds', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_button('Groups'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_button('Groups'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final shell = ShellScope.read(tester.element(_more));
    expect(shell.currentContent?.id, 'all-categories');
    expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
    final groups = tester.getRect(_button('Groups'));
    await tester.tapAt(Offset(groups.left - 5, groups.center.dy));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
    await tester.tapAt(Offset(groups.right + 2, groups.center.dy));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
    await tester.tap(_button('Topics'));
    await tester.pumpAndSettle();
    expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
    expect(tester.widget<DSidebarMenuButton>(_more).isActive, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'direct routes reveal More, and each destination opens its page',
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
      expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
      expect(
        tester.widget<DSidebarMenuButton>(_button('Groups')).isActive,
        isTrue,
      );
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
        expect(
          tester.widget<DSidebarMenuButton>(_button(label)).isActive,
          isTrue,
        );
        expect(tester.widget<DSidebarMenuButton>(_more).isActive, isTrue);
        expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
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
    expect(_labels(tester), ['Categories', 'Groups', 'Badges', 'Interface']);
    expect(tester.widget<DSidebarMenuButton>(_more).expanded, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
