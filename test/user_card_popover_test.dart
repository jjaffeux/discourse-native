import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

Future<_CardApi> _pumpTarget(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double scale = 1,
  bool dark = false,
  bool nested = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = _CardApi();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.example')]),
    api: api,
    authenticator: FakeAuthenticator(),
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
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.macOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
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
  await tester.pump(const Duration(milliseconds: 150));
}

class _CardApi extends FakeDiscourseApi {
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
