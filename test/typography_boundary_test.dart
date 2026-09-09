import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'controls and reading keep their roles at every zoom in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettingsController(
          store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
        );
        addTearDown(settings.dispose);
        final theme = brightness == Brightness.dark
            ? AppTheme.dark
            : AppTheme.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) =>
                AppTextScaleRegion(controller: settings, child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DText(
                        'Page title',
                        variant: DTextVariant.h3,
                        headingLevel: 1,
                      ),
                      const DText(
                        'Section title',
                        variant: DTextVariant.large,
                        headingLevel: 2,
                      ),
                      const DText('Native reading'),
                      const DText(
                        'Inline code',
                        variant: DTextVariant.inlineCode,
                      ),
                      const CookedHtml(html: '<p>Reading a discussion.</p>'),
                      for (final size in DButtonSize.values)
                        DButton(
                          label: Text('Native ${size.name}'),
                          onPressed: () {},
                          size: size,
                        ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Material action'),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Outlined action'),
                      ),
                      MenuItemButton(
                        onPressed: () {},
                        child: const Text('Menu action'),
                      ),
                      ListTile(
                        title: const Text('Navigation item'),
                        subtitle: const Text('Metadata'),
                        onTap: () {},
                      ),
                      DSelect<String>(
                        value: 'latest',
                        items: const [
                          DropdownMenuItem(
                            value: 'latest',
                            child: Text('Latest topics'),
                          ),
                          DropdownMenuItem(
                            value: 'new',
                            child: Text('New topics'),
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                      DSelectField<String>(
                        initialValue: 'all',
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All categories'),
                          ),
                          DropdownMenuItem(
                            value: 'help',
                            child: Text('Help and support'),
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                      PopupMenuButton<String>(
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'all',
                            child: Text('Menu destination'),
                          ),
                        ],
                        child: const Text('Open popup'),
                      ),
                      DataTable(
                        columns: const [
                          DataColumn(label: Text('Topic column')),
                          DataColumn(label: Text('Replies column')),
                        ],
                        rows: const [
                          DataRow(
                            cells: [
                              DataCell(Text('Table discussion')),
                              DataCell(Text('42')),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (final zoom in AppTextScale.values) {
          await settings.setTextScale(zoom);
          await tester.pumpAndSettle();
          for (final label in [
            'Inline code',
            'Native small',
            'Native regular',
            'Native large',
            'Material action',
            'Outlined action',
            'Menu action',
            'Navigation item',
            'Latest topics',
            'All categories',
            'Topic column',
            'Replies column',
            'Table discussion',
            '42',
          ]) {
            final paragraph = _paragraph(tester, label);
            // base-nova's small button is text-[0.8rem] with 22.4px leading.
            final (fontSize, lineHeight) = label == 'Native small'
                ? (12.8, 22.4)
                : (14.0, 20.0);
            expect(
              paragraph.text.style!.fontSize,
              fontSize,
              reason: '$label at $zoom',
            );
            expect(
              paragraph.text.style!.height,
              closeTo(lineHeight / fontSize, 0.001),
              reason: label,
            );
            expect(
              paragraph.textScaler.scale(fontSize),
              closeTo(fontSize * settings.textScaleFactor, 0.001),
              reason: label,
            );
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '$label at $zoom',
            );
          }
          expect(
            _paragraph(tester, 'Reading a discussion.').text.style!.fontSize,
            16 * settings.textScaleFactor,
          );
          expect(_paragraph(tester, 'Native reading').text.style!.fontSize, 16);
          expect(
            _paragraph(tester, 'Native reading').textScaler.scale(16),
            16 * settings.textScaleFactor,
          );
          expect(_paragraph(tester, 'Page title').text.style!.fontSize, 24);
          expect(_paragraph(tester, 'Section title').text.style!.fontSize, 18);
          expect(_paragraph(tester, 'Metadata').text.style!.fontSize, 12);
          expect(tester.takeException(), isNull, reason: '$zoom');
        }
        // Popup and dropdown routes live in overlays. They must retain the root
        // zoom and the same role as the closed controls.
        await tester.ensureVisible(find.text('Latest topics'));
        await tester.tap(find.text('Latest topics'));
        await tester.pumpAndSettle();
        final option = _paragraph(tester, 'New topics');
        expect(option.text.style!.fontSize, 14);
        expect(option.textScaler.scale(14), 28);
        expect(option.didExceedMaxLines, isFalse);
        await tester.tap(find.text('New topics').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Open popup'));
        await tester.tap(find.text('Open popup'));
        await tester.pumpAndSettle();
        final popup = _paragraph(tester, 'Menu destination');
        expect(popup.text.style!.fontSize, 14);
        expect(popup.textScaler.scale(14), 28);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('tabs grow for zoom and nonlinear platform text scaling', (
    tester,
  ) async {
    final settings = AppSettingsController(
      store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
    );
    addTearDown(settings.dispose);
    await settings.setTextScale(AppTextScale.percent200);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const _PlatformScaler()),
          child: AppTextScaleRegion(controller: settings, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ForumTabsBar(
              forumName: 'Forum',
              items: const [ForumTabItem(id: 'latest', title: 'Latest')],
              selectedId: 'latest',
              onAdd: () {},
              onSelect: (_) {},
              onClose: (_) {},
              onReorder: (_, _) {},
              onCloseOthers: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = _paragraph(tester, 'Latest');
    final barRect = tester.getRect(
      find.byKey(const ValueKey('forum-tabs-bar')),
    );
    final labelRect = tester.getRect(find.text('Latest'));
    expect(label.text.style!.fontSize, 14);
    expect(label.textScaler.scale(14), 36);
    expect(barRect.height, greaterThan(ForumTabsBar.height));
    expect(barRect.contains(labelRect.topLeft), isTrue);
    expect(barRect.contains(labelRect.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find
          .byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          )
          .last,
    );

final class _PlatformScaler extends TextScaler {
  const _PlatformScaler();
  @override
  double scale(double fontSize) => fontSize + 4;
  @override
  double get textScaleFactor => 1.25;
}
