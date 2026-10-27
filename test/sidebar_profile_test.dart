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
import 'package:discourse_native/src/shell/mobile_shell.dart';
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

  for (final key in [
    UserMenuButton.avatarKey,
    const ValueKey('user-presence-menu'),
  ]) {
    testWidgets('Escape from drawer footer $key closes navigation', (
      tester,
    ) async {
      final shell = await _pumpProduction(tester, phone);
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      tester.widget<DButton>(find.byKey(key)).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isFalse);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets('opening drawer preview includes an inert profile footer', (
    tester,
  ) async {
    final shell = await _pumpProduction(tester, phone);
    final profile = find.byKey(UserMenuButton.avatarKey);
    final open = await tester.startGesture(const Offset(8, 400));
    await open.moveBy(
      const Offset(120, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(profile, findsOneWidget);
    expect(profile.hitTestable(), findsNothing);
    await open.cancel();
    await tester.pumpAndSettle();
    expect(profile, findsNothing);

    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('drawer presence is the reference icon-only circle at 34', (
    tester,
  ) async {
    await _pumpProduction(tester, phone);
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    final presence = find.byKey(const ValueKey('user-presence-menu'));
    final button = tester.widget<DButton>(presence);
    expect(button.size, DControlSize.toolbar);
    expect(DControlStyle.height(DControlSize.toolbar), 34);
    final bounds = tester.getSize(presence);
    expect(bounds.width, bounds.height);
    final icon = tester.widget<DIcon>(
      find.descendant(of: presence, matching: find.byType(DIcon)),
    );
    expect(icon.size, 10, reason: 'one glyph, no chevron');
    expect(buttonSurface(tester, of: presence).color, Colors.transparent);
    await tester.tap(presence);
    await tester.pumpAndSettle();
    expect(
      buttonSurface(tester, of: presence).color,
      DTokens.of(tester.element(presence)).raisedBackground,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('closing drawer footer follows its page and ignores input', (
    tester,
  ) async {
    final shell = await _pumpProduction(tester, phone);
    final profile = find.byKey(UserMenuButton.avatarKey);
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    final before = tester.getRect(profile);
    final page = find.byKey(const ValueKey('mobile-navigation-page'));
    final pageBefore = tester.getRect(page);
    final close = await tester.startGesture(const Offset(386, 400));
    await close.moveBy(
      const Offset(-120, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(shell.mobileNavigation.sidebarOpen, isTrue);
    final during = tester.getRect(profile);
    final pageDuring = tester.getRect(page);
    expect(during, isNot(before));
    expect(
      (during.left - pageDuring.left) / pageDuring.width,
      closeTo((before.left - pageBefore.left) / pageBefore.width, .00001),
    );
    expect(
      during.width / before.width,
      closeTo(pageDuring.width / pageBefore.width, .00001),
    );
    expect(profile.hitTestable(), findsNothing);
    await close.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(profile), before);
    expect(profile.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'drawer presence retires on site change while profile follows selection',
    (tester) async {
      const otherSite = 'https://team.example';
      await pumpShell(
        tester,
        phone,
        instances: [
          instance('meta.example').copyWith(user: _user),
          instance('team.example').copyWith(user: _user),
        ],
        authenticator: FakeAuthenticator()
          ..keys[_site] = 'key'
          ..keys[otherSite] = 'other-key',
        api: FakeDiscourseApi(user: _user, feeds: const {'/latest.json': []}),
      );
      final shell = ShellScope.read(tester.element(find.byType(AdaptiveShell)));
      final body = tester.element(find.byType(MobileHistoryGestures));
      Future<void> drawer() async {
        await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
        await tester.pumpAndSettle();
      }

      await drawer();
      final presence = find.byKey(const ValueKey('user-presence-menu'));
      await tester.tap(presence);
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      expect(tester.widget<DButton>(presence).expanded, isTrue);
      expect(find.byType(DSheetContent), findsOneWidget);
      expect(tester.element(find.byType(MobileHistoryGestures)), same(body));
      shell.selectInstance(1);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(tester.element(find.byType(MobileHistoryGestures)), same(body));
      await drawer();
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
      shell.selectInstance(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('user-menu-hide-presence')));
      await tester.pumpAndSettle();
      expect(shell.hidePresenceFor(_site), isTrue);
      expect(shell.hidePresenceFor(otherSite), isFalse);
      await shell.connectCurrentInstance();
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(tester.element(find.byType(MobileHistoryGestures)), same(body));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('drawer host preserves its body without an account', (
    tester,
  ) async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore([]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await shell.load();
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          home: UserMenuButton.drawer(
            builder: (context, footer) =>
                Text(footer == null ? 'Body without account' : 'Account body'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Body without account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'mobile drawer profile opens a sheet over the sidebar on $platform',
      (tester) async {
        final shell = await _pumpProduction(tester, phone);
        final profile = find.byKey(UserMenuButton.avatarKey);
        final navigation = find.byKey(const ValueKey('mobile-navigation-page'));
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
        expect(shell.mobileNavigation.sidebarOpen, isTrue);
        expect(navigation, findsOneWidget);
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(
          find.byKey(const ValueKey('user-menu-own-card')),
          findsOneWidget,
        );
        await _capture(tester, '${platform.name}-profile-sheet');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(shell.mobileNavigation.sidebarOpen, isTrue);
        expect(profile.hitTestable(), findsOneWidget);
        final focus = FocusManager.instance.primaryFocus?.context;
        expect(
          focus?.findAncestorWidgetOfExactType<Offstage>()?.offstage ?? false,
          isFalse,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.sidebarOpen, isFalse);
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
  testWidgets(
    'mobile profile supports Native Tab dismissal and menu selection',
    (tester) async {
      final shell = await _pumpProduction(tester, phone);
      Future<void> profile() async {
        if (!shell.mobileNavigation.sidebarOpen) {
          await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(UserMenuButton.avatarKey));
        await tester.pumpAndSettle();
      }

      await profile();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      for (var visit = 0; visit < 2; visit++) {
        await profile();
        await tester.tap(find.byKey(const ValueKey('user-menu-row-summary')));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'summary');
        expect(find.byType(DSheetContent), findsNothing);
        expect(shell.mobileNavigation.sidebarOpen, isFalse, reason: '$visit');
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

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
  const profile = SizedBox(
    width: 300,
    child: UserMenuButton(presentation: UserMenuPresentation.profileCard),
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
        home: const AccountMenuScope(
          child: Scaffold(
            body: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: UserMenuButton(
                    presentation: UserMenuPresentation.notifications,
                  ),
                ),
                Spacer(),
                profile,
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
