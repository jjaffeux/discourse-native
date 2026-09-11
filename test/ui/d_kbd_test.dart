import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chord = DShortcut(
    SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      control: true,
      alt: true,
      shift: true,
      meta: true,
    ),
  );
  const sequence = DShortcut.sequence(
    SingleActivator(LogicalKeyboardKey.keyG),
    [SingleActivator(LogicalKeyboardKey.keyH)],
  );

  test(
    'spoken formatting preserves activators and distinguishes sequences',
    () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        expect(
          chord.semanticLabel(platform),
          'Control + Option + Shift + Command + Arrow Left',
        );
      }
      expect(
        chord.semanticLabel(TargetPlatform.linux),
        'Control + Alt + Shift + Meta + Arrow Left',
      );
      expect(sequence.semanticLabel(TargetPlatform.macOS), 'G, then H');
      expect(chord[0].control, isTrue);
      expect(chord[0].meta, isTrue);
      final nextSteps = [const SingleActivator(LogicalKeyboardKey.keyH)];
      final equivalent = DShortcut.sequence(
        const SingleActivator(LogicalKeyboardKey.keyG),
        nextSteps,
      );
      expect(equivalent, sequence);
      expect(equivalent.hashCode, sequence.hashCode);
      expect(
        const DShortcut(
          SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false),
        ),
        isNot(const DShortcut(SingleActivator(LogicalKeyboardKey.keyG))),
      );
    },
  );

  testWidgets('reference geometry, type and colors follow the active palette', (
    tester,
  ) async {
    for (final palette in [
      StyleguideTheme.light,
      StyleguideTheme.dark,
      StyleguideTheme.forest,
      StyleguideTheme.plum,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: palette.resolve(AppTheme.light),
          home: const Scaffold(
            body: Center(
              child: DKbdGroup(
                children: [
                  DKbd('K'),
                  DKbd.child(
                    semanticLabel: 'Brightness up',
                    child: Icon(Icons.brightness_high),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final caps = find.byType(DKbd);
      final context = tester.element(caps.first);
      final tokens = DTokens.of(context);
      final surface = tester.widget<AnimatedContainer>(
        find.descendant(
          of: caps.first,
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = surface.decoration! as BoxDecoration;
      final style = DefaultTextStyle.of(tester.element(find.text('K'))).style;
      expect(tester.getSize(caps.first), const Size(20, 20));
      expect(tester.getSize(caps.last), const Size(20, 20));
      expect(
        tester.getTopLeft(caps.last).dx - tester.getTopRight(caps.first).dx,
        4,
      );
      expect(surface.padding, const EdgeInsets.symmetric(horizontal: 4));
      expect(decoration.border, isNull);
      expect(decoration.color, tokens.muted);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(tokens.radius * .6),
      );
      expect(style.color, tokens.mutedForeground);
      expect(
        style.fontFamily,
        Theme.of(context).textTheme.labelSmall!.fontFamily,
      );
      expect(style.fontSize, 12);
      expect(style.height, 16 / 12);
      expect(style.leadingDistribution, TextLeadingDistribution.even);
      expect(style.fontWeight, FontWeight.w500);
      expect(tester.getSize(find.byType(Icon)), const Size(12, 12));
    }
  });

  testWidgets('symbols and custom icons are spoken without button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        child: const DKbdGroup(
          children: [
            DKbd('⌘'),
            DKbd('↑'),
            DKbd.child(
              semanticLabel: 'Brightness up',
              child: Icon(Icons.brightness_high),
            ),
          ],
        ),
      );
      expect(find.bySemanticsLabel('Command'), findsOneWidget);
      expect(find.bySemanticsLabel('Arrow Up'), findsOneWidget);
      expect(find.bySemanticsLabel('Brightness up'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Command')),
        isSemantics(label: 'Command'),
      );
      final focus = FocusManager.instance.primaryFocus;
      await tester.tapAt(tester.getCenter(find.byType(DKbd).first));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, focus);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'a labelled group speaks one localized chord with no duplicate key labels',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          child: const DShortcutKeycaps(
            shortcut: chord,
            semanticLabel: 'تراجع',
            platform: TargetPlatform.macOS,
          ),
        );
        expect(find.bySemanticsLabel('تراجع'), findsOneWidget);
        expect(find.bySemanticsLabel('Command'), findsNothing);
        expect(find.text('⌘'), findsOneWidget);
        expect(find.text('⌥'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} formats hints without changing logical keys',
      (tester) async {
        await _pump(
          tester,
          child: DShortcutKeycaps(shortcut: chord, platform: platform),
        );
        final apple = platform != TargetPlatform.linux;
        expect(find.text(apple ? '⌘' : 'Meta'), findsOneWidget);
        expect(find.text(apple ? '⌃' : 'Ctrl'), findsOneWidget);
        expect(find.text(apple ? '⌥' : 'Alt'), findsOneWidget);
        expect(find.text('←'), findsOneWidget);
        expect(
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft),
          isFalse,
        );
        await tester.pump();
        expect(_cap(tester, 0, 0).highlighted, isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      },
    );
  }

  testWidgets(
    'wrapping and intrinsic labels fit narrow widths at 200 percent text',
    (tester) async {
      for (final width in [80.0, 240.0, 360.0]) {
        await _pump(
          tester,
          width: width,
          scale: 2,
          child: const DKbdGroup(
            children: [
              DKbd('Control + Backspace'),
              DKbd('Page Down'),
              DKbd('KeyboardLanguageSwitch'),
              DShortcutKeycaps(shortcut: chord, platform: TargetPlatform.linux),
            ],
          ),
        );
        expect(tester.takeException(), isNull, reason: 'width $width');
        final bounds = tester.getRect(find.byKey(const ValueKey('bounds')));
        for (final key in find.byType(DKbd).evaluate()) {
          final rect = tester.getRect(find.byWidget(key.widget));
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
        }
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        )) {
          expect(paragraph.didExceedMaxLines, isFalse);
        }
      }
    },
  );

  testWidgets(
    'groups follow direction while notation islands and arrows retain their intent',
    (tester) async {
      await _pump(
        tester,
        child: const DDirection(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              DKbdGroup(children: [DKbd('A'), DKbd('B')]),
              DKbdGroup(
                textDirection: TextDirection.ltr,
                children: [DKbd('Ctrl'), DKbd('←')],
              ),
            ],
          ),
        ),
      );
      expect(
        tester.getCenter(find.text('A')).dx,
        greaterThan(tester.getCenter(find.text('B')).dx),
      );
      expect(
        tester.getCenter(find.text('Ctrl')).dx,
        lessThan(tester.getCenter(find.text('←')).dx),
      );
      expect(tester.widget<Text>(find.text('←')).data, '←');
    },
  );

  testWidgets(
    'theme fonts stay live without replacing reference text metrics',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: theme,
            builder: (_, value, child) => Theme(data: value, child: child!),
            child: const MediaQuery(
              data: MediaQueryData(
                disableAnimations: true,
                textScaler: TextScaler.linear(2),
              ),
              child: Center(child: DKbd('K', highlighted: true)),
            ),
          ),
        ),
      );
      for (final palette in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        theme.value = palette
            .resolve(AppTheme.light)
            .copyWith(
              textTheme: AppTheme.light.textTheme.copyWith(
                labelSmall: TextStyle(
                  fontFamily: palette.name,
                  fontSize: 17,
                  height: 1.7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            );
        await tester.pump();
        final context = tester.element(find.byType(DKbd));
        final tokens = DTokens.of(context);
        final surface = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(DKbd),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final style = tester
            .widget<AnimatedDefaultTextStyle>(
              find.descendant(
                of: find.byType(DKbd),
                matching: find.byType(AnimatedDefaultTextStyle),
              ),
            )
            .style;
        expect((surface.decoration! as BoxDecoration).color, tokens.primary);
        expect(
          (surface.decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(tokens.radius * 0.6),
        );
        expect(surface.duration, Duration.zero);
        expect(style.fontFamily, palette.name);
        expect(style.fontSize, 12);
        expect(style.height, 16 / 12);
        expect(style.leadingDistribution, TextLeadingDistribution.even);
        expect(style.letterSpacing, 0);
        expect(style.fontWeight, FontWeight.w600);
        expect(style.color, tokens.primaryForeground);
        expect(style.decoration, TextDecoration.underline);
        expect(tester.getSize(find.byType(DKbd)).height, 32);
      }
    },
  );

  testWidgets(
    'sequence feedback survives equivalent rebuilds and resets on wrong keys or completion',
    (tester) async {
      final revision = ValueNotifier(0);
      List<SingleActivator> following() => [
        const SingleActivator(LogicalKeyboardKey.keyH),
      ];
      addTearDown(revision.dispose);
      await _pump(
        tester,
        child: ValueListenableBuilder(
          valueListenable: revision,
          builder: (_, value, _) => DShortcutKeycaps(
            shortcut: DShortcut.sequence(
              const SingleActivator(LogicalKeyboardKey.keyG),
              following(),
            ),
          ),
        ),
      );
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyG), isFalse);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isTrue);
      revision.value++;
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.pump();
      expect(_cap(tester, 1, 0).highlighted, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isFalse);
      expect(_cap(tester, 1, 0).highlighted, isFalse);
    },
  );

  testWidgets(
    'hidden, inactive, unfocused and removed hints release feedback listeners',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await _pump(
        tester,
        child: ValueListenableBuilder(
          valueListenable: visible,
          builder: (_, value, child) =>
              TickerMode(enabled: value, child: child!),
          child: const DShortcutKeycaps(shortcut: sequence),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isTrue);
      visible.value = false;
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isFalse);
      expect(_cap(tester, 1, 0).highlighted, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      visible.value = true;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.unfocused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isFalse);
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.focused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyH), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'static hints do not observe presses and empty groups have no height',
    (tester) async {
      await _pump(
        tester,
        child: const Column(
          children: [
            DShortcutKeycaps(shortcut: chord, listenToKeyboard: false),
            DKbdGroup(key: ValueKey('empty'), children: []),
          ],
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_cap(tester, 0, 0).highlighted, isFalse);
      expect(tester.getSize(find.byKey(const ValueKey('empty'))).height, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    },
  );

  test(
    'named keys keep their printed names while characters read as keycaps',
    () {
      expect(
        const DShortcut(
          SingleActivator(LogicalKeyboardKey.pageDown, control: true),
        ).semanticLabel(TargetPlatform.linux),
        'Control + Page Down',
      );
      expect(
        const DShortcut(
          SingleActivator(LogicalKeyboardKey.home),
        ).semanticLabel(TargetPlatform.macOS),
        'Home',
      );
      expect(
        const DShortcut(
          SingleActivator(LogicalKeyboardKey.keyA),
        ).semanticLabel(TargetPlatform.macOS),
        'A',
      );
      expect(
        const DShortcut(
          SingleActivator(LogicalKeyboardKey.f6),
        ).semanticLabel(TargetPlatform.linux),
        'F6',
      );
    },
  );

  testWidgets('named keys render their printed names on keycaps', (
    tester,
  ) async {
    await _pump(
      tester,
      child: const DShortcutKeycaps(
        platform: TargetPlatform.linux,
        listenToKeyboard: false,
        shortcut: DShortcut.sequence(
          SingleActivator(LogicalKeyboardKey.pageDown, control: true),
          [SingleActivator(LogicalKeyboardKey.home)],
        ),
      ),
    );
    expect(find.widgetWithText(DKbd, 'Ctrl'), findsOneWidget);
    expect(find.widgetWithText(DKbd, 'Page Down'), findsOneWidget);
    expect(find.widgetWithText(DKbd, 'Home'), findsOneWidget);
    expect(find.text('then'), findsOneWidget);
  });

  testWidgets('a custom text style leaves icons at the reference 12px', (
    tester,
  ) async {
    await _pump(
      tester,
      child: const DKbdGroup(
        children: [
          DKbd('K', style: TextStyle(fontSize: 18)),
          DKbd.child(
            semanticLabel: 'Brightness up',
            style: TextStyle(fontSize: 18),
            child: Icon(Icons.brightness_high),
          ),
        ],
      ),
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('K'))).style.fontSize,
      18,
    );
    expect(tester.getSize(find.byType(Icon)), const Size(12, 12));
  });

  testWidgets(
    'an ancestor keycap theme supplies colors and radius without changing geometry',
    (tester) async {
      const radius = BorderRadius.all(Radius.circular(1));
      await _pump(
        tester,
        child: const DKbdTheme(
          foregroundColor: Color(0xFF102030),
          backgroundColor: Color(0xFF405060),
          borderRadius: radius,
          child: DKbdGroup(children: [DKbd('K')]),
        ),
      );
      final surface = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(DKbd),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF405060));
      expect(decoration.borderRadius, radius);
      expect(
        DefaultTextStyle.of(tester.element(find.text('K'))).style.color,
        const Color(0xFF102030),
      );
      expect(tester.getSize(find.byType(DKbd)), const Size(20, 20));
      await _pump(
        tester,
        child: const DKbdTheme(
          foregroundColor: Color(0xFF102030),
          backgroundColor: Color(0xFF405060),
          child: DKbdGroup(children: [DKbd('K')]),
        ),
      );
      final tokens = DTokens.of(tester.element(find.byType(DKbd)));
      expect(
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byType(DKbd),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .borderRadius,
        BorderRadius.circular(tokens.radius * 0.6),
      );
    },
  );

  testWidgets('unrelated keys and repeats leave feedback keycaps unbuilt', (
    tester,
  ) async {
    await _pump(tester, child: const DShortcutKeycaps(shortcut: sequence));
    final idle = _cap(tester, 0, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(identical(_cap(tester, 0, 0), idle), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    final progressed = _cap(tester, 0, 0);
    expect(identical(progressed, idle), isFalse);
    expect(progressed.highlighted, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(identical(_cap(tester, 0, 0), progressed), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(identical(_cap(tester, 0, 0), progressed), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(_cap(tester, 0, 0).highlighted, isFalse);
  });
}

DKbd _cap(WidgetTester tester, int step, int index) =>
    tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-$step-$index')));

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  double width = 360,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: const ValueKey('bounds'),
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  ),
);
