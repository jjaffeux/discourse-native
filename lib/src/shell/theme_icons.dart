import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

/// Theme form artwork rendered by the Native icon component.
/// Section icons are Font Awesome Free (CC BY 4.0):
/// https://fontawesome.com/license/free.
abstract final class ThemeIcons {
  static const palette = DIconData(
    'theme-palette',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="currentColor"><path d="M512 256c0 .9 0 1.8 0 2.7-.4 36.5-33.6 61.3-70.1 61.3L344 320c-26.5 0-48 21.5-48 48 0 3.4 .4 6.7 1 9.9 2.1 10.2 6.5 20 10.8 29.9 6.1 13.8 12.1 27.5 12.1 42 0 31.8-21.6 60.7-53.4 62-3.5 .1-7 .2-10.6 .2-141.4 0-256-114.6-256-256S114.6 0 256 0 512 114.6 512 256zM128 288a32 32 0 1 0 -64 0 32 32 0 1 0 64 0zm0-96a32 32 0 1 0 0-64 32 32 0 1 0 0 64zM288 96a32 32 0 1 0 -64 0 32 32 0 1 0 64 0zm96 96a32 32 0 1 0 0-64 32 32 0 1 0 0 64z"/></svg>',
  );
  static const preset = DIconData(
    'theme-preset',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="currentColor"><path d="M0 48C0 21.5 21.5 0 48 0l96 0c26.5 0 48 21.5 48 48l0 368c0 53-43 96-96 96S0 469 0 416L0 48zM240 409.6l0-271.5 48.1-48.1c18.7-18.7 49.1-18.7 67.9 0l67.9 67.9c18.7 18.7 18.7 49.1 0 67.9L240 409.6zM205.5 512l192-192 66.6 0c26.5 0 48 21.5 48 48l0 96c0 26.5-21.5 48-48 48l-258.5 0zM80 64c-8.8 0-16 7.2-16 16l0 32c0 8.8 7.2 16 16 16l32 0c8.8 0 16-7.2 16-16l0-32c0-8.8-7.2-16-16-16L80 64zM64 208l0 32c0 8.8 7.2 16 16 16l32 0c8.8 0 16-7.2 16-16l0-32c0-8.8-7.2-16-16-16l-32 0c-8.8 0-16 7.2-16 16zM96 440a24 24 0 1 0 0-48 24 24 0 1 0 0 48z"/></svg>',
  );
  static const background = DIconData(
    'theme-background',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 384 512" fill="currentColor"><path d="M192 512C86 512 0 426 0 320 0 228.8 130.2 45.9 166.6-3.5 172.5-11.5 181.8-16 191.8-16l.4 0c10 0 19.3 4.5 25.2 12.5 36.4 49.4 166.6 232.3 166.6 323.5 0 106-86 192-192 192zM112 312c0-13.3-10.7-24-24-24s-24 10.7-24 24c0 75.1 60.9 136 136 136 13.3 0 24-10.7 24-24s-10.7-24-24-24c-48.6 0-88-39.4-88-88z"/></svg>',
  );
  static const texture = DIconData(
    'theme-texture',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="currentColor"><path d="M64 96c0-17.7 14.3-32 32-32l160 0c17.7 0 32 14.3 32 32l0 288 96 0 0-128c0-17.7 14.3-32 32-32l64 0c17.7 0 32 14.3 32 32s-14.3 32-32 32l-32 0 0 128c0 17.7-14.3 32-32 32l-160 0c-17.7 0-32-14.3-32-32l0-288-96 0 0 128c0 17.7-14.3 32-32 32l-64 0c-17.7 0-32-14.3-32-32s14.3-32 32-32l32 0 0-128z"/></svg>',
  );
  static const paper = DIconData(
    'theme-paper',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><circle cx="9.4" cy="4.2" r="0.72"/><circle cx="12" cy="4.2" r="0.72"/><circle cx="14.6" cy="4.2" r="0.72"/><circle cx="6.8" cy="6.8" r="0.72"/><circle cx="9.4" cy="6.8" r="0.72"/><circle cx="12" cy="6.8" r="0.72"/><circle cx="14.6" cy="6.8" r="0.72"/><circle cx="17.2" cy="6.8" r="0.72"/><circle cx="4.2" cy="9.4" r="0.72"/><circle cx="6.8" cy="9.4" r="0.72"/><circle cx="9.4" cy="9.4" r="0.72"/><circle cx="12" cy="9.4" r="0.72"/><circle cx="14.6" cy="9.4" r="0.72"/><circle cx="17.2" cy="9.4" r="0.72"/><circle cx="19.8" cy="9.4" r="0.72"/><circle cx="4.2" cy="12" r="0.72"/><circle cx="6.8" cy="12" r="0.72"/><circle cx="9.4" cy="12" r="0.72"/><circle cx="12" cy="12" r="0.72"/><circle cx="14.6" cy="12" r="0.72"/><circle cx="17.2" cy="12" r="0.72"/><circle cx="19.8" cy="12" r="0.72"/><circle cx="4.2" cy="14.6" r="0.72"/><circle cx="6.8" cy="14.6" r="0.72"/><circle cx="9.4" cy="14.6" r="0.72"/><circle cx="12" cy="14.6" r="0.72"/><circle cx="14.6" cy="14.6" r="0.72"/><circle cx="17.2" cy="14.6" r="0.72"/><circle cx="19.8" cy="14.6" r="0.72"/><circle cx="6.8" cy="17.2" r="0.72"/><circle cx="9.4" cy="17.2" r="0.72"/><circle cx="12" cy="17.2" r="0.72"/><circle cx="14.6" cy="17.2" r="0.72"/><circle cx="17.2" cy="17.2" r="0.72"/><circle cx="9.4" cy="19.8" r="0.72"/><circle cx="12" cy="19.8" r="0.72"/><circle cx="14.6" cy="19.8" r="0.72"/></svg>',
  );
  static const lava = DIconData(
    'theme-lava',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><circle cx="7.6" cy="7.6" r="1.45"/><circle cx="12" cy="7.6" r="1.45"/><circle cx="16.4" cy="7.6" r="1.45"/><circle cx="7.6" cy="12" r="1.45"/><circle cx="12" cy="12" r="1.45"/><circle cx="16.4" cy="12" r="1.45"/><circle cx="7.6" cy="16.4" r="1.45"/><circle cx="12" cy="16.4" r="1.45"/><circle cx="16.4" cy="16.4" r="1.45"/></svg>',
  );
  static const none = DIconData(
    'theme-no-texture',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><rect x="6.5" y="6.5" width="11" height="11" rx="2.5" stroke="currentColor" stroke-width="2"/></svg>',
  );
  static const gradient = DIconData(
    'theme-gradient',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><rect x="5" y="5" width="14" height="3" rx="1"/><rect x="5" y="9" width="14" height="3" rx="1" opacity=".7"/><rect x="5" y="13" width="14" height="3" rx="1" opacity=".4"/><rect x="5" y="17" width="14" height="3" rx="1" opacity=".15"/></svg>',
  );

  /// A window whose leading pane is drawn left-to-right; pair with
  /// [ThemeIcon.matchTextDirection] so the pane follows the sidebar in RTL.
  static const neutralSidebar = DIconData(
    'theme-neutral-sidebar',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><rect x="3.5" y="5" width="17" height="14" rx="2.5" stroke="currentColor" stroke-width="2"/><path d="M9.5 5v14" stroke="currentColor" stroke-width="2"/></svg>',
  );
  static const darkerSidebar = DIconData(
    'theme-darker-sidebar',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><path d="M2.5 7.5A3.5 3.5 0 0 1 6 4h4.5v16H6a3.5 3.5 0 0 1-3.5-3.5z" fill="currentColor"/><rect x="3.5" y="5" width="17" height="14" rx="2.5" stroke="currentColor" stroke-width="2"/></svg>',
  );
}

class ThemeIcon extends StatelessWidget {
  const ThemeIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.matchTextDirection = false,
  });
  final DIconData icon;
  final double? size;
  final Color? color;

  /// Mirrors the artwork in right-to-left text, for glyphs that picture the
  /// app's leading edge.
  final bool matchTextDirection;
  @override
  Widget build(BuildContext context) {
    final glyph = DIconGlyphTheme(
      scale: 1,
      child: DIcon(icon, size: size, color: color),
    );
    if (!matchTextDirection ||
        Directionality.of(context) == TextDirection.ltr) {
      return glyph;
    }
    return Transform.flip(flipX: true, child: glyph);
  }
}
