import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every role distinct, so a colour found in the preview names its role.
final _distinct = ForumTheme.fromJson(const {
  'version': 1,
  'name': 'Distinct',
  'mode': 'dark',
  'colors': {
    'primary': '#F0F1F2',
    'secondary': '#20242A',
    'tertiary': '#3D8BFD',
    'quaternary': '#F5A623',
    'danger': '#E5484D',
    'success': '#30A46C',
    'love': '#D6409F',
  },
}, id: 'custom-distinct');

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  double width = 520,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ForumThemePreview(theme: theme),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Set<Color> _painted(WidgetTester tester) {
  final colors = <Color>{};
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.style?.color case final color?) colors.add(color);
    span.children?.forEach(visit);
  }

  for (final widget in tester.widgetList(
    find.descendant(
      of: find.byType(ForumThemePreview),
      matching: find.byWidgetPredicate((_) => true),
    ),
  )) {
    switch (widget) {
      case Container(:final decoration?) when decoration is BoxDecoration:
        if (decoration.color case final color?) colors.add(color);
        if (decoration.border case Border(:final bottom)) {
          colors.add(bottom.color);
        }
      case ColoredBox(:final color):
        colors.add(color);
      case DIcon(:final color?):
        colors.add(color);
      case RichText(:final text):
        visit(text);
    }
  }
  return colors;
}

void main() {
  testWidgets(
    'draws every colour a theme defines, including ones pages rarely show',
    (tester) async {
      final theme = AppTheme.fromPalette(_distinct.resolve(Brightness.dark));
      await _pump(tester, theme);
      final painted = _painted(tester);
      final tokens = theme.extension<DTokens>()!;
      final roles = {
        'text': tokens.foreground,
        'accent': tokens.primary,
        'highlight': theme.colorScheme.secondary,
        'mention': theme.shell.mention,
        'success': theme.discourse.success,
        'attention': tokens.destructive,
        'likes': theme.discourse.love,
      };
      for (final MapEntry(key: role, value: color) in roles.entries) {
        expect(painted, contains(color), reason: role);
      }
      expect(theme.colorScheme.secondary, const Color(0xfff5a623));
      expect(tokens.destructive, const Color(0xffe5484d));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fits narrow and wide columns in every preset, mode and text size',
    (tester) async {
      for (final preset in forumThemePresets) {
        for (final mode in Brightness.values) {
          for (final (width, scale) in [
            (220.0, 2.0),
            (360.0, 1.0),
            (760.0, 1.0),
          ]) {
            await _pump(
              tester,
              AppTheme.fromPalette(preset.resolve(mode)),
              width: width,
              scale: scale,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${preset.id} $mode $width@$scale',
            );
          }
        }
      }
    },
  );

  testWidgets('is one image to assistive technology', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      AppTheme.fromPalette(_distinct.resolve(Brightness.dark)),
    );
    expect(find.bySemanticsLabel('Forum appearance preview'), findsOneWidget);
    expect(find.bySemanticsLabel('Topics'), findsNothing);
    expect(find.bySemanticsLabel('New topic'), findsNothing);
    semantics.dispose();
  });

  testWidgets('darker sidebars reach the sample navigation', (tester) async {
    final theme = AppTheme.fromPalette(
      _distinct.copyWith(darkerSidebars: true).resolve(Brightness.dark),
    );
    await _pump(tester, theme);
    final sidebar = theme.extension<ForumThemeEffects>()!.sidebarTheme!;
    expect(
      Theme.of(tester.element(find.text('Topics'))).shell.sidebar,
      sidebar.shell.sidebar,
    );
    expect(
      Theme.of(
        tester.element(find.text('Welcome to the community')),
      ).shell.sidebar,
      theme.shell.sidebar,
    );
  });
}
