import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'horizontal group joins radii and preserves independent actions',
    (tester) async {
      var first = 0;
      var second = 0;
      await _pump(
        tester,
        DButtonGroup(
          semanticLabel: 'Message actions',
          children: [
            DButton(
              key: const ValueKey('first'),
              variant: DButtonVariant.outline,
              onPressed: () => first++,
              label: const Text('Archive'),
            ),
            DButton(
              key: const ValueKey('second'),
              variant: DButtonVariant.outline,
              onPressed: () => second++,
              label: const Text('Report'),
            ),
          ],
        ),
      );

      final firstRect = tester.getRect(find.byKey(const ValueKey('first')));
      final secondRect = tester.getRect(find.byKey(const ValueKey('second')));
      expect(firstRect.right, secondRect.left);
      expect(firstRect.height, secondRect.height);
      _expectCorners(tester, 0, const [false, true, true, false]);
      _expectCorners(tester, 1, const [true, false, false, true]);

      await tester.tap(find.byKey(const ValueKey('first')));
      await tester.tap(find.byKey(const ValueKey('second')));
      expect((first, second), (1, 1));
      expect(
        tester.getSemantics(find.byType(DButtonGroup)),
        matchesSemantics(label: 'Message actions', hasEnabledState: false),
      );
    },
  );

  testWidgets('RTL mirrors the joined corners without reordering callbacks', (
    tester,
  ) async {
    final activations = <String>[];
    await _pump(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: DButtonGroup(
          children: [
            DButton(
              onPressed: () => activations.add('first'),
              label: const Text('الأول'),
            ),
            DButton(
              onPressed: () => activations.add('second'),
              label: const Text('الثاني'),
            ),
          ],
        ),
      ),
    );

    _expectCorners(tester, 0, const [true, false, false, true]);
    _expectCorners(tester, 1, const [false, true, true, false]);
    await tester.tap(find.text('الأول'));
    await tester.tap(find.text('الثاني'));
    expect(activations, ['first', 'second']);
  });

  testWidgets('vertical group joins top and bottom and keeps Tab navigation', (
    tester,
  ) async {
    await _pump(
      tester,
      DButtonGroup(
        orientation: DButtonGroupOrientation.vertical,
        semanticLabel: 'Zoom controls',
        children: [
          DButton.iconOnly(
            icon: const Icon(Icons.add),
            tooltip: 'Zoom in',
            onPressed: () {},
          ),
          DButton.iconOnly(
            icon: const Icon(Icons.remove),
            tooltip: 'Zoom out',
            onPressed: () {},
          ),
        ],
      ),
    );

    _expectCorners(tester, 0, const [false, false, true, true]);
    _expectCorners(tester, 1, const [true, true, false, false]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
      Focus.of(tester.element(find.byType(FilledButton).first)).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
      Focus.of(tester.element(find.byType(FilledButton).last)).hasFocus,
      isTrue,
    );
  });

  testWidgets('input expands beside a fixed action and retains editing state', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 280,
        child: DButtonGroup(
          mainAxisSize: MainAxisSize.max,
          semanticLabel: 'Search',
          children: [
            const DButtonGroupText(child: Text('Query')),
            DButtonGroupExpanded(child: DInput(hintText: 'Search...')),
            const DButton.iconOnly(
              icon: Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _noop,
              variant: DButtonVariant.outline,
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'joined state');
    await tester.pump();
    expect(find.text('joined state'), findsOneWidget);
    expect(tester.getRect(find.byType(DButtonGroup)).width, 280);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separator and text remain passive while controls stay enabled', (
    tester,
  ) async {
    await _pump(
      tester,
      const DButtonGroup(
        children: [
          DButtonGroupText(
            semanticLabel: 'Current branch main',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.account_tree), Text('main')],
            ),
          ),
          DButtonGroupSeparator(),
          DButton(label: Text('Copy'), onPressed: _noop),
        ],
      ),
    );

    expect(find.byType(DSeparator), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(DButtonGroupText)),
      matchesSemantics(label: 'Current branch main'),
    );
  });

  testWidgets('touch targets stay 48px while desktop artwork remains compact', (
    tester,
  ) async {
    await _pump(
      tester,
      const DButtonGroup(
        children: [
          DButton.iconOnly(
            icon: Icon(Icons.add),
            tooltip: 'Add',
            size: DButtonSize.extraSmall,
            onPressed: _noop,
          ),
          DButton.iconOnly(
            icon: Icon(Icons.remove),
            tooltip: 'Remove',
            size: DButtonSize.extraSmall,
            onPressed: _noop,
          ),
        ],
      ),
      platform: TargetPlatform.iOS,
    );

    for (final button in find.byType(FilledButton).evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)).height, 48);
    }
  });
}

void _expectCorners(WidgetTester tester, int index, List<bool> square) {
  final button = tester.widget<FilledButton>(
    find.byType(FilledButton).at(index),
  );
  final shape = button.style!.shape!.resolve({})!;
  final size = tester.getSize(find.byType(FilledButton).at(index));
  final path = shape.getOuterPath(Offset.zero & size);
  final points = [
    const Offset(.25, .25),
    Offset(size.width - .25, .25),
    Offset(size.width - .25, size.height - .25),
    Offset(.25, size.height - .25),
  ];
  for (var corner = 0; corner < points.length; corner++) {
    expect(path.contains(points[corner]), square[corner]);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    home: Scaffold(body: Center(child: child)),
  ),
);

void _noop() {}
