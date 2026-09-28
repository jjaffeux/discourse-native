import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _captureKey = ValueKey('mobile-sheet-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'topic composer docks inside content without covering navigation',
    (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';
      final controller = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.linux),
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await controller.openNewTopicFromSidebar();
      await tester.pumpAndSettle();

      final panel = find.byType(ComposerPanel);
      expect(panel, findsOneWidget);
      final sidebarRect = tester.getRect(find.byType(InstanceSidebar));
      final railRect = tester.getRect(find.byType(InstanceRail));

      final docked = tester.getRect(panel);
      expect(docked.overlaps(sidebarRect), isFalse);
      expect(docked.overlaps(railRect), isFalse);
      expect(find.byKey(const ValueKey('composer-drag-handle')), findsNothing);
      final composer = controller.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: 'Selected topic text',
        selection: TextSelection(baseOffset: 0, extentOffset: 8),
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'full mobile sheet extends behind the keyboard in $brightness',
      (tester) async {
        const user = DiscourseUser(
          id: 7,
          username: 'sam',
          canCreateTopic: true,
        );
        final controller = ShellController(
          mobileNavigationEnabled: true,
          forumTabsEnabled: false,
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(
            user: user,
            feeds: const {'/latest.json': []},
            creatableFeedPaths: const {'/latest.json'},
          ),
          authenticator: FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        tester.view.physicalSize =
            const Size(390, 844) * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.viewInsets = FakeViewPadding(
          bottom: 336 * tester.view.devicePixelRatio,
        );
        tester.view.padding = FakeViewPadding(
          top: 59 * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.view.resetPadding);
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.forBrightness(
                brightness,
              ).copyWith(platform: TargetPlatform.iOS),
              home: const RepaintBoundary(
                key: _captureKey,
                child: AdaptiveShell(),
              ),
            ),
          ),
        );
        await controller.openNewTopicFromSidebar();
        await tester.pumpAndSettle();
        expect(find.byType(ComposerPanel), findsOneWidget);
        expect(
          tester
              .widget<DCard>(find.byKey(const ValueKey('composer-toolbar-bar')))
              .variant,
          DCardVariant.capsule,
        );
        final panelContext = tester.element(find.byType(ComposerPanel));
        final background = Theme.of(panelContext).shell.content;
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          background,
        );
        final footer = tester.widget<Container>(
          find.byKey(const ValueKey('composer-footer')),
        );
        expect((footer.decoration! as BoxDecoration).gradient, isNull);
        final topBlur = find.byKey(const ValueKey('composer-header-blur'));
        final bottomBlur = find.byKey(const ValueKey('composer-footer-blur'));
        expect(
          tester.widget<DGradientBlur>(topBlur).edge,
          DGradientBlurEdge.top,
        );
        expect(
          tester.widget<DGradientBlur>(bottomBlur).edge,
          DGradientBlurEdge.bottom,
        );
        expect(
          tester.getRect(bottomBlur).top,
          closeTo(
            tester
                .getCenter(
                  find.byKey(const ValueKey('composer-category-action')),
                )
                .dy,
            .01,
          ),
        );
        expect(tester.getRect(bottomBlur).bottom, 844 - 336);
        expect(
          tester
              .widget<CustomScrollView>(
                find.byKey(const ValueKey('composer-mobile-scroll')),
              )
              .clipBehavior,
          Clip.none,
        );

        expect(tester.getRect(find.byType(ComposerPanel)).bottom, 844);
        expect(
          tester.getRect(find.byType(ComposerPanel)).top,
          59 + DSpacing.sm,
        );
        final sheet = tester.widget<DSheetContent>(
          find.byKey(const ValueKey('composer-mobile-sheet')),
        );
        expect(sheet.extendBehindKeyboard, isTrue);
        final backgroundToken = DTokens.of(panelContext).background;
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is ModalBarrier &&
                widget.color == backgroundToken.withValues(alpha: 1),
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Create topic').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Composer options'), findsNothing);
        expect(find.text('Dock side'), findsNothing);

        final composer = controller.visibleComposer!;
        composer.focus.unfocus();
        composer.text.value = TextEditingValue(
          text: List.generate(
            60,
            (i) => 'Line $i ${'word ' * (i % 5 + 1)}',
          ).join('\n'),
          selection: const TextSelection.collapsed(offset: 0),
        );
        await tester.pumpAndSettle();
        final before = await _pixelsUnderKeyboard(tester);
        final viewport = find.byKey(const ValueKey('composer-mobile-scroll'));
        final scroll = tester.widget<CustomScrollView>(viewport).controller!;
        final footerBefore = tester.getRect(
          find.byKey(const ValueKey('composer-footer')),
        );
        await tester.drag(viewport, const Offset(0, -137));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(50));
        final after = await _pixelsUnderKeyboard(tester);
        expect(
          [
            for (var i = 0; i < before.length; i++)
              if (before[i] != after[i]) i,
          ].length,
          greaterThan(100),
          reason: 'Scrolling the sheet must repaint text behind the keyboard.',
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('composer-footer'))),
          footerBefore,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('composer-mobile-sheet')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<List<int>> _pixelsUnderKeyboard(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (var y = 528; y < 588; y++)
          for (var x = 16; x < 374; x++)
            data.getUint32((y * image.width + x) * 4),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}
