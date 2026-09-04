import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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

  testWidgets('uses compact desktop navigation metrics', (tester) async {
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1200, 800));

    expect(tester.getSize(find.byType(InstanceRail)).width, 56);

    final aggregateButton = find.byKey(const ValueKey('aggregate-rail-button'));
    expect(tester.getSize(aggregateButton), const Size.square(44));
    expect(
      tester.getSize(find.byKey(const ValueKey('aggregate-rail-visual'))),
      const Size.square(36),
    );
    expect(
      tester
          .widget<DIcon>(
            find.descendant(
              of: aggregateButton,
              matching: find.byWidgetPredicate(
                (widget) => widget is DIcon && widget.icon == DIcons.house,
              ),
            ),
          )
          .size,
      18,
    );

    final topics = find.descendant(
      of: find.byType(InstanceSidebar),
      matching: find.text('Topics'),
    );
    expect(topics, findsOneWidget);
    expect(
      tester.widget<Text>(topics).style?.fontSize,
      DiscourseTypography.fontDown1,
    );
    expect(
      tester
          .getSize(
            find.ancestor(of: topics, matching: find.byType(InkWell)).first,
          )
          .height,
      30,
    );
  });

  for (final size in [const Size(390, 700), const Size(1200, 800)]) {
    testWidgets(
      'scaled sidebar text remains inside expanded ${size.width}px rows',
      (tester) async {
        final controller = await _controller();
        await controller.appSettings.setTextScale(AppTextScale.percent200);
        await _pumpShell(tester, controller, size);

        final topics = find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text('Topics'),
        );
        final row = find
            .ancestor(of: topics, matching: find.byType(InkWell))
            .first;
        final textRect = tester.getRect(topics);
        final rowRect = tester.getRect(row);

        expect(rowRect.height, greaterThan(size.width <= 640 ? 38.4 : 30));
        expect(textRect.top, greaterThanOrEqualTo(rowRect.top));
        expect(textRect.bottom, lessThanOrEqualTo(rowRect.bottom));
      },
    );
  }

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
    final divider = find.descendant(
      of: handle,
      matching: find.byType(ColoredBox),
    );
    expect(divider, findsOneWidget);
    expect(tester.getSize(divider).width, 1);
    expect(
      tester.widget<ColoredBox>(divider).color,
      Theme.of(tester.element(divider)).shell.divider,
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

    expect(_sidebarWidth(tester), 392);
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

  testWidgets('live drag leaves the shell and pane content unrebuilt', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1200, 800));

    final shell = tester.element(find.byType(AdaptiveShell));
    final rail = tester.element(find.byType(InstanceRail));
    final sidebar = tester.element(find.byType(InstanceSidebar));
    final content = tester.element(find.byType(MainContent));
    final rebuilt = <Element>{};
    final previousRebuildCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previousRebuildCallback?.call(element, builtOnce);
    };
    addTearDown(() {
      debugOnRebuildDirtyWidget = previousRebuildCallback;
    });

    final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
    final drag = await tester.startGesture(tester.getCenter(handle));
    try {
      await drag.moveBy(const Offset(20, 0));
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(_sidebarWidth(tester), 280);
      for (final isolated in [shell, rail, sidebar, content]) {
        expect(rebuilt, isNot(contains(isolated)));
      }
    } finally {
      await drag.up();
    }
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
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => AppTextScaleRegion(
          controller: controller.appSettings,
          child: child!,
        ),
        home: const AdaptiveShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
