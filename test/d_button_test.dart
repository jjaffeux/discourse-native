import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text buttons use core font-relative geometry', (tester) async {
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

      final fontSize = DButton.fontSizeFor(size);
      final rendered = find.byType(FilledButton);
      final style = tester.widget<FilledButton>(rendered).style!;

      expect(
        style.padding!.resolve({}),
        EdgeInsets.symmetric(
          horizontal: fontSize * 0.65 + 1,
          vertical: fontSize * 0.5 + 1,
        ),
      );
      expect(style.minimumSize!.resolve({}), Size.zero);
      expect(style.textStyle!.resolve({})?.height, 1.2);
      expect(
        tester.getSize(rendered).height,
        moreOrLessEquals(fontSize * 2.2 + 2, epsilon: 0.5),
      );
    }
  });

  testWidgets('icon-only buttons stay square and follow the site radius', (
    tester,
  ) async {
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
      final style = tester.widget<FilledButton>(rendered).style!;
      final shape = style.shape!.resolve({WidgetState.hovered});

      expect(
        tester.getSize(rendered),
        Size.square(DButton.iconOnlyDimensionFor(size)),
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
      AppTheme.dark.textTheme.bodySmall?.fontSize,
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

void _noop() {}
