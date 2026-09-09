import 'package:flutter/material.dart';

import '../../discourse_ui.dart';

/// The documentation canvas is neutral; previews receive the original host
/// theme separately. Changing this theme never changes app settings or samples.
ThemeData styleguideDocumentationTheme(ThemeData host, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = Color(dark ? 0xFF0A0A0A : 0xFFFFFFFF);
  final foreground = Color(dark ? 0xFFFAFAFA : 0xFF171717);
  final muted = Color(dark ? 0xFF171717 : 0xFFF5F5F5);
  final secondary = Color(dark ? 0xFFA3A3A3 : 0xFF737373);
  final border = Color(dark ? 0xFF262626 : 0xFFE5E5E5);
  final colors = host.colorScheme.copyWith(
    brightness: brightness,
    surface: background,
    onSurface: foreground,
    onSurfaceVariant: secondary,
    primary: foreground,
    onPrimary: background,
    outline: secondary,
    outlineVariant: border,
    surfaceContainerLow: muted,
    surfaceContainer: muted,
    surfaceContainerHigh: border,
  );
  final textTheme = host.textTheme.apply(
    bodyColor: foreground,
    displayColor: foreground,
  );
  return host.copyWith(
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    hoverColor: foreground.withValues(alpha: .04),
    focusColor: foreground.withValues(alpha: .08),
    highlightColor: foreground.withValues(alpha: .06),
    splashColor: Colors.transparent,
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    extensions: [
      ...host.extensions.values.where((extension) => extension is! DTokens),
      DTokens(
        colors: colors,
        background: background,
        surface: muted,
        muted: muted,
        border: border,
        hover: muted,
        selected: muted,
        selectedForeground: foreground,
        radius: 10,
      ),
    ],
  );
}

TextStyle styleguideText(
  BuildContext context, {
  double size = 14,
  double height = 20,
  FontWeight weight = FontWeight.w400,
  bool muted = false,
}) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  letterSpacing: 0,
  color: muted
      ? DTokens.of(context).mutedForeground
      : DTokens.of(context).foreground,
);

double styleguideTargetHeight(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => 44,
      _ => 32,
    };

/// Documentation navigation and toolbar geometry, not a catalogue Button.
class StyleguideAction extends StatelessWidget {
  const StyleguideAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconOnly = false,
    this.selected,
    this.outlined = false,
    this.alignment = Alignment.center,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool iconOnly;
  final bool? selected;
  final bool outlined;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final target = styleguideTargetHeight(context);
    final button = Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          alignment: alignment,
          minimumSize: WidgetStatePropertyAll(Size(target, target)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: iconOnly ? 8 : 10, vertical: 6),
          ),
          textStyle: WidgetStatePropertyAll(
            styleguideText(
              context,
              size: 13,
              height: 18,
              weight: FontWeight.w500,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.mutedForeground
                : tokens.foreground,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => selected == true || states.contains(WidgetState.hovered)
                ? tokens.muted
                : Colors.transparent,
          ),
          overlayColor: WidgetStatePropertyAll(
            tokens.foreground.withValues(alpha: .06),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? tokens.foreground
                  : outlined
                  ? tokens.border
                  : Colors.transparent,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: tokens.borderRadius),
          ),
        ),
        child: iconOnly
            ? Icon(icon, size: 16)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Flexible(child: Text(label)),
                ],
              ),
      ),
    );
    return iconOnly
        ? DTooltip(message: label, labelTrigger: true, child: button)
        : button;
  }
}

class StyleguideChoice<T> extends StatelessWidget {
  const StyleguideChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      label: label,
      child: Container(
        key: ValueKey('styleguide-$label'),
        constraints: BoxConstraints(minHeight: styleguideTargetHeight(context)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: tokens.borderRadius,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            itemHeight: null,
            menuMaxHeight: 360,
            borderRadius: tokens.borderRadius,
            dropdownColor: tokens.background,
            focusColor: tokens.muted,
            icon: Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: tokens.mutedForeground,
            ),
            style: styleguideText(context, size: 13, height: 18),
            items: [
              for (final option in options.entries)
                DropdownMenuItem(value: option.key, child: Text(option.value)),
            ],
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}
