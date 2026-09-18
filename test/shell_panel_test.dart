import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop workspace leaves six pixels at the bottom and end', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Directionality(
            textDirection: direction,
            child: const ShellWorkspace(
              child: WorkspacePanel(
                child: SizedBox.expand(key: ValueKey('workspace-content')),
              ),
            ),
          ),
        ),
      );
      final frame = tester.getRect(find.byType(ShellWorkspace));
      final content = tester.getRect(
        find.byKey(const ValueKey('workspace-content')),
      );
      expect(frame.bottom - content.bottom, 6);
      expect(
        direction == TextDirection.ltr
            ? frame.right - content.right
            : content.left - frame.left,
        6,
      );
      expect(find.byType(DCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('rounds only the top-left corner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ShellPanel(child: SizedBox.expand()),
      ),
    );

    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(ShellPanel),
        matching: find.byType(ClipRRect),
      ),
    );

    expect(
      clip.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(ShellPanel.cornerRadius),
      ),
    );
  });

  testWidgets('draws a divider outline around the panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ShellPanel(child: SizedBox.expand()),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ShellPanel),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = box.decoration as BoxDecoration;

    expect(box.position, DecorationPosition.foreground);
    expect(
      decoration.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(ShellPanel.cornerRadius),
      ),
    );
    expect(decoration.border, Border.all(color: ShellColors.light.divider));
  });
}
