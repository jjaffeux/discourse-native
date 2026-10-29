import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'inset segments keep menu and overflow actions independent on $platform',
      (tester) async {
        var selected = 'Latest';
        var overflowActions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => DButtonGroup.inset(
                    semanticLabel: 'Topic views',
                    children: [
                      DToggle(
                        size: DControlSize.segment,
                        variant: DToggleVariant.segmented,
                        pressed: selected == 'Latest',
                        onPressedChanged: (_) =>
                            setState(() => selected = 'Latest'),
                        child: const Text('Latest'),
                      ),
                      DDropdownMenu(
                        content: DDropdownMenuContent(
                          children: [
                            DDropdownMenuItem(
                              onPressed: () => setState(() => selected = 'New'),
                              child: const Text('New topics'),
                            ),
                          ],
                        ),
                        child: DDropdownMenuTrigger(
                          builder: (_, trigger) => DToggle(
                            size: DControlSize.segment,
                            variant: DToggleVariant.segmented,
                            pressed: selected == 'New',
                            focusNode: trigger.focusNode,
                            onPressedChanged: (_) => trigger.toggle(),
                            child: const Text('New'),
                          ),
                        ),
                      ),
                      DButton.iconOnly(
                        size: DControlSize.segment,
                        variant: DButtonVariant.ghost,
                        tooltip: 'More views',
                        icon: const DIcon(DIcons.ellipsis),
                        onPressed: () => overflowActions++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final frame = find.byType(DButtonGroup);
        expect(
          tester.getSize(frame).height,
          platform == TargetPlatform.macOS ? 30 : 36,
        );
        await tester.tap(find.text('New'));
        await tester.pumpAndSettle();
        expect(find.text('New topics').hitTestable(), findsOneWidget);
        await tester.tap(find.text('New topics'));
        await tester.pumpAndSettle();
        expect(selected, 'New');
        await tester.tap(find.byTooltip('More views'));
        await tester.pumpAndSettle();
        expect(overflowActions, 1);
        expect(selected, 'New');
        await tester.tap(find.text('Latest'));
        await tester.pumpAndSettle();
        expect(selected, 'Latest');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final menuToggle = tester.widget<DToggle>(
          find.widgetWithText(DToggle, 'New'),
        );
        expect(menuToggle.focusNode!.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('New topics'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
