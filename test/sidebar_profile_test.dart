import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/account_menu_scope.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.example';
const _user = DiscourseUser(
  id: 7,
  username: 'tynaut',
  name: 'Ty',
  hidePresence: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('org.discourse.native/notification_opens');
  setUpAll(
    () => messenger.setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('desktop profile follows sidebar and stays open at ${scale}x', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpProduction(tester, desktop);
      final profile = find.byKey(UserMenuButton.avatarKey);
      final header = find.byType(ShellTitleBar);
      expect(find.descendant(of: header, matching: profile), findsNothing);
      expect(profile, findsOneWidget);
      expect(find.text('Ty'), findsOneWidget);
      expect(find.text('@tynaut'), findsOneWidget);
      final bounds = tester.getRect(profile);
      final sidebar = tester.getRect(find.byType(InstanceSidebar));
      expect(bounds.left, lessThan(AdaptiveShell.railWidth));
      expect(bounds.right, greaterThan(AdaptiveShell.railWidth));
      expect(bounds.top, greaterThanOrEqualTo(sidebar.bottom));
      expect(bounds.bottom, lessThanOrEqualTo(desktop.height - 6));
      expect(profile.hitTestable(), findsOneWidget);
      await _capture(tester, 'desktop-expanded-${scale}x');
      await tester.tap(profile);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('user-menu-own-card'));
      expect(menu, findsOneWidget);
      final popup = tester.getRect(find.byType(DDropdownMenuContent));
      expect(popup.bottom, lessThanOrEqualTo(bounds.top));
      await _capture(tester, 'desktop-menu-${scale}x');
      final toggle = tester.widget<DButton>(
        find.byKey(const ValueKey('rail-sidebar-toggle')),
      );
      toggle.onPressed!();
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      final compact = tester.getRect(profile);
      expect(compact.left, greaterThanOrEqualTo(0));
      expect(compact.right, lessThanOrEqualTo(AdaptiveShell.railWidth));
      expect(
        find.descendant(of: profile, matching: find.text('Ty')),
        findsNothing,
      );
      final avatar = tester.widget<DAvatar>(
        find.descendant(of: profile, matching: find.byType(DAvatar)).first,
      );
      expect(avatar.ring, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _capture(tester, 'desktop-collapsed-${scale}x');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'mobile drawer profile opens an independent sheet on $platform',
      (tester) async {
        final shell = await _pumpProduction(tester, phone);
        final profile = find.byKey(UserMenuButton.avatarKey);
        expect(profile, findsNothing);
        expect(find.byKey(UserMenuButton.bellKey), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
        await tester.pumpAndSettle();
        expect(profile, findsOneWidget);
        final sidebar = tester.getRect(find.byType(InstanceSidebar));
        final profileBounds = tester.getRect(profile);
        expect(profileBounds.bottom, lessThanOrEqualTo(sidebar.bottom));
        expect(profileBounds.bottom, greaterThan(sidebar.bottom - 30));
        await _capture(tester, '${platform.name}-drawer');
        await tester.tap(profile);
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.sidebarOpen, isFalse);
        expect(
          find.byKey(const ValueKey('mobile-navigation-page')),
          findsNothing,
        );
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(
          find.byKey(const ValueKey('user-menu-own-card')),
          findsOneWidget,
        );
        await _capture(tester, '${platform.name}-profile-sheet');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(profile, findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('dark desktop profile ring tracks presence and paused state', (
    tester,
  ) async {
    final shell = await _pumpProduction(tester, laptop, dark: true);
    final profile = find.byKey(UserMenuButton.avatarKey);
    DAvatar avatar() => tester.widget<DAvatar>(
      find.descendant(of: profile, matching: find.byType(DAvatar)).first,
    );
    expect(avatar().ring, isTrue);
    expect(tester.widget<DButton>(profile).semanticLabel, contains('Online'));
    await shell.toggleHidePresence(_site);
    await tester.pumpAndSettle();
    expect(avatar().ring, isFalse);
    expect(tester.widget<DButton>(profile).semanticLabel, contains('Offline'));
    await shell.doNotDisturb.pause(
      _site,
      const DoNotDisturbDuration.minutes(30),
    );
    await tester.pumpAndSettle();
    expect(avatar().ring, isTrue);
    expect(
      tester.widget<DButton>(profile).semanticLabel,
      contains('Notifications paused'),
    );
    await _capture(tester, 'desktop-dark-paused');
    await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
    await tester.pumpAndSettle();
    await _capture(tester, 'desktop-dark-expanded');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('footer menus retire with their account on $platform', (
      tester,
    ) async {
      final shell = await _pumpProduction(
        tester,
        platform == TargetPlatform.macOS ? desktop : phone,
      );
      Future<void> openDrawer() async {
        if (platform == TargetPlatform.macOS ||
            shell.mobileNavigation.sidebarOpen) {
          return;
        }
        await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
        await tester.pumpAndSettle();
      }

      await openDrawer();
      await tester.tap(find.byKey(const ValueKey('user-presence-menu')));
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsOneWidget);
      await shell.connectCurrentInstance();
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      await openDrawer();
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
      await shell.disconnectInstance(_site);
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('RTL profile handles long live status at enlarged text', (
    tester,
  ) async {
    final shell = await _pump(
      tester,
      direction: TextDirection.rtl,
      scale: 2,
      dark: true,
      user: const DiscourseUser(
        id: 7,
        username: 'tynaut-with-a-long-username',
        name: 'Ty with a long display name',
        hidePresence: false,
      ),
    );
    const status = UserStatus(
      description: 'Sailing with a long status that must stay inside the card',
      emoji: 'sailboat',
    );
    shell.userStatuses.record(_site, 7, status);
    await tester.pumpAndSettle();
    expect(find.text(status.description), findsOneWidget);
    final profile = find.byKey(UserMenuButton.avatarKey);
    final bounds = tester.getRect(profile);
    final statusBounds = tester.getRect(find.text(status.description));
    expect(statusBounds.left, greaterThanOrEqualTo(bounds.left));
    expect(statusBounds.right, lessThanOrEqualTo(bounds.right));
    await tester.tap(profile);
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(DDropdownMenuContent));
    expect(menu.right, closeTo(bounds.right, .01));
    await _capture(tester, 'profile-dark-rtl-2x');
    expect(tester.takeException(), isNull);
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('drawer profile sheet survives closing drawer on $platform', (
      tester,
    ) async {
      final drawer = ValueNotifier(true);
      addTearDown(drawer.dispose);
      await _pump(tester, platform: platform, drawer: drawer);
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      expect(drawer.value, isFalse);
      expect(find.byType(DSheetContent), findsOneWidget);
      expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
      final online = find.byKey(const ValueKey('user-menu-hide-presence'));
      expect(online.hitTestable(), findsOneWidget);
      await tester.tap(online);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);
      final focus = FocusManager.instance.primaryFocus?.context;
      expect(
        focus?.findAncestorWidgetOfExactType<Offstage>()?.offstage ?? false,
        isFalse,
      );
      drawer.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('separate header and profile controls close the other menu', (
    tester,
  ) async {
    await _pump(tester);
    void activate(Key key) =>
        tester.widget<DButton>(find.byKey(key)).onPressed!();

    activate(UserMenuButton.bellKey);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-menu-own-card')), findsNothing);
    activate(UserMenuButton.avatarKey);
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsOneWidget);
    expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
    activate(UserMenuButton.bellKey);
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsOneWidget);
    expect(find.byKey(const ValueKey('user-menu-own-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile card retains Native hover and popup feedback', (
    tester,
  ) async {
    await _pump(tester);
    final profile = find.byKey(UserMenuButton.avatarKey);
    final bounds = tester.getRect(profile);
    final resting = buttonSurface(tester, of: profile).color;
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(bounds.center);
    await tester.pumpAndSettle();
    expect(buttonSurface(tester, of: profile).color, isNot(resting));
    await tester.tap(profile);
    await tester.pumpAndSettle();
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(buttonSurface(tester, of: profile).color, isNot(resting));
    expect(tester.getRect(profile), bounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile card status returns to username when it expires', (
    tester,
  ) async {
    await _pump(
      tester,
      user: DiscourseUser(
        id: 7,
        username: 'tynaut',
        name: 'Ty',
        hidePresence: false,
        status: UserStatus(
          description: 'Sailing',
          emoji: 'sailboat',
          endsAt: DateTime.now().add(const Duration(seconds: 3)),
        ),
      ),
    );
    expect(find.text('Ty'), findsOneWidget);
    expect(find.text('Sailing'), findsOneWidget);
    expect(find.text('@tynaut'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Sailing'), findsNothing);
    expect(find.text('@tynaut'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<ShellController> _pumpProduction(
  WidgetTester tester,
  Size size, {
  DiscourseUser user = _user,
  bool dark = false,
}) async {
  const config = SiteConfig(userStatusEnabled: true);
  await pumpShell(
    tester,
    size,
    instances: [instance('meta.example').copyWith(user: user, config: config)],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: user,
      doNotDisturbUntil: DateTime.now().add(const Duration(minutes: 30)),
      siteConfigs: const {_site: config},
      feeds: const {'/latest.json': []},
    ),
  );
  final shell = ShellScope.read(tester.element(find.byType(AdaptiveShell)));
  await shell.forumSettings.setShared(
    shell.forumSettings.shared.copyWith(
      font: ForumFont.lato,
      interfaceFont: ForumFont.lato,
      material: dark
          ? DAppearanceMaterial.liquidGlass
          : DAppearanceMaterial.standard,
    ),
  );
  await shell.forumSettings.setThemes(
    _site,
    ForumThemePreferences.preset('dracula'),
  );
  await shell.forumSettings.setThemeMode(
    _site,
    dark ? AppThemeMode.dark : AppThemeMode.light,
  );
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['NATIVE_PROFILE_CAPTURE_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      tester.view.physicalSize.width.toInt(),
      tester.view.physicalSize.height.toInt(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
      scene.dispose();
    }
  });
}

Future<ShellController> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  ValueNotifier<bool>? drawer,
  DiscourseUser user = _user,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(
    platform == TargetPlatform.macOS ? 900 : 430,
    800,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const config = SiteConfig(userStatusEnabled: true);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user, config: config),
    ]),
    api: FakeDiscourseApi(user: user, siteConfigs: const {_site: config}),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  addTearDown(shell.dispose);
  final profile = SizedBox(
    width: 300,
    child: UserMenuButton(
      presentation: UserMenuPresentation.profileCard,
      onBeforeProfileOpen: () => drawer?.value = false,
    ),
  );
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
          textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
            fontFamily: 'Lato',
          ),
        ),
        builder: (context, child) => Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: AccountMenuScope(
          child: Scaffold(
            body: Column(
              children: [
                const Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: UserMenuButton(
                    presentation: UserMenuPresentation.notifications,
                  ),
                ),
                const Spacer(),
                if (drawer == null)
                  profile
                else
                  ValueListenableBuilder<bool>(
                    valueListenable: drawer,
                    child: profile,
                    builder: (context, open, child) => Offstage(
                      offstage: !open,
                      child: ExcludeFocus(excluding: !open, child: child!),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}
