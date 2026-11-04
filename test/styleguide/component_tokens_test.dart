import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'derived controls reuse immutable tokens and follow palette changes',
    () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final installed = theme.extension<DTokens>()!;
        expect(installed.buttonTheme, same(installed.buttonTheme));
        final tokens = DTokens.fromTheme(theme);
        expect(tokens.controlTheme, same(tokens.controlTheme));
        expect(tokens.buttonTheme, same(tokens.buttonTheme));
        final changed = tokens.copyWith(
          colors: tokens.colors.copyWith(onSurface: Colors.purple),
          background: Colors.orange,
        );
        expect(changed.controlTheme, isNot(same(tokens.controlTheme)));
        expect(changed.controlTheme.outline.foreground, Colors.purple);
        expect(changed.buttonTheme, isNot(same(tokens.buttonTheme)));
        expect(
          changed.buttonTheme.outline.background,
          isNot(tokens.buttonTheme.outline.background),
        );
        final controls = tokens.controlTheme;
        final custom = changed.copyWith(controls: controls);
        expect(custom.controlTheme, same(controls));
        expect(custom.buttonTheme.radius, controls.radius);
        expect(custom.buttonTheme, same(custom.buttonTheme));
        final resized = DTokens.fromTheme(theme).copyWith(radius: 12);
        expect(resized.controlRadius, 12);
        expect(resized.buttonTheme.radius, 12);
      }
    },
  );

  test(
    'all app and sample palettes map existing colors to component tokens',
    () {
      for (final mode in StyleguideTheme.values) {
        final theme = mode.resolve(AppTheme.light);
        final tokens = theme.extension<DTokens>()!;
        expect(tokens.background, theme.shell.content);
        expect(tokens.surface, theme.shell.floating);
        expect(tokens.border, theme.shell.divider);
        expect(tokens.hover, theme.hoverColor);
        expect(tokens.selected, theme.shell.selected);
        expect(tokens.selectedForeground, theme.shell.selectedForeground);
        expect(tokens.primary, theme.colorScheme.primary);
      }
    },
  );

  testWidgets(
    'components work under an ordinary Flutter theme and honor reduced motion',
    (tester) async {
      late DTokens tokens;
      late Duration duration;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.teal),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                tokens = DTokens.of(context);
                duration = DMotion.duration(context, DMotion.enter);
                return Text(
                  'Fallback',
                  style: TextStyle(color: tokens.foreground),
                );
              },
            ),
          ),
        ),
      );
      expect(
        tokens.primary,
        Theme.of(tester.element(find.text('Fallback'))).colorScheme.primary,
      );
      expect(duration, Duration.zero);
    },
  );

  testWidgets('an open overlay receives live palette changes', (tester) async {
    final controller = OverlayPortalController();
    var dark = false;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            themeAnimationDuration: Duration.zero,
            home: OverlayPortal(
              controller: controller,
              overlayChildBuilder: (context) => Center(
                child: ColoredBox(
                  key: const ValueKey('open-token-overlay'),
                  color: DTokens.of(context).surface,
                  child: const Text('Overlay'),
                ),
              ),
              child: const SizedBox(),
            ),
          );
        },
      ),
    );
    controller.show();
    await tester.pump();
    final overlay = find.byKey(const ValueKey('open-token-overlay'));
    expect(
      tester.widget<ColoredBox>(overlay).color,
      AppTheme.light.shell.floating,
    );
    update(() => dark = true);
    await tester.pump();
    expect(
      tester.widget<ColoredBox>(overlay).color,
      AppTheme.dark.shell.floating,
    );
  });
}
