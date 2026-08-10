import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ResolvedSitePalette palette({Brightness brightness = Brightness.light}) =>
    ResolvedSitePalette(
      brightness: brightness,
      primary: const Color(0xFF111111),
      secondary: const Color(0xFFFDFDFD),
      tertiary: const Color(0xFF1256A0),
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
      expect(theme.discourse.love, source.love);
      expect(theme.discourse.whisper, source.primaryMedium);
    });

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
