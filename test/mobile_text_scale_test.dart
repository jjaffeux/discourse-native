import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'shared scale reaches titles, reading, controls and overlays in $brightness',
      (tester) async {
        final baseline = switch (defaultTargetPlatform) {
          TargetPlatform.iOS || TargetPlatform.android => 17.0,
          _ => 14.0,
        };
        final baselineScale = baseline / 14;
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettingsController(
          store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
        );
        addTearDown(settings.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            builder: (context, child) =>
                AppTextScaleRegion(controller: settings, child: child!),
            home: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TopicListRow(
                    siteUrl: 'https://example.invalid',
                    topic: const Topic(
                      id: 1,
                      title: 'Conference Days Single Source of Truth-Seville',
                      slug: 'conference-days',
                      postsCount: 20,
                      lastPosterUsername: 'markdoerr',
                      excerpt:
                          'Hey team! The countdown is on until we see each other in Seville!',
                      tags: [
                        TopicTag(name: '2026-seville'),
                        TopicTag(name: 'conference-days'),
                      ],
                    ),
                    onTap: () {},
                  ),
                  const DText('Page title', variant: DTextVariant.h3),
                  const DText('Native reading'),
                  const CookedHtml(html: '<p>Cooked reading</p>'),
                  for (final size in DButtonSize.values)
                    DButton(
                      label: Text(size.name),
                      size: size,
                      onPressed: () {},
                    ),
                  DSelect<String>(
                    value: 'latest',
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'latest', child: Text('Latest')),
                      DropdownMenuItem(value: 'new', child: Text('New')),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        for (final zoom in AppTextScale.values) {
          await settings.setTextScale(zoom);
          await tester.pumpAndSettle();
          final native = _paragraph(tester, 'Native reading');
          final cooked = _paragraph(tester, 'Cooked reading');
          final page = _paragraph(tester, 'Page title');
          final title = _paragraph(
            tester,
            'Conference Days Single Source of Truth-Seville',
          );
          expect(native.text.style!.fontSize, 14);
          expect(page.text.style!.fontSize, 22);
          expect(page.text.style!.height! * 22, 27.5);
          expect(title.text.style!.fontSize, 14.5);
          expect(title.text.style!.height! * 14.5, closeTo(19.575, .001));
          expect(
            native.textScaler.scale(14),
            closeTo(baseline * zoom.factor, .001),
          );
          expect(
            cooked.textScaler.scale(cooked.text.style!.fontSize!),
            closeTo(native.textScaler.scale(14), .001),
          );
          for (final (size, base) in [
            ('small', 12.5),
            ('regular', 13.0),
            ('large', 14.0),
          ]) {
            final label = _paragraph(tester, size);
            expect(label.text.style!.fontSize, base);
            expect(
              label.textScaler.scale(base.toDouble()),
              closeTo(base * baselineScale * zoom.factor, .001),
            );
            expect(label.didExceedMaxLines, isFalse);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text('Latest'));
        await tester.tap(find.text('Latest'));
        await tester.pumpAndSettle();
        final option = _paragraph(tester, 'New');
        expect(option.text.style!.fontSize, 13);
        expect(option.textScaler.scale(13), closeTo(26 * baselineScale, .001));
        expect(option.didExceedMaxLines, isFalse);
        await tester.tap(find.text('New').last);
        await tester.pumpAndSettle();
        await settings.resetTextScale();
        await tester.pumpAndSettle();
        expect(
          _paragraph(tester, 'Native reading').textScaler.scale(14),
          baseline,
        );
        expect(settings.textScale, AppTextScale.percent100);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets(
    'mobile baseline respects minimum and larger system text sizes',
    (tester) async {
      final settings = AppSettingsController(
        store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
      );
      addTearDown(settings.dispose);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final (systemScale, expectedSize) in [
        (14 / 17, 14.0),
        (1.0, 17.0),
        (2.0, 34.0),
      ]) {
        tester.platformDispatcher.textScaleFactorTestValue = systemScale;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) =>
                AppTextScaleRegion(controller: settings, child: child!),
            home: const Column(
              children: [
                DText('Native reading'),
                CookedHtml(html: '<p>Cooked reading</p>'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['Native reading', 'Cooked reading']) {
          final paragraph = _paragraph(tester, label);
          expect(
            paragraph.textScaler.scale(paragraph.text.style!.fontSize!),
            closeTo(expectedSize, .001),
            reason: '$label at $systemScale',
          );
        }
        expect(settings.textScale, AppTextScale.percent100);
        expect(tester.takeException(), isNull);
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find
          .byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          )
          .last,
    );
