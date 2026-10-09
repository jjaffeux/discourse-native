import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/global_search_fixtures.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment.containsKey('SEARCH_INPUT_CAPTURE_DIR')) {
      final systemFont = File('/System/Library/Fonts/SFNS.ttf');
      final font = await systemFont.exists()
          ? (await systemFont.readAsBytes()).buffer.asByteData()
          : await rootBundle.load('assets/fonts/Lato-Regular.ttf');
      await (FontLoader('SearchReference')..addFont(Future.value(font))).load();
    }
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('search chrome dark=$dark scale=$scale', (tester) async {
        tester.view.physicalSize = const Size(800, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final shell = createGlobalSearchFixtureController();
        addTearDown(shell.dispose);
        await shell.load();
        final boundary = GlobalKey();
        final theme = dark ? AppTheme.dark : AppTheme.light;
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  platform: TargetPlatform.macOS,
                  textTheme: theme.textTheme.apply(
                    fontFamily: 'SearchReference',
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 600,
                        child: ForumSearch(
                          size: DControlSize.field,
                          showNavigationControls: false,
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
        final group = find.byType(DInputGroup);
        final before = tester.getRect(group);
        final editor = find.descendant(
          of: find.byKey(ForumSearch.inputKey),
          matching: find.byType(EditableText),
        );
        final editorBefore = tester.getRect(editor);
        final icon = find.descendant(
          of: group,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DIcon && widget.icon == DIcons.magnifyingGlass,
          ),
        );
        expect(before.height, 36 + (scale - 1) * 19.5);
        expect(tester.getRect(icon).left - before.left, 15);
        expect(editorBefore.left - tester.getRect(icon).right, 8);
        expect(tester.widget<EditableText>(editor).style.fontSize, 13);
        expect(
          tester
              .widget<DShortcutKeycaps>(find.byType(DShortcutKeycaps))
              .compact,
          isTrue,
        );
        await _capture(tester, boundary, '$dark-$scale-closed');

        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byKey(ForumSearch.panelKey));
        expect(panel.left, before.left);
        expect(panel.width, before.width);
        expect(panel.top, before.top - 5);
        expect(tester.getRect(group), before);
        expect(tester.getRect(editor), editorBefore);
        expect(
          tester
              .widget<DPopoverContent>(find.byKey(ForumSearch.panelKey))
              .cornerRadius,
          14,
        );
        expect(tester.widget<DInputGroup>(group).borderless, isTrue);
        await _capture(tester, boundary, '$dark-$scale-open');

        await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        final clear = find.byKey(const ValueKey('forum-search-clear'));
        expect(tester.getSize(clear), Size.square(12 * scale));
        expect(before.right - tester.getRect(clear).right, 15);
        await _capture(tester, boundary, '$dark-$scale-query');

        shell.globalSearch.completeFilter(
          const GlobalSearchCondition(
            filterId: 'category',
            operator: 'any',
            value: ['support'],
          ),
        );
        await tester.pumpAndSettle();
        final chip = find.byType(SearchFilterChip).first;
        expect(tester.getRect(icon).right, lessThan(tester.getRect(chip).left));
        final viewport = find
            .ancestor(of: chip, matching: find.byType(DScrollArea))
            .first;
        expect(
          tester.getRect(viewport).right,
          lessThan(tester.getRect(editor).left),
        );
        await _capture(tester, boundary, '$dark-$scale-filter');
        shell.globalSearch.setQuery('');
        await tester.pumpAndSettle();
        expect(find.text('Add words or filters…'), findsOneWidget);
        expect(clear, findsOneWidget);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(shell.globalSearch.conditions, isEmpty);
        expect(find.text('Search this forum'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['SEARCH_INPUT_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
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
