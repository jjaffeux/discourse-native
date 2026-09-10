import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
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
import 'package:flutter/rendering.dart' show RenderParagraph;
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

    expect(tester.getSize(find.byType(InstanceRail)).width, 48);

    final aggregateButton = find.byKey(const ValueKey('aggregate-rail-button'));
    expect(tester.getSize(aggregateButton), const Size.square(44));
    expect(
      tester.getSize(find.byKey(const ValueKey('aggregate-rail-visual'))),
      const Size.square(32),
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
      16,
    );

    final topics = find.descendant(
      of: find.byType(InstanceSidebar),
      matching: find.text('Topics'),
    );
    expect(topics, findsOneWidget);
    expect(DefaultTextStyle.of(tester.element(topics)).style.fontSize, 14);
    expect(
      tester
          .getSize(
            find
                .ancestor(of: topics, matching: find.byType(DSidebarMenuButton))
                .first,
          )
          .height,
      32,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final size in [const Size(390, 700), const Size(1200, 800)]) {
    testWidgets(
      'scaled sidebar labels and forum identity fit ${size.width}px layouts',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          SidebarWidthStore.storageKey: AdaptiveShell.sidebarMinWidth,
        });
        const address =
            'very-long-community-address.example.com/discussion/subfolder';
        final site = instance(
          address,
          title: 'A forum name that is much too long for the sidebar',
        );
        final controller = await _controller(store: FakeInstanceStore([site]));
        await controller.appSettings.setTextScale(AppTextScale.percent200);
        await _pumpShell(tester, controller, size);

        final topics = find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text('Topics'),
        );
        final row = find
            .ancestor(of: topics, matching: find.byType(DSidebarMenuButton))
            .first;
        final textRect = tester.getRect(topics);
        final rowRect = tester.getRect(row);

        expect(DefaultTextStyle.of(tester.element(topics)).style.fontSize, 14);
        expect(rowRect.height, greaterThan(size.width <= 640 ? 38.4 : 30));
        expect(textRect.top, greaterThanOrEqualTo(rowRect.top));
        expect(textRect.bottom, lessThanOrEqualTo(rowRect.bottom));

        final header = find.byKey(const ValueKey('forum-identity-header'));
        final name = find.descendant(
          of: header,
          matching: find.text(site.title),
        );
        final url = find.byKey(const ValueKey('forum-identity-url'));
        final headerRect = tester.getRect(header);
        final cardRect = tester.getRect(
          find.byKey(const ValueKey('forum-identity-button')),
        );
        expect(cardRect.left, rowRect.left);
        expect(cardRect.right, rowRect.right);
        expect(tester.widget<Text>(url).data, address);
        expect(
          tester.getRect(name).bottom,
          lessThanOrEqualTo(tester.getRect(url).top),
        );
        for (final label in [name, url]) {
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.maxLines, 1);
          expect(paragraph.overflow, TextOverflow.ellipsis);
          expect(paragraph.didExceedMaxLines, isTrue);
          final labelRect = tester.getRect(label);
          expect(labelRect.left, greaterThanOrEqualTo(headerRect.left));
          expect(labelRect.right, lessThanOrEqualTo(headerRect.right));
          expect(labelRect.bottom, lessThanOrEqualTo(headerRect.bottom));
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('scaled sidebar section titles reflow around their controls', (
    tester,
  ) async {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    final site = instance(
      'meta.discourse.org',
      title: 'Meta',
    ).copyWith(user: me);
    final authenticator = FakeAuthenticator()..keys[site.url] = 'api-key';
    final controller = await _controller(
      store: FakeInstanceStore([site]),
      api: FakeDiscourseApi(
        customSidebarSectionsBySite: {
          site.url: [
            SidebarSection(
              id: 'lead-calls',
              title: 'Teach Lead Calls',
              destinations: const [],
              actionLabel: 'Add lead call',
              onAction: () {},
            ),
            SidebarSection(
              id: 'utils',
              title: 'Utils',
              destinations: const [],
              actionLabel: 'Add utility',
              onAction: () {},
            ),
          ],
        },
      ),
      authenticator: authenticator,
    );
    await controller.appSettings.setTextScale(AppTextScale.percent200);
    await _pumpShell(tester, controller, const Size(1200, 1200));

    final longTitle = find.text('TEACH LEAD CALLS');
    final shortTitle = find.text('UTILS');
    final longHeader = find
        .ancestor(of: longTitle, matching: find.byType(DCollapsibleTrigger))
        .first;
    final shortHeader = find
        .ancestor(of: shortTitle, matching: find.byType(DCollapsibleTrigger))
        .first;
    final longTitleRect = tester.getRect(longTitle);
    final shortTitleRect = tester.getRect(shortTitle);
    final longHeaderRect = tester.getRect(longHeader);
    final shortHeaderRect = tester.getRect(shortHeader);

    expect(longHeaderRect.height, greaterThan(shortHeaderRect.height));
    expect(longTitleRect.top, greaterThanOrEqualTo(longHeaderRect.top));
    expect(longTitleRect.bottom, lessThanOrEqualTo(longHeaderRect.bottom));
    expect(shortHeaderRect.top, greaterThan(longHeaderRect.bottom));
    expect(
      longTitleRect.top - longHeaderRect.top,
      closeTo(shortTitleRect.top - shortHeaderRect.top, 0.25),
    );
    expect(
      longHeaderRect.bottom - longTitleRect.bottom,
      closeTo(shortHeaderRect.bottom - shortTitleRect.bottom, 0.25),
    );

    final actionRect = tester.getRect(find.byTooltip('Add lead call'));
    final chevronRect = tester.getRect(
      find.byTooltip('Collapse Teach Lead Calls'),
    );
    expect(longTitleRect.right, lessThanOrEqualTo(actionRect.left));
    expect(
      actionRect.center.dy,
      inInclusiveRange(longHeaderRect.top, longHeaderRect.bottom),
    );
    expect(
      chevronRect.center.dy,
      inInclusiveRange(longHeaderRect.top, longHeaderRect.bottom),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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

    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 120);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      AdaptiveShell.sidebarWidth + 120,
    );

    controller.selectInstance(1);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 120);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpShell(tester, controller, const Size(1200, 800));
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 120);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
    expect(data.value, '${AdaptiveShell.sidebarWidth.toInt()} pixels wide');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('sidebar-resize-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 16);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      AdaptiveShell.sidebarWidth + 16,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth);
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('narrow windows constrain rather than replace the preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SidebarWidthStore.storageKey: AdaptiveShell.sidebarMaxWidth,
    });
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(768, 800));

    expect(_sidebarWidth(tester), 400);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      AdaptiveShell.sidebarMaxWidth,
    );

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarMaxWidth);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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

      expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 40);
      for (final isolated in [shell, rail, sidebar, content]) {
        expect(rebuilt, isNot(contains(isolated)));
      }
    } finally {
      await drag.up();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byType(InstanceSidebar)).width;

Future<ShellController> _controller({
  FakeInstanceStore? store,
  FakeDiscourseApi? api,
  FakeAuthenticator? authenticator,
}) async {
  final controller = ShellController(
    instanceStore:
        store ??
        FakeInstanceStore([
          instance('meta.discourse.org', title: 'Meta'),
          instance('discuss.example.com', title: 'Discuss'),
        ]),
    api: api ?? FakeDiscourseApi(),
    authenticator: authenticator ?? FakeAuthenticator(),
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
