import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('button sizes keep the same control typography', () {
    for (final size in DButtonSize.values) {
      expect(DButton.fontSizeFor(size), DiscourseTypography.sm);
    }
  });

  testWidgets('button sizes change spacing while keeping control typography', (
    tester,
  ) async {
    for (final size in DButtonSize.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: DButton(
                label: const Text('Action'),
                onPressed: _noop,
                size: size,
              ),
            ),
          ),
        ),
      );

      final spacingUnit = switch (size) {
        DButtonSize.small => 14.0,
        DButtonSize.regular => 16.0,
        DButtonSize.large => 18.0,
      };
      final rendered = find.byType(FilledButton);
      final style = tester.widget<FilledButton>(rendered).style!;

      expect(
        style.padding!.resolve({}),
        EdgeInsets.symmetric(
          horizontal: spacingUnit * 0.65 + 1,
          vertical: spacingUnit * 0.5 + 1,
        ),
      );
      expect(style.minimumSize!.resolve({}), Size.zero);
      expect(style.textStyle!.resolve({})?.fontSize, 14);
      expect(
        style.textStyle!.resolve({})?.height,
        DiscourseTypography.lineHeightSmall,
      );
      expect(
        tester.getSize(rendered).height,
        moreOrLessEquals(20 + spacingUnit + 2, epsilon: 0.5),
      );
    }
  });

  testWidgets('flat icon buttons inset their visual surface', (tester) async {
    for (final (radius, size) in [
      (0.0, DButtonSize.small),
      (13.0, DButtonSize.regular),
      (0.0, DButtonSize.large),
    ]) {
      final base = AppTheme.light;
      final buttons = base.discourseButtons.copyWith(borderRadius: radius);
      final theme = base.copyWith(
        extensions: [base.shell, base.code, base.discourse, buttons],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Center(
              child: DButton.iconOnly(
                tooltip: 'Action',
                onPressed: _noop,
                variant: DButtonVariant.flat,
                size: size,
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      );

      final rendered = find.byType(FilledButton);
      final surface = find.descendant(
        of: rendered,
        matching: find.byType(Material),
      );
      final style = tester.widget<FilledButton>(rendered).style!;
      final shape = style.shape!.resolve({WidgetState.hovered});
      final targetDimension = DButton.iconOnlyDimensionFor(size);

      expect(tester.getSize(rendered), Size.square(targetDimension));
      expect(surface, findsOneWidget);
      expect(
        tester.getSize(surface),
        Size.square(targetDimension - DButton.flatSurfacePadding * 2),
      );
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(radius),
      );
      expect(
        style.backgroundColor!.resolve({WidgetState.hovered}),
        theme.shell.hover,
      );
    }
  });

  testWidgets('flat icon button padding remains interactive', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              tooltip: 'Action',
              onPressed: () => presses++,
              variant: DButtonVariant.flat,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final rendered = find.byType(FilledButton);
    final surface = find.descendant(
      of: rendered,
      matching: find.byType(Material),
    );
    final targetRect = tester.getRect(rendered);
    final surfaceRect = tester.getRect(surface);
    final paddedPoint = Offset(targetRect.left + 1, targetRect.center.dy);
    final theme = Theme.of(tester.element(rendered));

    expect(surfaceRect.contains(paddedPoint), isFalse);
    expect(tester.widget<Material>(surface).color, Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer();
    await pointer.moveTo(paddedPoint);
    await tester.pump();

    expect(tester.widget<Material>(surface).color, theme.shell.hover);

    await tester.tapAt(paddedPoint);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('buttons can override the radius for joined controls', (
    tester,
  ) async {
    const radius = BorderRadius.horizontal(left: Radius.circular(8));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Action'),
              onPressed: _noop,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );

    final rendered = tester.widget<FilledButton>(find.byType(FilledButton));
    final shape = rendered.style!.shape!.resolve({});

    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).borderRadius, radius);
  });

  testWidgets('buttons use a pointer cursor when enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              DButton(label: Text('Action'), onPressed: _noop),
              DButton.iconOnly(
                tooltip: 'Icon action',
                onPressed: _noop,
                icon: Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );

    for (final button in tester.widgetList<FilledButton>(
      find.byType(FilledButton),
    )) {
      expect(button.style!.mouseCursor!.resolve({}), SystemMouseCursors.click);
      expect(
        button.style!.mouseCursor!.resolve({WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
    }
  });

  testWidgets('interactive background can stay transparent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton.iconOnly(
              tooltip: 'Action',
              onPressed: _noop,
              variant: DButtonVariant.flat,
              interactiveBackgroundColor: Colors.transparent,
              icon: Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    for (final state in const [
      WidgetState.hovered,
      WidgetState.pressed,
      WidgetState.focused,
    ]) {
      expect(style.backgroundColor!.resolve({state}), Colors.transparent);
    }
  });

  testWidgets('shortcut tooltips render platform keycaps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Reply'),
              tooltip: 'Reply to this topic',
              shortcut: DShortcut(
                SingleActivator(LogicalKeyboardKey.keyR, shift: true),
              ),
              onPressed: _noop,
            ),
          ),
        ),
      ),
    );

    final tooltip = find.byType(RawTooltip);
    expect(
      tester.widget<RawTooltip>(tooltip).semanticsTooltip,
      'Reply to this topic',
    );

    tester.state<RawTooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final message = find.text('Reply to this topic');
    expect(
      DefaultTextStyle.of(tester.element(message)).style.fontSize,
      AppTheme.dark.textTheme.bodyMedium?.fontSize,
    );
    expect(find.byType(DKbd), findsNWidgets(2));
    expect(find.text('⇧'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);

    DKbd keycap(int index) =>
        tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-0-$index')));

    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);
  });

  testWidgets('shortcut sequences retain completed key highlights', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: DTooltip(
              message: 'Open projects',
              shortcut: DShortcut.sequence(
                SingleActivator(LogicalKeyboardKey.keyP),
                [SingleActivator(LogicalKeyboardKey.keyK)],
              ),
              child: Text('Projects'),
            ),
          ),
        ),
      ),
    );

    final tooltip = find.byType(RawTooltip);
    tester.state<RawTooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    DKbd keycap(int step) =>
        tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-$step-0')));

    expect(find.byType(DKbd), findsNWidgets(2));
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);
  });

  for (final (description, label, name) in [
    ('text', const Text('Save changes'), 'Save changes'),
    (
      'rich text',
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text.rich(
          TextSpan(
            text: 'Save ',
            children: [
              TextSpan(text: 'changes', semanticsLabel: 'preferences'),
            ],
          ),
        ),
      ),
      'Save preferences',
    ),
    (
      'custom widget',
      Semantics(
        label: 'Save preferences',
        excludeSemantics: true,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('Save'), Text(' changes')],
        ),
      ),
      'Save preferences',
    ),
  ]) {
    testWidgets('$description button keeps its name while loading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        var expectedPresses = 0;
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(label: label, onPressed: () => presses++, loading: loading),
          );

          _expectButtonSemantics(tester, label: name, loading: loading);
          await tester.tap(find.byType(DButton));
          if (!loading) expectedPresses++;
          expect(presses, expectedPresses);

          if (loading) {
            final fontSize = DButton.fontSizeFor(DButtonSize.regular);
            final rendered = find.byType(FilledButton);
            expect(
              tester.getSize(rendered).width,
              moreOrLessEquals(fontSize + 16 * 1.3 + 2),
            );
            expect(
              tester.getSize(rendered).height,
              moreOrLessEquals(fontSize + 16 + 2),
            );
            expect(rendered, paintsExactlyCountTimes(#drawParagraph, 0));
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          }
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('loading text does not replace or duplicate the button name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final loadingText in ['Saving changes…', 'Save changes']) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(
              label: const Text('Save changes'),
              icon: const Icon(Icons.save, semanticLabel: 'Decorative icon'),
              loadingLabel: Text(loadingText),
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: 'Save changes',
            loading: loading,
          );
          if (loading) {
            expect(
              find.byType(FilledButton),
              paintsExactlyCountTimes(#drawParagraph, 1),
            );
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          }
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('retained names do not affect loading geometry or baselines', (
    tester,
  ) async {
    for (final loadingLabel in [null, const Text('Saving changes…')]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  for (final semanticLabel in [null, 'Save preferences'])
                    IntrinsicWidth(
                      child: DButton(
                        label: const Text('Save changes to all preferences'),
                        semanticLabel: semanticLabel,
                        loadingLabel: loadingLabel,
                        loading: true,
                        onPressed: _noop,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final buttons = find.byType(FilledButton);
      final retainedNameRect = tester.getRect(buttons.at(0));
      final explicitNameRect = tester.getRect(buttons.at(1));
      expect(retainedNameRect.size, explicitNameRect.size);
      expect(retainedNameRect.top, explicitNameRect.top);
    }
  });

  testWidgets('explicit button names override labels and tooltips while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final loadingLabel in [null, const Text('Saving changes…')]) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(
              label: const Text.rich(TextSpan(text: 'Save changes')),
              icon: const Icon(Icons.save, semanticLabel: 'Decorative icon'),
              tooltip: 'Save these settings',
              semanticLabel: 'Save preferences',
              loadingLabel: loadingLabel,
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: 'Save preferences',
            loading: loading,
          );
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('icon buttons retain their tooltip or explicit name while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final semanticLabel in [null, 'Add an item']) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton.iconOnly(
              icon: const Icon(Icons.add, semanticLabel: 'Decorative icon'),
              tooltip: 'Add',
              semanticLabel: semanticLabel,
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: semanticLabel ?? '',
            tooltip: semanticLabel == null ? 'Add' : '',
            loading: loading,
          );
          expect(
            tester.getSize(find.byType(FilledButton)),
            const Size.square(DButton.minimumDimension),
          );
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('loading labels keep progress visible on text buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Save changes'),
              loadingLabel: Text('Saving changes…'),
              semanticLabel: 'Saving preferences',
              onPressed: _noop,
              loading: true,
              variant: DButtonVariant.primary,
            ),
          ),
        ),
      ),
    );

    final rendered = find.byType(FilledButton);
    final semantics = tester.ensureSemantics();
    try {
      expect(find.text('Save changes'), findsNothing);
      expect(find.text('Saving changes…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(rendered).width,
        greaterThan(tester.getSize(rendered).height),
      );
      expect(tester.widget<FilledButton>(rendered).onPressed, isNull);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Saving preferences')),
        isSemantics(
          label: 'Saving preferences',
          value: 'Loading',
          isButton: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpButton(WidgetTester tester, DButton button) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: button)),
      ),
    );

void _expectButtonSemantics(
  WidgetTester tester, {
  required String label,
  required bool loading,
  String tooltip = '',
}) {
  expect(
    tester.getSemantics(find.byType(DButton)),
    isSemantics(
      label: label,
      tooltip: tooltip,
      value: loading ? 'Loading' : '',
      isButton: true,
      hasEnabledState: true,
      isEnabled: !loading,
      hasTapAction: !loading,
      isLiveRegion: loading,
    ),
  );
}

void _noop() {}
