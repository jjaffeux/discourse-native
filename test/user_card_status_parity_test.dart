import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_status_editor.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_image_http_client.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://forum.example';
const _status = UserStatus(description: 'Working from home', emoji: 'house');
const _user = DiscourseUser(
  id: 7,
  username: 'reader',
  name: 'Alex Morgan',
  status: _status,
);
const _card = UserCard(
  id: 7,
  username: 'reader',
  name: 'Alex Morgan',
  title: 'Community guide',
  cardBackgroundUrl: 'https://forum.example/card-background.png',
  isStaff: true,
  isModerator: true,
  status: _status,
);
const _capture = ValueKey('users-parity-render');
late Uint8List _bannerBytes;
Future<ShellController> _shell() async {
  addTearDown(() => debugNetworkImageHttpClientProvider = null);

  // Deterministic local image responses exercise the real emoji rendering path.
  installTestMediaPipeline(
    client: MockClient(
      (_) async => http.Response(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="#b36e4d" d="M2 11 12 2 22 11v2h-3v9H5v-9H2z"/><path fill="#f4d289" d="M6 12h12v10H6z"/><path fill="#649bc1" d="M10 14h4v8h-4z"/></svg>',
        200,
        headers: {'content-type': 'image/svg+xml'},
      ),
    ),
  );

  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('forum.example').copyWith(
        user: _user,
        config: const SiteConfig(userStatusEnabled: true),
      ),
    ]),
    api: FakeDiscourseApi(
      user: _user,
      cards: const {'reader': _card},
      userPreferences: const UserPreferences(
        username: 'reader',
        canEdit: true,
        canChangeTrackingPreferences: true,
      ),
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  addTearDown(shell.dispose);
  return shell;
}

Future<void> _pump(
  WidgetTester tester,
  ShellController shell,
  Widget child, {
  bool dark = false,
  double width = 800,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  final theme = dark ? AppTheme.dark : AppTheme.light;
  debugNetworkImageHttpClientProvider = () => FakeImageHttpClient(_bannerBytes);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            platform: platform,
            textTheme: theme.textTheme.apply(fontFamily: 'ParityFont'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => precacheImage(
      const NetworkImage('https://forum.example/card-background.png'),
      tester.element(find.byType(Scaffold).first),
    ),
  );
  await tester.pumpAndSettle();
  debugNetworkImageHttpClientProvider = null;
}

Future<void> _export(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  final path = Platform.environment['USER_PARITY_EXPORT_DIR'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, 320, 160);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff36576b), Color(0xffc9aa70)],
        ).createShader(bounds),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, 160);
    _bannerBytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();

    await (FontLoader(
      'ParityFont',
    )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'card and editable header render from the same identity dark=$dark',
      (tester) async {
        final shell = await _shell();
        await _pump(
          tester,
          shell,
          Center(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DCard(
                    spacing: 0,
                    child: UserCardHeader(card: _card, siteUrl: _site),
                  ),
                  Builder(
                    builder: (context) => DButton(
                      label: const Text('Edit status'),
                      onPressed: () =>
                          showUserStatusEditor(context, siteUrl: _site),
                    ),
                  ),
                ],
              ),
            ),
          ),
          dark: dark,
        );
        expect(find.text('Moderator'), findsOneWidget);
        await _export(tester, 'card-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Edit status'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('user-status-card-preview')),
          findsOneWidget,
        );
        final input = tester.widget<DInput>(find.byType(DInput));
        expect(input.borderless, isTrue);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('user-status-card-preview')),
            matching: find.byType(UserCardHeader),
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.byType(EditableText),
          'Reading and replying',
        );
        await tester.pumpAndSettle();
        await _export(tester, 'status-editor-${dark ? 'dark' : 'light'}');
      },
    );
  }
  testWidgets('large RTL status editor fits a narrow mobile sheet', (
    tester,
  ) async {
    final shell = await _shell();
    await _pump(
      tester,
      shell,
      Builder(
        builder: (context) => DButton(
          label: const Text('Edit status'),
          onPressed: () => showUserStatusEditor(context, siteUrl: _site),
        ),
      ),
      width: 320,
      scale: 2,
      platform: TargetPlatform.android,
      direction: TextDirection.rtl,
    );
    await tester.tap(find.text('Edit status'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText),
      'A longer status that fits the current account',
    );
    await tester.pumpAndSettle();
    await _export(tester, 'status-mobile-rtl-2x');
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets('own menu identity opens the real user card on $platform', (
      tester,
    ) async {
      final shell = await _shell();
      final menu = DDropdownMenuController();
      addTearDown(menu.dispose);
      await _pump(
        tester,
        shell,
        Center(
          child: DDropdownMenu(
            controller: menu,
            sheetOnMobile: true,
            mobileSheetVariant: DSheetVariant.adaptiveMenu,
            content: DDropdownMenuContent(
              children: [
                UserProfileMenuItems(siteUrl: _site, onDismiss: menu.close),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => DButton(
                label: const Text('Account'),
                onPressed: state.toggle,
              ),
            ),
          ),
        ),
        platform: platform,
      );
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user-menu-own-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-card-surface')), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(
        find.text(
          platform == TargetPlatform.android ? 'Edit profile' : 'Preferences',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.text(
          platform == TargetPlatform.android ? 'Edit profile' : 'Preferences',
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent!.isPreferences, isTrue);
    });
  }
  testWidgets(
    'preferences and real directory names render without fixture seeding',
    (tester) async {
      final shell = await _shell();
      await _pump(tester, shell, const PreferencesPage(siteUrl: _site));
      await tester.tap(
        find.byKey(const ValueKey('preferences-section-notifications')),
      );
      await tester.pumpAndSettle();
      await _export(tester, 'preferences-desktop');
      await _pump(
        tester,
        shell,
        const UsersPage(
          siteUrl: _site,
          data: UsersPageData(
            loaded: true,
            totalRows: 1,
            columns: [
              UserDirectoryColumn(
                id: 1,
                name: 'likes_received',
                type: UserDirectoryColumnType.automatic,
                position: 1,
              ),
            ],
            items: [
              UserDirectoryItem(
                id: 7,
                user: UserDirectoryUser(
                  id: 7,
                  username: 'reader',
                  name: 'Alex Morgan',
                ),
                values: {'likes_received': 42},
              ),
            ],
          ),
        ),
      );
      await _export(tester, 'directory-desktop');
      await tester.tap(find.byKey(const ValueKey('user-name-reader')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-card-surface')), findsOneWidget);
      expect(find.text('Community guide'), findsOneWidget);
    },
  );
}
