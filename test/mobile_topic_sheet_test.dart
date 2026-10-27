import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
final _handle = find.byKey(const ValueKey('sheet-drag-handle'));
final _sheet = find.byType(DSheetContent);
final _header = find.byKey(const ValueKey('mobile-header'));
final _dock = find.byKey(const ValueKey('mobile-bottom-bar'));
const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});

Future<ShellController> _openTopic(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  final shell = await pumpMobileShellFixture(
    tester,
    size: size,
    topic: topicPayload(
      id: 7,
      title: "What's everyone's sourdough hydration sweet spot? 🍞",
      canCreatePost: true,
      posts: [
        for (var id = 1; id <= 30; id++)
          Post(
            id: id,
            postNumber: id,
            username: 'crumbcoat',
            createdAt: DateTime.utc(2026, 5, 18),
            cooked:
                '<p>I have been experimenting between 72% and 82% and '
                'keep landing back at 76%. Crumb is open enough without '
                'turning into a pancake. Curious if anyone has gone higher '
                'with good results on a home oven.</p><p>My setup: 80% strong '
                'white, 20% wholemeal, 2% salt, overnight retard at 4°C.</p>',
          ),
      ],
    ),
  );
  await tester.tap(find.byKey(const ValueKey('topic-card-7')));
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureTopicSheet')) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(390, 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/inset-body-topic-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

void main() {
  if (const bool.fromEnvironment('captureTopicSheet')) {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.discourse.native/notification_opens');
    setUpAll(() async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(entry['family'] as String);
        for (final face
            in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    });
    tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
  }

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    testWidgets('topic sheet geometry ${mode.name} flat', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      final shell = await _openTopic(tester);
      await shell.forumSettings.setThemeMode(_site, mode);
      await shell.forumSettings.setThemes(
        _site,
        ForumThemePreferences.preset('dracula'),
      );
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: ForumFont.lato,
          interfaceFont: ForumFont.lato,
          effects: shell.forumSettings.shared.effects.copyWith(
            transparency: .3,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(_sheet);
      expect(bounds.left, 0);
      expect(bounds.right, 390);
      expect(bounds.bottom, 844);
      expect(bounds.top, tester.getRect(_header).bottom + 6);
      expect(tester.getSize(_handle), const Size(36, 5));
      expect(tester.getRect(_handle).top, bounds.top + 7);
      final surface = find
          .descendant(of: _sheet, matching: find.byType(DPageSurface))
          .first;
      expect(
        tester.widget<DPageSurface>(surface).borderRadius,
        const BorderRadius.vertical(
          top: Radius.circular(31),
          bottom: Radius.circular(22),
        ),
      );
      expect(find.byType(TopicListView), findsNothing);
      expect(find.byKey(const ValueKey('topic-close-reader')), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-card-7')).hitTestable(),
        findsNothing,
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Shared topic card'), findsNothing);
      semantics.dispose();
      expect(
        tester.widget<DPageSurface>(surface).backgroundColor!.a,
        lessThan(1),
      );
      final header = tester.getRect(_header);
      final dock = tester.getRect(_dock);
      final platform = Theme.of(tester.element(_header)).platform.name;
      await _capture(tester, '$platform-${mode.name}-flat-open');
      final drag = await tester.startGesture(tester.getCenter(_handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 70));
      await tester.pump();
      expect(tester.getRect(_sheet).top, greaterThan(bounds.top));
      expect(find.byType(TopicListView), findsOneWidget);
      expect(tester.widget<DPageSurface>(surface).backgroundColor!.a, 1);
      expect(
        find.byKey(const ValueKey('topic-card-7')).hitTestable(),
        findsNothing,
      );
      expect(tester.getRect(_header), header);
      expect(tester.getRect(_dock), dock);
      await _capture(tester, '$platform-${mode.name}-flat-pull');
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(_sheet), bounds);
      expect(find.byType(TopicListView), findsNothing);
      expect(shell.currentContent?.topicId, 7);
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }

  testWidgets(
    'topic locks both edges until downward dismissal restores the list',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      final list = find.byType(TopicListView);
      final element = tester.element(list);
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();
      // A forward entry ensures both history callbacks would otherwise be live.
      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.users),
          title: 'Users',
          icon: DIcons.user,
        ),
      );
      shell.handleBack();
      await tester.pumpAndSettle();
      final visit = shell.mobileNavigation.entryId;
      final origin = tester.getRect(_sheet);
      for (final y in [
        tester.getCenter(_header).dy,
        400.0,
        tester.getCenter(_dock).dy,
      ]) {
        for (final right in [true, false]) {
          await tester.dragFrom(
            Offset(right ? 2 : 388, y),
            Offset(right ? 180 : -180, 0),
          );
          await tester.pumpAndSettle();
          expect(shell.mobileNavigation.entryId, same(visit));
          expect(shell.mobileNavigation.sidebarOpen, isFalse);
          expect(tester.getRect(_sheet), origin);
        }
      }
      final drag = await tester.startGesture(tester.getCenter(_handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 160));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'latest');
      expect(_sheet, findsNothing);
      expect(tester.element(list), same(element));
      await tester.dragFrom(const Offset(2, 400), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  testWidgets(
    'dismissing a topic sheet keeps the revealed topic rows in place',
    (tester) async {
      final shell = await pumpMobileShellFixture(
        tester,
        topics: [
          for (var id = 1; id <= 40; id++)
            Topic(id: id, title: 'Discussion $id', slug: 'topic-$id'),
        ],
        topic: topicPayload(id: 7, title: 'Discussion 7'),
      );
      final list = find.byType(TopicListView);
      final card = find.byKey(const ValueKey('topic-card-7'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      double currentOffset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(
        (position.pixels - 180).clamp(0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      final offset = position.pixels;
      final bounds = tester.getRect(card);
      await _capture(tester, 'stable-list-before');

      await tester.tap(card);
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(tester.getCenter(_handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 220));
      await tester.pump();
      expect(currentOffset(), closeTo(offset, .01));
      expect(tester.getRect(card).top, closeTo(bounds.top, 1));
      await _capture(tester, 'stable-list-pull');
      await drag.up();
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          currentOffset(),
          closeTo(offset, .01),
          reason: 'The revealed list moved during dismissal frame $frame',
        );
        expect(tester.getRect(card).top, closeTo(bounds.top, 1));
      }
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'latest');
      expect(currentOffset(), closeTo(offset, .01));
      expect(tester.getRect(card), bounds);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'stable-list-after');
    },
    variant: _platforms,
  );

  testWidgets('reading scrolls normally and a pull at the top dismisses', (
    tester,
  ) async {
    final shell = await _openTopic(tester);
    final scroll = find
        .descendant(
          of: find.byType(TopicView),
          matching: find.byType(CustomScrollView),
        )
        .first;
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    final origin = tester.getRect(_sheet);
    expect(origin.bottom, 844);
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(tester.getRect(_sheet), origin);
    await tester.drag(scroll, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 7);
    expect(tester.getRect(_sheet), origin);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(const Offset(180, 500));
    await drag.moveBy(const Offset(0, 20));
    await drag.moveBy(const Offset(0, 170));
    await tester.pump();
    expect(tester.getRect(_sheet).top, greaterThan(origin.top));
    await drag.up();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets(
    'returning to the top cancels a pending compact header during dismissal',
    (tester) async {
      final shell = await _openTopic(tester);
      final scroll = find
          .descendant(
            of: find.byType(TopicView),
            matching: find.byType(CustomScrollView),
          )
          .first;
      final controller = tester.widget<CustomScrollView>(scroll).controller!;
      await tester.drag(scroll, const Offset(0, -900));
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      await tester.pump();
      // Cross the compact threshold while the hidden header is returning, then
      // reach the top before the deferred compact layout can take effect.
      controller.jumpTo(160);
      await tester.pump();
      controller.jumpTo(0);
      await tester.pump();
      final band = find.byKey(const ValueKey('topic-header-band'));
      expect(
        tester.widget<DecoratedBox>(band).decoration,
        const BoxDecoration(),
      );
      final drag = await tester.startGesture(const Offset(180, 500));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 170));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (band.evaluate().isNotEmpty) {
          expect(
            tester.widget<DecoratedBox>(band).decoration,
            const BoxDecoration(),
            reason: 'dismissal frame $frame',
          );
        }
        if (frame == 4) await drag.up();
      }
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'latest');
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  testWidgets('short pull restores and trackpad pull dismisses at the top', (
    tester,
  ) async {
    final shell = await _openTopic(tester);
    final origin = tester.getRect(_sheet);
    final drag = await tester.startGesture(tester.getCenter(_handle));
    await drag.moveBy(
      const Offset(0, 20),
      timeStamp: const Duration(milliseconds: 100),
    );
    await drag.moveBy(
      const Offset(0, 50),
      timeStamp: const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(_sheet), origin);
    expect(shell.currentContent?.topicId, 7);
    for (var i = 0; i < 4; i++) {
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(180, 500),
          scrollDelta: Offset(0, -45),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.getRect(_sheet).top, greaterThan(origin.top + 120));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
  testWidgets(
    'topics opened from Bookmarks use the sheet and return to Bookmarks',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(
        find.byKey(const ValueKey('mobile-mode-destination/user-bookmarks')),
      );
      await tester.pumpAndSettle();
      final origin = shell.currentContent;
      shell.openTopic(
        const Topic(id: 7, title: 'Shared topic card', slug: 'shared'),
      );
      await tester.pumpAndSettle();
      expect(_handle, findsOneWidget);
      expect(tester.getRect(_sheet).bottom, 844);
      await tester.drag(_handle, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(shell.currentContent, origin);
      expect(_sheet, findsNothing);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('mobile-content-panel')))
            .bottom,
        844,
      );
      expect(tester.takeException(), isNull);
    },
    variant: _platforms,
  );

  for (final width in [320.0, 800.0, 1024.0]) {
    testWidgets(
      'sheet fills screen with safe controls and large text at $width with reduced motion',
      (tester) async {
        final shell = await _openTopic(tester, size: Size(width, 844));
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        await shell.appSettings.setTextScale(AppTextScale.percent200);
        await shell.appSettings.setReduceMotion(true);
        await tester.pumpAndSettle();
        expect(tester.getRect(_sheet).width, width);
        expect(tester.getRect(_sheet).top, tester.getRect(_header).bottom + 6);
        expect(tester.getRect(_sheet).bottom, 844);
        // The bar reaches the screen's bottom; what it shows of its row
        // keeps 30 over the foot.
        expect(tester.getRect(_dock).bottom, 844);
        expect(
          tester
              .getRect(
                find.descendant(of: _dock, matching: find.byType(ClipRRect)),
              )
              .bottom,
          closeTo(844 - 30, .01),
        );
        expect(tester.getSize(_handle), const Size(36, 5));
        await tester.drag(_handle, const Offset(0, 180));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'latest');
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }

  testWidgets('native trackpad pan at the top dismisses the reader', (
    tester,
  ) async {
    final shell = await _openTopic(tester);
    const point = Offset(180, 500);
    await tester.sendEventToBinding(
      const PointerPanZoomStartEvent(pointer: 99, position: point),
    );
    for (var i = 1; i <= 6; i++) {
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 99,
          position: point,
          pan: Offset(0, i * 40),
          panDelta: const Offset(0, 40),
          timeStamp: Duration(milliseconds: i * 50),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.sendEventToBinding(
      const PointerPanZoomEndEvent(pointer: 99, position: point),
    );
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
