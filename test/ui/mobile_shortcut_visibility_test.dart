import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_shortcuts_help.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _shortcut = DShortcut.sequence(SingleActivator(LogicalKeyboardKey.keyG), [
  SingleActivator(LogicalKeyboardKey.keyH),
]);

void main() {
  for (final platform in TargetPlatform.values) {
    final mobile = {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    }.contains(platform);
    for (final width in [390.0, 1100.0]) {
      testWidgets('${platform.name} shortcut hints at $width px', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var invoked = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: Scaffold(
                body: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.keyB): () {
                      invoked = true;
                    },
                  },
                  child: const Focus(
                    autofocus: true,
                    child: Column(
                      children: [
                        DShortcutKeycaps(
                          key: ValueKey('hint'),
                          shortcut: _shortcut,
                          // Formatting cannot override the device's visibility.
                          platform: TargetPlatform.macOS,
                          semanticLabel: 'Go home keys',
                        ),
                        DCommandShortcut(Text('Command keys')),
                        DDropdownMenuShortcut('Dropdown keys'),
                        DContextMenuShortcut('Context keys'),
                        DMenubarShortcut('Menubar keys'),
                        DKbd('Authored keyboard content'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          for (final label in [
            'G',
            'H',
            'Command keys',
            'Dropdown keys',
            'Context keys',
            'Menubar keys',
          ]) {
            expect(find.text(label), mobile ? findsNothing : findsOneWidget);
          }
          expect(
            find.bySemanticsLabel(RegExp('Go home keys')),
            mobile ? findsNothing : findsWidgets,
          );
          if (mobile) {
            expect(
              tester.getSize(find.byKey(const ValueKey('hint'))),
              Size.zero,
            );
          }
          expect(find.text('Authored keyboard content'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
          expect(invoked, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets('${platform.name} tooltip retains its description', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = DTooltipController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: Scaffold(
              body: Center(
                child: DTooltip(
                  controller: controller,
                  message: 'Go home',
                  shortcut: _shortcut,
                  child: const Text('Target'),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSemantics(find.text('Target')).getSemanticsData().tooltip,
          mobile ? 'Go home' : 'Go home, ${_shortcut.semanticLabel(platform)}',
        );
        controller.show();
        await tester.pumpAndSettle();
        expect(find.text('Go home'), findsOneWidget);
        expect(find.byType(DKbd), mobile ? findsNothing : findsNWidgets(2));
        final surface = find
            .ancestor(of: find.text('Go home'), matching: find.byType(Padding))
            .first;
        if (mobile) {
          expect(
            tester.widget<Padding>(surface).padding,
            const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
          );
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name} does not open shortcut help', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Help'),
                onPressed: () => showKeyboardShortcuts(context),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-shortcuts-help')),
        findsNothing,
      );
    });
  }
}
