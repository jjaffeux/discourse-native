import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inline badges retain paragraph metrics, baseline and ellipsis', (
    tester,
  ) async {
    for (final fontSize in [12.0, 17.0, 24.0]) {
      for (final scale in [1.0, 2.0]) {
        await _pump(
          tester,
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: DBadge.inline(
                  baseStyle: TextStyle(
                    fontSize: fontSize,
                    height: 1.8,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                  child: const Text(
                    'A long inline label that must remain one line',
                  ),
                ),
              ),
              Text('Ag', style: TextStyle(fontSize: fontSize, height: 1.8)),
            ],
          ),
          width: 180,
          scale: scale,
        );
        final label = find.text(
          'A long inline label that must remain one line',
        );
        final paragraph = tester.renderObject<RenderParagraph>(label);
        final style = (paragraph.text as TextSpan).style!;
        expect(style.fontSize, closeTo(fontSize * .93, .001));
        expect(style.height, 1);
        expect(style.fontWeight, FontWeight.w400);
        expect(style.decoration, TextDecoration.none);
        expect(paragraph.maxLines, 1);
        expect(paragraph.softWrap, isFalse);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        expect(paragraph.didExceedMaxLines, isTrue);
        final reference = tester.renderObject<RenderParagraph>(find.text('Ag'));
        final labelBaseline = paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        );
        final referenceBaseline = reference.getDryBaseline(
          reference.constraints,
          TextBaseline.alphabetic,
        );
        expect(labelBaseline, isNotNull);
        expect(referenceBaseline, isNotNull);
        expect(
          paragraph.localToGlobal(Offset(0, labelBaseline!)).dy,
          closeTo(
            reference.localToGlobal(Offset(0, referenceBaseline!)).dy,
            .001,
          ),
        );
        expect(
          tester.getSize(find.byType(DBadge)).width,
          lessThanOrEqualTo(180),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'inline artwork uses Native optical metrics and stays decorative',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final artwork in DBadgeInlineArtwork.values) {
          double? dimension;
          await _pump(
            tester,
            DBadge.inline(
              baseStyle: const TextStyle(fontSize: 20),
              leadingArtwork: artwork,
              leadingBuilder: (context, size) {
                dimension = size;
                return Semantics(
                  label: 'Decorative artwork',
                  child: const SizedBox.expand(),
                );
              },
              child: const Text('Tag'),
            ),
          );
          final expected =
              20 *
              .93 *
              switch (artwork) {
                DBadgeInlineArtwork.icon => .93 / DIcon.glyphScale,
                DBadgeInlineArtwork.image => .93,
                DBadgeInlineArtwork.square => .72,
              };
          expect(dimension, closeTo(expected, .001));
          expect(find.bySemanticsLabel('Decorative artwork'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'inline projected state changes paint without changing its bounds',
    (tester) async {
      const fill = Color(0xff456789);
      const baseStyle = TextStyle(fontSize: 17);
      Widget badge({bool hovered = false, bool highlighted = false}) =>
          DBadge.inline(
            baseStyle: baseStyle,
            backgroundColor: fill,
            hovered: hovered,
            highlighted: highlighted,
            child: const Text('Poll'),
          );
      await _pump(tester, badge());
      final bounds = tester.getRect(find.byType(DBadge));
      final tokens = DTokens.of(tester.element(find.byType(DBadge)));
      expect(_decoration(tester).color, fill);
      await _pump(tester, badge(hovered: true, highlighted: true));
      expect(
        _decoration(tester).color,
        Color.alphaBlend(tokens.foreground.withValues(alpha: .08), fill),
      );
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final highlight = container.foregroundDecoration! as BoxDecoration;
      expect(highlight.border!.top.color, tokens.primary);
      expect(highlight.border!.top.width, 1.5);
      expect(tester.getRect(find.byType(DBadge)), bounds);
      await _pump(tester, badge());
      expect(_decoration(tester).color, fill);
      expect(tester.getRect(find.byType(DBadge)), bounds);
      expect(
        find.descendant(
          of: find.byType(DBadge),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('inline actions activate only inside their visible bounds', (
    tester,
  ) async {
    var activations = 0;
    await _pump(
      tester,
      SizedBox(
        width: 300,
        child: DBadge.inline(
          baseStyle: const TextStyle(fontSize: 17),
          semanticLabel: 'Open support',
          onPressed: () => activations++,
          child: const Text('support'),
        ),
      ),
    );
    final visible = tester.getRect(find.byType(AnimatedContainer));
    final whole = tester.getRect(find.byType(DBadge));
    expect(visible.width, lessThan(whole.width));
    await tester.tapAt(Offset(visible.right + 8, visible.center.dy));
    expect(activations, 0);
    await tester.tapAt(visible.center);
    expect(activations, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'control badges match filter controls across platforms and text scales',
    (tester) async {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        for (final scale in [1.0, 2.0, 3.0]) {
          var activated = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DBadge.link(
                          size: DBadgeSize.control,
                          onPressed: () => activated = true,
                          child: const Text('Tag'),
                        ),
                        DButton(
                          size: DControlSize.filter,
                          label: const Text('Category'),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final tag = tester.renderObject<RenderParagraph>(find.text('Tag'));
          final category = tester.renderObject<RenderParagraph>(
            find.text('Category'),
          );
          expect(tag.text.style!.fontSize, category.text.style!.fontSize);
          expect(tag.text.style!.height, category.text.style!.height);
          final badge = find
              .descendant(
                of: find.byType(DBadge),
                matching: find.byType(AnimatedContainer),
              )
              .first;
          expect(
            tester.getSize(badge).height,
            DControlStyle.scaledHeight(
              DControlSize.filter,
              TextScaler.linear(scale),
            ),
          );
          await tester.tap(find.text('Tag'));
          expect(activated, isTrue);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('regular badge focus semantics preserve visible focus policy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        DFocusHighlight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DBadge.action(onPressed: () {}, child: const Text('First')),
              DBadge.action(onPressed: () {}, child: const Text('Second')),
            ],
          ),
        ),
      );
      final tokens = DTokens.of(tester.element(find.text('First')));
      await tester.tap(find.text('First'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('First')).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      expect(
        _decorationOf(tester, 'First').border!.top.color,
        Colors.transparent,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('First')).flagsCollection.isFocused,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(find.text('Second')).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      expect(
        _decorationOf(tester, 'Second').border!.top.color,
        tokens.focusRing,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('overlay pills grow left without obscuring the icon or count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final scale in [1.0, 2.0]) {
        for (final rtl in [false, true]) {
          var previousWidth = 0.0;
          double? rightEdge;
          for (final count in ['4', '129', '999+']) {
            await _pump(
              tester,
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const SizedBox.square(dimension: 32),
                  Positioned(
                    right: -1.5,
                    bottom: -1.5,
                    child: DBadge.overlay(
                      semanticLabel: '1284 unread notifications',
                      child: Text(count),
                    ),
                  ),
                ],
              ),
              scale: scale,
              rtl: rtl,
            );
            final bounds = tester.getRect(find.byType(DBadge));
            final label = tester.getRect(find.text(count));
            expect(bounds.height, closeTo(12 * scale + 2, 0.01));
            expect(bounds.width, greaterThan(previousWidth));
            expect(bounds.contains(label.topLeft), isTrue);
            expect(bounds.contains(label.bottomRight), isTrue);
            if (rightEdge != null) expect(bounds.right, rightEdge);
            rightEdge = bounds.right;
            previousWidth = bounds.width;
            expect(
              find.bySemanticsLabel('1284 unread notifications'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('overlay counts fit a narrow rail at large text sizes', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0, 3.0]) {
      await _pump(
        tester,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 36),
          child: const DBadge.overlay(child: Text('999+')),
        ),
        scale: scale,
      );
      final bounds = tester.getRect(find.byType(DBadge));
      final label = tester.getRect(find.text('999+'));
      expect(bounds.width, lessThanOrEqualTo(36));
      expect(bounds.contains(label.topLeft), isTrue);
      expect(bounds.contains(label.bottomRight), isTrue);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('999+'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('overlay count does not intercept its parent action', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const DBadge.overlay(child: Text('129')),
      ),
    );
    await tester.tapAt(tester.getCenter(find.text('129')));
    expect(taps, 1);
  });

  testWidgets('compact counts keep full text and semantics at large scales', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final scale in [1.0, 2.0, 3.0]) {
        await _pump(
          tester,
          const DBadge(
            size: DBadgeSize.compact,
            semanticLabel: '123 unread',
            child: Text('99+'),
          ),
          width: 150,
          scale: scale,
          rtl: true,
        );
        final bounds = tester.getRect(find.byType(DBadge));
        final labelBounds = tester.getRect(find.text('99+'));
        expect(bounds.height, closeTo(14 * scale + 2, 0.01));
        expect(bounds.width, closeTo(labelBounds.width + 10, 0.01));
        expect(bounds.contains(labelBounds.topLeft), isTrue);
        expect(bounds.contains(labelBounds.bottomRight), isTrue);
        expect(find.bySemanticsLabel('123 unread'), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('99+'))
              .didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'static badges have compact geometry and no activation or tab stop',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(tester, const DBadge(child: Text('Badge')));
        expect(tester.getSize(find.byType(DBadge)).height, 22);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Badge'),
        );
        final style = (paragraph.text as TextSpan).style!;
        expect(style.fontSize, 12);
        expect(style.height, 1.5);
        expect(style.fontWeight, FontWeight.w500);
        final node = tester.getSemantics(find.text('Badge'));
        expect(node.flagsCollection.isButton, isFalse);
        expect(node.flagsCollection.isLink, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        final focused = FocusManager.instance.primaryFocus?.context;
        expect(
          find.descendant(
            of: find.byType(DBadge),
            matching: find.byElementPredicate(
              (element) => identical(element, focused),
            ),
          ),
          findsNothing,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'badge hover transfers immediately without intermediate fills or trails',
    (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await _pump(
          tester,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final label in ['First', 'Second'])
                DBadge.link(
                  variant: DBadgeVariant.outline,
                  onPressed: () {},
                  child: Text(label),
                ),
            ],
          ),
          theme: theme,
          reducedMotion: false,
        );
        final tokens = DTokens.of(tester.element(find.byType(DBadge).first));
        for (final active in ['First', 'Second', null]) {
          await mouse.moveTo(
            active == null ? Offset.zero : tester.getCenter(find.text(active)),
          );
          await tester.pump();
          for (final elapsed in [0, 50, 100, 150]) {
            await tester.pump(Duration(milliseconds: elapsed));
            for (final label in ['First', 'Second']) {
              expect(
                _paintedDecorationOf(tester, label).color,
                label == active ? tokens.muted : Colors.transparent,
              );
            }
          }
        }
      }
    },
  );

  testWidgets(
    'static ghost and link badges paint hover while other static variants ignore the pointer',
    (tester) async {
      var primaryBuilds = 0;
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DBadge(variant: DBadgeVariant.ghost, child: Text('Ghost')),
            const DBadge(variant: DBadgeVariant.link, child: Text('Link')),
            DBadge(
              child: Builder(
                builder: (_) {
                  primaryBuilds++;
                  return const Text('Primary');
                },
              ),
            ),
          ],
        ),
      );
      final tokens = DTokens.of(tester.element(find.text('Ghost')));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Ghost')));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester, 'Ghost').color, tokens.muted);
      expect(_styleOf(tester, 'Ghost').color, tokens.mutedForeground);
      await mouse.moveTo(tester.getCenter(find.text('Link')));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester, 'Ghost').color, Colors.transparent);
      expect(_styleOf(tester, 'Ghost').color, tokens.foreground);
      expect(_decorationOf(tester, 'Link').color, Colors.transparent);
      expect(_styleOf(tester, 'Link').decoration, TextDecoration.underline);
      final settledBuilds = primaryBuilds;
      await mouse.moveTo(tester.getCenter(find.text('Primary')));
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_styleOf(tester, 'Link').decoration, TextDecoration.none);
      expect(_decorationOf(tester, 'Primary').color, tokens.primary);
      expect(primaryBuilds, settledBuilds);
    },
  );

  testWidgets(
    'switching a hovered static badge away from ghost drops the stale hover',
    (tester) async {
      Widget badge(DBadgeVariant variant) =>
          DBadge(variant: variant, child: const Text('Status'));
      await _pump(tester, badge(DBadgeVariant.ghost));
      final state = tester.state(find.byType(DBadge));
      final tokens = DTokens.of(tester.element(find.byType(DBadge)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Status')));
      await tester.pumpAndSettle();
      expect(_decoration(tester).color, tokens.muted);
      await _pump(tester, badge(DBadgeVariant.primary));
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await _pump(tester, badge(DBadgeVariant.ghost));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(DBadge)), same(state));
      expect(_decoration(tester).color, Colors.transparent);
      await mouse.moveTo(tester.getCenter(find.text('Status')));
      await tester.pumpAndSettle();
      expect(_decoration(tester).color, tokens.muted);
    },
  );

  testWidgets('static decoration changes retain the reference 150ms timing', (
    tester,
  ) async {
    await _pump(
      tester,
      const DBadge(child: Text('Badge')),
      reducedMotion: false,
    );
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(container.duration, const Duration(milliseconds: 150));
    expect(container.curve, const Cubic(.4, 0, .2, 1));
    await _pump(tester, const DBadge(child: Text('Badge')));
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
  });

  testWidgets('badge text takes part in an enclosing selection area', (
    tester,
  ) async {
    SelectedContent? selection;
    await _pump(
      tester,
      SelectionArea(
        onSelectionChanged: (content) => selection = content,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Before'),
            DBadge(child: Text('Badge')),
            Text('After'),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.text('Before')),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getBottomRight(find.text('After')));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(selection?.plainText, 'BeforeBadgeAfter');
  });

  for (final variant in DBadgeVariant.values) {
    testWidgets(
      '${variant.name} follows four live palettes without remounting',
      (tester) async {
        State? original;
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
          StyleguideTheme.plum.resolve(AppTheme.light),
        ]) {
          await _pump(
            tester,
            DBadge(variant: variant, child: const Text('Status')),
            theme: theme,
          );
          final state = tester.state(find.byType(DBadge));
          original ??= state;
          expect(state, same(original));
          final t = DTokens.of(tester.element(find.byType(DBadge)));
          final expected = switch (variant) {
            DBadgeVariant.primary => t.primary,
            DBadgeVariant.secondary => t.muted,
            DBadgeVariant.destructive => t.destructive.withValues(
              alpha: theme.brightness == Brightness.dark ? .2 : .1,
            ),
            _ => Colors.transparent,
          };
          expect(_decoration(tester).color, expected);
        }
      },
    );
  }

  testWidgets(
    'theme radii and extreme text keep fixed pill curvature without clipping',
    (tester) async {
      for (final radius in [0.0, 1.0, 4.0, 12.0]) {
        final theme = AppTheme.light.copyWith(
          extensions: [
            AppTheme.light.extension<DTokens>()!.copyWith(radius: radius),
          ],
        );
        await _pump(
          tester,
          const DBadge(child: Text('A label that grows across several lines')),
          theme: theme,
          width: 140,
          scale: 3,
        );
        expect(
          _decoration(tester).borderRadius,
          BorderRadius.circular(DRadius.pill),
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.byType(Text))
              .didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('control badges follow the theme button radius', (tester) async {
    for (final radius in [0.0, 4.0, 12.0]) {
      final theme = AppTheme.light.copyWith(
        extensions: [
          AppTheme.light.extension<DTokens>()!.copyWith(radius: radius),
        ],
      );
      await _pump(
        tester,
        DBadge.link(
          size: DBadgeSize.control,
          onPressed: () {},
          child: const Text('# tag'),
        ),
        theme: theme,
      );
      expect(
        _decoration(tester).borderRadius,
        BorderRadius.circular(theme.extension<DTokens>()!.controlRadius),
      );
    }
  });

  testWidgets('badge sizes own their touch targets and inline tag geometry', (
    tester,
  ) async {
    for (final size in DBadgeSize.values) {
      var activated = false;
      await _pump(
        tester,
        DBadge.action(
          size: size,
          onPressed: () => activated = true,
          child: const Text('Go'),
        ),
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
      );
      final bounds = tester.getRect(find.byType(DBadge));
      expect(bounds, tester.getRect(find.byType(AnimatedContainer)));
      expect(
        tester.getSize(find.byType(AnimatedContainer)).height,
        switch (size) {
          DBadgeSize.compact => 16,
          DBadgeSize.regular => 22,
          DBadgeSize.featured => 26,
          DBadgeSize.control => 30,
          DBadgeSize.unread => 19,
        },
      );
      await tester.tapAt(bounds.topCenter + const Offset(0, 2));
      expect(activated, isTrue);
    }
  });
}

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration!
        as BoxDecoration;
BoxDecoration _paintedDecorationOf(WidgetTester tester, String text) =>
    tester
            .renderObject<RenderDecoratedBox>(
              find
                  .ancestor(
                    of: find.text(text),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is DecoratedBox &&
                          widget.decoration is BoxDecoration,
                    ),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;
BoxDecoration _decorationOf(WidgetTester tester, String text) =>
    tester
            .widget<AnimatedContainer>(
              find.ancestor(
                of: find.text(text),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration!
        as BoxDecoration;
TextStyle _styleOf(WidgetTester tester, String text) =>
    (tester.renderObject<RenderParagraph>(find.text(text)).text as TextSpan)
        .style!;
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double width = 400,
  double scale = 1,
  bool rtl = false,
  bool reducedMotion = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: theme ?? AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reducedMotion,
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Align(child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}
