import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/calendar_day.dart';
import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fake_image_http_client.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _profile = UserCard(
  username: 'sam',
  name: 'Sam Example',
  title: 'Community member',
  bioExcerpt: '<p>Builds things with the community.</p>',
  location: 'Paris',
);
final _surface = find.byKey(const ValueKey('user-card-surface'));
final _target = find.byType(UserCardTarget);

void main() {
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  testWidgets(
    'mobile card matches banner, facts and badge layout in both materials',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 132),
        Paint()..color = const Color(0xffd9b668),
      );
      canvas.drawCircle(
        const Offset(300, 22),
        26,
        Paint()..color = const Color(0xffdce3eb),
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, 58)
          ..lineTo(70, 90)
          ..lineTo(190, 60)
          ..lineTo(300, 90)
          ..lineTo(400, 72)
          ..lineTo(400, 132)
          ..lineTo(0, 132)
          ..close(),
        Paint()..color = const Color(0xff82738c),
      );
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(400, 132));
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      image!.dispose();
      picture.dispose();
      debugNetworkImageHttpClientProvider = () =>
          FakeImageHttpClient(bytes!.buffer.asUint8List());
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      const reader = DiscourseUser(
        id: 7,
        username: 'reader',
        canSendPrivateMessages: true,
      );
      for (final material in DAppearanceMaterial.values) {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 2.0]) {
            final api = await _pumpTarget(
              tester,
              platform: TargetPlatform.iOS,
              size: const Size(390, 844),
              material: material,
              dark: dark,
              scale: scale,
              currentUser: reader,
              safeBottom: 34,
            );
            await _open(tester);
            api.requests.single.complete(
              UserCard(
                username: 'sam',
                id: 8,
                name: 'Silas Vance',
                cardBackgroundUrl: 'https://meta.example/banner.png',
                canSendPrivateMessage: true,
                bioExcerpt: '<p>Will happily talk switches for an hour.</p>',
                timezone: 'America/Los_Angeles',
                location: 'Portland, OR',
                createdAt: DateTime(2017, 6, 1),
                lastPostedAt: DateTime.now().subtract(const Duration(days: 20)),
                timeRead: 30 * Duration.secondsPerDay,
                badgeCount: 29,
                featuredBadges: const [
                  UserCardBadge(
                    id: 1,
                    name: 'Great reply',
                    icon: 'reply',
                    tier: BadgeTier.gold,
                  ),
                  UserCardBadge(id: 2, name: 'Autobiographer', icon: 'user'),
                  UserCardBadge(
                    id: 3,
                    name: 'Popular link',
                    icon: 'link',
                    tier: BadgeTier.silver,
                  ),
                ],
                plugins: PluginData.none.withValue(
                  chatUserCardKey,
                  const ChatUserCardData(canChat: true),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => precacheImage(
                const NetworkImage('https://meta.example/banner.png'),
                tester.element(_surface),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(_surface).bottom, 804);
            expect(find.text('Silas Vance'), findsOneWidget);
            expect(find.text('Message'), findsOneWidget);
            expect(find.text('Chat'), findsOneWidget);
            expect(find.text('Portland, OR'), findsOneWidget);
            expect(
              find.text('Last post 20d', findRichText: true),
              findsOneWidget,
            );
            expect(
              find.text('Joined Jun 2017', findRichText: true),
              findsOneWidget,
            );
            expect(
              find.text('Read time 1mon', findRichText: true),
              findsOneWidget,
            );
            expect(find.text('+26 more'), findsOneWidget);
            final handle = tester.widget<DecoratedBox>(
              find.byKey(const ValueKey('sheet-drag-handle')),
            );
            expect(
              (handle.decoration as BoxDecoration).color,
              Colors.white.withValues(alpha: .9),
            );
            for (final label in [
              'Great reply',
              'Autobiographer',
              'Popular link',
            ]) {
              final badge = find.widgetWithText(DBadge, label);
              expect(tester.getSize(badge).height, 26 + (scale - 1) * 18);
            }
            await _captureCard(
              tester,
              '${material.name}-${dark ? 'dark' : 'light'}-$scale',
            );
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byKey(const ValueKey('sheet-drag-handle')),
              Offset(0, scale == 1 ? 180 : 400),
              kind: PointerDeviceKind.touch,
            );
            await tester.pumpAndSettle();
            expect(_surface, findsNothing);
          }
        }
      }
      debugNetworkImageHttpClientProvider = null;
    },
  );

  for (final permitted in [false, true]) {
    testWidgets(
      'mobile Message ${permitted ? 'opens the addressed draft' : 'respects a denied permission'}',
      (tester) async {
        const reader = DiscourseUser(
          id: 7,
          username: 'reader',
          canSendPrivateMessages: true,
        );
        final api = await _pumpTarget(
          tester,
          platform: TargetPlatform.iOS,
          currentUser: reader,
        );
        final shell = ShellScope.read(tester.element(_target));
        await _open(tester);
        api.requests.single.complete(
          UserCard(username: 'sam', id: 8, canSendPrivateMessage: permitted),
        );
        await tester.pumpAndSettle();
        if (permitted) {
          await tester.tap(find.text('Message'));
          await tester.pumpAndSettle();
          expect(_surface, findsNothing);
          expect(shell.visibleComposer?.target.targetRecipients, 'sam');
        } else {
          expect(find.text('Message'), findsNothing);
          expect(shell.visibleComposer, isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} card is an inset sheet with swipe dismissal',
      (tester) async {
        final api = await _pumpTarget(
          tester,
          platform: platform,
          size: const Size(390, 844),
        );
        var completed = false;
        unawaited(
          showUserCard(
            context: tester.element(_target),
            username: 'sam',
            siteUrl: _siteUrl,
          ).then((_) => completed = true),
        );
        await _pumpOpen(tester);
        expect(tester.widget(_surface), isA<DSheetContent>());
        expect(find.byType(DPopoverContent), findsNothing);
        final bounds = tester.getRect(_surface);
        expect(bounds.left, 6);
        expect(bounds.right, 384);
        expect(bounds.bottom, 838);
        final handle = find.byKey(const ValueKey('sheet-drag-handle'));
        await tester.drag(
          handle,
          const Offset(0, 12),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(tester.getRect(_surface), bounds);
        await tester.drag(
          handle,
          const Offset(0, 180),
          kind: PointerDeviceKind.touch,
        );
        await tester.pumpAndSettle();
        expect(_surface, findsNothing);
        expect(completed, isTrue);
        api.requests.single.complete(_profile);
        await tester.pumpAndSettle();
        expect(_surface, findsNothing);
        await _open(tester);
        expect(find.text('Sam Example'), findsOneWidget);
        expect(_surface, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_surface, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('loading and ready cards stay compact on a tall desktop', (
    tester,
  ) async {
    final api = await _pumpTarget(tester, size: const Size(1800, 1100));
    final semantics = tester.ensureSemantics();
    try {
      await _open(tester);

      expect(tester.widget(_surface), isA<DPopoverContent>());
      expect(tester.getSize(_surface).width, 400);
      expect(tester.getSize(_surface).height, inInclusiveRange(180, 240));
      expect(tester.getRect(_surface).top, tester.getRect(_target).bottom + 8);
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.bySemanticsLabel('Loading profile'), findsOneWidget);
      expect(find.byType(DSpinner), findsNothing);

      api.requests.single.complete(_profile);
      await tester.pumpAndSettle();

      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.text('Sam Example'), findsOneWidget);
      expect(find.text('View profile'), findsOneWidget);
      expect(tester.getSize(_surface).width, 400);
      expect(tester.getSize(_surface).height, lessThan(300));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('metadata names the reader\'s months and the web\'s read time', (
    tester,
  ) async {
    final api = await _pumpTarget(tester);
    await _open(tester);
    // Both are still the previous month, and the join the previous year, from
    // UTC-4 westward. A UTC run cannot tell the two apart;
    // TZ=America/Los_Angeles can.
    final lastPostedAt = DateTime.utc(2026, 9, 1, 3);
    final createdAt = DateTime.utc(2024, 1, 1, 3);
    api.requests.single.complete(
      UserCard(
        username: 'sam',
        createdAt: createdAt,
        lastPostedAt: lastPostedAt,
        timeRead: 100 * Duration.secondsPerHour,
      ),
    );
    await tester.pumpAndSettle();

    String month(DateTime at) {
      final day = calendarDay(at)!;
      return '${shortMonthName(day.month)} ${day.year}';
    }

    expect(
      find.text('Last post ${month(lastPostedAt)}', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Joined ${month(createdAt)}', findRichText: true),
      findsOneWidget,
    );
    // The profile summary and the web both round 100 hours to days.
    expect(find.text('Time read 4d', findRichText: true), findsOneWidget);
  });

  testWidgets('failed cards remain compact and Retry restores the skeleton', (
    tester,
  ) async {
    final api = await _pumpTarget(tester);
    await _open(tester);
    api.requests.single.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load @sam."), findsOneWidget);
    expect(tester.getSize(_surface).height, lessThan(200));
    expect(find.byType(DSkeletonRegion), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(api.requests, hasLength(2));

    api.requests.last.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.text('Sam Example'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  for (final dismissal in ['Escape', 'outside press']) {
    testWidgets('$dismissal closes a loading card and completes its future', (
      tester,
    ) async {
      final api = await _pumpTarget(tester);
      var closed = false;
      unawaited(
        showUserCard(
          context: tester.element(_target),
          username: 'sam',
          siteUrl: _siteUrl,
        ).then((_) => closed = true),
      );
      await _pumpOpen(tester);
      expect(_surface, findsOneWidget);

      if (dismissal == 'Escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tapAt(const Offset(750, 550));
      }
      await tester.pumpAndSettle();
      expect(_surface, findsNothing);
      expect(closed, isTrue);

      api.requests.single.complete(_profile);
      await tester.pumpAndSettle();
      expect(_surface, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Escape restores keyboard focus to the profile target', (
    tester,
  ) async {
    final api = await _pumpTarget(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final action = tester.widget<InkWell>(
      find.descendant(of: _target, matching: find.byType(InkWell)),
    );
    expect(action.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpOpen(tester);
    expect(_surface, findsOneWidget);
    api.requests.single.complete(_profile);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_surface, findsNothing);
    expect(action.focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'View profile closes its own route and preserves a newer dialog',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final urls = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          urls.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final api = await _pumpTarget(tester);
      await _open(tester);
      api.requests.single.complete(_profile);
      await tester.pumpAndSettle();
      final context = tester.element(_surface);
      final navigator = Navigator.of(context);

      await tester.tap(find.text('View profile'));
      final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Newer dialog')),
      );
      await tester.pumpAndSettle();
      expect(urls, ['$_siteUrl/u/sam']);
      expect(find.text('Newer dialog'), findsOneWidget);
      expect(_surface, findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      await dialog;
      expect(_target, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cards stay inside the nearest nested navigator', (tester) async {
    await _pumpTarget(tester, nested: true);
    final viewport = tester.getRect(find.byType(Navigator).last);
    await _open(tester);
    final bounds = tester.getRect(_surface);
    expect(bounds.width, 336);
    expect(bounds.left, greaterThanOrEqualTo(viewport.left + 12));
    expect(bounds.right, lessThanOrEqualTo(viewport.right - 12));
    expect(bounds.top, tester.getRect(_target).bottom + 8);
    expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom - 12));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Navigator), findsNWidgets(2));
    expect(_target, findsOneWidget);
  });

  testWidgets('profile links with a large source still open and dismiss', (
    tester,
  ) async {
    await _pumpTarget(tester);
    expect(
      showUserCardForUrl(
        tester.element(find.byType(Scaffold)),
        '$_siteUrl/u/sam',
      ),
      isTrue,
    );
    await _pumpOpen(tester);
    expect(tester.getSize(_surface).height, inInclusiveRange(180, 240));
    expect(tester.getSize(_surface).width, 400);
    await tester.tapAt(const Offset(750, 50));
    await tester.pumpAndSettle();
    expect(_surface, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long cards scroll within a narrow viewport at large text', (
    tester,
  ) async {
    final api = await _pumpTarget(
      tester,
      size: const Size(320, 420),
      scale: 2,
      dark: true,
    );
    await _open(tester);
    expect(tester.getSize(_surface).width, 296);
    api.requests.single.complete(
      UserCard(
        username: 'sam',
        name: 'Sam Example with a long display name',
        bioExcerpt: '<p>${List.filled(30, 'Community member.').join(' ')}</p>',
        badgeCount: 12,
      ),
    );
    await tester.pumpAndSettle();

    final bounds = tester.getRect(_surface);
    expect(bounds.left, greaterThanOrEqualTo(12));
    expect(bounds.right, lessThanOrEqualTo(308));
    expect(bounds.top, greaterThanOrEqualTo(12));
    expect(bounds.bottom, lessThanOrEqualTo(408));
    final scrollable = find
        .descendant(of: _surface, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('12 badges').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (count, label) in [(1, '1 badge'), (2, '2 badges')]) {
    testWidgets('a card with $label counts them in agreement', (tester) async {
      final api = await _pumpTarget(tester, size: const Size(1800, 1100));
      await _open(tester);
      api.requests.single.complete(
        UserCard(username: 'sam', name: 'Sam Example', badgeCount: count),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _surface, matching: find.text(label)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'hover preview has a small skeleton and shares the card request',
    (tester) async {
      final api = await _pumpTarget(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_target));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(
        tester.getSize(find.byType(DHoverCardContent)).height,
        lessThan(100),
      );
      expect(find.byType(DSpinner), findsNothing);
      await _open(tester);
      expect(find.byType(DHoverCardContent), findsNothing);
      expect(_surface, findsOneWidget);
      expect(api.requests, hasLength(1));
      api.requests.single.complete(_profile);
      await tester.pumpAndSettle();
      expect(find.text('Sam Example'), findsOneWidget);
    },
  );

  testWidgets('a failed hover preview loads again on the next hover', (
    tester,
  ) async {
    final api = await _pumpTarget(tester);
    const away = Offset(750, 550);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: away);
    Future<void> hover() async {
      await mouse.moveTo(tester.getCenter(_target));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    }

    await hover();
    api.requests.single.completeError(StateError('Unavailable'));
    await tester.pump();
    expect(find.text("Couldn't load @sam."), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);

    await mouse.moveTo(away);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(DHoverCardContent), findsNothing);

    await hover();
    expect(api.requests, hasLength(2));
    expect(find.text("Couldn't load @sam."), findsNothing);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    api.requests.last.complete(_profile);
    await tester.pump();
    expect(find.text('Sam Example'), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
  });
}

Future<_CardApi> _pumpTarget(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double scale = 1,
  bool dark = false,
  bool nested = false,
  TargetPlatform platform = TargetPlatform.macOS,
  DAppearanceMaterial material = DAppearanceMaterial.standard,
  DiscourseUser? currentUser,
  double safeBottom = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = _CardApi(user: currentUser);
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: currentUser),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: currentUser == null ? null : installedPlugins,
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: DMaterialTheme.apply(
          (dark ? AppTheme.dark : AppTheme.light).copyWith(
            platform: platform,
            textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
              fontFamily: 'Lato',
            ),
          ),
          material,
        ),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('user-card-capture'),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewPadding: EdgeInsets.only(bottom: safeBottom),
              padding: EdgeInsets.only(bottom: safeBottom),
            ),
            child: child!,
          ),
        ),
        home: nested
            ? Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: 360,
                  height: 500,
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const _TargetPage(),
                    ),
                  ),
                ),
              )
            : const _TargetPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

class _TargetPage extends StatelessWidget {
  const _TargetPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: UserCardTarget(
          username: 'sam',
          siteUrl: _siteUrl,
          child: Text('Open Sam'),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_target);
  await _pumpOpen(tester);
}

Future<void> _pumpOpen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

class _CardApi extends FakeDiscourseApi {
  _CardApi({super.user});
  final requests = <Completer<UserCard>>[];

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<UserCard>();
    requests.add(response);
    return response.future;
  }
}

Future<void> _captureCard(WidgetTester tester, String name) async {
  final path = Platform.environment['USER_CARD_CAPTURE_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('user-card-capture')),
        )
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$path/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
