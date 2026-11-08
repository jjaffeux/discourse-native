import 'package:discourse_native/src/shell/component_styleguide_scope.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _button = ValueKey('styleguide-rail-button');

void main() {
  late ShellController controller;

  setUp(() {
    controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    );
    addTearDown(controller.dispose);
  });

  Future<void> pumpRail(WidgetTester tester, ComponentStyleguideOpener? open) =>
      tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: ComponentStyleguideScope(
            open: open,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: SizedBox(width: 72, child: InstanceRail()),
              ),
            ),
          ),
        ),
      );

  testWidgets('the composition root decides whether the rail offers it', (
    tester,
  ) async {
    await pumpRail(tester, null);
    expect(find.byKey(_button), findsNothing);

    BuildContext? opened;
    await pumpRail(tester, (context) async => opened = context);
    await tester.pump();
    expect(find.byKey(_button), findsOneWidget);

    await tester.tap(find.byKey(_button));
    await tester.pump();
    expect(opened, isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
