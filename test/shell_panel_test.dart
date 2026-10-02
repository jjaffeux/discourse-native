import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('nested panel previews do not inherit the outer window corner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: const WorkspacePanelCorner(
          radius: 10,
          child: WorkspacePanel(
            child: WorkspacePanel(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    final cards = tester.widgetList<DCard>(find.byType(DCard));
    expect(
      (cards.first.borderRadius as BorderRadius).bottomRight,
      const Radius.circular(10),
    );
    expect(cards.last.borderRadius, isNull);
    expect(cards.every((card) => !card.border), isTrue);
  });

  testWidgets('window corner follows native radius and only the outer panel', (
    tester,
  ) async {
    const channel = MethodChannel('org.discourse.native/window');
    var windowRadius = 16.0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => windowRadius,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    Future<void> show({
      TargetPlatform platform = TargetPlatform.macOS,
      bool atWindowEdge = true,
      TextDirection direction = TextDirection.ltr,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Directionality(
            textDirection: direction,
            child: ShellWorkspace(
              atWindowEdge: atWindowEdge,
              child: const Row(
                children: [
                  Expanded(
                    child: WorkspacePanel(
                      atRightEdge: false,
                      child: SizedBox.expand(),
                    ),
                  ),
                  Expanded(child: WorkspacePanel(child: SizedBox.expand())),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    BorderRadius? lastRadius() =>
        tester.widgetList<DCard>(find.byType(DCard)).last.borderRadius
            as BorderRadius?;
    await show();
    expect(
      tester.widgetList<DCard>(find.byType(DCard)).first.borderRadius,
      isNull,
    );
    expect(lastRadius()!.bottomRight, const Radius.circular(10));
    expect(lastRadius()!.bottomLeft, isNot(const Radius.circular(10)));

    for (final radius in [10.0, 0.0, 16.0]) {
      windowRadius = radius;
      tester.view.physicalSize = Size(800 + radius, 600);
      await tester.pumpAndSettle();
      expect(
        lastRadius()!.bottomRight,
        Radius.circular((radius - 6).clamp(0, double.infinity)),
      );
    }
    addTearDown(tester.view.reset);
    await show(atWindowEdge: false);
    expect(lastRadius(), isNull);
    await show(direction: TextDirection.rtl);
    expect(lastRadius(), isNull);
    await show(platform: TargetPlatform.windows);
    expect(lastRadius(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop workspace leaves six pixels at top, bottom and end', (
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
      expect(content.top - frame.top, 6);
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
