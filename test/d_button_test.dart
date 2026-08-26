import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
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
}

void _noop() {}
