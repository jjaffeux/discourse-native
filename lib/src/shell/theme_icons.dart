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
  const ThemeIcon(this.icon, {super.key, this.size});
  final DIconData icon;
  final double? size;
  @override
  Widget build(BuildContext context) =>
      DIconGlyphTheme(scale: 1, child: DIcon(icon, size: size));
}
