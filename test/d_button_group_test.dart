import 'dart:ui' show ImageByteFormat, SemanticsValidationResult;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  for (final axis in Axis.values) {
    for (final direction in TextDirection.values) {
      testWidgets('recessed separator paints two edges: $axis $direction', (
        tester,
      ) async {
        const background = Color(0xff080808);
        const fill = Color(0xff262626);
        const rule = Color(0xff0785aa);
        final boundary = GlobalKey();
        await _pump(
          tester,
          Directionality(
            textDirection: direction,
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: background,
                child: DButtonGroup(
                  orientation: axis == Axis.horizontal
                      ? DButtonGroupOrientation.horizontal
                      : DButtonGroupOrientation.vertical,
                  children: [
                    const DButton(
                      label: Text('Copy'),
                      backgroundColor: fill,
                      onPressed: _noop,
                    ),
                    DButtonGroupSeparator(
                      orientation: axis == Axis.horizontal
                          ? Axis.vertical
                          : Axis.horizontal,
                      color: rule,
                    ),
                    const DButton(
                      label: Text('Paste'),
                      backgroundColor: fill,
                      onPressed: _noop,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(DSeparator)),
          axis == Axis.horizontal
              ? Size(1, tester.getSize(find.byType(DButtonGroup)).height)
              : Size(tester.getSize(find.byType(DButtonGroup)).width, 1),
        );
        final origin = tester.getTopLeft(find.byKey(boundary));
        final seam = tester
            .getRect(find.byType(DButtonGroupSeparator))
            .shift(-origin);
        expect(axis == Axis.horizontal ? seam.width : seam.height, 2);
        final colors = await tester.runAsync(() async {
          final box =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await box.toImage(pixelRatio: 1);
          final data = (await image.toByteData(
            format: ImageByteFormat.rawRgba,
          ))!;
          final result = <Color>[];
          for (var index = 0; index < 2; index++) {
            final x = axis == Axis.horizontal
                ? seam.left.toInt() + index
                : seam.center.dx.toInt();
            final y = axis == Axis.horizontal
                ? seam.center.dy.toInt()
                : seam.top.toInt() + index;
            final offset = (y * image.width + x) * 4;
            result.add(
              Color.fromARGB(
                data.getUint8(offset + 3),
                data.getUint8(offset),
                data.getUint8(offset + 1),
                data.getUint8(offset + 2),
              ),
            );
          }
          image.dispose();
          return result;
        });
        final expected =
            axis == Axis.horizontal && direction == TextDirection.rtl
            ? [
                Color.lerp(rule, Colors.white, .15)!,
                Color.lerp(rule, Colors.black, .25)!,
              ]
            : [
                Color.lerp(rule, Colors.black, .25)!,
                Color.lerp(rule, Colors.white, .15)!,
              ];
        expect(
          colors!.map((color) => color.toARGB32()),
          expected.map((color) => color.toARGB32()),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'translucent custom colors paint one joined border between fills',
    (tester) async {
      const background = Color(0xff222222);
      const fill = Color(0x1aed1681);
      const border = Color(0x40ed1681);
      final boundary = GlobalKey();
      await _pump(
        tester,
        RepaintBoundary(
          key: boundary,
          child: const ColoredBox(
            color: background,
            child: DButtonGroup(
              children: [
                DButton(
                  label: Text('sales'),
                  variant: DButtonVariant.outline,
                  backgroundColor: fill,
                  borderColor: border,
                  onPressed: _noop,
                ),
                DButton.iconOnly(
                  icon: Icon(Icons.open_in_new),
                  tooltip: 'Browse sales',
                  variant: DButtonVariant.outline,
                  backgroundColor: fill,
                  borderColor: border,
                  onPressed: _noop,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getSize(find.byType(FilledButton).first);
      final pixels = await tester.runAsync(() async {
        final box =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await box.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
        final pixels = [
          for (final dx in [-2, -1, 0])
            bytes!.buffer
                .asUint8List(
                  ((first.height ~/ 2) * image.width +
                          first.width.ceil() +
                          dx) *
                      4,
                  4,
                )
                .toList(),
        ];
        image.dispose();
        return pixels;
      });
      final fillOnBackground = Color.alphaBlend(fill, background);
      final borderOnBackground = Color.alphaBlend(border, background);
      for (final (index, color) in [
        (0, fillOnBackground),
        (1, borderOnBackground),
        (2, fillOnBackground),
      ]) {
        for (final (channel, value) in [
          (0, color.r),
          (1, color.g),
          (2, color.b),
          (3, color.a),
        ]) {
          expect(
            pixels![index][channel],
            closeTo(value * 255, 1),
            reason: 'join pixel $index, channel $channel',
          );
        }
      }
    },
  );

  testWidgets('focused control paints its ring above the adjacent surface', (
    tester,
  ) async {
    final highlightStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = highlightStrategy,
    );
    final focus = FocusNode();
    final boundary = GlobalKey();
    addTearDown(focus.dispose);
    await _pump(
      tester,
      RepaintBoundary(
        key: boundary,
        child: DButtonGroup(
          children: [
            DButton(
              focusNode: focus,
              variant: DButtonVariant.outline,
              label: const Text('First'),
              onPressed: _noop,
            ),
            const DButton(
              variant: DButtonVariant.secondary,
              label: Text('Second'),
              onPressed: _noop,
            ),
          ],
        ),
      ),
    );
    final first = tester.getSize(find.byType(FilledButton).first);
    Future<int> seamPixel() async {
      final box =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await box.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      final index =
          ((first.height ~/ 2) * image.width + first.width.ceil() + 1) * 4;
      final pixel = bytes!.getUint32(index);
      image.dispose();
      return pixel;
    }

    final idle = await tester.runAsync(seamPixel);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(
      buttonSurface(tester, of: find.byType(FilledButton).first).ringWidth,
      3,
    );
    expect(
      buttonSurface(tester, of: find.byType(FilledButton).last).ringWidth,
      0,
    );
    expect(await tester.runAsync(seamPixel), isNot(idle));
  });

  testWidgets(
    'horizontal group joins radii and preserves independent actions',
    (tester) async {
      var first = 0;
      var second = 0;
      await _pump(
        tester,
        DButtonGroup(
          semanticLabel: 'Message actions',
          children: [
            DButton(
              key: const ValueKey('first'),
              variant: DButtonVariant.outline,
              onPressed: () => first++,
              label: const Text('Archive'),
            ),
            DButton(
              key: const ValueKey('second'),
              variant: DButtonVariant.outline,
              onPressed: () => second++,
              label: const Text('Report'),
            ),
          ],
        ),
      );

      final firstRect = tester.getRect(find.byKey(const ValueKey('first')));
      final secondRect = tester.getRect(find.byKey(const ValueKey('second')));
      expect(firstRect.right, secondRect.left);
      expect(firstRect.height, secondRect.height);
      _expectCorners(tester, 0, const [false, true, true, false]);
      _expectCorners(tester, 1, const [true, false, false, true]);

      await tester.tap(find.byKey(const ValueKey('first')));
      await tester.tap(find.byKey(const ValueKey('second')));
      expect((first, second), (1, 1));
      expect(
        tester.getSemantics(find.byType(DButtonGroup)),
        matchesSemantics(label: 'Message actions', hasEnabledState: false),
      );
    },
  );

  testWidgets('RTL mirrors the joined corners without reordering callbacks', (
    tester,
  ) async {
    final activations = <String>[];
    await _pump(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: DButtonGroup(
          children: [
            DButton(
              onPressed: () => activations.add('first'),
              label: const Text('الأول'),
            ),
            DButton(
              onPressed: () => activations.add('second'),
              label: const Text('الثاني'),
            ),
          ],
        ),
      ),
    );

    _expectCorners(tester, 0, const [true, false, false, true]);
    _expectCorners(tester, 1, const [false, true, true, false]);
    await tester.tap(find.text('الأول'));
    await tester.tap(find.text('الثاني'));
    expect(activations, ['first', 'second']);
  });

  testWidgets(
    'nested groups add spacing and retain their own outside corners',
    (tester) async {
      await _pump(
        tester,
        const DButtonGroup(
          children: [
            DButtonGroup(
              children: [
                DButton(
                  key: ValueKey('nested-first'),
                  label: Text('First'),
                  onPressed: _noop,
                ),
              ],
            ),
            DButtonGroup(
              children: [
                DButton(
                  key: ValueKey('nested-second'),
                  label: Text('Second'),
                  onPressed: _noop,
                ),
              ],
            ),
          ],
        ),
      );

      final first = tester.getRect(find.byKey(const ValueKey('nested-first')));
      final second = tester.getRect(
        find.byKey(const ValueKey('nested-second')),
      );
      expect(second.left - first.right, DSpacing.sm);
      _expectCorners(tester, 0, const [false, false, false, false]);
      _expectCorners(tester, 1, const [false, false, false, false]);
    },
  );

  testWidgets('vertical group joins top and bottom and keeps Tab navigation', (
    tester,
  ) async {
    await _pump(
      tester,
      DButtonGroup(
        orientation: DButtonGroupOrientation.vertical,
        semanticLabel: 'Zoom controls',
        children: [
          DButton.iconOnly(
            icon: const Icon(Icons.add),
            tooltip: 'Zoom in',
            onPressed: () {},
          ),
          DButton.iconOnly(
            icon: const Icon(Icons.remove),
            tooltip: 'Zoom out',
            onPressed: () {},
          ),
        ],
      ),
    );

    _expectCorners(tester, 0, const [false, false, true, true]);
    _expectCorners(tester, 1, const [true, true, false, false]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
      Focus.of(tester.element(find.byType(FilledButton).first)).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
      Focus.of(tester.element(find.byType(FilledButton).last)).hasFocus,
      isTrue,
    );
  });

  testWidgets('input expands beside a fixed action and retains editing state', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 280,
        child: DButtonGroup(
          mainAxisSize: MainAxisSize.max,
          semanticLabel: 'Search',
          children: [
            const DButtonGroupText(child: Text('Query')),
            DButtonGroupExpanded(child: DInput(hintText: 'Search...')),
            const DButton.iconOnly(
              icon: Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _noop,
              variant: DButtonVariant.outline,
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'joined state');
    await tester.pump();
    expect(find.text('joined state'), findsOneWidget);
    expect(tester.getRect(find.byType(DButtonGroup)).width, 280);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separator and text remain passive while controls stay enabled', (
    tester,
  ) async {
    await _pump(
      tester,
      const DButtonGroup(
        children: [
          DButtonGroupText(
            semanticLabel: 'Current branch main',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.account_tree), Text('main')],
            ),
          ),
          DButtonGroupSeparator(),
          DButton(label: Text('Copy'), onPressed: _noop),
        ],
      ),
    );

    expect(find.byType(DSeparator), findsOneWidget);
    expect(
      tester.widget<DSeparator>(find.byType(DSeparator)).color,
      Color.lerp(
        DTokens.of(tester.element(find.byType(DButtonGroupSeparator))).muted,
        Colors.white,
        .15,
      ),
    );
    expect(find.byType(FilledButton), findsOneWidget);
    final buttonHeight = tester.getSize(find.byType(FilledButton)).height;
    expect(tester.getSize(find.byType(DButtonGroup)).height, buttonHeight);
    expect(tester.getSize(find.byType(DSeparator)).height, buttonHeight);
    expect(
      tester.getSemantics(find.byType(DButtonGroupText)),
      matchesSemantics(label: 'Current branch main'),
    );
  });

  testWidgets('touch targets stay 48px while desktop artwork remains compact', (
    tester,
  ) async {
    await _pump(
      tester,
      const DButtonGroup(
        children: [
          DButton.iconOnly(
            icon: Icon(Icons.add),
            tooltip: 'Add',
            size: DButtonSize.small,
            onPressed: _noop,
          ),
          DButton.iconOnly(
            icon: Icon(Icons.remove),
            tooltip: 'Remove',
            size: DButtonSize.small,
            onPressed: _noop,
          ),
        ],
      ),
      platform: TargetPlatform.iOS,
    );

    for (final button in find.byType(FilledButton).evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)).height, 48);
    }
  });

  testWidgets('vertical separator follows the widest control', (tester) async {
    await _pump(
      tester,
      const DButtonGroup(
        orientation: DButtonGroupOrientation.vertical,
        children: [
          DButton(label: Text('Short'), onPressed: _noop),
          DButtonGroupSeparator(orientation: Axis.horizontal),
          DButton(label: Text('A wider action'), onPressed: _noop),
        ],
      ),
    );

    final width = tester.getSize(find.byType(FilledButton).last).width;
    expect(tester.getSize(find.byType(DButtonGroup)).width, width);
    expect(tester.getSize(find.byType(DSeparator)).width, width);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'input group composes as one joined child with independent action',
    (tester) async {
      var voiceToggles = 0;
      await _pump(
        tester,
        SizedBox(
          width: 320,
          child: DButtonGroup(
            mainAxisSize: MainAxisSize.max,
            children: [
              const DButton.iconOnly(
                icon: Icon(Icons.add),
                tooltip: 'Add attachment',
                onPressed: _noop,
                variant: DButtonVariant.outline,
              ),
              DButtonGroupExpanded(
                child: DInputGroup(
                  semanticLabel: 'Message composer',
                  children: [
                    DInputGroupInput(
                      semanticLabel: 'Message',
                      hintText: 'Send a message...',
                    ),
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DInputGroupButton.icon(
                        icon: const Icon(Icons.graphic_eq),
                        tooltip: 'Enable voice mode',
                        onPressed: () => voiceToggles++,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'retained draft');
      await tester.tap(find.byTooltip('Enable voice mode'));
      await tester.pump();

      final attachmentRect = tester.getRect(find.byTooltip('Add attachment'));
      final inputGroupRect = tester.getRect(find.byType(DInputGroup));
      expect(attachmentRect.right, inputGroupRect.left);
      expect(tester.getRect(find.byType(DButtonGroup)).width, 320);
      expect(find.text('retained draft'), findsOneWidget);
      expect(voiceToggles, 1);
      _expectCornersForFinder(tester, find.byType(FilledButton).last, const [
        false,
        false,
        false,
        false,
      ]);
      expect(
        tester.getSemantics(find.byType(DInputGroup)),
        matchesSemantics(
          label: 'Message composer',
          hasEnabledState: true,
          isEnabled: true,
          validationResult: SemanticsValidationResult.valid,
        ),
      );
    },
  );

  testWidgets('input group composition mirrors visually in RTL', (
    tester,
  ) async {
    await _pump(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          width: 320,
          child: DButtonGroup(
            mainAxisSize: MainAxisSize.max,
            children: [
              const DButton.iconOnly(
                icon: Icon(Icons.add),
                tooltip: 'إرفاق',
                onPressed: _noop,
                variant: DButtonVariant.outline,
              ),
              DButtonGroupExpanded(
                child: DInputGroup(
                  children: [
                    DInputGroupInput(hintText: 'رسالة'),
                    const DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DInputGroupButton.icon(
                        icon: Icon(Icons.graphic_eq),
                        tooltip: 'صوت',
                        onPressed: _noop,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final attachmentRect = tester.getRect(find.byTooltip('إرفاق'));
    final inputGroupRect = tester.getRect(find.byType(DInputGroup));
    expect(inputGroupRect.right, attachmentRect.left);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu overlay descendants do not inherit joined group scope', (
    tester,
  ) async {
    await _pump(
      tester,
      DButtonGroup(
        children: [
          const DButton(label: Text('Follow'), onPressed: _noop),
          DPopover(
            content: const DPopoverContent(
              child: DButton(
                key: ValueKey('overlay-action'),
                label: Text('Overlay action'),
                onPressed: _noop,
              ),
            ),
            child: DPopoverTrigger(
              builder: (context, state) => DButton.iconOnly(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: 'More',
                focusNode: state.focusNode,
                onPressed: state.toggle,
                variant: DButtonVariant.outline,
              ),
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    _expectCorners(tester, 0, const [false, true, true, false]);
    _expectCorners(tester, 1, const [true, false, false, true]);
    _expectCornersForFinder(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('overlay-action')),
        matching: find.byType(FilledButton),
      ),
      const [false, false, false, false],
    );
  });
}

void _expectCorners(WidgetTester tester, int index, List<bool> square) {
  _expectCornersForFinder(tester, find.byType(FilledButton).at(index), square);
}

void _expectCornersForFinder(
  WidgetTester tester,
  Finder finder,
  List<bool> square,
) {
  final button = tester.widget<FilledButton>(finder);
  final shape = button.style!.shape!.resolve({})!;
  final size = tester.getSize(finder);
  final path = shape.getOuterPath(Offset.zero & size);
  final points = [
    const Offset(.25, .25),
    Offset(size.width - .25, .25),
    Offset(size.width - .25, size.height - .25),
    Offset(.25, size.height - .25),
  ];
  for (var corner = 0; corner < points.length; corner++) {
    expect(path.contains(points[corner]), square[corner]);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    home: Scaffold(body: Center(child: child)),
  ),
);

void _noop() {}
