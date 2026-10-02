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
        expect(titleBar.height, 53);
        expect(field.height, 35.5);
        expect(field.top - titleBar.top, 8.75);
        expect(titleBar.bottom - field.bottom, 8.75);
        for (final panel in panels.evaluate()) {
          expect(tester.getRect(find.byWidget(panel.widget)).top, 59);
        }
        if (find.byType(InstanceSidebar).evaluate().isNotEmpty) {
          expect(tester.getRect(find.byType(InstanceSidebar)).top, 59);
        }
        await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(InstanceSidebar), findsNothing);
        for (final panel in panels.evaluate()) {
          expect(tester.getRect(find.byWidget(panel.widget)).top, 59);
        }
        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(DInputGroup)), field);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(DInputGroup)), field);
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
        expect(field.top - titleBar.top, closeTo(8.75, .01));
        expect(titleBar.bottom - field.bottom, closeTo(8.75, .01));
        expect(panel.top - field.bottom, closeTo(14.75, .01));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
