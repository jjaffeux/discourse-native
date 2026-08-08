import 'package:discourse_native/src/shell/shell_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rounds only the top-left corner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ShellPanel(child: SizedBox.expand())),
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
}
