import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('table-background-capture');
typedef _Frame = ({ByteData pixels, int width, int height});

Future<_Frame> _capture(WidgetTester tester, String name) async =>
    (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final image = await boundary.toImage();
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final directory = Platform.environment['TABLE_BACKGROUND_EXPORT_DIR'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          await File(
            '$directory/$name.png',
          ).writeAsBytes(png.buffer.asUint8List());
        }
        return (pixels: pixels, width: image.width, height: image.height);
      } finally {
        image.dispose();
      }
    }))!;

Color _pixel(WidgetTester tester, _Frame frame, Offset global) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final local = boundary.globalToLocal(global);
  final offset = (local.dy.floor() * frame.width + local.dx.floor()) * 4;
  return Color.fromARGB(
    frame.pixels.getUint8(offset + 3),
    frame.pixels.getUint8(offset),
    frame.pixels.getUint8(offset + 1),
    frame.pixels.getUint8(offset + 2),
  );
}

void _expectColor(Color actual, Color expected) {
  final a = actual.toARGB32();
  final e = expected.toARGB32();
  for (final shift in [0, 8, 16, 24]) {
    expect((a >> shift) & 255, closeTo((e >> shift) & 255, 2));
  }
}

void main() {
  testWidgets(
    'row highlights finish independently during quick pointer moves',
    (tester) async {
      final theme = ThemeData(scaffoldBackgroundColor: Colors.white);
      final tokens = DTokens.fromTheme(theme).copyWith(muted: Colors.black);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(extensions: [tokens]),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _captureKey,
                child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                    width: 300,
                    child: DTable(
                      columnWidths: const {
                        0: FixedColumnWidth(100),
                        1: FixedColumnWidth(100),
                      },
                      body: DTableBody(
                        rows: [
                          for (var row = 0; row < 3; row++)
                            DTableRow(
                              cells: [
                                DTableCell(
                                  key: ValueKey('rapid-$row'),
                                  child: Text('Row $row'),
                                ),
                                const DTableCell(child: Text('Last')),
                              ],
                            ),
                        ],
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
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(799, 599));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Row 0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await mouse.moveTo(tester.getCenter(find.text('Row 1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await mouse.moveTo(tester.getCenter(find.text('Row 2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final frame = await _capture(tester, 'independent-row-fades');
      final point =
          tester.getTopLeft(find.byKey(const ValueKey('rapid-0'))) +
          const Offset(2, 2);
      _expectColor(_pixel(tester, frame, point), Colors.white);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover and selected states use live multiplied alpha with reduced motion',
    (tester) async {
      final colors = ThemeData().colorScheme;
      var tokens = DTokens.fromTheme(
        ThemeData(),
      ).copyWith(muted: const Color(0x80334455));
      Widget host({bool selected = false}) {
        final theme = ThemeData(colorScheme: colors, extensions: [tokens]);
        return MaterialApp(
          theme: theme,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: _captureKey,
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: SizedBox(
                      width: 300,
                      child: DTable(
                        body: DTableBody(
                          rows: [
                            DTableRow(
                              selected: selected,
                              cells: const [
                                DTableCell(
                                  key: ValueKey('live-muted'),
                                  child: Text('Row'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Offset point() =>
          tester.getTopLeft(find.byKey(const ValueKey('live-muted'))) +
          const Offset(2, 2);
      final background = ThemeData(colorScheme: colors).scaffoldBackgroundColor;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(799, 599));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Row')));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      final hovered = await _capture(tester, 'live-muted-hovered');
      _expectColor(
        _pixel(tester, hovered, point()),
        Color.alphaBlend(
          tokens.muted.withValues(alpha: tokens.muted.a * .5),
          background,
        ),
      );
      await mouse.moveTo(const Offset(799, 599));
      await tester.pumpAndSettle();
      final left = await _capture(tester, 'live-muted-left');
      _expectColor(_pixel(tester, left, point()), background);
      tokens = tokens.copyWith(muted: const Color(0x40665544));
      await tester.pumpWidget(host(selected: true));
      await tester.pumpAndSettle();
      final selected = await _capture(tester, 'live-muted-selected');
      _expectColor(
        _pixel(tester, selected, point()),
        Color.alphaBlend(tokens.muted, background),
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final selected in [false, true]) {
    testWidgets(
      'a single header keeps background paint order (selected=$selected)',
      (tester) async {
        final theme = AppTheme.dark;
        final tokens = theme.extension<DTokens>()!;
        final background = theme.scaffoldBackgroundColor;
        const header = Color(0x8044aa66);
        const border = Color(0x80553322);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: _captureKey,
                  child: ColoredBox(
                    color: background,
                    child: SizedBox(
                      width: 300,
                      child: DTable(
                        columnWidths: const {0: FlexColumnWidth()},
                        headerBackgroundColor: header,
                        borderColor: border,
                        header: DTableHeader(
                          rows: [
                            DTableRow(
                              selected: selected,
                              cells: const [
                                DTableHead(
                                  key: ValueKey('only-head'),
                                  child: Text('Header'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        body: const DTableBody(rows: []),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final frame = await _capture(tester, 'single-header-$selected');
        final underneath = Color.alphaBlend(
          selected ? tokens.muted : header,
          background,
        );
        final fill = Color.alphaBlend(header, underneath);
        _expectColor(
          _pixel(
            tester,
            frame,
            tester.getTopLeft(find.byKey(const ValueKey('only-head'))) +
                const Offset(2, 2),
          ),
          fill,
        );
        _expectColor(
          _pixel(
            tester,
            frame,
            tester.getBottomLeft(find.byKey(const ValueKey('only-head'))) +
                const Offset(2, 0),
          ),
          Color.alphaBlend(border, fill),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'table backgrounds preserve bounds and states ($dark, $direction)',
        (tester) async {
          final theme = dark ? AppTheme.dark : AppTheme.light;
          final tokens = theme.extension<DTokens>()!;
          final background = theme.scaffoldBackgroundColor;
          const headerColor = Color(0x8044aa66);
          const borderColor = Color(0x80553322);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: const MediaQueryData(disableAnimations: true),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: ColoredBox(
                          color: background,
                          child: const SizedBox(
                            width: 300,
                            child: DTable(
                              minimumWidth: 300,
                              columnWidths: {
                                0: FixedColumnWidth(100),
                                1: FixedColumnWidth(100),
                              },
                              headerBackgroundColor: headerColor,
                              borderColor: borderColor,
                              header: DTableHeader(
                                rows: [
                                  DTableRow(
                                    cells: [
                                      DTableHead(
                                        key: ValueKey('head'),
                                        child: Text('First'),
                                      ),
                                      DTableHead(child: Text('Last')),
                                    ],
                                  ),
                                ],
                              ),
                              body: DTableBody(
                                rows: [
                                  DTableRow(
                                    cells: [
                                      DTableCell(
                                        key: ValueKey('hover'),
                                        child: Text('A'),
                                      ),
                                      DTableCell(child: Text('B')),
                                    ],
                                  ),
                                  DTableRow(
                                    selected: true,
                                    cells: [
                                      DTableCell(
                                        key: ValueKey('selected'),
                                        columnSpan: 2,
                                        child: Text('Selected'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              footer: DTableFooter(
                                rows: [
                                  DTableRow(
                                    cells: [
                                      DTableCell(
                                        key: ValueKey('footer'),
                                        columnSpan: 2,
                                        child: Text('Footer'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              caption: DTableCaption(child: Text('Caption')),
                            ),
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
          Offset point(String key) =>
              tester.getTopLeft(find.byKey(ValueKey(key))) + const Offset(2, 2);
          final id = '${dark ? 'dark' : 'light'}-${direction.name}';
          final idle = await _capture(tester, '$id-idle');
          _expectColor(_pixel(tester, idle, point('hover')), background);
          _expectColor(
            _pixel(tester, idle, point('selected')),
            Color.alphaBlend(tokens.muted, background),
          );
          _expectColor(
            _pixel(tester, idle, point('head')),
            Color.alphaBlend(
              headerColor,
              Color.alphaBlend(headerColor, background),
            ),
          );
          _expectColor(
            _pixel(tester, idle, point('footer')),
            Color.alphaBlend(
              tokens.muted.withValues(alpha: tokens.muted.a * .5),
              background,
            ),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(799, 599));
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(find.text('A')));
          await tester.pumpAndSettle();
          final hovered = await _capture(tester, '$id-hovered');
          _expectColor(
            _pixel(tester, hovered, point('hover')),
            Color.alphaBlend(
              tokens.muted.withValues(alpha: tokens.muted.a * .5),
              background,
            ),
          );
          _expectColor(
            _pixel(
              tester,
              hovered,
              tester.getBottomLeft(find.byKey(const ValueKey('hover'))) +
                  const Offset(2, 0),
            ),
            Color.alphaBlend(borderColor, background),
          );
          _expectColor(
            _pixel(
              tester,
              hovered,
              tester.getTopLeft(find.byKey(const ValueKey('footer'))) +
                  const Offset(2, -1),
            ),
            Color.alphaBlend(borderColor, background),
          );
          final row = tester.getRect(find.byKey(const ValueKey('hover')));
          final gap = Offset(
            direction == TextDirection.ltr ? 250 : 50,
            row.top + 2,
          );
          _expectColor(_pixel(tester, hovered, gap), background);
          await mouse.moveTo(const Offset(799, 599));
          await tester.pumpAndSettle();
          final left = await _capture(tester, '$id-left');
          expect(
            left.pixels.buffer.asUint8List(),
            idle.pixels.buffer.asUint8List(),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
