import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('sidebar-count-capture');

void main() {
  testWidgets('sidebar counts follow the muted palette through theme changes', (
    tester,
  ) async {
    final directory = Platform.environment['SIDEBAR_COUNT_REVIEW_DIR'];
    if (directory != null) {
      await (FontLoader(
        'Open Sans',
      )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
    }
    final themes = {
      'light': AppTheme.forBrightness(
        Brightness.light,
        fontFamily: 'Open Sans',
      ),
      'dark': AppTheme.forBrightness(Brightness.dark, fontFamily: 'Open Sans'),
      for (final id in ['dracula', 'shades-of-blue'])
        id: AppTheme.fromPalette(
          forumThemePresets
              .firstWhere((theme) => theme.id == id)
              .resolve(
                forumThemePresets
                    .firstWhere((theme) => theme.id == id)
                    .brightness,
              ),
          fontFamily: 'Open Sans',
        ),
    };
    for (final entry in themes.entries) {
      final theme = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationStyle: AnimationStyle.noAnimation,
          home: Center(
            child: RepaintBoundary(
              key: _capture,
              child: SizedBox(
                width: 280,
                height: 240,
                child: DSidebarProvider(
                  child: DSidebar(
                    collapsible: DSidebarCollapsible.none,
                    child: DSidebarContent(
                      children: [
                        DSidebarGroup(
                          child: DSidebarMenu(
                            children: [
                              for (final row in [
                                ('topics', 'Topics', 2696, false),
                                ('drafts', 'Drafts', 55, true),
                                ('category-alerts', 'alerts', 53, false),
                                ('tag-design', 'design', 3, false),
                              ])
                                SidebarDestinationTile(
                                  destination: SidebarDestination(
                                    id: row.$1,
                                    label: row.$2,
                                    icon: DIcons.tag,
                                    onTap: () {},
                                  ),
                                  selected: row.$4,
                                  badge: SidebarBadge.count(row.$3),
                                  onTap: () {},
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      void checkCounts() {
        for (final count in ['2696', '55', '53', '3']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(count),
          );
          expect(paragraph.text.style!.color, theme.discourse.whisper);
          expect(
            paragraph.text.style!.color,
            isNot(DTokens.fromTheme(theme).foreground),
          );
        }
      }

      checkCounts();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('alerts')));
      await tester.pumpAndSettle();
      checkCounts();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      if (directory != null) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_capture),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
            '$directory/sidebar-counts-${entry.key}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
