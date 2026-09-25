import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

/// Theme form artwork rendered by the Native icon component.
/// Section icons are Font Awesome Free (CC BY 4.0):
/// https://fontawesome.com/license/free.
abstract final class ThemeIcons {
  static const sun = DIconData(
    'theme-sun',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512" fill="currentColor"><path d="M288-32c8.4 0 16.3 4.4 20.6 11.7L364.1 72.3 468.9 46c8.2-2 16.9 .4 22.8 6.3S500 67 498 75.1l-26.3 104.7 92.7 55.5c7.2 4.3 11.7 12.2 11.7 20.6s-4.4 16.3-11.7 20.6L471.7 332.1 498 436.8c2 8.2-.4 16.9-6.3 22.8S477 468 468.9 466l-104.7-26.3-55.5 92.7c-4.3 7.2-12.2 11.7-20.6 11.7s-16.3-4.4-20.6-11.7L211.9 439.7 107.2 466c-8.2 2-16.8-.4-22.8-6.3S76 445 78 436.8l26.2-104.7-92.6-55.5C4.4 272.2 0 264.4 0 256s4.4-16.3 11.7-20.6L104.3 179.9 78 75.1c-2-8.2 .3-16.8 6.3-22.8S99 44 107.2 46l104.7 26.2 55.5-92.6 1.8-2.6c4.5-5.7 11.4-9.1 18.8-9.1zm0 144a144 144 0 1 0 0 288 144 144 0 1 0 0-288zm0 240a96 96 0 1 1 0-192 96 96 0 1 1 0 192z"/></svg>',
  );
  static const moon = DIconData(
    'theme-moon',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="currentColor"><path d="M256 0C114.6 0 0 114.6 0 256S114.6 512 256 512c68.8 0 131.3-27.2 177.3-71.4 7.3-7 9.4-17.9 5.3-27.1s-13.7-14.9-23.8-14.1c-4.9 .4-9.8 .6-14.8 .6-101.6 0-184-82.4-184-184 0-72.1 41.5-134.6 102.1-164.8 9.1-4.5 14.3-14.3 13.1-24.4S322.6 8.5 312.7 6.3C294.4 2.2 275.4 0 256 0z"/></svg>',
  );
  static const automatic = DIconData(
    'theme-automatic',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="currentColor"><path d="M448 256c0-106-86-192-192-192l0 384c106 0 192-86 192-192zM0 256a256 256 0 1 1 512 0 256 256 0 1 1 -512 0z"/></svg>',
  );
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
}

class ThemeIcon extends StatelessWidget {
  const ThemeIcon(this.icon, {super.key, this.size, this.color});
  final DIconData icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) => DIconGlyphTheme(
    scale: 1,
    child: DIcon(icon, size: size, color: color),
  );
}
