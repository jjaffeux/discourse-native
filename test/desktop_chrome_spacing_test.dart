import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_panel.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_test_harness.dart';

void main() {
  for (final (width, scale, narrowWidth, rowHeight) in [
    (1000.0, 1.0, 511.5, 49.0),
    (1200.0, 2.0, 711.5, 84.0),
  ]) {
    testWidgets(
      'desktop chrome follows sidebar resizing at ${scale * 100}% text',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpShell(tester, Size(width, 900));
        if (find.byType(InstanceSidebar).evaluate().isEmpty) {
          await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
          await tester.pumpAndSettle();
        }

        final titleBar = find.byType(ShellTitleBar);
        final originalHeader = tester.getRect(titleBar);
        expect(originalHeader.height, rowHeight);
        final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
        final delta = originalHeader.width - narrowWidth;
        await tester.drag(handle, Offset(delta, 0), touchSlopX: 0);
        await tester.pumpAndSettle();

        final stackedHeader = tester.getRect(titleBar);
        final search = tester.getRect(find.byKey(ForumSearch.inputKey));
        final account = tester.getRect(userMenu);
        expect(stackedHeader.width, closeTo(narrowWidth, .01));
        expect(stackedHeader.height, rowHeight * 2);
        expect(search.bottom, lessThanOrEqualTo(account.top));
        expect(account.bottom, lessThanOrEqualTo(stackedHeader.bottom));
        expect(
          tester.getRect(find.byType(ShellWorkspace)).top,
          greaterThanOrEqualTo(stackedHeader.bottom),
        );
        expect(tester.takeException(), isNull);

        await tester.drag(handle, Offset(-delta, 0), touchSlopX: 0);
        await tester.pumpAndSettle();
        final restoredHeader = tester.getRect(titleBar);
        expect(restoredHeader.width, closeTo(originalHeader.width, .01));
        expect(restoredHeader.height, rowHeight);
        expect(
          tester.getRect(find.byKey(ForumSearch.inputKey)).center.dy,
          closeTo(tester.getRect(userMenu).center.dy, .01),
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.desktop(),
    );
  }

  for (final size in [laptop, desktop]) {
    testWidgets(
      'desktop chrome matches mockup spacing at width ${size.width}',
      (tester) async {
        await pumpShell(tester, size);
        if (find
            .byKey(const ValueKey('desktop-navigation-trigger'))
            .evaluate()
            .isNotEmpty) {
          await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
          await tester.pumpAndSettle();
        }

        final titleBar = tester.getRect(find.byType(ShellTitleBar));
        final field = tester.getRect(find.byType(DInputGroup));
        final panels = find.descendant(
          of: find.byType(ShellWorkspace),
          matching: find.byType(WorkspacePanel),
        );
        expect(panels, findsWidgets);
        expect(titleBar.height, 49);
        expect(field.height, 36);
        expect(field.top - titleBar.top, 8.5);
        expect(titleBar.bottom - field.bottom, 4.5);
        for (final panel in panels.evaluate()) {
          expect(tester.getRect(find.byWidget(panel.widget)).top, 55);
        }
        if (find.byType(InstanceSidebar).evaluate().isNotEmpty) {
          expect(tester.getRect(find.byType(InstanceSidebar)).top, 0);
          expect(
            titleBar.left,
            greaterThan(tester.getRect(find.byType(InstanceSidebar)).left),
          );
        }
        await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(InstanceSidebar), findsNothing);
        for (final panel in panels.evaluate()) {
          expect(tester.getRect(find.byWidget(panel.widget)).top, 55);
        }
        final collapsedField = tester.getRect(find.byType(DInputGroup));
        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(DInputGroup)), collapsedField);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(DInputGroup)), collapsedField);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.desktop(),
    );
  }

  for (final scale in [1.5, 2.0]) {
    testWidgets(
      'desktop chrome retains search clearance at ${scale * 100}% text',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpShell(tester, desktop);

        final titleBar = tester.getRect(find.byType(ShellTitleBar));
        final field = tester.getRect(find.byType(DInputGroup));
        final panel = tester.getRect(
          find
              .descendant(
                of: find.byType(ShellWorkspace),
                matching: find.byType(WorkspacePanel),
              )
              .first,
        );
        // The 36px profile grows with text, and the row reserves its full
        // bounds plus the mockup's 8px top / 4px bottom padding.
        final avatarHeight = 36 * scale;
        expect(titleBar.height, avatarHeight + 12);
        expect(
          field.center.dy,
          closeTo(titleBar.top + 8 + avatarHeight / 2, .01),
        );
        expect(panel.top - titleBar.bottom, 6);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
