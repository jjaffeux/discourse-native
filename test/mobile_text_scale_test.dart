import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'mobile baseline reaches reading, controls and overlays in $brightness',
      (tester) async {
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
          expect(
            native.textScaler.scale(16),
            closeTo(19.2 * zoom.factor, .001),
          );
          expect(
            cooked.textScaler.scale(cooked.text.style!.fontSize!),
            closeTo(native.textScaler.scale(16), .001),
          );
          for (final (size, base) in [
            ('small', 14),
            ('regular', 15),
            ('large', 16),
          ]) {
            final label = _paragraph(tester, size);
            expect(
              label.textScaler.scale(base.toDouble()),
              closeTo(base * 1.2 * zoom.factor, .001),
            );
            expect(label.didExceedMaxLines, isFalse);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text('Latest'));
        await tester.tap(find.text('Latest'));
        await tester.pumpAndSettle();
        final option = _paragraph(tester, 'New');
        expect(option.textScaler.scale(15), closeTo(36, .001));
        expect(option.didExceedMaxLines, isFalse);
        await tester.tap(find.text('New').last);
        await tester.pumpAndSettle();
        await settings.resetTextScale();
        await tester.pumpAndSettle();
        expect(_paragraph(tester, 'Native reading').textScaler.scale(16), 19.2);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find
          .byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          )
          .last,
    );
