import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
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

  testWidgets('rail toggle preserves sidebar width and content state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SidebarWidthStore.storageKey: 260.0,
    });
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1200, 800));
    final toggle = find.byKey(const ValueKey('rail-sidebar-toggle'));
    final sidebarWidth = tester.getSize(find.byType(InstanceSidebar)).width;
    final content = tester.element(find.byType(MainContent));
    // The main panel keeps its own width beside the secondary panel, so the
    // space the sidebar gives up is measured across the whole panel area.
    final panelsWidth = tester.getSize(find.byType(DesktopPanels)).width;
    expect(
      tester.getTopLeft(toggle).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('aggregate-rail-button')))
            .dy,
      ),
    );
    expect(tester.widget<DButton>(toggle).tooltip, 'Collapse sidebar');
    final expandedColor = tester.widget<DButton>(toggle).foregroundColor!;
    expect(
      tester.widget<DButton>(toggle).variant,
      DButtonVariant.transparentBackground,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(InstanceSidebar), findsNothing);
    expect(
      tester.getSize(find.byType(DesktopPanels)).width,
      greaterThan(panelsWidth),
    );
    expect(tester.element(find.byType(MainContent)), same(content));
    expect(tester.widget<DButton>(toggle).tooltip, 'Expand sidebar');
    expect(
      tester.widget<DButton>(toggle).foregroundColor!.a,
      lessThan(expandedColor.a),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(InstanceSidebar)).width, sidebarWidth);
    expect(tester.element(find.byType(MainContent)), same(content));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a sidebar closed from the rail stays closed past a forum gate', (
    tester,
  ) async {
    final controller = await _controller(
      store: FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
        instance(
          'private.example.com',
          title: 'Private',
        ).copyWith(loginRequired: true),
      ]),
    );
    await _pumpShell(tester, controller, const Size(1200, 800));
    final toggle = find.byKey(const ValueKey('rail-sidebar-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(InstanceSidebar), findsNothing);

    // The sign-in gate takes the whole forum shell's place while it is shown.
    controller.selectInstance(1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('private-forum-gate')), findsOneWidget);
    controller.selectInstance(0);
    await tester.pumpAndSettle();

    expect(find.byType(InstanceSidebar), findsNothing);
    expect(tester.widget<DButton>(toggle).tooltip, 'Expand sidebar');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(InstanceSidebar), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Home keeps the rail toggle visible until a forum is selected', (
    tester,
  ) async {
    final controller = await _controller();
    controller.selectAggregate();
    await _pumpShell(tester, controller, const Size(1200, 800));
    final toggle = find.byKey(const ValueKey('rail-sidebar-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<DButton>(toggle).onPressed, isNull);
    expect(
      tester.getTopLeft(toggle).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('aggregate-rail-button')))
            .dy,
      ),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('uses compact desktop navigation metrics', (tester) async {
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1200, 800));

    expect(tester.getSize(find.byType(InstanceRail)).width, 48);

    final aggregateButton = find.byKey(const ValueKey('aggregate-rail-button'));
    expect(tester.widget<DButton>(aggregateButton).size, DButtonSize.large);
    expect(
      tester.widget<DButton>(aggregateButton).variant,
      DButtonVariant.transparentBackground,
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
      DControlStyle.largeHeight,
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
        if (size.width < 1100) {
          await tester.tap(
            find.byKey(const ValueKey('desktop-navigation-trigger')),
          );
          await tester.pumpAndSettle();
        }

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
        expect(rowRect.height, greaterThan(DControlStyle.largeHeight));
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
    var actions = 0;
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
              onAction: () => actions++,
            ),
            SidebarSection(
              id: 'one-to-one',
              title: '1:1',
              destinations: const [],
              actionLabel: 'Add 1:1',
              onAction: () {},
            ),
          ],
        },
      ),
      authenticator: authenticator,
    );
    await controller.appSettings.setTextScale(AppTextScale.percent200);
    await _pumpShell(tester, controller, const Size(1200, 1200));

    final longTitle = find.text('Teach Lead Calls');
    final shortTitle = find.text('1:1');
    final longHeader = find
        .ancestor(of: longTitle, matching: find.byType(DSidebarMenuButton))
        .first;
    final shortHeader = find
        .ancestor(of: shortTitle, matching: find.byType(DSidebarMenuButton))
        .first;
    final longTitleRect = tester.getRect(longTitle);
    final shortTitleRect = tester.getRect(shortTitle);
    final longHeaderRect = tester.getRect(longHeader);
    final shortHeaderRect = tester.getRect(shortHeader);

    expect(longHeaderRect.height, greaterThan(shortHeaderRect.height));
    expect(longTitleRect.top, greaterThanOrEqualTo(longHeaderRect.top));
    expect(longTitleRect.bottom, lessThanOrEqualTo(longHeaderRect.bottom));
    expect(shortHeaderRect.top, longHeaderRect.bottom + 2);
    expect(
      longTitleRect.top - longHeaderRect.top,
      closeTo(shortTitleRect.top - shortHeaderRect.top, 0.25),
    );
    expect(
      longHeaderRect.bottom - longTitleRect.bottom,
      closeTo(shortHeaderRect.bottom - shortTitleRect.bottom, 0.25),
    );

    final actionRect = tester.getRect(find.byTooltip('Add lead call'));
    final chevronRect = tester.getRect(longHeader);
    expect(longTitleRect.right, lessThanOrEqualTo(actionRect.left));
    expect(
      actionRect.center.dy,
      inInclusiveRange(longHeaderRect.top, longHeaderRect.bottom),
    );
    expect(
      chevronRect.center.dy,
      inInclusiveRange(longHeaderRect.top, longHeaderRect.bottom),
    );

    await tester.tap(find.byTooltip('Add lead call'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(tester.widget<DSidebarMenuButton>(longHeader).expanded, isTrue);

    await tester.tap(longHeader);
    await tester.pumpAndSettle();
    expect(tester.widget<DSidebarMenuButton>(longHeader).expanded, isFalse);
    expect(actions, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('resizes once for every forum and restores after reload', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1200, 800));

    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth);
    await tester.drag(
      find.byKey(const ValueKey('sidebar-resize-handle')),
      // Every delivered delta counts, including updates before a frame.
      const Offset(140, 0),
    );
    await tester.pumpAndSettle();

    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 140);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      AdaptiveShell.sidebarWidth + 140,
    );

    controller.selectInstance(1);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 140);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpShell(tester, controller, const Size(1200, 800));
    expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 140);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'resize handle is its visible grip and adjusts by keyboard and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = await _controller();
      await _pumpShell(tester, controller, const Size(1200, 800));

      final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
      // The grip centred in the panel gap is the whole target; the rest of the
      // gap is not a resize strip.
      final grip = tester.getRect(
        find.descendant(
          of: handle,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                widget.constraints ==
                    const BoxConstraints.tightFor(width: 4, height: 24),
          ),
        ),
      );
      expect(tester.getRect(handle), grip);
      expect(tester.getSemantics(handle).rect.size, grip.size);
      final sidebarRight = tester
          .getTopRight(
            find.ancestor(
              of: find.byType(InstanceSidebar),
              matching: find.byType(ResizablePane),
            ),
          )
          .dx;
      expect(grip.center.dx, sidebarRight - workspacePanelGap / 2);
      for (final outside in [
        grip.centerLeft - const Offset(1, 0),
        grip.centerRight + const Offset(1, 0),
        grip.topCenter - const Offset(0, 1),
        grip.bottomCenter + const Offset(0, 1),
      ]) {
        await tester.dragFrom(
          outside,
          const Offset(40, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(
          _sidebarWidth(tester),
          AdaptiveShell.sidebarWidth,
          reason: 'Drag outside $grip from $outside',
        );
      }
      await tester.dragFrom(
        grip.topLeft + const Offset(1, 1),
        const Offset(40, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 40);
      await tester.dragFrom(
        grip.topLeft + const Offset(41, 1),
        const Offset(-40, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth);
      final divider = find.descendant(
        of: handle,
        matching: find.byType(ColoredBox),
      );
      expect(divider, findsOneWidget);
      expect(tester.getSize(divider).width, 0);
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
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('narrow navigation preserves the permanent sidebar preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SidebarWidthStore.storageKey: 640.0,
    });
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(768, 800));

    expect(find.byType(InstanceSidebar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('desktop-navigation-trigger')));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 288);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        SidebarWidthStore.storageKey,
      ),
      640.0,
    );

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 640.0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('viewport resizing preserves the rail until navigation changes', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpShell(tester, controller, const Size(1400, 800));
    final rail = tester.element(find.byType(InstanceRail));
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    for (final width in [1500.0, 1250.0, 1150.0]) {
      rebuilt.clear();
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(rebuilt, isNot(contains(rail)));
    }

    final toggle = find.byKey(const ValueKey('rail-sidebar-toggle'));
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(toggle).tooltip, 'Expand sidebar');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(toggle).tooltip, 'Collapse sidebar');

    controller.selectAggregate();
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(toggle).onPressed, isNull);
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

      expect(_sidebarWidth(tester), AdaptiveShell.sidebarWidth + 60);
      for (final isolated in [shell, rail, sidebar, content]) {
        expect(rebuilt, isNot(contains(isolated)));
      }
    } finally {
      await drag.up();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

double _sidebarWidth(WidgetTester tester) {
  final pane = find.ancestor(
    of: find.byType(InstanceSidebar),
    matching: find.byType(ResizablePane),
  );
  return tester
      .getSize(pane.evaluate().isEmpty ? find.byType(InstanceSidebar) : pane)
      .width;
}

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
