import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('Lato', 'Lato-Regular.ttf'),
      ('Open Sans', 'OpenSans.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$asset'))).load();
    }
  });

  for (final imperative in [false, true]) {
    for (final ratio in [1.0, 3.0]) {
      testWidgets('bottom drawer clears the keyboard and clips its bleed '
          '(imperative: $imperative, ratio: $ratio)', (tester) async {
        tester.view.physicalSize = const Size(390, 844) * ratio;
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.reset);
        Widget content() =>
            DDrawerContent(height: 440, children: [DInput(hintText: 'Filter')]);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: imperative
                  ? Builder(
                      builder: (context) => DButton(
                        onPressed: () => showDDrawer<void>(
                          context: context,
                          builder: (_, _) => content(),
                        ),
                        label: const Text('Open'),
                      ),
                    )
                  : DDrawer<void>(
                      trigger: DDrawerTrigger(
                        builder: (_, open) =>
                            DButton(onPressed: open, label: const Text('Open')),
                      ),
                      content: content(),
                    ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final drawer = find.byType(DDrawerContent);
        expect(tester.getRect(drawer).bottom, 844);
        final input = find.byType(EditableText);
        await tester.enterText(input, 'dev');
        tester.view.viewInsets = FakeViewPadding(bottom: 300 * ratio);
        await tester.pumpAndSettle();
        expect(tester.getRect(drawer).bottom, 543);
        final clip = find
            .ancestor(of: drawer, matching: find.byType(ClipRect))
            .first;
        expect(tester.getRect(clip).bottom, 543);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        expect(tester.getRect(drawer).bottom, 844);
        expect(tester.widget<EditableText>(input).controller.text, 'dev');
        expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final variant in [DSheetVariant.standard, DSheetVariant.menu]) {
      testWidgets(
        '$variant clears the keyboard on $platform without an inset',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(platform: platform),
              home: Scaffold(
                body: DSheet<void>(
                  trigger: DSheetTrigger(
                    builder: (_, open) =>
                        DButton(onPressed: open, label: const Text('Open')),
                  ),
                  content: DSheetContent(
                    side: DSheetSide.bottom,
                    variant: variant,
                    children: const [DSheetBody(child: SizedBox(height: 200))],
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final sheet = find.byType(DSheetContent);
          expect(tester.getRect(sheet).bottom, 844);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).bottom, 543);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(tester.getRect(sheet).bottom, 844);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final tags in [false, true]) {
    testWidgets('${tags ? 'tag' : 'category'} sheet field aligns with rows '
        'and clears the keyboard by one pixel', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
      tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark.copyWith(
            platform: TargetPlatform.iOS,
            textTheme: AppTheme.dark.textTheme.apply(fontFamily: 'Lato'),
          ),
          home: Scaffold(
            body: tags
                ? TopicTagSelector(
                    selectedTags: const [],
                    search: (_) async => const TopicTagSearch(
                      tags: [TopicTag(id: 1, name: 'dev')],
                    ),
                    onChanged: (_) {},
                  )
                : TopicCategorySelector(
                    siteUrl: 'https://example.invalid',
                    categories: const [
                      TopicCategory(id: 1, name: 'dev', color: '333333'),
                      TopicCategory(id: 2, name: 'todo', color: 'CC44AA'),
                    ],
                    selected: null,
                    onSelected: (_) {},
                  ),
          ),
        ),
      );
      await tester.tap(find.byType(DButton).first);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      tester.view.padding = const FakeViewPadding(top: 141);
      await tester.pumpAndSettle();
      await capture(tester, tags ? 'tags' : 'categories');
      final sheet = tester.getRect(find.byType(DSheetContent));
      expect(844 - 300 - sheet.bottom, closeTo(1, .01));
      final field = tester.getRect(find.byType(DInputGroup));
      final row = tester.getRect(
        find.byKey(
          tags
              ? const ValueKey(('tag-selector-option', 'dev'))
              : const ValueKey(('category-selector-option', 1)),
        ),
      );
      expect(field.left, row.left);
      expect(field.right, row.right);
      expect(field.height, 44);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).style.fontSize,
        16,
      );
      final header = tester.getRect(find.byType(DSheetHeader));
      expect(field.top - header.bottom, 6);
      final close = find.byTooltip('Close');
      final button = tester.widget<DButton>(
        find.byWidgetPredicate(
          (widget) => widget is DButton && widget.tooltip == 'Close',
        ),
      );
      expect(button.variant, DButtonVariant.quiet);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SHEET_PICKER_REVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      tester.view.physicalSize.width.round(),
      tester.view.physicalSize.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
