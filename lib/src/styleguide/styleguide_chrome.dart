import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

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
        successColor: host.extension<DTokens>()?.success ?? colors.tertiary,
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
    final variant = outlined ? DButtonVariant.outline : DButtonVariant.ghost;
    return Semantics(
      selected: selected,
      child: iconOnly
          ? DButton.iconOnly(
              tooltip: label,
              icon: Icon(icon),
              onPressed: onPressed,
              variant: variant,
              expanded: selected == true,
            )
          : DButton(
              label: Text(label),
              icon: icon == null ? null : Icon(icon),
              onPressed: onPressed,
              variant: variant,
              expanded: selected == true,
              alignment: alignment,
            ),
    );
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
    return DSelect<T>.controlled(
      key: ValueKey('styleguide-$label'),
      semanticLabel: label,
      value: value,
      isExpanded: true,
      entries: [
        for (final option in options.entries)
          DSelectItem(
            value: option.key,
            textValue: option.value,
            child: Text(option.value),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}
