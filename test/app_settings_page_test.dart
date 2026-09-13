import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

void main() {
  testWidgets('the app settings form is centered and updates immediately', (
    tester,
  ) async {
    final persistence = MemoryAppSettingsPersistence();
    final controller = _controller(appSettingsPersistence: persistence);
    addTearDown(controller.dispose);
    await controller.appSettings.load();

    await _pumpPage(tester, controller, size: const Size(1100, 700));

    expect(find.byType(DDialogContent), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(DFieldGroup), findsOneWidget);
    expect(find.byType(DButtonGroup), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('app-settings-form'))).width,
      568,
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Content alignment'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Disable GIF animations'), findsOneWidget);
    expect(
      find.textContaining('reading lane is limited to 825 px'),
      findsNothing,
    );
    expect(find.textContaining('Save'), findsNothing);

    var segmented = tester.widget<DToggleGroup<ContentAlignment>>(
      find.byKey(const ValueKey('content-alignment-segmented-button')),
    );
    expect(segmented.values, [ContentAlignment.center]);

    await tester.tap(find.text('Left'));
    await tester.pump();

    expect(controller.appSettings.contentAlignment, ContentAlignment.left);
    expect(persistence.contentAlignment, 'left');
    segmented = tester.widget<DToggleGroup<ContentAlignment>>(
      find.byKey(const ValueKey('content-alignment-segmented-button')),
    );
    expect(segmented.values, [ContentAlignment.left]);

    await tester.tap(find.byKey(const ValueKey('text-size-increase')));
    await tester.pump();

    expect(controller.appSettings.textScale, AppTextScale.percent110);
    expect(persistence.textScale, AppTextScale.percent110.name);
    expect(find.text('110%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('text-size-reset')));
    await tester.pump();

    expect(controller.appSettings.textScale, AppTextScale.percent100);
    expect(persistence.textScale, AppTextScale.percent100.name);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('Disable GIF animations'));
    await tester.pump();

    expect(controller.appSettings.disableGifAnimations, isTrue);
    expect(persistence.disableGifAnimations, isTrue);
  });

  testWidgets('settings heading grows to fit 200% text without clipping', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller, scale: 2, size: const Size(800, 800));
    final title = tester.getRect(find.text('Settings'));
    final header = tester.getRect(
      find.byKey(const ValueKey('app-settings-header')),
    );
    expect(header.height, greaterThanOrEqualTo(title.height));
    expect(tester.getSize(find.text('100%')).height, closeTo(40, 0.001));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('app-settings-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSettingsModal), findsNothing);
  });

  testWidgets('the form and Close control expose useful semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller();
    addTearDown(controller.dispose);
    try {
      await controller.appSettings.load();
      await _pumpPage(tester, controller);

      expect(find.bySemanticsLabel('Close settings'), findsOneWidget);
      for (final (label, level) in [
        ('Settings', 1),
        ('Content alignment', 2),
        ('Text size', 2),
      ]) {
        expect(
          tester.getSemantics(find.text(label)).getSemanticsData().headingLevel,
          level,
        );
      }
      expect(
        find.bySemanticsLabel('Content alignment options'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Decrease text size'), findsOneWidget);
      expect(find.bySemanticsLabel('Increase text size'), findsOneWidget);
      expect(find.bySemanticsLabel('Current text size'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Disable GIF animations')),
        findsOneWidget,
      );
      for (final label in ['Left', 'Center', 'Right']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();

      expect(find.byType(AppSettingsModal), findsNothing);
      expect(controller.appSettingsModalOpen, isFalse);
      expect(controller.rootMode, ShellRootMode.forum);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Diagnostics is the bottom-most rail destination when present', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.load();
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
    );

    try {
      await _pumpRail(tester, controller, diagnostics: diagnostics);

      final settings = find.byKey(const ValueKey('settings-rail-button'));
      final diagnosticsButton = find.byKey(
        const ValueKey('diagnostics-rail-button'),
      );
      expect(settings, findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(
        find.descendant(of: settings, matching: find.dIcon(DIcons.gear)),
        findsOneWidget,
      );
      for (final key in [
        'styleguide-rail-button',
        'settings-rail-button',
        'diagnostics-rail-button',
      ]) {
        final control = find.byKey(ValueKey(key));
        final button = tester.widget<DButton>(control);
        expect(button.variant, DButtonVariant.ghost);
        expect(button.size, DButtonSize.large);
        expect(tester.getSize(control), const Size.square(48));
      }
      expect(
        tester.getRect(diagnosticsButton).top,
        greaterThan(tester.getRect(settings).bottom),
      );
      expect(
        tester.getRect(find.byType(InstanceRail)).bottom -
            tester.getRect(diagnosticsButton).bottom,
        6,
      );

      final data = tester.getSemantics(settings).getSemanticsData();
      expect(data.label, 'Settings');
      expect(data.flagsCollection.isButton, isTrue);

      await tester.tap(settings);
      await tester.pumpAndSettle();

      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.appSettingsModalOpen, isTrue);
      expect(find.byType(AppSettingsModal), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();
    } finally {
      await diagnostics.close();
      semantics.dispose();
    }
  });

  testWidgets('the gear remains available before sites have loaded', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await _pumpRail(tester, controller);

    expect(controller.loadStatus, InstanceLoadStatus.loading);
    expect(find.byKey(const ValueKey('settings-rail-button')), findsOneWidget);
  });

  testWidgets('Settings uses Home colors and responds to system appearance', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final siteTheme = StyleguideTheme.plum.resolve(AppTheme.light);
    await _pumpPage(tester, controller, theme: siteTheme);
    void expectHome(ThemeData expected) {
      for (final finder in [
        find.byType(DDialogContent),
        find.byType(DToggleGroup<ContentAlignment>),
        find.byType(DSwitchTile),
        find.byKey(const ValueKey('text-size-increase')),
      ]) {
        final context = tester.element(finder);
        expect(Theme.of(context).colorScheme, expected.colorScheme);
        expect(
          DTokens.of(context).surface,
          expected.extension<DTokens>()!.surface,
        );
      }
      expect(
        Theme.of(tester.element(find.text('Open settings'))).colorScheme,
        siteTheme.colorScheme,
      );
      expect(controller.rootMode, ShellRootMode.forum);
    }

    expectHome(AppTheme.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expectHome(AppTheme.dark);
  });

  testWidgets(
    'narrow Settings supports large RTL text and reachable controls',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pumpPage(
        tester,
        controller,
        size: const Size(360, 640),
        scale: 2,
        rtl: true,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Left'));
      await tester.tap(find.text('Left'));
      await tester.pumpAndSettle();
      expect(controller.appSettings.contentAlignment, ContentAlignment.left);
      await tester.ensureVisible(
        find.byKey(const ValueKey('text-size-increase')),
      );
      await tester.tap(find.byKey(const ValueKey('text-size-increase')));
      await tester.pumpAndSettle();
      expect(controller.appSettings.textScale, AppTextScale.percent110);
      await tester.ensureVisible(find.text('Disable GIF animations'));
      await tester.tap(find.text('Disable GIF animations'));
      await tester.pumpAndSettle();
      expect(controller.appSettings.disableGifAnimations, isTrue);
      await tester.ensureVisible(
        find.byKey(const ValueKey('app-settings-close')),
      );
      await tester.tap(find.byKey(const ValueKey('app-settings-close')));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsModal), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

ShellController _controller({AppSettingsPersistence? appSettingsPersistence}) =>
    ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
      appSettingsStore: AppSettingsStore(
        persistence: appSettingsPersistence ?? MemoryAppSettingsPersistence(),
      ),
    );

Future<void> _pumpPage(
  WidgetTester tester,
  ShellController controller, {
  Size size = const Size(800, 600),
  double scale = 1,
  ThemeData? theme,
  bool rtl = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-app-settings'),
              onPressed: () => showAppSettingsModal(context),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-app-settings')));
  await tester.pumpAndSettle();
}

Future<void> _pumpRail(
  WidgetTester tester,
  ShellController controller, {
  DiagnosticsController? diagnostics,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget rail = const SizedBox(width: 72, child: InstanceRail());
  if (diagnostics != null) {
    rail = DiagnosticsScope(controller: diagnostics, child: rail);
  }
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(alignment: Alignment.centerLeft, child: rail),
        ),
      ),
    ),
  );
  await tester.pump();
}
