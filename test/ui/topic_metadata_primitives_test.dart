import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filled selection uses the accent without a border or stripe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DItem(
            selected: true,
            selectionStyle: DItemSelectionStyle.filled,
            showSelectionIndicator: false,
            onPressed: () {},
            children: const [
              DItemContent(children: [Text('Topic')]),
            ],
          ),
        ),
      ),
    );
    final surfaces = tester.widgetList<Container>(
      find.descendant(of: find.byType(DItem), matching: find.byType(Container)),
    );
    final surface = surfaces.singleWhere((w) => w.decoration is BoxDecoration);
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect((decoration.border! as Border).top.color, Colors.transparent);
    expect(surface.foregroundDecoration, isNull);
    expect(
      decoration.color,
      DTokens.of(
        tester.element(find.byType(DItem)),
      ).primary.withValues(alpha: .12),
    );
  });
}
