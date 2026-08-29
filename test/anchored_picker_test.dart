import 'package:discourse_native/src/shell/anchored_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<TextEditingController> pumpPicker(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: Scaffold(
          body: AnchoredPickerContent(
            queryKey: const ValueKey('query'),
            queryController: controller,
            queryHint: 'Search…',
            onQueryChanged: (_) {},
            onQuerySubmitted: (_) {},
            children: [
              AnchoredPickerOption(
                title: const Text('Choice'),
                selected: true,
                showSelectionIndicator: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('uses compact input and option geometry for pointers', (
    tester,
  ) async {
    await pumpPicker(tester, TargetPlatform.macOS);

    final query = tester.widget<TextField>(find.byKey(const ValueKey('query')));
    expect(query.decoration?.isDense, isTrue);
    expect(
      query.decoration?.contentPadding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );

    final option = tester.widget<ListTile>(find.byType(ListTile));
    expect(option.minTileHeight, 32);
    expect(option.minLeadingWidth, 14);
    expect(option.contentPadding, const EdgeInsets.symmetric(horizontal: 10));
    expect(option.selected, isTrue);
    final highlight = Color.alphaBlend(
      AppTheme.light.colorScheme.onSurface.withValues(alpha: 0.06),
      AppTheme.light.shell.floating,
    );
    expect(option.selectedTileColor, highlight);
    expect(option.hoverColor, highlight);
    expect(
      (option.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(8),
    );
  });

  testWidgets('keeps input and option targets touch-friendly in sheets', (
    tester,
  ) async {
    await pumpPicker(tester, TargetPlatform.iOS);

    final query = tester.widget<TextField>(find.byKey(const ValueKey('query')));
    expect(query.decoration?.isDense, isFalse);
    expect(query.decoration?.contentPadding, isNull);

    final option = tester.widget<ListTile>(find.byType(ListTile));
    expect(option.minTileHeight, isNull);
    expect(option.minLeadingWidth, isNull);
    expect(option.contentPadding, const EdgeInsets.symmetric(horizontal: 16));
  });
}
