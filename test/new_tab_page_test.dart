import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shell_test_harness.dart';

void main() {
  testWidgets('panel guide keeps its close action at the top right', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(560, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: NewTabPage(onBrowseTopics: () {})),
      ),
    );
    await tester.pumpAndSettle();

    final dismiss = tester.getRect(
      find.byKey(const ValueKey('dismiss-panel-tutorial')),
    );
    final title = tester.getRect(find.text('Work with two panels'));
    expect(dismiss.top, lessThan(title.bottom));
    expect(dismiss.right, greaterThan(title.right - 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel tutorial appears on new tabs until dismissed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var opened = 0;

    Widget page(Key key) => MaterialApp(
      home: Scaffold(
        body: NewTabPage(key: key, onBrowseTopics: () => opened++),
      ),
    );

    await tester.pumpWidget(page(const ValueKey('first-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Work with two panels'), findsOneWidget);
    expect(find.text('Opens a new tab in main panel'), findsOneWidget);
    expect(find.text('Open in secondary panel'), findsOneWidget);
    expect(find.text('Open in a new tab in secondary panel'), findsOneWidget);
    expect(find.byType(DSkeleton), findsNWidgets(6));
    expect(find.text('This page'), findsNothing);
    expect(find.text('Opened link'), findsNothing);
    expect(find.text("Don't show again"), findsNothing);
    expect(find.text('Got it'), findsNothing);
    expect(find.text('Read side by side'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dismiss-panel-tutorial')));
    await tester.pumpAndSettle();
    expect(find.text('Work with two panels'), findsNothing);

    await tester.pumpWidget(page(const ValueKey('next-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Work with two panels'), findsNothing);
    await tester.tap(find.text('Browse latest topics'));
    expect(opened, 1);
  });

  testWidgets('empty recent sections are hidden', (tester) async {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    await pumpShell(tester, desktop);
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();

    expect(find.text('Everything else'), findsOneWidget);
    final groups = tester.widget<DButton>(
      find.widgetWithText(DButton, 'Groups'),
    );
    expect(groups.variant, DButtonVariant.secondary);
    expect(groups.backgroundColor, isNot(Colors.transparent));
    expect(groups.borderColor, Colors.transparent);
    expect(find.text('Latest topics'), findsNothing);
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Chat'), findsNothing);

    shell.openTopicUrl('/t/recent-topic/42');
    shell.pushContent(ContentRoute.newTab());
    await tester.pumpAndSettle();
    expect(find.text('Latest topics'), findsOneWidget);
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Chat'), findsNothing);
  });
}
