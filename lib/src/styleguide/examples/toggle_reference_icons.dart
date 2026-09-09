import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Exact Lucide artwork used by the frozen Toggle examples (MIT license).
class ToggleReferenceIcon extends StatelessWidget {
  const ToggleReferenceIcon(this.svg, {super.key, this.filled = false});

  final String svg;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    final source = filled
        ? svg.replaceFirst('fill="none"', 'fill="currentColor"')
        : svg;
    return SvgPicture.string(
      source,
      width: iconTheme.size ?? 16,
      height: iconTheme.size ?? 16,
      theme: SvgTheme(currentColor: color),
      excludeFromSemantics: true,
    );
  }

  static const bookmark =
      '''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>''';

  static const bold =
      '''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 12a4 4 0 0 0 0-8H6v8"/><path d="M15 20a4 4 0 0 0 0-8H6v8Z"/></svg>''';

  static const italic =
      '''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="19" x2="10" y1="4" y2="4"/><line x1="14" x2="5" y1="20" y2="20"/><line x1="15" x2="9" y1="4" y2="20"/></svg>''';
}
