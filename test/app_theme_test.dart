import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_tooltip.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ResolvedSitePalette palette({
  Brightness brightness = Brightness.light,
  double borderRadius = defaultDiscourseBorderRadius,
}) => ResolvedSitePalette(
  borderRadius: borderRadius,
  brightness: brightness,
  primary: const Color(0xFF111111),
  secondary: const Color(0xFFFDFDFD),
  tertiary: const Color(0xFF1256A0),
  accentSubtle: const Color(0xFF6E9BCB),
  quaternary: const Color(0xFF9A3412),
  headerBackground: const Color(0xFF010203),
  headerPrimary: const Color(0xFFF0F1F2),
  metadataColor: const Color(0xFF5A6470),
  contentBorderColor: const Color(0xFFD1D5DA),
  highlight: const Color(0xFFF2C200),
  danger: const Color(0xFFC80001),
  success: const Color(0xFF168821),
  love: const Color(0xFFEC5E82),
  selected: const Color(0xFF334455),
  selectedForeground: const Color(0xFFF6F7F8),
  hover: const Color(0xFF445566),
  primaryVeryLow: const Color(0xFFF5F5F5),
  primaryLow: const Color(0xFFE1E1E1),
  primaryLowMid: const Color(0xFFBBBBBB),
  primaryMedium: const Color(0xFF888888),
  primaryHigh: const Color(0xFF555555),
  primaryVeryHigh: const Color(0xFF292929),
  secondaryVeryHigh: const Color(0xFFF1F2F3),
  tertiaryLow: const Color(0xFFD5E8F6),
  quaternaryLow: const Color(0xFFF4D6C8),
  highlightLow: const Color(0xFFFFF1A8),
  dangerLow: const Color(0xFFF5C7C7),
  mentionBackground: const Color(0xFFE0E7EE),
  codeBlockBackground: const Color(0xFF20252B),
  inlineCodeBackground: const Color(0xFFE7EBEF),
  codeKeyword: const Color(0xFF8B2FA0),
  codeString: const Color(0xFF2E7D32),
  codeComment: const Color(0xFF6B7280),
  codeNumber: const Color(0xFFB35309),
  codeName: const Color(0xFF1A56B0),
  codeMeta: const Color(0xFF00707A),
);

double contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

double paintedContrast(
  Color foreground,
  Color background, {
  required Color backdrop,
}) {
  final paintedBackground = Color.alphaBlend(background, backdrop);
  final paintedForeground = Color.alphaBlend(foreground, paintedBackground);
  return contrast(paintedForeground, paintedBackground);
}

void main() {
  group('AppTheme.fromPalette', () {
    test('translates Discourse colors into Material roles', () {
      final source = palette();
      final theme = AppTheme.fromPalette(source);
      final scheme = theme.colorScheme;

      expect(scheme.brightness, source.brightness);
      expect(scheme.primary, source.tertiary);
      expect(scheme.onPrimary, source.secondary);
      expect(scheme.primaryContainer, source.tertiaryLow);
      expect(scheme.onPrimaryContainer, source.primary);
      expect(scheme.secondary, source.quaternary);
      expect(scheme.onSecondary, source.secondary);
      expect(scheme.secondaryContainer, source.quaternaryLow);
      expect(scheme.onSecondaryContainer, source.primary);
      expect(scheme.tertiary, source.highlight);
      expect(scheme.onTertiary, source.primary);
      expect(scheme.tertiaryContainer, source.highlightLow);
      expect(scheme.onTertiaryContainer, source.primary);
      expect(scheme.error, source.danger);
      expect(scheme.onError, source.secondary);
      expect(scheme.errorContainer, source.dangerLow);
      expect(scheme.onErrorContainer, source.primary);
      expect(scheme.surface, source.secondary);
      expect(scheme.onSurface, source.primary);
      expect(scheme.onSurfaceVariant, source.metadataColor);
      expect(scheme.surfaceContainerLowest, source.secondary);
      expect(scheme.surfaceContainerLow, source.primaryVeryLow);
      expect(scheme.surfaceContainer, source.primaryVeryLow);
      expect(scheme.surfaceContainerHigh, source.primaryLow);
      expect(scheme.surfaceContainerHighest, source.primaryLow);
      expect(scheme.outline, source.contentBorderColor);
      expect(scheme.outlineVariant, source.contentBorderColor);
      expect(scheme.surfaceTint, source.tertiary);
      expect(theme.discourse.primaryLowMid, source.primaryLowMid);
      expect(theme.discourse.primaryHigh, source.primaryHigh);
    });

    test('repairs low-contrast Material foreground roles', () {
      const gray = Color(0xFF777777);
      final json = palette().toJson();
      for (final name in [
        'primary',
        'secondary',
        'tertiary',
        'quaternary',
        'highlight',
        'danger',
        'tertiaryLow',
        'quaternaryLow',
        'highlightLow',
        'dangerLow',
      ]) {
        json[name] = gray.toARGB32();
      }

      final scheme = AppTheme.fromPalette(
        ResolvedSitePalette.fromJson(json),
      ).colorScheme;
      final pairs = [
        (scheme.onPrimary, scheme.primary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onSecondaryContainer, scheme.secondaryContainer),
        (scheme.onTertiary, scheme.tertiary),
        (scheme.onTertiaryContainer, scheme.tertiaryContainer),
        (scheme.onError, scheme.error),
        (scheme.onErrorContainer, scheme.errorContainer),
      ];

      for (final (foreground, background) in pairs) {
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
    });

    test('measures contrast after transparent roles are painted', () {
      final json = palette().toJson()
        ..['primary'] = Colors.black.toARGB32()
        ..['secondary'] = Colors.black.toARGB32()
        ..['tertiary'] = const Color(0x00FFFFFF).toARGB32()
        ..['tertiaryLow'] = const Color(0x40FFFFFF).toARGB32()
        ..['quaternary'] = const Color(0x20FFFFFF).toARGB32()
        ..['quaternaryLow'] = const Color(0x60FFFFFF).toARGB32()
        ..['highlight'] = const Color(0x00FFFFFF).toARGB32()
        ..['highlightLow'] = const Color(0x40FFFFFF).toARGB32()
        ..['danger'] = const Color(0x20FFFFFF).toARGB32()
        ..['dangerLow'] = const Color(0x60FFFFFF).toARGB32();

      final scheme = AppTheme.fromPalette(
        ResolvedSitePalette.fromJson(json),
      ).colorScheme;
      final pairs = [
        (scheme.onPrimary, scheme.primary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onSecondaryContainer, scheme.secondaryContainer),
        (scheme.onTertiary, scheme.tertiary),
        (scheme.onTertiaryContainer, scheme.tertiaryContainer),
        (scheme.onError, scheme.error),
        (scheme.onErrorContainer, scheme.errorContainer),
      ];

      for (final (foreground, background) in pairs) {
        expect(
          paintedContrast(foreground, background, backdrop: scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('maps shell, code, and Discourse semantic colors', () {
      final source = palette();
      final theme = AppTheme.fromPalette(source);

      expect(theme.scaffoldBackgroundColor, source.headerBackground);
      expect(theme.shell.rail, source.headerBackground);
      expect(theme.shell.railForeground, source.headerPrimary);
      expect(theme.shell.sidebar, source.primaryVeryLow);
      expect(theme.shell.content, source.secondary);
      expect(theme.shell.panel, source.primaryVeryLow);
      expect(theme.shell.divider, source.contentBorderColor);
      expect(theme.shell.floating, source.secondaryVeryHigh);
      expect(theme.shell.hover, source.hover);
      expect(theme.shell.selected, source.selected);
      expect(theme.shell.selectedForeground, source.selectedForeground);
      expect(theme.shell.marker, source.primaryHigh);
      expect(theme.shell.mention, source.mentionBackground);
      expect(theme.dividerTheme.color, source.contentBorderColor);

      expect(theme.code.blockBackground, source.codeBlockBackground);
      expect(theme.code.inlineBackground, source.inlineCodeBackground);
      expect(theme.code.keyword, source.codeKeyword);
      expect(theme.code.string, source.codeString);
      expect(theme.code.comment, source.codeComment);
      expect(theme.code.number, source.codeNumber);
      expect(theme.code.name, source.codeName);
      expect(theme.code.meta, source.codeMeta);

      expect(theme.discourse.success, source.success);
      expect(theme.discourse.unreadIndicator, source.accentSubtle);
      expect(theme.discourse.love, source.love);
      expect(theme.discourse.primaryHigh, source.primaryHigh);
      expect(theme.discourse.whisper, source.primaryMedium);
      expect(theme.discourse.primaryHigh, source.primaryHigh);
      expect(theme.discourse.primaryVeryHigh, source.primaryVeryHigh);
    });

    test(
      'uses the Discourse modular type scale instead of Material defaults',
      () {
        final text = AppTheme.fromPalette(palette()).textTheme;

        expect(text.displayLarge?.fontSize, DiscourseTypography.fontUp6);
        expect(text.displayMedium?.fontSize, DiscourseTypography.fontUp5);
        expect(text.displaySmall?.fontSize, DiscourseTypography.fontUp4);
        expect(text.headlineSmall?.fontSize, DiscourseTypography.fontUp3);
        expect(text.titleLarge?.fontSize, DiscourseTypography.fontUp2);
        expect(text.titleMedium?.fontSize, DiscourseTypography.fontUp1);
        expect(text.titleSmall?.fontSize, DiscourseTypography.base);
        expect(text.bodyLarge?.fontSize, DiscourseTypography.base);
        expect(text.bodyMedium?.fontSize, DiscourseTypography.base);
        expect(text.bodySmall?.fontSize, DiscourseTypography.fontDown1);
        expect(text.labelLarge?.fontSize, DiscourseTypography.base);
        expect(text.labelMedium?.fontSize, DiscourseTypography.fontDown1);
        expect(text.labelSmall?.fontSize, DiscourseTypography.fontDown2);

        for (final style in [
          text.displayLarge,
          text.displayMedium,
          text.displaySmall,
          text.headlineLarge,
          text.headlineMedium,
          text.headlineSmall,
          text.titleLarge,
          text.titleMedium,
          text.titleSmall,
          text.bodyLarge,
          text.bodyMedium,
          text.bodySmall,
          text.labelLarge,
          text.labelMedium,
          text.labelSmall,
        ]) {
          expect(style?.fontWeight, FontWeight.normal);
          expect(style?.letterSpacing, 0);
        }

        expect(text.titleMedium?.height, DiscourseTypography.lineHeightMedium);
        expect(text.bodyMedium?.height, DiscourseTypography.lineHeightLarge);
        expect(text.labelSmall?.height, DiscourseTypography.lineHeightMedium);
      },
    );

    test('maps the site palette into adaptive Cupertino controls', () {
      final source = palette();
      final theme = AppTheme.fromPalette(source);
      final cupertino = theme.cupertinoOverrideTheme!;

      expect(cupertino.brightness, source.brightness);
      expect(cupertino.primaryColor, source.tertiary);
      expect(cupertino.primaryContrastingColor, source.secondary);
      expect(cupertino.barBackgroundColor, source.primaryVeryLow);
      expect(cupertino.scaffoldBackgroundColor, source.secondary);
      expect(cupertino.selectionHandleColor, source.tertiary);
      expect(cupertino.applyThemeToAll, isTrue);
    });

    test('styles modal surfaces with Discourse theme tokens', () {
      final source = palette(borderRadius: 13);
      final theme = AppTheme.fromPalette(source);
      final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
      final sheetShape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;

      expect(theme.dialogTheme.backgroundColor, source.secondary);
      expect(
        theme.dialogTheme.titleTextStyle?.fontSize,
        DiscourseTypography.fontUp3,
      );
      expect(theme.dialogTheme.titleTextStyle?.fontWeight, FontWeight.w700);
      expect(
        theme.dialogTheme.contentTextStyle?.fontSize,
        DiscourseTypography.base,
      );
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(theme.dialogTheme.barrierColor, discourseModalBarrier);
      expect(theme.dialogTheme.clipBehavior, Clip.antiAlias);
      expect(
        theme.dialogTheme.actionsPadding,
        const EdgeInsets.fromLTRB(24, 16, 24, 16),
      );
      expect(dialogShape.borderRadius, BorderRadius.circular(13));

      for (final style in [
        theme.filledButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
        theme.textButtonTheme.style!,
      ]) {
        final shape = style.shape?.resolve({}) as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(13));
        expect(style.minimumSize?.resolve({}), const Size(0, 32));
        expect(
          style.padding?.resolve({}),
          const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        );
      }

      expect(theme.bottomSheetTheme.modalBackgroundColor, source.secondary);
      expect(theme.bottomSheetTheme.modalBarrierColor, discourseModalBarrier);
      expect(theme.bottomSheetTheme.clipBehavior, Clip.antiAlias);
      expect(
        sheetShape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(13)),
      );
    });

    test('keeps app-only placeholder colors out of site palettes', () {
      expect(
        AppTheme.fromPalette(palette()).shell.placeholder,
        ShellColors.light.placeholder,
      );
      expect(
        AppTheme.fromPalette(
          palette(brightness: Brightness.dark),
        ).shell.placeholder,
        ShellColors.dark.placeholder,
      );
    });

    test('forPalette is the same translation entry point', () {
      final source = palette();
      final theme = AppTheme.forPalette(source);

      expect(theme.colorScheme.primary, source.tertiary);
      expect(theme.shell.rail, source.headerBackground);
      expect(theme.code.keyword, source.codeKeyword);
      expect(theme.discourse.love, source.love);
    });
  });

  test('fallback themes retain their established semantic defaults', () {
    expect(AppTheme.light.shell, ShellColors.light);
    expect(AppTheme.dark.shell, ShellColors.dark);
    expect(AppTheme.light.code, CodeColors.light);
    expect(AppTheme.dark.code, CodeColors.dark);
    expect(AppTheme.light.discourse, DiscourseColors.light);
    expect(AppTheme.dark.discourse, DiscourseColors.dark);
  });

  test('fallback Material roles use the built-in Discourse schemes', () {
    final light = AppTheme.light.colorScheme;
    final dark = AppTheme.dark.colorScheme;

    expect(light.primary, discourseBlue);
    expect(light.secondary, const Color(0xFFE45735));
    expect(light.tertiary, const Color(0xFFFFFF4D));
    expect(light.error, const Color(0xFFC80001));
    expect(light.surface, ShellColors.light.content);
    expect(light.onSurface, ShellColors.light.railForeground);
    expect(light.onSurfaceVariant, DiscourseColors.light.primaryHigh);

    expect(dark.primary, discourseDarkBlue);
    expect(dark.secondary, const Color(0xFFC14924));
    expect(dark.tertiary, const Color(0xFFA87137));
    expect(dark.error, const Color(0xFFE45735));
    expect(dark.surface, ShellColors.dark.content);
    expect(dark.onSurface, ShellColors.dark.railForeground);
    expect(dark.onSurfaceVariant, DiscourseColors.dark.primaryHigh);
  });

  test('menus share the floating surface geometry', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final popup = theme.popupMenuTheme;
      expect(popup.color, theme.shell.floating);
      expect(popup.elevation, 8);
      expect(popup.surfaceTintColor, Colors.transparent);
      expect(popup.position, PopupMenuPosition.under);
      expect(popup.menuPadding, const EdgeInsets.all(6));

      final menu = theme.menuTheme.style!;
      expect(menu.backgroundColor!.resolve({}), theme.shell.floating);
      expect(menu.elevation!.resolve({}), 8);
      expect(menu.padding!.resolve({}), const EdgeInsets.all(6));
      final menuButton = theme.menuButtonTheme.style!;
      final hoverColor = Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
        ),
        theme.shell.floating,
      );
      expect(
        menuButton.backgroundColor!.resolve({WidgetState.hovered}),
        hoverColor,
      );
      expect(theme.hoverColor, hoverColor);
      expect(menuButton.backgroundColor!.resolve({}), Colors.transparent);
      expect(menuButton.overlayColor!.resolve({}), Colors.transparent);
      expect(menuButton.mouseCursor!.resolve({}), SystemMouseCursors.click);
      expect(
        menuButton.mouseCursor!.resolve({WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
      expect(
        theme.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve({}),
        theme.shell.floating,
      );
    }
  });

  testWidgets('menu rows paint their shared hover treatment', (tester) async {
    final controller = MenuController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MenuAnchor(
            controller: controller,
            menuChildren: [
              MenuItemButton(onPressed: () {}, child: const Text('Action')),
            ],
            builder: (context, controller, child) => TextButton(
              onPressed: controller.open,
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    controller.open();
    await tester.pumpAndSettle();

    final action = find.widgetWithText(MenuItemButton, 'Action');
    final material = find.descendant(
      of: action,
      matching: find.byType(Material),
    );
    expect(tester.widget<Material>(material).color, Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(action));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(action));
    final hoverColor = theme.menuButtonTheme.style!.backgroundColor!.resolve({
      WidgetState.hovered,
    });
    expect(tester.widget<Material>(material).color, hoverColor);
    expect(hoverColor, isNot(Colors.transparent));
  });

  test('tooltips use the floating surface and readable app typography', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final tooltip = theme.tooltipTheme;
      final decoration = tooltip.decoration! as BoxDecoration;

      expect(tooltip.constraints, DTooltip.defaultConstraints);
      expect(tooltip.padding, DTooltip.defaultPadding);
      expect(tooltip.margin, DTooltip.defaultMargin);
      expect(tooltip.verticalOffset, DTooltip.defaultVerticalOffset);
      expect(tooltip.textStyle?.fontSize, theme.textTheme.bodyMedium?.fontSize);
      expect(tooltip.textStyle?.color, theme.colorScheme.onSurface);
      expect(decoration.color, theme.shell.floating);
      expect(decoration.border, Border.all(color: theme.shell.divider));
      expect(decoration.borderRadius, BorderRadius.circular(10));
      expect(decoration.boxShadow, isNotEmpty);
    }
  });

  testWidgets('compact menu motion respects reduced motion', (tester) async {
    AnimationStyle? style;
    Widget app() => MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) {
          style = discoursePopupMenuAnimationStyle(context);
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(app());
    expect(style!.duration, discourseMenuOpenDuration);
    expect(style!.reverseDuration, discourseMenuCloseDuration);

    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(app());
    expect(style, AnimationStyle.noAnimation);
  });

  testWidgets('MaterialApp exposes the mapped Cupertino theme', (tester) async {
    late CupertinoThemeData cupertino;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            cupertino = CupertinoTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(cupertino.primaryColor, AppTheme.light.colorScheme.primary);
    expect(cupertino.barBackgroundColor, AppTheme.light.shell.sidebar);
    expect(cupertino.scaffoldBackgroundColor, AppTheme.light.shell.content);
    expect(cupertino.applyThemeToAll, isTrue);
  });
}
