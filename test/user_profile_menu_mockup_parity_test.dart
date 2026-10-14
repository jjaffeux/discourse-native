import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _captureKey = ValueKey('profile-menu-capture');
const _site = 'https://meta.example';
const _user = DiscourseUser(
  id: 7,
  username: 'tynaut',
  name: 'Ty',
  hidePresence: false,
  draftCount: 2,
);
const _rows = [
  ('Set a custom status', 'user-menu-row-user-status'),
  ('Online', 'user-menu-hide-presence'),
  ('Pause notifications', 'pause-notifications-row'),
  ('Summary', 'user-menu-row-summary'),
  ('Activity', 'user-menu-row-activity'),
  ('Drafts', 'user-menu-row-drafts'),
  ('Preferences', 'user-menu-row-preferences'),
  ('About', 'user-menu-row-about'),
  ('Disconnect', 'user-menu-row-disconnect'),
];

void main() {
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final dark in [false, true]) {
      for (final glass in [false, true]) {
        for (final direction in TextDirection.values) {
          for (final scale in [1.0, 2.0]) {
            testWidgets(
              'profile mockup: ${platform.name}, dark $dark, glass $glass, ${direction.name}, ${scale}x',
              (tester) async {
                final shadows = debugDisableShadows;
                debugDisableShadows = false;
                try {
                  final controller = await _pump(
                    tester,
                    platform: platform,
                    dark: dark,
                    glass: glass,
                    direction: direction,
                    scale: scale,
                  );
                  final avatar = find.byKey(UserMenuButton.avatarKey);
                  final anchor = tester.getRect(avatar);
                  await tester.tap(avatar);
                  await tester.pumpAndSettle();

                  final menu = find.byType(DDropdownMenuContent);
                  expect(menu, findsOneWidget);
                  expect(find.byType(DSheetContent), findsNothing);
                  expect(find.byTooltip('Close'), findsNothing);
                  final bounds = tester.getRect(menu);
                  final screen = tester.view.physicalSize;
                  expect(bounds.width, 216);
                  expect(bounds.left, greaterThanOrEqualTo(5));
                  expect(bounds.right, lessThanOrEqualTo(screen.width - 5));
                  expect(bounds.top, greaterThanOrEqualTo(59));
                  expect(bounds.bottom, lessThanOrEqualTo(screen.height - 34));
                  if (scale == 1) {
                    expect(bounds.top, closeTo(anchor.bottom + 8, .01));
                    expect(
                      direction == TextDirection.ltr
                          ? bounds.right
                          : bounds.left,
                      direction == TextDirection.ltr
                          ? anchor.right
                          : anchor.left,
                    );
                  }
                  final popup = tester.widget<DPopoverContent>(
                    find.byType(DPopoverContent),
                  );
                  expect(popup.variant, DPopoverVariant.timeline);
                  final tokens = DTokens.of(
                    tester.element(
                      find.byKey(const ValueKey('user-menu-own-card')),
                    ),
                  );
                  final outerTokens = DTokens.of(tester.element(avatar));
                  expect(
                    tokens.mutedForeground,
                    Color.lerp(
                      outerTokens.background,
                      outerTokens.foreground,
                      .50,
                    ),
                  );
                  expect(
                    tokens.success,
                    Color.lerp(
                      outerTokens.foreground,
                      outerTokens.success,
                      .50,
                    ),
                  );
                  expect(
                    tokens.destructive,
                    Color.lerp(
                      outerTokens.foreground,
                      outerTokens.destructive,
                      .50,
                    ),
                  );
                  final ownCard = find.byKey(
                    const ValueKey('user-menu-own-card'),
                  );
                  final accountAvatar = find.descendant(
                    of: ownCard,
                    matching: find.byType(DAvatar),
                  );
                  expect(
                    tester.getSize(accountAvatar),
                    Size.square(32 * scale),
                  );
                  final name = tester.widget<Text>(find.text('Ty'));
                  final handle = tester.widget<Text>(find.text('@tynaut'));
                  expect(name.style!.fontSize, 13.5);
                  expect(name.style!.fontWeight, FontWeight.w600);
                  expect(handle.style!.fontSize, 12);
                  final separators = find.descendant(
                    of: menu,
                    matching: find.byType(DDropdownMenuSeparator),
                  );
                  expect(separators, findsNWidgets(3));
                  for (final separator in separators.evaluate()) {
                    final line = find.descendant(
                      of: find.byWidget(separator.widget),
                      matching: find.byType(ColoredBox),
                    );
                    final lineRect = tester.getRect(line);
                    expect(lineRect.left - bounds.left, 15);
                    expect(bounds.right - lineRect.right, 15);
                    expect(lineRect.height, 1);
                  }
                  if (scale == 1) {
                    final positions = [
                      tester.getRect(ownCard),
                      ...separators.evaluate().map(
                        (element) =>
                            tester.getRect(find.byWidget(element.widget)),
                      ),
                    ];
                    expect(positions[1].top, positions[0].bottom);
                    expect(
                      positions[2].top,
                      tester
                          .getRect(
                            find.byKey(
                              const ValueKey('pause-notifications-row'),
                            ),
                          )
                          .bottom,
                    );
                    expect(
                      positions[3].top,
                      tester
                          .getRect(
                            find.byKey(
                              const ValueKey('user-menu-row-preferences'),
                            ),
                          )
                          .bottom,
                    );
                  }

                  double start(Rect rect) =>
                      direction == TextDirection.ltr ? rect.left : rect.right;
                  double? labelStart;
                  for (final (label, key) in _rows) {
                    final row = find.byKey(ValueKey(key));
                    await tester.ensureVisible(row);
                    await tester.pumpAndSettle();
                    expect(row.hitTestable(), findsOneWidget);
                    final textRect = tester.getRect(find.text(label));
                    labelStart ??= start(textRect);
                    expect(start(textRect), labelStart, reason: label);
                    if (scale == 1) {
                      expect(tester.getRect(row).height, closeTo(33.5, .01));
                    }
                    if (label == 'Drafts') {
                      final count = tester.getRect(find.text('2'));
                      expect(count.center.dy, closeTo(textRect.center.dy, 1));
                    }
                  }
                  expect(tester.getRect(menu), bounds);
                  expect(tester.takeException(), isNull);

                  if (scale == 1 && direction == TextDirection.ltr) {
                    await _capture(
                      tester,
                      '${platform.name}-${dark ? 'dark' : 'light'}-${glass ? 'glass' : 'standard'}',
                    );
                  }
                  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                  await tester.pumpAndSettle();
                  expect(menu, findsNothing);
                  final focus = tester.widget<DButton>(avatar).focusNode!;
                  expect(focus.hasFocus, isTrue);
                  await tester.tap(avatar);
                  await tester.pumpAndSettle();
                  await tester.tapAt(Offset(20, screen.height - 50));
                  await tester.pumpAndSettle();
                  expect(menu, findsNothing);
                  expect(controller.currentInstance!.user!.username, 'tynaut');
                } finally {
                  debugDisableShadows = shadows;
                }
              },
            );
          }
        }
      }
    }
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('profile actions and toggles on ${platform.name}', (
      tester,
    ) async {
      final controller = await _pump(tester, platform: platform);
      final semantics = tester.ensureSemantics();
      try {
        final avatar = find.byKey(UserMenuButton.avatarKey);
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        final menu = find.byType(DDropdownMenuContent);
        final online = find.byKey(const ValueKey('user-menu-hide-presence'));
        expect(
          tester.getSemantics(online),
          isSemantics(hasCheckedState: true, isChecked: true),
        );
        await tester.tap(online);
        await tester.pumpAndSettle();
        expect(controller.hidePresenceFor(_site), isTrue);
        expect(find.text('Online'), findsOneWidget);
        expect(menu, findsOneWidget);
        expect(
          tester.getSemantics(online),
          isSemantics(hasCheckedState: true, isChecked: false),
        );
        await tester.tap(online);
        await tester.pumpAndSettle();
        expect(controller.hidePresenceFor(_site), isFalse);

        await tester.tap(find.byKey(const ValueKey('pause-notifications-row')));
        await tester.pumpAndSettle();
        expect(menu, findsNothing);
        expect(find.text('Pause notifications for…'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        await tester.tap(avatar);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('user-menu-row-user-status')),
        );
        await tester.pumpAndSettle();
        expect(menu, findsNothing);
        expect(
          find.byKey(const ValueKey('user-status-editor')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('user-menu-own-card')), findsNothing);
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('user-menu-own-card')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('user-menu-row-disconnect')),
        );
        await tester.pumpAndSettle();
        expect(menu, findsNothing);
        expect(controller.currentInstance!.user, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'hover, keyboard, and reduced motion retain mockup row geometry',
    (tester) async {
      await _pump(tester, reducedMotion: true);
      final avatar = find.byKey(UserMenuButton.avatarKey);
      tester.widget<DButton>(avatar).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      final disconnect = find.byKey(const ValueKey('user-menu-row-disconnect'));
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<DDropdownMenuItem>()
            ?.key,
        disconnect.evaluate().single.widget.key,
      );
      final summary = find.byKey(const ValueKey('user-menu-row-summary'));
      final bounds = tester.getRect(summary);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(bounds.center);
      await tester.pump();
      final fill = tester
          .widgetList<Container>(
            find.descendant(of: summary, matching: find.byType(Container)),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .single;
      expect(fill.color!.a, greaterThan(0));
      expect(fill.borderRadius, BorderRadius.circular(7));
      expect(tester.getRect(summary), bounds);
      await mouse.removePointer();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ShellController> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  bool dark = true,
  bool glass = false,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  bool reducedMotion = false,
}) async {
  final size = Size(
    platform == TargetPlatform.macOS
        ? 900
        : scale == 1
        ? 430
        : 320,
    800,
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(tester.view.reset);
  const config = SiteConfig(userStatusEnabled: true);
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: _user, config: config),
    ]),
    api: FakeDiscourseApi(user: _user, siteConfigs: const {_site: config}),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  addTearDown(controller.dispose);
  final palette = forumThemePresets
      .firstWhere((preset) => preset.id == 'dracula')
      .resolve(dark ? Brightness.dark : Brightness.light);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: ShellScope(
        controller: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DMaterialTheme.apply(
            AppTheme.fromPalette(
              palette,
              fontFamily: 'Lato',
            ).copyWith(platform: platform),
            glass
                ? DAppearanceMaterial.liquidGlass
                : DAppearanceMaterial.standard,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: const Scaffold(
            body: SafeArea(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: UserMenuButton(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['NATIVE_PROFILE_CAPTURE_DIR'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
