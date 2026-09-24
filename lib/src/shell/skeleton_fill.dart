import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// The opaque surface a loading placeholder is drawn on.
enum SkeletonSurface {
  /// The content page, and cards drawn on it with their default fill.
  page,

  /// Sidebars and side panels, which paint the UI kit's muted surface.
  panel,

  /// Popovers, hover cards, menus, and the UI kit's dialogs, sheets and
  /// drawers.
  floating,

  /// Rows that highlight while selected, hovered or pressed, such as sidebar
  /// destinations. The fill is drawn for the kit's hover colour, so it holds
  /// on the idle row beneath it too.
  row,
}

/// Fill for the app's loading placeholders on [on], for their region's
/// [DSkeletonRegion.color].
///
/// The UI kit skeleton paints with `muted`, which a forum palette maps to its
/// `--primary-very-low`: a tint a few percent off the page, halved again by
/// the pulse, and the very colour sidebars and panels paint themselves. So
/// placeholders mix the text colour into the surface they sit on. Light pages
/// keep the border neutral instead, which sits about as far off the page, and
/// other light surfaces mix a little less than dark ones to match its weight.
/// Dark palettes cannot use that neutral: it is a hairline colour, still faint
/// on the app's own dark theme.
Color skeletonFill(
  BuildContext context, {
  SkeletonSurface on = SkeletonSurface.page,
}) {
  final tokens = DTokens.of(context);
  final light = Theme.of(context).brightness == Brightness.light;
  final surface = switch (on) {
    SkeletonSurface.page => tokens.background,
    SkeletonSurface.panel => tokens.muted,
    SkeletonSurface.floating => tokens.surface,
    SkeletonSurface.row => tokens.hover,
  };
  if (light && on == SkeletonSurface.page) return tokens.border;
  return Color.lerp(surface, tokens.foreground, light ? .14 : .18)!;
}
