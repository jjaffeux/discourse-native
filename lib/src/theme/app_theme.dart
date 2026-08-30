import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/site_appearance.dart';
import 'color_contrast.dart';
import 'd_button.dart';
import 'd_tooltip.dart';

/// The tertiary color of Discourse's default light scheme.
const Color discourseBlue = Color(0xFF0088CC);

/// The tertiary color of Discourse's built-in dark scheme.
const Color discourseDarkBlue = Color(0xFF099DD7);

/// What Discourse paints a like — `$love` in its stylesheets.
///
/// The fallback used until a site supplies its own `$love` value.
const Color discourseLove = Color(0xFFFA6C8D);

/// Discourse's default `$success` colour.
const Color discourseSuccess = Color(0xFF009900);

/// Core Discourse's modal backdrop: black animated to 60% opacity.
const Color discourseModalBarrier = Color(0x99000000);

const Duration discourseMenuOpenDuration = Duration(milliseconds: 140);
const Duration discourseMenuCloseDuration = Duration(milliseconds: 100);

/// The compact menu motion used where Flutter owns the popup route.
///
/// Rich choice menus use the same timing with an app-owned transition. Raw
/// popup menus cannot replace Flutter's grow transition, but this removes its
/// slow 300ms stagger and keeps reduced-motion behavior consistent.
AnimationStyle discoursePopupMenuAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: discourseMenuOpenDuration,
        reverseDuration: discourseMenuCloseDuration,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

/// Discourse's 16px modular type scale, resolved from `font-variables.scss`.
///
/// Keeping the values here avoids silently falling back to Material's smaller
/// 14px body and title styles when a widget only chooses a semantic text role.
abstract final class DiscourseTypography {
  static const double base = 16;
  static const double fontUp1 = 18.3792;
  static const double fontUp2 = 21.112;
  static const double fontUp3 = 24.2512;
  static const double fontUp4 = 28.0176;
  static const double fontUp5 = 32;
  static const double fontUp6 = 36.736;
  static const double fontDown1 = 13.9296;
  static const double fontDown2 = 12.1264;
  static const double fontDown3 = 10.5584;
  static const double code = 14;
  static const double codeLineHeight = 17 / 13;

  static const double lineHeightMedium = 1.2;
  static const double lineHeightLarge = 1.4;
  static const double lineHeightCooked = 1.5;
}

Color _readableOn(
  Color background,
  Color preferred, {
  required Color backdrop,
  Color? alternative,
}) => contrastSafeForeground(
  background: background,
  backdrop: backdrop,
  preferred: [preferred, alternative],
);

/// The stacked neutral surfaces the shell is built from.
///
/// These live outside [ColorScheme] because the shell needs several distinct
/// neutrals sitting directly next to each other, which Material's surface roles
/// do not map onto cleanly.
@immutable
class ShellColors extends ThemeExtension<ShellColors> {
  const ShellColors({
    required this.rail,
    required this.railForeground,
    required this.sidebar,
    required this.content,
    required this.panel,
    required this.divider,
    required this.floating,
    required this.hover,
    required this.selected,
    required this.selectedForeground,
    required this.placeholder,
    required this.marker,
    required this.mention,
  });

  final Color rail;

  /// Text and icon colour drawn directly on [rail].
  final Color railForeground;

  final Color sidebar;
  final Color content;
  final Color panel;
  final Color divider;

  /// Surface for elements that float *over* the columns, such as the user bar.
  final Color floating;

  /// Wash laid over [content] for the row the pointer is on. Opaque rather than
  /// a translucent tint so a hovered row does not go see-through over whatever
  /// happens to be painted behind the column.
  final Color hover;

  /// Background and foreground for the currently selected navigation row.
  final Color selected;
  final Color selectedForeground;

  /// Text for anything the UI shows but cannot do yet: fake rows, stand-in
  /// counts, destinations with nothing behind them. Nothing that actually works
  /// is ever drawn in it, so anything orange on screen is a to-do list item.
  final Color placeholder;

  /// The markdown syntax itself in the composer — the `**`, the `#`, the
  /// backticks.
  ///
  /// Its own colour rather than [CodeColors.comment], which reads as "de-
  /// emphasised" but only reaches 4.3:1 against [content] in the dark scheme.
  /// These characters are not decoration: someone who cannot read the `**`
  /// cannot tell bold from italic, and the two post differently. Both values
  /// clear 4.5:1 against the surface the composer is drawn on.
  final Color marker;

  /// Behind a mention or hashtag pill, mirroring Discourse's
  /// `--mention-background-color`.
  ///
  /// Not [rail], which is the nearest existing neutral and the wrong one: in
  /// the dark scheme it is *darker* than every surface a pill is drawn on —
  /// [content], [sidebar] where chat renders, [floating] in a user card —
  /// while Discourse's is a step lighter than its surface. Inline code has its
  /// own [CodeColors.inlineBackground], because a mention is not a code span.
  final Color mention;

  static const ShellColors dark = ShellColors(
    rail: Color(0xFF131417),
    railForeground: Color(0xFFDDDDDD),
    sidebar: Color(0xFF1A1C20),
    content: Color(0xFF212429),
    panel: Color(0xFF1A1C20),
    divider: Color(0xFF2B2E35),
    floating: Color(0xFF272B32),
    hover: Color(0xFF262A30),
    selected: Color(0x290099DD),
    selectedForeground: Color(0xFFDDDDDD),
    placeholder: Color(0xFFFF9E4D),
    marker: Color(0xFF8B939F),
    mention: Color(0xFF3A3F48),
  );

  static const ShellColors light = ShellColors(
    rail: Color(0xFFE3E6EA),
    railForeground: Color(0xFF222222),
    sidebar: Color(0xFFF1F3F5),
    content: Color(0xFFFFFFFF),
    panel: Color(0xFFF1F3F5),
    divider: Color(0xFFDBDFE4),
    floating: Color(0xFFFFFFFF),
    hover: Color(0xFFF6F8F9),
    selected: Color(0x290088CC),
    selectedForeground: Color(0xFF222222),
    placeholder: Color(0xFFC25400),
    marker: Color(0xFF6B7280),
    mention: Color(0xFFDFE4E9),
  );

  @override
  ShellColors copyWith({
    Color? rail,
    Color? railForeground,
    Color? sidebar,
    Color? content,
    Color? panel,
    Color? divider,
    Color? floating,
    Color? hover,
    Color? selected,
    Color? selectedForeground,
    Color? placeholder,
    Color? marker,
    Color? mention,
  }) {
    return ShellColors(
      rail: rail ?? this.rail,
      railForeground: railForeground ?? this.railForeground,
      sidebar: sidebar ?? this.sidebar,
      content: content ?? this.content,
      panel: panel ?? this.panel,
      divider: divider ?? this.divider,
      floating: floating ?? this.floating,
      hover: hover ?? this.hover,
      selected: selected ?? this.selected,
      selectedForeground: selectedForeground ?? this.selectedForeground,
      placeholder: placeholder ?? this.placeholder,
      marker: marker ?? this.marker,
      mention: mention ?? this.mention,
    );
  }

  @override
  ShellColors lerp(ThemeExtension<ShellColors>? other, double t) {
    if (other is! ShellColors) return this;
    return ShellColors(
      rail: Color.lerp(rail, other.rail, t)!,
      railForeground: Color.lerp(railForeground, other.railForeground, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      content: Color.lerp(content, other.content, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      floating: Color.lerp(floating, other.floating, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      selectedForeground: Color.lerp(
        selectedForeground,
        other.selectedForeground,
        t,
      )!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      marker: Color.lerp(marker, other.marker, t)!,
      mention: Color.lerp(mention, other.mention, t)!,
    );
  }
}

/// Colors for the token kinds a syntax highlighter reports.
///
/// Like [ShellColors] these sit outside [ColorScheme], which has no roles for
/// "string" or "comment". The fallbacks are tuned per brightness rather than
/// derived from the seed, and a resolved site palette supplies the exact
/// syntax roles: generated Material colors do not guarantee that tokens stay
/// distinguishable from each other.
@immutable
class CodeColors extends ThemeExtension<CodeColors> {
  const CodeColors({
    required this.blockBackground,
    required this.inlineBackground,
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.name,
    required this.meta,
  });

  /// Backgrounds for fenced blocks and inline code respectively.
  final Color blockBackground;
  final Color inlineBackground;

  /// Keywords, literals and operators.
  final Color keyword;

  /// String and regexp literals.
  final Color string;

  /// Comments and quoted documentation.
  final Color comment;

  /// Numbers and other scalar literals.
  final Color number;

  /// Declared names: functions, classes, sections, tags.
  final Color name;

  /// Annotations, preprocessor lines, attributes.
  final Color meta;

  static const CodeColors dark = CodeColors(
    blockBackground: Color(0xFF131417),
    inlineBackground: Color(0xFF131417),
    keyword: Color(0xFFC792EA),
    string: Color(0xFF9CCC7C),
    comment: Color(0xFF7E8794),
    number: Color(0xFFF78C6C),
    name: Color(0xFF82AAFF),
    meta: Color(0xFF89DDFF),
  );

  static const CodeColors light = CodeColors(
    blockBackground: Color(0xFFE3E6EA),
    inlineBackground: Color(0xFFE3E6EA),
    keyword: Color(0xFF8B2FA0),
    string: Color(0xFF2E7D32),
    comment: Color(0xFF6B7280),
    number: Color(0xFFB35309),
    name: Color(0xFF1A56B0),
    meta: Color(0xFF00707A),
  );

  @override
  CodeColors copyWith({
    Color? blockBackground,
    Color? inlineBackground,
    Color? keyword,
    Color? string,
    Color? comment,
    Color? number,
    Color? name,
    Color? meta,
  }) {
    return CodeColors(
      blockBackground: blockBackground ?? this.blockBackground,
      inlineBackground: inlineBackground ?? this.inlineBackground,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      comment: comment ?? this.comment,
      number: number ?? this.number,
      name: name ?? this.name,
      meta: meta ?? this.meta,
    );
  }

  @override
  CodeColors lerp(ThemeExtension<CodeColors>? other, double t) {
    if (other is! CodeColors) return this;
    return CodeColors(
      blockBackground: Color.lerp(blockBackground, other.blockBackground, t)!,
      inlineBackground: Color.lerp(
        inlineBackground,
        other.inlineBackground,
        t,
      )!,
      keyword: Color.lerp(keyword, other.keyword, t)!,
      string: Color.lerp(string, other.string, t)!,
      comment: Color.lerp(comment, other.comment, t)!,
      number: Color.lerp(number, other.number, t)!,
      name: Color.lerp(name, other.name, t)!,
      meta: Color.lerp(meta, other.meta, t)!,
    );
  }
}

/// Discourse semantic colours with no Material [ColorScheme] equivalent.
@immutable
class DiscourseColors extends ThemeExtension<DiscourseColors> {
  const DiscourseColors({
    required this.success,
    required this.unreadIndicator,
    required this.love,
    required this.primaryLowMid,
    required this.primaryHigh,
    required this.whisper,
    required this.primaryVeryHigh,
  });

  final Color success;

  /// An ordinary unread dot, matching core's
  /// `--token-color-background-accent-subtle` role.
  final Color unreadIndicator;

  final Color love;

  /// Faint foregrounds such as Chat's direct-reply icon, matching core's
  /// `--primary-low-mid` role.
  final Color primaryLowMid;

  /// Muted foregrounds such as legacy GitHub onebox SVGs, matching core's
  /// `--primary-high` role.
  final Color primaryHigh;

  /// Whisper body text, mirroring Discourse's `--primary-medium` role.
  final Color whisper;

  /// Strong secondary copy, mirroring `--primary-very-high`.
  final Color primaryVeryHigh;

  static const DiscourseColors light = DiscourseColors(
    success: discourseSuccess,
    unreadIndicator: Color(0xFF66CCFF),
    love: discourseLove,
    primaryLowMid: Color(0xFFBDBDBD),
    primaryHigh: Color(0xFF646464),
    whisper: Color(0xFF919191),
    primaryVeryHigh: Color(0xFF414141),
  );

  static const DiscourseColors dark = DiscourseColors(
    success: Color(0xFF1CA551),
    unreadIndicator: discourseBlue,
    love: discourseLove,
    primaryLowMid: Color(0xFF7A7A7A),
    primaryHigh: Color(0xFFA6A6A6),
    whisper: Color(0xFF909090),
    primaryVeryHigh: Color(0xFFC7C7C7),
  );

  @override
  DiscourseColors copyWith({
    Color? success,
    Color? unreadIndicator,
    Color? love,
    Color? primaryLowMid,
    Color? primaryHigh,
    Color? whisper,
    Color? primaryVeryHigh,
  }) => DiscourseColors(
    success: success ?? this.success,
    unreadIndicator: unreadIndicator ?? this.unreadIndicator,
    love: love ?? this.love,
    primaryLowMid: primaryLowMid ?? this.primaryLowMid,
    primaryHigh: primaryHigh ?? this.primaryHigh,
    whisper: whisper ?? this.whisper,
    primaryVeryHigh: primaryVeryHigh ?? this.primaryVeryHigh,
  );

  @override
  DiscourseColors lerp(ThemeExtension<DiscourseColors>? other, double t) {
    if (other is! DiscourseColors) return this;
    return DiscourseColors(
      success: Color.lerp(success, other.success, t)!,
      unreadIndicator: Color.lerp(unreadIndicator, other.unreadIndicator, t)!,
      love: Color.lerp(love, other.love, t)!,
      primaryLowMid: Color.lerp(primaryLowMid, other.primaryLowMid, t)!,
      primaryHigh: Color.lerp(primaryHigh, other.primaryHigh, t)!,
      whisper: Color.lerp(whisper, other.whisper, t)!,
      primaryVeryHigh: Color.lerp(primaryVeryHigh, other.primaryVeryHigh, t)!,
    );
  }
}

extension ShellColorsAccess on ThemeData {
  /// Shorthand for `Theme.of(context).extension<ShellColors>()!`.
  ShellColors get shell => extension<ShellColors>()!;

  /// Shorthand for `Theme.of(context).extension<CodeColors>()!`.
  CodeColors get code => extension<CodeColors>()!;

  /// Shorthand for `Theme.of(context).extension<DiscourseColors>()!`.
  DiscourseColors get discourse => extension<DiscourseColors>()!;
}

abstract final class AppTheme {
  static ThemeData get light => _build(
    Brightness.light,
    ShellColors.light,
    CodeColors.light,
    DiscourseColors.light,
  );
  static ThemeData get dark => _build(
    Brightness.dark,
    ShellColors.dark,
    CodeColors.dark,
    DiscourseColors.dark,
  );

  /// Builds the native shell from the colors resolved by Discourse itself.
  ///
  /// Discourse names colors for their CSS jobs rather than Material roles:
  /// `primary` is text, `secondary` is the page, and `tertiary` is its main
  /// interactive accent. This is the single translation boundary between the
  /// two vocabularies.
  static ThemeData fromPalette(ResolvedSitePalette palette) {
    final fallback = palette.brightness == Brightness.dark
        ? ShellColors.dark
        : ShellColors.light;
    final shell = ShellColors(
      rail: palette.headerBackground,
      railForeground: palette.headerPrimary,
      sidebar: palette.primaryVeryLow,
      content: palette.secondary,
      panel: palette.primaryVeryLow,
      divider: palette.contentBorderColor,
      floating: palette.secondaryVeryHigh,
      hover: palette.hover,
      selected: palette.selected,
      selectedForeground: palette.selectedForeground,
      // This is an app development affordance, not a Discourse theme role.
      placeholder: fallback.placeholder,
      marker: palette.primaryHigh,
      mention: palette.mentionBackground,
    );
    final code = CodeColors(
      blockBackground: palette.codeBlockBackground,
      inlineBackground: palette.inlineCodeBackground,
      keyword: palette.codeKeyword,
      string: palette.codeString,
      comment: palette.codeComment,
      number: palette.codeNumber,
      name: palette.codeName,
      meta: palette.codeMeta,
    );
    final discourse = DiscourseColors(
      success: palette.success,
      unreadIndicator: palette.accentSubtle,
      love: palette.love,
      primaryLowMid: palette.primaryLowMid,
      primaryHigh: palette.primaryHigh,
      whisper: palette.primaryMedium,
      primaryVeryHigh: palette.primaryVeryHigh,
    );
    final materialBackdrop = opaqueColorOnCanvas(
      palette.secondary,
      palette.brightness,
    );

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: palette.tertiary,
          brightness: palette.brightness,
        ).copyWith(
          primary: palette.tertiary,
          onPrimary: _readableOn(
            palette.tertiary,
            palette.secondary,
            backdrop: materialBackdrop,
            alternative: palette.primary,
          ),
          primaryContainer: palette.tertiaryLow,
          onPrimaryContainer: _readableOn(
            palette.tertiaryLow,
            palette.primary,
            backdrop: materialBackdrop,
            alternative: palette.secondary,
          ),
          secondary: palette.quaternary,
          onSecondary: _readableOn(
            palette.quaternary,
            palette.secondary,
            backdrop: materialBackdrop,
            alternative: palette.primary,
          ),
          secondaryContainer: palette.quaternaryLow,
          onSecondaryContainer: _readableOn(
            palette.quaternaryLow,
            palette.primary,
            backdrop: materialBackdrop,
            alternative: palette.secondary,
          ),
          tertiary: palette.highlight,
          onTertiary: _readableOn(
            palette.highlight,
            palette.primary,
            backdrop: materialBackdrop,
            alternative: palette.secondary,
          ),
          tertiaryContainer: palette.highlightLow,
          onTertiaryContainer: _readableOn(
            palette.highlightLow,
            palette.primary,
            backdrop: materialBackdrop,
            alternative: palette.secondary,
          ),
          error: palette.danger,
          onError: _readableOn(
            palette.danger,
            palette.secondary,
            backdrop: materialBackdrop,
            alternative: palette.primary,
          ),
          errorContainer: palette.dangerLow,
          onErrorContainer: _readableOn(
            palette.dangerLow,
            palette.primary,
            backdrop: materialBackdrop,
            alternative: palette.secondary,
          ),
          surface: palette.secondary,
          onSurface: palette.primary,
          onSurfaceVariant: palette.metadataColor,
          surfaceContainerLowest: palette.secondary,
          surfaceContainerLow: palette.primaryVeryLow,
          surfaceContainer: palette.primaryVeryLow,
          surfaceContainerHigh: palette.primaryLow,
          surfaceContainerHighest: palette.primaryLow,
          outline: palette.contentBorderColor,
          outlineVariant: palette.contentBorderColor,
          surfaceTint: palette.tertiary,
        );

    return _build(
      palette.brightness,
      shell,
      code,
      discourse,
      colorScheme: colorScheme,
      borderRadius: palette.borderRadius,
    );
  }

  /// Alias for callers that describe theme creation by its input.
  static ThemeData forPalette(ResolvedSitePalette palette) =>
      fromPalette(palette);

  static ThemeData _build(
    Brightness brightness,
    ShellColors shell,
    CodeColors code,
    DiscourseColors discourse, {
    ColorScheme? colorScheme,
    double borderRadius = defaultDiscourseBorderRadius,
  }) {
    final resolvedColorScheme =
        colorScheme ?? _fallbackColorScheme(brightness, shell, discourse);

    final modalShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );
    final textTheme = _discourseTextTheme(
      ThemeData(colorScheme: resolvedColorScheme).textTheme,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    );
    final buttonGeometry = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          // Keep Material call sites at the same regular, font-relative
          // geometry as DButton. The extra pixel accounts for the border
          // Flutter paints inside an outlined button's layout box.
          horizontal: DiscourseTypography.base * 0.65 + 1,
          vertical: DiscourseTypography.base * 0.5 + 1,
        ),
      ),
      shape: WidgetStatePropertyAll(buttonShape),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.normal),
      ),
      // Flutter's desktop density removes eight pixels of vertical padding,
      // making ordinary actions look substantially smaller than DButtons.
      // Compact toolbars opt into compact density at their own call sites.
      visualDensity: VisualDensity.standard,
    );
    // Flutter cannot express core's 0 8px 60px CSS shadow directly through a
    // dialog theme. Elevation 24 gives these native surfaces comparable depth.
    final modalShadow = Colors.black.withValues(
      alpha: brightness == Brightness.dark ? 1 : 0.6,
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: shell.divider),
    );
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(shell.floating),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.4)),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(8),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      side: WidgetStatePropertyAll(BorderSide(color: shell.divider)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final menuItemHoverColor = Color.alphaBlend(
      resolvedColorScheme.onSurface.withValues(
        alpha: brightness == Brightness.dark ? 0.10 : 0.06,
      ),
      shell.floating,
    );
    final tooltipDecoration = BoxDecoration(
      color: shell.floating,
      border: Border.all(color: shell.divider),
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: brightness == Brightness.dark ? 0.40 : 0.22,
          ),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return ThemeData(
      colorScheme: resolvedColorScheme,
      textTheme: textTheme,
      // MaterialApp remains the common application shell, but Flutter's
      // adaptive widgets read CupertinoTheme on Apple platforms. Keep that
      // theme on the same Discourse palette rather than falling back to the
      // system-blue/system-background defaults.
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: resolvedColorScheme.primary,
        primaryContrastingColor: resolvedColorScheme.onPrimary,
        barBackgroundColor: shell.sidebar,
        scaffoldBackgroundColor: shell.content,
        selectionHandleColor: resolvedColorScheme.primary,
        // Modern iOS and macOS both apply the accent to controls such as
        // switches. Flutter leaves this off by default for compatibility.
        applyThemeToAll: true,
      ).noDefault(),
      // The backdrop the panels sit on, visible above them and behind the rail.
      scaffoldBackgroundColor: shell.rail,
      // PopupMenuItem and DropdownButton rows still read ThemeData directly,
      // while MenuItemButton reads menuButtonTheme below. Give both menu
      // implementations the same visible pointer treatment.
      hoverColor: menuItemHoverColor,
      extensions: [
        shell,
        code,
        discourse,
        DiscourseButtonTheme.fromColors(
          resolvedColorScheme,
          borderRadius: borderRadius,
          hover: shell.hover,
          success: discourse.success,
        ),
      ],
      dividerTheme: DividerThemeData(
        color: shell.divider,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: shell.floating,
        shape: menuShape,
        menuPadding: const EdgeInsets.all(6),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        position: PopupMenuPosition.under,
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return menuItemHoverColor;
            }
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        menuStyle: menuStyle,
      ),
      tooltipTheme: TooltipThemeData(
        constraints: DTooltip.defaultConstraints,
        padding: DTooltip.defaultPadding,
        margin: DTooltip.defaultMargin,
        verticalOffset: DTooltip.defaultVerticalOffset,
        decoration: tooltipDecoration,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: resolvedColorScheme.onSurface,
          fontWeight: FontWeight.normal,
        ),
        textAlign: TextAlign.start,
        waitDuration: const Duration(milliseconds: 400),
        showDuration: const Duration(milliseconds: 1800),
        exitDuration: const Duration(milliseconds: 100),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: shell.content,
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          color: resolvedColorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: resolvedColorScheme.onSurface,
        ),
        elevation: 24,
        shadowColor: modalShadow,
        surfaceTintColor: Colors.transparent,
        shape: modalShape,
        barrierColor: discourseModalBarrier,
        clipBehavior: Clip.antiAlias,
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttonGeometry),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonGeometry),
      textButtonTheme: TextButtonThemeData(style: buttonGeometry),
      bottomSheetTheme: BottomSheetThemeData(
        modalBackgroundColor: shell.content,
        modalBarrierColor: discourseModalBarrier,
        modalElevation: 24,
        shadowColor: modalShadow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(borderRadius),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
    );
  }

  static TextTheme _discourseTextTheme(TextTheme base) => TextTheme(
    displayLarge: _textStyle(
      base.displayLarge,
      DiscourseTypography.fontUp6,
      DiscourseTypography.lineHeightMedium,
    ),
    displayMedium: _textStyle(
      base.displayMedium,
      DiscourseTypography.fontUp5,
      DiscourseTypography.lineHeightMedium,
    ),
    displaySmall: _textStyle(
      base.displaySmall,
      DiscourseTypography.fontUp4,
      DiscourseTypography.lineHeightMedium,
    ),
    headlineLarge: _textStyle(
      base.headlineLarge,
      DiscourseTypography.fontUp4,
      DiscourseTypography.lineHeightMedium,
    ),
    headlineMedium: _textStyle(
      base.headlineMedium,
      DiscourseTypography.fontUp3,
      DiscourseTypography.lineHeightMedium,
    ),
    headlineSmall: _textStyle(
      base.headlineSmall,
      DiscourseTypography.fontUp3,
      DiscourseTypography.lineHeightMedium,
    ),
    titleLarge: _textStyle(
      base.titleLarge,
      DiscourseTypography.fontUp2,
      DiscourseTypography.lineHeightMedium,
    ),
    titleMedium: _textStyle(
      base.titleMedium,
      DiscourseTypography.fontUp1,
      DiscourseTypography.lineHeightMedium,
    ),
    titleSmall: _textStyle(
      base.titleSmall,
      DiscourseTypography.base,
      DiscourseTypography.lineHeightMedium,
    ),
    bodyLarge: _textStyle(
      base.bodyLarge,
      DiscourseTypography.base,
      DiscourseTypography.lineHeightLarge,
    ),
    bodyMedium: _textStyle(
      base.bodyMedium,
      DiscourseTypography.base,
      DiscourseTypography.lineHeightLarge,
    ),
    bodySmall: _textStyle(
      base.bodySmall,
      DiscourseTypography.fontDown1,
      DiscourseTypography.lineHeightLarge,
    ),
    labelLarge: _textStyle(
      base.labelLarge,
      DiscourseTypography.base,
      DiscourseTypography.lineHeightMedium,
    ),
    labelMedium: _textStyle(
      base.labelMedium,
      DiscourseTypography.fontDown1,
      DiscourseTypography.lineHeightLarge,
    ),
    labelSmall: _textStyle(
      base.labelSmall,
      DiscourseTypography.fontDown2,
      DiscourseTypography.lineHeightMedium,
    ),
  );

  static TextStyle? _textStyle(
    TextStyle? base,
    double fontSize,
    double height,
  ) => base?.copyWith(
    fontSize: fontSize,
    fontWeight: FontWeight.normal,
    height: height,
    letterSpacing: 0,
  );

  static ColorScheme _fallbackColorScheme(
    Brightness brightness,
    ShellColors shell,
    DiscourseColors discourse,
  ) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? discourseDarkBlue : discourseBlue;
    final quaternary = isDark
        ? const Color(0xFFC14924)
        : const Color(0xFFE45735);
    final highlight = isDark
        ? const Color(0xFFA87137)
        : const Color(0xFFFFFF4D);
    final danger = isDark ? const Color(0xFFE45735) : const Color(0xFFC80001);
    final backdrop = opaqueColorOnCanvas(shell.content, brightness);

    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: _readableOn(
        primary,
        shell.content,
        backdrop: backdrop,
        alternative: shell.railForeground,
      ),
      secondary: quaternary,
      onSecondary: _readableOn(
        quaternary,
        shell.content,
        backdrop: backdrop,
        alternative: shell.railForeground,
      ),
      tertiary: highlight,
      onTertiary: _readableOn(
        highlight,
        shell.railForeground,
        backdrop: backdrop,
        alternative: shell.content,
      ),
      error: danger,
      onError: _readableOn(
        danger,
        shell.content,
        backdrop: backdrop,
        alternative: shell.railForeground,
      ),
      surface: shell.content,
      onSurface: shell.railForeground,
      onSurfaceVariant: discourse.primaryHigh,
      surfaceContainerLowest: shell.content,
      surfaceContainerLow: shell.sidebar,
      surfaceContainer: shell.panel,
      surfaceContainerHigh: shell.floating,
      surfaceContainerHighest: shell.floating,
      outline: shell.divider,
      outlineVariant: shell.divider,
      surfaceTint: primary,
    );
  }
}
