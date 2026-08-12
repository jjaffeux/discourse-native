import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('resizes once for every forum and restores after reload', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1200, 800));

    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth);
    await tester.drag(
      find.byKey(const ValueKey('sidebar-resize-handle')),
      // Flutter reserves the first 20 logical pixels for drag recognition.
      const Offset(140, 0),
    );
    await tester.pumpAndSettle();

    expect(_sidebarWidth(tester), 360);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      360,
    );

    controller.selectInstance(1);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 360);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpShell(tester, controller, const Size(1200, 800));
    expect(_sidebarWidth(tester), 360);
  });

  testWidgets('resize handle supports keyboard and semantics adjustment', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1000, 800));

    final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
    expect(tester.getSize(handle).width, 16);
    expect(
      find.descendant(of: handle, matching: find.byType(ColoredBox)),
      findsNothing,
    );
    final data = tester.getSemantics(handle).getSemanticsData();
    expect(data.label, 'Resize sidebar');
    expect(data.value, '240 pixels wide');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('sidebar-resize-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 256);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      256,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 240);
    semantics.dispose();
  });

  testWidgets('narrow windows constrain rather than replace the preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SidebarWidthStore.storageKey: AdaptiveShell.sidebarMaxWidth,
    });
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(768, 800));

    expect(_sidebarWidth(tester), 376);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      AdaptiveShell.sidebarMaxWidth,
    );

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarMaxWidth);
  });
}

double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byType(InstanceSidebar)).width;

Future<ShellController> _controller() async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org', title: 'Meta'),
      instance('discuss.example.com', title: 'Discuss'),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Future<void> _pumpShell(
  WidgetTester tester,
  ShellController controller,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(theme: AppTheme.light, home: const AdaptiveShell()),
    ),
  );
  await tester.pumpAndSettle();
}
