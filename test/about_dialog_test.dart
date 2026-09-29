import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/about_dialog.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _dialog = ValueKey('native-about-dialog');
const _replay = ValueKey('about-replay-mark');
const _open = ValueKey('open-about');
const _menuItem = ValueKey('user-menu-row-about');

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('profile menu opens About and dismisses on $platform', (
      tester,
    ) async {
      await _pumpMenu(tester, platform);
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_menuItem));
      await tester.tap(find.byKey(_menuItem));
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsOneWidget);
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(find.byKey(const ValueKey('user-menu-sheet')), findsNothing);
      expect(find.text('Discourse'), findsOneWidget);
      expect(find.text('Discourse Meta'), findsOneWidget);
      expect(find.text('Documentation'), findsOneWidget);
      if (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
      expect(tester.takeException(), isNull);

      if (platform == TargetPlatform.macOS) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        expect(focusedContext, isNotNull);
        expect(
          find.descendant(
            of: find.byKey(UserMenuButton.avatarKey),
            matching: find.byElementPredicate((e) => e == focusedContext),
          ),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('links use the external browser and announce their destination', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          final arguments = call.arguments as Map;
          launched.add(arguments['url'] as String);
          expect(arguments['useSafariVC'], isFalse);
          expect(arguments['useWebView'], isFalse);
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _pumpDialog(tester);
      for (final label in ['Discourse Meta', 'Documentation']) {
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('$label, opens in browser'),
          ),
          matchesSemantics(
            label: '$label, opens in browser',
            isLink: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(launched, [
        'https://meta.discourse.org',
        'https://meta.discourse.org/c/documentation/10',
      ]);
      expect(find.byKey(_dialog), findsOneWidget);
      expect(
        find.bySemanticsLabel('Replay Discourse logo animation'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'failed links leave an accessible retryable error in the dialog',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      var succeeds = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => succeeds,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _pumpDialog(tester);
      await tester.tap(find.text('Documentation'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open the link. Please try again.'),
        findsOneWidget,
      );
      succeeds = true;
      await tester.tap(find.text('Documentation'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open the link. Please try again.'),
        findsNothing,
      );
    },
  );

  for (final dismiss in ['close', 'barrier', 'escape', 'back']) {
    testWidgets('About supports $dismiss dismissal', (tester) async {
      await _pumpDialog(tester);
      switch (dismiss) {
        case 'close':
          await tester.tap(find.byTooltip('Close'));
        case 'barrier':
          await tester.tapAt(const Offset(5, 5));
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'back':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('About fits a narrow viewport with 200% text, dark $dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpDialog(tester, dark: dark, textScale: 2, rtl: true);
      expect(tester.takeException(), isNull);
      final bounds = tester.getRect(find.byKey(_dialog));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      await tester.ensureVisible(find.text('Documentation'));
      expect(find.text('Documentation').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Close'));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
    });
  }

  testWidgets(
    'replay redraws the mark and reduced motion stops it immediately',
    (tester) async {
      final reducedMotion = ValueNotifier(false);
      addTearDown(reducedMotion.dispose);
      await _pumpDialog(tester, reducedMotion: reducedMotion);
      final complete = await _markPixels(tester);
      expect(
        complete.where((channel) => channel != 0).length,
        greaterThan(5000),
      );
      await tester.tap(find.byKey(_replay));
      await tester.pump();
      final start = await _markPixels(tester);
      expect(start, isNot(orderedEquals(complete)));
      await tester.pump(const Duration(milliseconds: 600));
      final middle = await _markPixels(tester);
      expect(middle, isNot(orderedEquals(start)));
      expect(middle, isNot(orderedEquals(complete)));
      reducedMotion.value = true;
      await tester.pumpAndSettle();
      expect(await _markPixels(tester), orderedEquals(complete));
      await tester.tap(find.byKey(_replay));
      await tester.pump();
      expect(await _markPixels(tester), orderedEquals(complete));
      await tester.pump(const Duration(seconds: 1));
      expect(await _markPixels(tester), orderedEquals(complete));
    },
  );

  testWidgets('reduced motion presents the complete mark on first opening', (
    tester,
  ) async {
    final reducedMotion = ValueNotifier(true);
    addTearDown(reducedMotion.dispose);
    await _pumpDialog(tester, reducedMotion: reducedMotion);
    final complete = await _markPixels(tester);
    await tester.tap(find.byKey(_replay));
    await tester.pump(const Duration(milliseconds: 400));
    expect(await _markPixels(tester), orderedEquals(complete));
  });
}

Future<Uint8List> _markPixels(WidgetTester tester) async {
  final painting = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('about-mark-artwork')),
  );
  final recorder = ui.PictureRecorder();
  painting.painter!.paint(Canvas(recorder), const Size(96, 96));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(96, 96);
  final bytes = await tester.runAsync(() => image.toByteData());
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  bool dark = false,
  double textScale = 1,
  bool rtl = false,
  ValueNotifier<bool>? reducedMotion,
}) async {
  await tester.runAsync(() => rootBundle.loadString('assets/logo_mark.svg'));
  final motion = reducedMotion ?? ValueNotifier(false);
  if (reducedMotion == null) addTearDown(motion.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
        platform: TargetPlatform.macOS,
      ),
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: motion,
        builder: (context, reduced, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => DButton(
            key: _open,
            label: const Text('Open About'),
            onPressed: () => showNativeAboutDialog(context),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
}

Future<void> _pumpMenu(WidgetTester tester, TargetPlatform platform) async {
  await tester.runAsync(() => rootBundle.loadString('assets/logo_mark.svg'));
  tester.view.physicalSize = Size(
    platform == TargetPlatform.android || platform == TargetPlatform.iOS
        ? 390
        : 900,
    800,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 7, username: 'reader', name: 'Reader');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(user: user),
    authenticator: FakeAuthenticator()..keys['https://meta.example'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: UserMenuButton(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
