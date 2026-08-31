import 'package:discourse_native/src/shell/anchored_layout.dart';
import 'package:discourse_native/src/shell/anchored_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<TextEditingController> pumpPicker(
    WidgetTester tester,
    TargetPlatform platform, {
    Widget? footer,
    bool queryEnabled = true,
    bool queryAutofocus = true,
  }) async {
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
            footer: footer,
            queryEnabled: queryEnabled,
            queryAutofocus: queryAutofocus,
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

  testWidgets('separates optional form content and configures its query', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      TargetPlatform.macOS,
      footer: const TextField(key: ValueKey('note')),
      queryEnabled: false,
      queryAutofocus: false,
    );

    final query = tester.widget<TextField>(find.byKey(const ValueKey('query')));
    expect(query.enabled, isFalse);
    expect(query.autofocus, isFalse);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byKey(const ValueKey('note')), findsOneWidget);
  });

  testWidgets('an explicit rectangle wins over the anchor context', (
    tester,
  ) async {
    const explicitAnchor = Rect.fromLTWH(70, 80, 20, 20);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAnchoredPicker<void>(
                context: context,
                anchorContext: context,
                anchor: explicitAnchor,
                title: 'Picker',
                barrierLabel: 'Dismiss picker',
                popoverKey: const ValueKey('popover'),
                builder: (_) => const Text('Content'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final layout = tester.widget<CustomSingleChildLayout>(
      find.ancestor(
        of: find.byKey(const ValueKey('popover')),
        matching: find.byType(CustomSingleChildLayout),
      ),
    );
    expect((layout.delegate as AnchoredLayout).anchor, explicitAnchor);
    final routeSemantics = tester
        .widgetList<Semantics>(
          find.ancestor(
            of: find.byKey(const ValueKey('popover')),
            matching: find.byType(Semantics),
          ),
        )
        .singleWhere((widget) => widget.properties.scopesRoute == true);
    expect(routeSemantics.properties.namesRoute, isTrue);
    expect(routeSemantics.properties.label, 'Picker');
  });

  testWidgets('keeps its position while asynchronous content changes size', (
    tester,
  ) async {
    const anchor = Rect.fromLTWH(70, 400, 20, 20);
    final contentHeight = ValueNotifier<double>(40);
    addTearDown(contentHeight.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAnchoredPicker<void>(
                context: context,
                anchor: anchor,
                title: 'Picker',
                barrierLabel: 'Dismiss picker',
                popoverKey: const ValueKey('stable-popover'),
                builder: (_) => ValueListenableBuilder<double>(
                  valueListenable: contentHeight,
                  builder: (_, height, _) => SizedBox(height: height),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('stable-popover'));
    final loadingRect = tester.getRect(picker);
    expect(loadingRect.size, const Size(252, 360));

    contentHeight.value = 600;
    await tester.pump();

    expect(tester.getRect(picker), loadingRect);
  });
}
