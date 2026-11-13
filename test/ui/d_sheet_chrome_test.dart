import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/composer_sheet_header.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['SHEET_CHROME_CAPTURE_DIR'] == null) return;
    for (final (family, asset) in [
      ('Lato', 'Lato-Regular.ttf'),
      ('Open Sans', 'OpenSans.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$asset'))).load();
    }
  });
  for (final status in [false, true]) {
    testWidgets('profile identity clears the handle (status=$status)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Center(
              child: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.menu,
                card: true,
                showCloseButton: false,
                children: [
                  UserCardHeader(
                    card: const UserCard(
                      username: 'reader',
                      name: 'A long display name across the profile card',
                    ),
                    siteUrl: 'https://example.com',
                    mobileSheet: true,
                    statusContent: status
                        ? const Text('Working from home')
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final handle = tester.getRect(
        find.byKey(const ValueKey('sheet-drag-handle')),
      );
      expect(
        handle.bottom,
        lessThan(
          tester
              .getRect(find.text('A long display name across the profile card'))
              .top,
        ),
      );
      if (status) {
        expect(
          handle.bottom,
          lessThan(tester.getRect(find.text('Working from home')).top),
        );
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final variant in [
      DSheetVariant.standard,
      DSheetVariant.menu,
      DSheetVariant.adaptiveMenu,
    ]) {
      for (final customHeader in [false, true]) {
        testWidgets(
          '$platform $variant custom=$customHeader keeps chrome at the sheet edge',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
            tester.view.viewPadding = const FakeViewPadding(
              top: 47,
              bottom: 34,
            );
            addTearDown(tester.view.reset);
            for (final (scale, direction) in [
              (1.0, TextDirection.ltr),
              (2.0, TextDirection.ltr),
              (2.0, TextDirection.rtl),
            ]) {
              await tester.pumpWidget(
                MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.dark.copyWith(
                    platform: platform,
                    textTheme:
                        Platform.environment['SHEET_CHROME_CAPTURE_DIR'] == null
                        ? null
                        : AppTheme.dark.textTheme.apply(fontFamily: 'Lato'),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                      textDirection: direction,
                      child: DTouchTargets(child: child!),
                    ),
                  ),
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => DButton(
                        label: const Text('Open'),
                        onPressed: () => showDSheet<void>(
                          context: context,
                          side: DSheetSide.bottom,
                          variant: variant,
                          builder: (context, sheet) => DSheetContent(
                            side: DSheetSide.bottom,
                            variant: variant,
                            showCloseButton: !customHeader,
                            scrollWholeSheet: false,
                            children: [
                              if (customHeader)
                                const ComposerSheetHeader(title: 'Sheet title')
                              else
                                const DSheetHeader(
                                  children: [
                                    DSheetTitle(child: Text('Sheet title')),
                                  ],
                                ),
                              const DSheetBody(
                                child: SizedBox(
                                  height: 160,
                                  child: Text('Sheet content'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open'));
              await tester.pumpAndSettle();
              final bounds = tester.getRect(find.byType(DSheetContent));
              final handle = tester.getRect(
                find.byKey(const ValueKey('sheet-drag-handle')),
              );
              final close = find.byTooltip('Close');
              final closeBounds = tester.getRect(close);
              expect(handle.top - bounds.top, closeTo(8, .01));
              expect(handle.center.dx, closeTo(bounds.center.dx, .01));
              expect(closeBounds.top - bounds.top, closeTo(12, .01));
              expect(bounds.right - closeBounds.right, closeTo(12, .01));
              expect(closeBounds.width, closeTo(closeBounds.height, .01));
              expect(
                closeBounds.width,
                scale == 1 ? closeTo(44, .01) : greaterThan(44),
              );
              expect(
                tester.getRect(find.byType(DSheetTitle)).right,
                lessThan(closeBounds.left),
              );
              await _capture(
                tester,
                '${platform.name}-${variant.name}-$customHeader-$scale-${direction.name}',
              );
              await tester.tap(close);
              await tester.pumpAndSettle();
              expect(find.byType(DSheetContent), findsNothing);
              expect(tester.takeException(), isNull);
            }
          },
          variant: TargetPlatformVariant.only(platform),
        );
      }
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SHEET_CHROME_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
