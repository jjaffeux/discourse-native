import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('icon-only buttons stay square and follow the site radius', (
    tester,
  ) async {
    for (final radius in [0.0, 13.0]) {
      final base = AppTheme.light;
      final buttons = base.discourseButtons.copyWith(borderRadius: radius);
      final theme = base.copyWith(
        extensions: [base.shell, base.code, base.discourse, buttons],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: const Scaffold(
            body: Center(
              child: DButton.iconOnly(
                tooltip: 'Action',
                onPressed: _noop,
                variant: DButtonVariant.flat,
                icon: Icon(Icons.add),
              ),
            ),
          ),
        ),
      );

      final rendered = find.byType(FilledButton);
      final style = tester.widget<FilledButton>(rendered).style!;
      final shape = style.shape!.resolve({WidgetState.hovered});

      expect(tester.getSize(rendered), const Size.square(48));
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
}

void _noop() {}
