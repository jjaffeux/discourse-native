// Run with flutter test tool/chart_visual_export.dart --no-pub.
// Requires the documented, locally downloaded reference font files.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/styleguide/examples/chart_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'export actual registered chart examples and migrated production fixtures',
    (tester) async {
      const directory = String.fromEnvironment(
        'CHART_EXPORT_DIR',
        defaultValue: '/tmp/chart-browser-evidence/flutter',
      );
      await tester.runAsync(() async {
        await Directory(directory).create(recursive: true);
        for (final entry in {
          'Geist': 'Geist',
          'monospace': 'GeistMono',
          'Noto Sans Arabic': 'NotoSansArabic',
        }.entries) {
          final bytes = await File(
            '/tmp/chart-browser-evidence/fonts/${entry.value}.ttf',
          ).readAsBytes();
          await (FontLoader(
            entry.key,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> capture(
        String name,
        WidgetBuilder builder, {
        double width = 509,
        bool dark = false,
        bool rtl = false,
        double scale = 1,
        bool inspect = false,
        bool reference = true,
      }) async {
        final key = GlobalKey();
        final base = dark ? AppTheme.dark : AppTheme.light;
        final colors = base.colorScheme.copyWith(
          primary: const Color(0xff2563eb),
          tertiary: const Color(0xff60a5fa),
          onSurface: dark ? const Color(0xfffafafa) : const Color(0xff171717),
          onSurfaceVariant: const Color(0xff737373),
        );
        final tokens = DTokens.fromTheme(base).copyWith(
          colors: colors,
          background: dark ? const Color(0xff0a0a0a) : Colors.white,
          surface: dark ? const Color(0xff171717) : Colors.white,
          muted: dark ? const Color(0xff262626) : const Color(0xfff5f5f5),
          border: dark ? const Color(0x1affffff) : const Color(0xffe5e5e5),
          radius: 10,
        );
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(
            fontFamily: rtl ? 'Noto Sans Arabic' : 'Geist',
          ),
          extensions: reference ? [tokens] : base.extensions.values,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: RepaintBoundary(
                      key: key,
                      child: ColoredBox(
                        color: reference
                            ? tokens.background
                            : base.colorScheme.surface,
                        child: SizedBox(
                          width: width,
                          child: Builder(builder: builder),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (inspect) {
          final plot = find.byWidgetPredicate((w) => w is DBarChart).first;
          final rect = tester.getRect(plot);
          await tester.tapAt(
            rect.topLeft +
                Offset(
                  rect.width * 2.5 / 6,
                  (key.currentContext!.findRenderObject()! as RenderBox)
                          .size
                          .height *
                      .5,
                ),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: name);
        final metrics = <Map<String, Object?>>[];
        for (final element
            in find
                .descendant(of: find.byKey(key), matching: find.byType(Text))
                .evaluate()) {
          final text = element.widget as Text;
          final box = element.findRenderObject();
          if (box is RenderBox) {
            metrics.add({
              'text': text.data,
              'width': box.size.width,
              'height': box.size.height,
              'font': DefaultTextStyle.of(
                element,
              ).style.merge(text.style).toString(),
            });
          }
        }
        await tester.runAsync(
          () => File(
            '$directory/$name-metrics.json',
          ).writeAsString(jsonEncode(metrics)),
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$directory/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }

      for (final dark in [false, true]) {
        for (var i = 0; i < chartExamples.examples.length; i++) {
          await capture(
            '${dark ? 'dark' : 'light'}-$i',
            chartExamples.examples[i].builder,
            dark: dark,
            rtl: i == 8,
            width: i == 5
                ? 640
                : i == 8
                ? 558
                : 509,
            inspect: i == 3 || i == 4,
          );
        }
      }
      await capture(
        'narrow-rtl-200',
        chartExamples.examples[8].builder,
        width: 260,
        dark: true,
        rtl: true,
        scale: 2,
        inspect: true,
      );
      await capture(
        'narrow-rtl-100',
        chartExamples.examples[8].builder,
        width: 245,
        dark: true,
        rtl: true,
        inspect: true,
      );
      for (final dark in [false, true]) {
        await capture(
          'poll-${dark ? 'dark' : 'light'}',
          (_) => const PollCard(
            poll: Poll(
              name: 'review',
              voters: 10,
              options: [
                PollOption(id: 'a', html: 'Desktop', votes: 7),
                PollOption(id: 'b', html: 'Mobile', votes: 3),
              ],
            ),
            signedIn: true,
            archived: false,
          ),
          width: 509,
          dark: dark,
          reference: false,
        );
        await capture(
          'users-${dark ? 'dark' : 'light'}',
          (_) => SizedBox(
            height: 400,
            child: UsersPage(
              siteUrl: 'https://chart-review.invalid',
              columnWidthStore: UserDirectoryColumnWidthStore(
                persistence: _MemoryWidths(),
              ),
              data: const UsersPageData(
                loaded: true,
                totalRows: 2,
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
                    id: 1,
                    user: UserDirectoryUser(id: 1, username: 'local_alpha'),
                    values: {'likes_received': 290},
                  ),
                  UserDirectoryItem(
                    id: 2,
                    user: UserDirectoryUser(id: 2, username: 'local_beta'),
                    values: {'likes_received': 145},
                  ),
                ],
              ),
            ),
          ),
          width: 760,
          dark: dark,
          reference: false,
        );
      }
    },
  );
}

class _MemoryWidths implements UserDirectoryColumnWidthPersistence {
  @override
  Future<String?> readWidths({required String siteUrl}) async => null;
  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async => true;
}
