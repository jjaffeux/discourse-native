import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';

const _capture = ValueKey('writing-chrome-capture');
const _topic = Topic(id: 7, title: 'A conversation', slug: 'conversation');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    {
      for (final scale in [1.0, 2.0]) {
        testWidgets('writing capsule in $brightness / flat / ${scale}x', (
          tester,
        ) async {
          final shell = await _pump(tester, brightness, scale);
          final create = find.byKey(TopicCreateButton.buttonKey);
          final drafts = find.byKey(TopicCreateButton.draftsButtonKey);
          final capsule = find.ancestor(
            of: create,
            matching: find.byWidgetPredicate(
              (w) => w is DCard && w.variant == DCardVariant.primaryCapsule,
            ),
          );
          final tokens = DTokens.of(tester.element(create));
          expect(capsule, findsOneWidget);
          if (scale == 1) {
            expect(tester.getSize(capsule), const Size(81, 36));
            expect(tester.getSize(create), const Size(36, 28));
            expect(tester.getSize(drafts), const Size(32, 28));
          } else {
            expect(tester.getSize(capsule).height, greaterThan(36));
          }
          final pen = find.descendant(of: create, matching: find.byType(DIcon));
          final chevron = find.descendant(
            of: drafts,
            matching: find.byType(DIcon),
          );
          expect(tester.widget<DIcon>(pen).icon, DIcons.penToSquare);
          expect(
            IconTheme.of(tester.element(pen)).color,
            tokens.buttonTheme.primary.foreground,
          );
          expect(
            IconTheme.of(tester.element(chevron)).color,
            tokens.buttonTheme.primary.foreground,
          );
          expect(
            tester.getCenter(chevron).dx,
            closeTo(tester.getCenter(drafts).dx - 1.5, .01),
          );
          final separator = find.descendant(
            of: capsule,
            matching: find.byType(DSeparator),
          );
          expect(tester.getSize(separator), const Size(1, 16));
          expect(
            tester.widget<DSeparator>(separator).color,
            tokens.background.withValues(alpha: .3),
          );
          // The well's empty border and divider stay passive.
          await tester.tapAt(tester.getCenter(separator));
          await tester.pumpAndSettle();
          expect(shell.visibleComposer, isNull);
          expect(find.text('All drafts'), findsNothing);
          await _captureChrome(
            tester,
            '${brightness.name}-flat-${scale}x-new-topic',
          );

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(create));
          await tester.pumpAndSettle();
          expect(
            buttonSurface(tester, of: create).color,
            Colors.white.withValues(alpha: .16),
          );
          expect(buttonSurface(tester, of: drafts).color, Colors.transparent);
          await _captureChrome(
            tester,
            '${brightness.name}-flat-${scale}x-hover',
          );
          await mouse.removePointer();
          await tester.pumpAndSettle();

          // A native test window may start behind the user's foreground app.
          // Keep lifecycle state controlled while testing popup interaction;
          // actual background dismissal has its own popover tests.
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.tap(drafts);
          await tester.pumpAndSettle();
          expect(find.text('All drafts'), findsOneWidget);
          expect(tester.widget<DButton>(drafts).expanded, isTrue);

          await _captureChrome(
            tester,
            '${brightness.name}-flat-${scale}x-drafts-open',
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('All drafts'), findsNothing);
          expect(tester.widget<DButton>(drafts).expanded, isFalse);
          expect(
            tester.widget<DButton>(drafts).focusNode!.hasPrimaryFocus,
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          tester.widget<DButton>(drafts).focusNode!.requestFocus();
          await tester.pumpAndSettle();
          expect(buttonSurface(tester, of: drafts).ringWidth, greaterThan(0));
          await tester.tap(create);
          await tester.pumpAndSettle();
          expect(shell.visibleComposer?.isNewTopic, isTrue);
          expect(tester.takeException(), isNull);
        }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
      }
      testWidgets(
        'reply capsule opens the current topic in $brightness / flat',
        (tester) async {
          final shell = await _pump(tester, brightness, 1);
          shell.openTopic(_topic);
          await tester.pumpAndSettle();
          final reply = find.byKey(const ValueKey('title-bar-reply'));
          expect(reply, findsOneWidget);
          expect(find.byKey(TopicCreateButton.draftsButtonKey), findsNothing);
          final capsule = find.ancestor(
            of: reply,
            matching: find.byType(DCard),
          );
          expect(tester.getSize(capsule), const Size(44, 36));
          final icon = find.descendant(of: reply, matching: find.byType(DIcon));
          expect(
            IconTheme.of(tester.element(icon)).color,
            DTokens.of(tester.element(reply)).buttonTheme.primary.foreground,
          );
          await _captureChrome(tester, '${brightness.name}-flat-reply');
          await tester.tap(reply);
          await tester.pumpAndSettle();
          expect(
            (shell.visibleComposer?.target as ExistingTopicComposerTarget?)
                ?.topicId,
            _topic.id,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }

  testWidgets(
    'dropdown artwork follows the divider in RTL without widening its hit area',
    (tester) async {
      await _pump(tester, Brightness.dark, 1, rtl: true);
      final drafts = find.byKey(TopicCreateButton.draftsButtonKey);
      final icon = find.descendant(of: drafts, matching: find.byType(DIcon));
      expect(tester.getSize(drafts), const Size(32, 28));
      expect(
        tester.getCenter(icon).dx,
        closeTo(tester.getCenter(drafts).dx + 1.5, .01),
      );
      await tester.tap(drafts);
      await tester.pumpAndSettle();
      expect(find.text('All drafts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('reduced transparency keeps an opaque raised accent capsule', (
    tester,
  ) async {
    await _pump(tester, Brightness.dark, 1, highContrast: true);
    final capsule = find.byWidgetPredicate(
      (w) => w is DCard && w.variant == DCardVariant.primaryCapsule,
    );
    expect(tester.getSize(capsule), const Size(81, 36));
    // At the capsule's lower interior there is no sheen, glyph, divider or rim.
    // Reduced transparency must paint the full accent tint over the ground.
    final tokens = DTokens.of(tester.element(capsule));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final position =
        tester.getRect(capsule).topLeft -
        tester.getRect(find.byKey(_capture)).topLeft;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final x = ((position.dx + 30) * 2).round();
      final y = ((position.dy + 25) * 2).round();
      final color = tokens.buttonTheme.primary.background;
      final reference = [color.r, color.g, color.b];
      for (var channel = 0; channel < 3; channel++) {
        expect(
          bytes.getUint8((y * image.width + x) * 4 + channel),
          closeTo(reference[channel] * 255, 2),
        );
      }
      image.dispose();
    });
    await _captureChrome(tester, 'reduced-transparency');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  {
    testWidgets(
      'writing capsule paints the reference tint, sheen and rim in flat',
      (tester) async {
        const ground = Color(0xff282a36);
        const accent = Color(0xffbd93f9);
        final base = AppTheme.dark;
        final tokens = base.extension<DTokens>()!.copyWith(
          colors: base.colorScheme.copyWith(primary: accent),
          background: ground,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: base.copyWith(
              extensions: [
                ...base.extensions.values.where((e) => e is! DTokens),
                tokens,
              ],
            ),
            home: const Center(
              child: RepaintBoundary(
                key: _capture,
                child: ColoredBox(
                  color: ground,
                  child: DCard(
                    variant: DCardVariant.primaryCapsule,
                    size: DCardSize.small,
                    border: false,
                    child: SizedBox(width: 73, height: 28),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
              .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          List<int> rgb(int x, int y) => List.generate(
            3,
            (channel) => bytes.getUint8((y * image.width + x) * 4 + channel),
          );
          final reference = Color.alphaBlend(
            Color.lerp(ground, accent, .25)!,
            ground,
          );
          final center = rgb(40, 24);
          final expected = [reference.r, reference.g, reference.b];
          for (var channel = 0; channel < 3; channel++) {
            expect(center[channel], closeTo(expected[channel] * 255, 2));
            // Stock glass owns its specular rim; only the artwork paints one.

            expect(rgb(28, 5)[channel], closeTo(center[channel], 2));
            expect(rgb(40, 0)[channel], closeTo(center[channel], 2));
          }
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<ShellController> _pump(
  WidgetTester tester,
  Brightness brightness,
  double scale, {
  bool rtl = false,
  bool highContrast = false,
}) async {
  tester.view.physicalSize = const Size(1200, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
  final api = FakeDiscourseApi(
    user: user,
    feeds: const {
      '/latest.json': [_topic],
    },
    creatableFeedPaths: const {'/latest.json'},
    topics: {
      7: (
        detail: const TopicDetail(
          id: 7,
          title: 'A conversation',
          stream: [70],
          postsCount: 1,
          canCreatePost: true,
        ),
        posts: const [
          Post(id: 70, postNumber: 1, username: 'sam', cooked: '<p>Hello.</p>'),
        ],
      ),
    },
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys['https://meta.example'] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });
  await shell.load();
  await shell.loadFeed('latest');
  final base = AppTheme.forBrightness(
    brightness,
  ).copyWith(platform: TargetPlatform.macOS);
  final colors = base.colorScheme.copyWith(
    primary: const Color(0xffbd93f9),
    onSurface: brightness == Brightness.dark
        ? const Color(0xfff8f8f2)
        : const Color(0xff282a36),
  );
  final ground = brightness == Brightness.dark
      ? const Color(0xff282a36)
      : const Color(0xfff8f8f2);
  final theme = base.copyWith(
    extensions: [
      ...base.extensions.values.where((e) => e is! DTokens),
      base.extension<DTokens>()!.copyWith(colors: colors, background: ground),
    ],
  );
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => DFocusHighlight(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              highContrast: highContrast,
            ),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
          ),
        ),
        home: Material(
          color: ground,
          child: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              key: _capture,
              child: ColoredBox(
                color: ground,
                child: const ShellTitleBar(leadingInset: 80),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (tester.binding is LiveTestWidgetsFlutterBinding) {
    // Register after the controls so native window deactivation cannot race
    // the synthetic popup and focus actions in this renderer fixture.
    final lifecycle = _ResumedNativeFixture();
    tester.binding.addObserver(lifecycle);
    addTearDown(() => tester.binding.removeObserver(lifecycle));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  return shell;
}

class _ResumedNativeFixture with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    }
  }
}

Future<void> _captureChrome(WidgetTester tester, String name) async {
  const path = String.fromEnvironment('PRIMARY_ACTION_CAPTURE_DIR');
  if (path.isEmpty) return;
  await tester.runAsync(() async {
    final destination = path == 'native-temp'
        ? '${Directory.systemTemp.path}/primary-action-captures'
        : path;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    await Directory(destination).create(recursive: true);
    final capsule = find.byWidgetPredicate(
      (w) => w is DCard && w.variant == DCardVariant.primaryCapsule,
    );
    final bounds = tester
        .getRect(capsule)
        .shift(-tester.getRect(find.byKey(_capture)).topLeft);
    // Capture the actual painted native layer, including the capsule's rim.
    final detail = await (boundary.debugLayer! as OffsetLayer).toImage(
      bounds.inflate(4),
      pixelRatio: 2,
    );
    final detailBytes = (await detail.toByteData(
      format: ui.ImageByteFormat.png,
    ))!;
    await File(
      '$destination/$name-capsule.png',
    ).writeAsBytes(detailBytes.buffer.asUint8List());
    detail.dispose();
    // Native macOS runs export within the app sandbox.
    if (path == 'native-temp') {
      debugPrint('Native writing capture: $destination/$name-capsule.png');
    }
  });
}
