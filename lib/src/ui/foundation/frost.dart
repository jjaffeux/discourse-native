import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Whether the active palette lets the window through its surfaces, and the
/// frosting a floating surface then owes what is behind it.
///
/// [sheer] is the share of the panel fill, in percent, that the palette thins
/// away. Zero is an opaque palette: no surface frosts, so none pays for a
/// backdrop filter. The host puts one on its theme beside the palette.
@immutable
class DFrost extends ThemeExtension<DFrost> {
  const DFrost({this.sheer = 0}) : assert(sheer >= 0 && sheer <= 100);

  static const none = DFrost();

  /// A backdrop filter's standard deviation is the CSS blur length itself.
  static const blurSigma = 26.0;
  static const saturation = 1.3;

  static DFrost of(BuildContext context) =>
      Theme.of(context).extension<DFrost>() ?? none;

  final int sheer;

  bool get isSheer => sheer > 0;

  /// A panel's fill with the palette's thinning applied.
  Color panel(Color solid) =>
      isSheer ? solid.withValues(alpha: 1 - sheer / 100) : solid;

  /// A floating surface keeps most of its fill: it cannot be as thin as the
  /// panel under it, or that panel's text reads straight through it.
  Color menu(Color solid) =>
      isSheer ? solid.withValues(alpha: 1 - (sheer / 3).round() / 100) : solid;

  static final _filter = ui.ImageFilter.compose(
    outer: const ColorFilter.matrix(<double>[
      // Rec. 709 luminance weights, as CSS saturate() uses.
      .213 + .787 * saturation, .715 - .715 * saturation,
      .072 - .072 * saturation, 0, 0, //
      .213 - .213 * saturation, .715 + .285 * saturation,
      .072 - .072 * saturation, 0, 0, //
      .213 - .213 * saturation, .715 - .715 * saturation,
      .072 + .928 * saturation, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    inner: ui.ImageFilter.blur(
      sigmaX: blurSigma,
      sigmaY: blurSigma,
      tileMode: TileMode.clamp,
    ),
  );

  /// Frosts what is behind [child], within [borderRadius], when the palette is
  /// see-through and [enabled], and is [child] alone otherwise.
  static Widget backdrop(
    BuildContext context, {
    required BorderRadius borderRadius,
    required Widget child,
    bool enabled = true,
  }) => enabled && of(context).isSheer
      ? ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(filter: _filter, child: child),
        )
      : child;

  @override
  DFrost copyWith({int? sheer}) => DFrost(sheer: sheer ?? this.sheer);

  @override
  DFrost lerp(DFrost? other, double t) =>
      other == null ? this : DFrost(sheer: t < .5 ? sheer : other.sheer);
}
