import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _capture = ValueKey('notification-parity-capture');

void main() {
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      for (final material in DAppearanceMaterial.values) {
        testWidgets('reference geometry on $platform, dark $dark, $material', (
          tester,
        ) async {
          final shadowsDisabled = debugDisableShadows;
          debugDisableShadows = false;
          try {
            final (shell, _) = await _mount(
              tester,
              platform: platform,
              dark: dark,
              material: material,
              paletteId: dark ? 'dracula' : 'solarized',
            );
            final originalRoute = shell.currentContent;
            final panel = tester.getRect(find.byType(UserMenuPanel));
            if (platform == TargetPlatform.macOS) {
              final bell = tester.getRect(find.byKey(UserMenuButton.bellKey));
              expect(panel.width, 400);
              expect(panel.height, 640);
              expect(panel.top - bell.bottom, 8);
              expect(find.byType(DSheetContent), findsNothing);
            } else {
              final sheet = find.byType(DSheetContent);
              expect(
                tester.widget<DSheetContent>(sheet).side,
                DSheetSide.bottom,
              );
              expect(
                tester.widget<DSheetContent>(sheet).variant,
                DSheetVariant.adaptiveMenu,
              );
              final bounds = tester.getRect(sheet);
              expect(bounds.width, 390);
              expect(bounds.top, closeTo(844 * .45, 1));
              expect(bounds.bottom, greaterThanOrEqualTo(844));
            }
            expect(find.text('Notifications'), findsOneWidget);
            expect(find.text('Mark all read'), findsOneWidget);
            final filters = find.byKey(const ValueKey('user-menu-mobile-tabs'));
            final all = _filter('all');
            expect(tester.getSize(all).height, 26);
            final inactive = _filter('replies');
            final tokens = DTokens.of(tester.element(inactive));
            if (platform == TargetPlatform.macOS) {
              final menuSurface = tester.widget<DMaterialSurface>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is DMaterialSurface &&
                      widget.depth == DSurfaceDepth.menu,
                ),
              );
              expect(
                menuSurface.color,
                Color.lerp(tokens.colors.surface, tokens.foreground, .03),
              );
            }
            final well = tester.widget<DMaterialSurface>(
              find.descendant(
                of: inactive,
                matching: find.byType(DMaterialSurface),
              ),
            );
            expect(well.depth, DSurfaceDepth.recessed);
            expect(
              well.color,
              Colors.black.withValues(alpha: dark ? .16 : .045),
            );
            expect(well.preserveColor, isTrue);
            expect(well.insetEdges, isTrue);
            final border =
                tester
                        .widget<AnimatedContainer>(
                          find.descendant(
                            of: inactive,
                            matching: find.byType(AnimatedContainer),
                          ),
                        )
                        .decoration
                    as BoxDecoration;
            expect((border.border! as Border).top.color, Colors.transparent);
            final label = tester.renderObject<RenderParagraph>(
              find.descendant(of: inactive, matching: find.text('Replies')),
            );
            expect(
              label.text.style!.color,
              Color.lerp(tokens.colors.surface, tokens.foreground, .62),
            );
            expect(
              find.descendant(of: all, matching: find.text('4')),
              findsOneWidget,
            );
            final row = find.byKey(const ValueKey('notification-row-1'));
            expect(tester.getSize(row).height, closeTo(52.05, .05));
            expect(
              tester.getSize(
                find.descendant(of: row, matching: find.byType(DAvatar)),
              ),
              const Size(30, 30),
            );
            final image = tester.widget<AvatarImage>(
              find.descendant(of: row, matching: find.byType(AvatarImage)),
            );
            expect(image.url, 'https://meta.example/avatars/mossy_mo/90.png');
            final time = tester.getRect(
              find.descendant(of: row, matching: find.text('22m')),
            );
            final dot = tester.getRect(
              find.descendant(of: row, matching: find.byType(DNotificationDot)),
            );
            expect(dot.right, time.right);
            expect(dot.top, greaterThan(time.bottom));
            expect(
              find.text('What is everyone’s sourdough hydration?'),
              findsOneWidget,
            );
            final headline = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: row,
                matching: find.textContaining('mossy_mo', findRichText: true),
              ),
            );
            expect(
              headline.text.style!.color,
              Color.lerp(tokens.colors.surface, tokens.foreground, .50),
            );
            final subject = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: row,
                matching: find.text('What is everyone’s sourdough hydration?'),
              ),
            );
            expect(
              subject.text.style!.color,
              Color.lerp(tokens.colors.surface, tokens.foreground, .90),
            );
            final readRow = find.byKey(const ValueKey('notification-row-4'));
            final readSubject = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: readRow,
                matching: find.text('Show & tell: houseplant shelfie thread'),
              ),
            );
            expect(
              readSubject.text.style!.color,
              Color.lerp(tokens.colors.surface, tokens.foreground, .50),
            );
            expect(
              tester
                  .renderObject<RenderParagraph>(
                    find.descendant(of: row, matching: find.text('22m')),
                  )
                  .text
                  .style!
                  .color,
              Color.lerp(tokens.colors.surface, tokens.foreground, .40),
            );
            final grouped = find.byKey(const ValueKey('notification-row-2'));
            expect(
              find.descendant(of: grouped, matching: find.text('3')),
              findsNothing,
            );
            expect(
              find.descendant(of: grouped, matching: find.byType(DIcon)),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: grouped,
                matching: find.textContaining('3 réponses', findRichText: true),
              ),
              findsOneWidget,
            );
            await _captureImage(
              tester,
              '${platform.name}-${dark ? 'dark' : 'light'}-${material.name}',
            );
            if (platform != TargetPlatform.macOS) {
              await tester.tap(_filter('replies'));
              await tester.pumpAndSettle();
              final shortTab = tester.getRect(find.byType(DSheetContent));
              expect(shortTab.top, closeTo(844 * .45, 1));
              expect(shortTab.height, greaterThan(844 * .5));
              await _captureImage(
                tester,
                '${platform.name}-${dark ? 'dark' : 'light'}-${material.name}-short-tab',
              );
              await tester.tap(_filter('all'));
              await tester.pumpAndSettle();
              await _expandSheet(tester);
            }
            final filtersRect = tester.getRect(filters);
            await tester.drag(
              find.descendant(
                of: find.byType(UserMenuPanel),
                matching: find.byType(ListView),
              ),
              const Offset(0, -250),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(filters), filtersRect);
            expect(shell.currentContent, same(originalRoute));
            expect(tester.takeException(), isNull);
          } finally {
            debugDisableShadows = shadowsDisabled;
          }
        });
      }
    }
  }

  testWidgets('message filter stays open and bulk-read failure can retry', (
    tester,
  ) async {
    final (shell, api) = await _mount(tester);
    final originalRoute = shell.currentContent;
    final originalTop = tester.getRect(find.byType(DSheetContent)).top;
    await tester.ensureVisible(_filter('messages'));
    await tester.pumpAndSettle();
    await tester.tap(_filter('messages'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageNotificationsSection), findsOneWidget);
    expect(find.text('A private message'), findsOneWidget);
    expect(find.byType(UserMenuPanel), findsOneWidget);
    expect(tester.getSize(find.byType(UserMenuPanel)).height, lessThan(220));
    expect(tester.getRect(find.byType(DSheetContent)).top, originalTop);
    expect(tester.getSize(find.byType(DSheetContent)).height, greaterThan(400));
    await _captureImage(tester, 'iOS-messages-fixed-height');
    expect(shell.currentContent, same(originalRoute));
    expect(api.notificationFilters.last, const [
      NotificationTypeName('private_message'),
      NotificationTypeName('group_message_summary'),
    ]);
    api.failBulkRead = true;
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(
      find.text(appL10n.couldnTMarkNotificationsAsReadTryAgain),
      findsOneWidget,
    );
    expect(
      shell.messageNotificationsFor(_site).notifications.single.isUnread,
      isTrue,
    );
    api.failBulkRead = false;
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(
      shell.messageNotificationsFor(_site).notifications.single.isUnread,
      isFalse,
    );
    expect(find.byType(DNotificationDot), findsNothing);
    expect(shell.allNotificationUnreadCount(_site), 0);
    expect(tester.takeException(), isNull);
  });

  for (final height in [380.0, 560.0]) {
    testWidgets('short viewport keeps the header fixed at $height px', (
      tester,
    ) async {
      await _mount(tester, height: height);
      await _expandSheet(tester);
      final panel = tester.getRect(find.byType(UserMenuPanel));
      expect(panel.bottom, lessThanOrEqualTo(height));
      final header = tester.getRect(find.text('Mark all read'));
      await tester.drag(
        find.descendant(
          of: find.byType(UserMenuPanel),
          matching: find.byType(ListView),
        ),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Mark all read')), header);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('physical safe area and keyboard leave the menu bounded', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await _mount(tester);
    final panel = tester.getRect(find.byType(UserMenuPanel));
    expect(panel.left, greaterThanOrEqualTo(6));
    expect(panel.bottom, lessThanOrEqualTo(844 - 300 - 6));
    expect(find.text('Mark all read').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _expandSheet(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('sheet-drag-handle')),
    const Offset(0, -400),
  );
  await tester.pumpAndSettle();
}

Finder _filter(String id) => find.ancestor(
  of: find.byKey(ValueKey('user-menu-tab-$id')),
  matching: find.byType(DToggle),
);

Future<(ShellController, _MenuApi)> _mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
  bool dark = false,
  DAppearanceMaterial material = DAppearanceMaterial.standard,
  double height = 844,
  String? paletteId,
}) async {
  tester.view.physicalSize = Size(
    platform == TargetPlatform.macOS ? 1000 : 390,
    height,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 7, username: 'reader');
  final api = _MenuApi(user);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.accountActivity.refresh(shell.currentInstance!);
  addTearDown(shell.dispose);
  final base =
      (paletteId == null
              ? dark
                    ? AppTheme.dark
                    : AppTheme.light
              : AppTheme.fromPalette(
                  forumThemePresets
                      .firstWhere((p) => p.id == paletteId)
                      .resolve(dark ? Brightness.dark : Brightness.light),
                ))
          .copyWith(platform: platform);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: ShellScope(
        controller: shell,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => DToaster(child: child!),
          theme: DMaterialTheme.apply(
            base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Lato')),
            material,
          ),
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
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(UserMenuButton.bellKey));
  await tester.pumpAndSettle();
  return (shell, api);
}

class _MenuApi extends FakeDiscourseApi {
  _MenuApi(DiscourseUser user)
    : super(
        user: user,
        replyNotificationList: const [],
        totals: NotificationTotals(
          groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
            '2': 3,
            '6': 1,
          }),
        ),
        notificationList: [
          DiscourseNotification.fromJson({
            'id': 1,
            'notification_type': 2,
            'created_at': DateTime.now()
                .subtract(const Duration(minutes: 22))
                .toIso8601String(),
            'fancy_title': 'What is everyone’s sourdough hydration?',
            'acting_user_avatar_template': '/avatars/mossy_mo/{size}.png',
            'data': const {'display_username': 'mossy_mo'},
          }),
          for (var id = 2; id <= 20; id++)
            DiscourseNotification.test(
              id: id,
              typeId: NotificationTypeId(id == 3 ? 2 : 9),
              read: id > 3,
              title: 'Show & tell: houseplant shelfie thread',
              createdAt: DateTime.now().subtract(const Duration(hours: 1)),
              data: id == 2
                  ? const {
                      'display_username': '3 réponses',
                      'original_username': 'sam',
                    }
                  : id == 3
                  ? const {
                      'consolidated_count': 4,
                      'display_username': '4 replies',
                      'original_username': 'sam',
                    }
                  : const {'count': 4},
            ),
        ],
        otherNotificationList: const [
          DiscourseNotification.test(
            id: 30,
            typeId: NotificationTypeId(6),
            title: 'A private message',
            data: {'display_username': 'sam'},
          ),
        ],
      );
  bool failBulkRead = false;
  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => markedTypesRead.isEmpty ? totals! : const NotificationTotals();
  @override
  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async {
    if (failBulkRead) throw StateError('Offline');
    await super.markNotificationsRead(
      siteUrl: siteUrl,
      apiKey: apiKey,
      types: types,
      clientId: clientId,
    );
  }
}

Future<void> _captureImage(WidgetTester tester, String name) async {
  final directory = Platform.environment['NOTIFICATION_PARITY_CAPTURES'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    final bounds = tester
        .getRect(_filter('all'))
        .shift(-tester.getRect(find.byKey(_capture)).topLeft);
    final detail = await (boundary.debugLayer! as OffsetLayer).toImage(
      bounds.inflate(12),
      pixelRatio: 2,
    );
    try {
      final detailBytes = await detail.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await File(
        '$directory/$name-all-filter.png',
      ).writeAsBytes(detailBytes!.buffer.asUint8List());
    } finally {
      detail.dispose();
    }
    image.dispose();
  });
}
