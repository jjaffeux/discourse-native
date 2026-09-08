import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  for (final loaded in [false, true]) {
    testWidgets(
      'the bottom-left rail opens the styleguide ${loaded ? 'without any sites' : 'before loading'} and restores its workspace',
      (tester) async {
        final controller = ShellController(
          instanceStore: FakeInstanceStore(),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
          initialRootMode: ShellRootMode.forum,
          appSettingsStore: AppSettingsStore(
            persistence: MemoryAppSettingsPersistence(),
          ),
        );
        addTearDown(controller.dispose);
        if (loaded) await controller.load();
        final semantics = tester.ensureSemantics();

        try {
          tester.view.physicalSize = const Size(390, 750);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            ShellScope(
              controller: controller,
              child: MaterialApp(
                theme: AppTheme.light,
                home: const Scaffold(
                  body: Row(
                    children: [
                      SizedBox(width: 72, child: InstanceRail()),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'Workspace draft',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.enterText(find.byType(TextField), 'Keep this draft');
          final launch = find.byKey(const ValueKey('styleguide-rail-button'));
          expect(
            find.bySemanticsLabel('Open component styleguide'),
            findsOneWidget,
          );
          expect(tester.getSize(launch).shortestSide, greaterThanOrEqualTo(44));
          expect(tester.getCenter(launch).dx, lessThan(72));
          expect(tester.getCenter(launch).dy, greaterThan(600));
          await tester.tap(launch);
          await tester.pumpAndSettle();
          expect(find.byType(ComponentStyleguidePage), findsOneWidget);
          expect(controller.rootMode, ShellRootMode.forum);

          await tester.tap(find.byKey(const ValueKey('styleguide-close')));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.byType(ComponentStyleguidePage), findsNothing);
          expect(find.text('Keep this draft'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
