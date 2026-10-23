import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The material shared by all forum palettes. Controls keep their kit geometry.
enum DAppearanceMaterial { standard, liquidGlass }

@immutable
class DMaterialTheme extends ThemeExtension<DMaterialTheme> {
  const DMaterialTheme({this.material = DAppearanceMaterial.standard});
  final DAppearanceMaterial material;
  static DMaterialTheme? of(BuildContext context) =>
      Theme.of(context).extension<DMaterialTheme>();
  static bool glassOf(BuildContext context) =>
      of(context)?.material == DAppearanceMaterial.liquidGlass &&
      !reducedOf(context);
  static bool reducedOf(BuildContext context) =>
      MediaQuery.highContrastOf(context) ||
      (context
              .dependOnInheritedWidgetOfExactType<_MaterialAccessibilityScope>()
              ?.reduced ??
          false);

  /// Install at the existing theme boundary; never change control APIs.
  static ThemeData apply(ThemeData theme, DAppearanceMaterial material) =>
      theme.copyWith(
        extensions: [
          ...theme.extensions.values,
          DMaterialTheme(material: material),
        ],
      );
  @override
  DMaterialTheme copyWith({DAppearanceMaterial? material}) =>
      DMaterialTheme(material: material ?? this.material);
  @override
  DMaterialTheme lerp(DMaterialTheme? other, double t) =>
      t < .5 ? this : other ?? this;
}

/// Draws [child] in the Standard material whatever the saved choice, for
/// controls the mockups keep flat under Liquid Glass. Hosts without a
/// material theme stay as they are.
class DStandardMaterial extends StatelessWidget {
  const DStandardMaterial({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final material = DMaterialTheme.of(context)?.material;
    if (material == null || material == DAppearanceMaterial.standard) {
      return child;
    }
    return Theme(
      data: DMaterialTheme.apply(
        Theme.of(context),
        DAppearanceMaterial.standard,
      ),
      child: child,
    );
  }
}

/// Draws [child] in neither material: controls keep their flat kit fill and
/// border, with no glass lens, raised edge or drop shadow, whatever the saved
/// choice. Overlays opened from inside keep the window's material.
class DFlatMaterial extends StatelessWidget {
  const DFlatMaterial({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.extension<DMaterialTheme>() == null) return child;
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final extension in theme.extensions.values)
            if (extension is! DMaterialTheme) extension,
        ],
      ),
      child: child,
    );
  }
}

/// Keeps the OS Reduce Transparency preference live without changing the saved
/// material choice. Preview/test hosts can omit the platform channel.
class DMaterialAccessibility extends StatefulWidget {
  const DMaterialAccessibility({super.key, required this.child});
  final Widget child;
  @override
  State<DMaterialAccessibility> createState() => _DMaterialAccessibilityState();
}

class _DMaterialAccessibilityState extends State<DMaterialAccessibility> {
  static const _channel = MethodChannel(
    'org.discourse.native/material_accessibility',
  );
  bool _reduced = false;
  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceTransparencyChanged' && mounted) {
        setState(() => _reduced = call.arguments == true);
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await _channel.invokeMethod<bool>('reduceTransparency');
      if (mounted) setState(() => _reduced = value == true);
    } on MissingPluginException {
      // Embedded shells and other platforms use MediaQuery's high contrast.
    } on PlatformException {
      // Keep the current readable material if the host is unavailable.
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MaterialAccessibilityScope(reduced: _reduced, child: widget.child);
}

class _MaterialAccessibilityScope extends InheritedWidget {
  const _MaterialAccessibilityScope({
    required this.reduced,
    required super.child,
  });
  final bool reduced;
  @override
  bool updateShouldNotify(_MaterialAccessibilityScope old) =>
      old.reduced != reduced;
}
