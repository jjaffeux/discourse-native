import 'package:flutter/widgets.dart';

/// Sets the reading direction of a subtree using Flutter's [Directionality].
///
/// Omit [textDirection] to inherit the nearest direction, including the locale
/// direction supplied by a [WidgetsApp]. An explicit value overrides only this
/// subtree; nested [DDirection] or [Directionality] widgets take precedence.
///
/// [of] and [maybeOf] read the nearest native provider and rebuild dependents
/// when its direction changes. Changing [textDirection], including switching
/// between an explicit value and inheritance, keeps child state and focus.
/// Use a descendant context (for example, a [Builder]) to read this scope.
///
/// Directional Flutter layout, text semantics and reading-order focus traversal
/// use this same provider. This widget adds no focus stops, styling, animation
/// or translation, and does not mirror physical left/right geometry or all
/// icons. Use directional alignment/padding and direction-aware icons in children.
/// Keep intentional code, URL and markup direction boundaries explicit.
///
/// Place the provider above a [Navigator] to affect its routes. For a local
/// overlay, [OverlayPortal] preserves the originating inherited context; an
/// overlay inserted elsewhere does not automatically inherit this scope.
class DDirection extends StatelessWidget {
  const DDirection({super.key, this.textDirection, required this.child});

  /// The explicit direction, or null to inherit from an existing provider.
  ///
  /// Inherited mode requires a [Directionality] ancestor, normally supplied by
  /// the app. It deliberately does not replace the host locale with an LTR
  /// fallback. An explicit value can establish a scope without an ancestor.
  final TextDirection? textDirection;

  final Widget child;

  /// Reads the nearest direction and subscribes [context] to live changes.
  ///
  /// This is the native equivalent of the reference's `useDirection` hook.
  /// Requires a [Directionality] ancestor, whether native or created here.
  static TextDirection of(BuildContext context) => Directionality.of(context);

  /// Reads and subscribes to the nearest direction, or returns null if absent.
  static TextDirection? maybeOf(BuildContext context) =>
      Directionality.maybeOf(context);

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: textDirection ?? of(context), child: child);
}
