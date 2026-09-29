import 'd_icon.dart';

abstract final class DNativeIcons {
  static const DIconData indent = DIconData(
    'discourse-native-indent',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="2" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M3 4h18M11 9h10M11 14h10M3 20h18M3 9l3 3-3 3"/>'
        '</svg>',
  );

  static const DIconData outdent = DIconData(
    'discourse-native-outdent',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="2" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M3 4h18M11 9h10M11 14h10M3 20h18M6 9l-3 3 3 3"/>'
        '</svg>',
  );

  // Font Awesome Free 7.3.1, from the native mockup's FilterPill.
  // Icons: CC BY 4.0, https://fontawesome.com/license/free
  static const DIconData filterChevron = DIconData(
    'discourse-native-filter-chevron',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512" fill="currentColor">'
        '<path d="M201.4 406.6c12.5 12.5 32.8 12.5 45.3 0l192-192c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L224 338.7 54.6 169.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3l192 192z"/>'
        '</svg>',
  );

  // Lucide 1.17.0 artwork from the contextual-tints mockup. License:
  // docs/component-library/evidence/avatar/lucide-LICENSE.txt
  static const DIconData bookmark = DIconData(
    'discourse-native-bookmark',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z"/>'
        '</svg>',
  );

  static const DIconData bookmarkCheck = DIconData(
    'discourse-native-bookmark-check',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z"/>'
        '<path d="m9 10 2 2 4-4"/>'
        '</svg>',
  );

  static const DIconData bell = DIconData(
    'discourse-native-bell',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M10.268 21a2 2 0 0 0 3.464 0"/>'
        '<path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"/>'
        '</svg>',
  );

  static const DIconData bellRing = DIconData(
    'discourse-native-bell-ring',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M10.268 21a2 2 0 0 0 3.464 0"/>'
        '<path d="M22 8c0-2.3-.8-4.3-2-6"/>'
        '<path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"/>'
        '<path d="M4 2C2.8 3.7 2 5.7 2 8"/>'
        '</svg>',
  );

  static const DIconData bellOff = DIconData(
    'discourse-native-bell-off',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M10.268 21a2 2 0 0 0 3.464 0"/>'
        '<path d="M17 17H4a1 1 0 0 1-.74-1.673C4.59 13.956 6 12.499 6 8a6 6 0 0 1 .258-1.742"/>'
        '<path d="m2 2 20 20"/>'
        '<path d="M8.668 3.01A6 6 0 0 1 18 8c0 2.687.77 4.653 1.707 6.05"/>'
        '</svg>',
  );

  static const DIconData chevronDown = DIconData(
    'discourse-native-chevron-down',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="m6 9 6 6 6-6"/>'
        '</svg>',
  );

  static const DIconData closeTopicPane = DIconData(
    'discourse-native-close-topic-pane',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="2" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="3" y="3" width="18" height="18" rx="2"/>'
        '<path d="M15 3v18M7 12h5m-3-3 3 3-3 3"/>'
        '</svg>',
  );

  static const DIconData topic = DIconData(
    'discourse-native-topic',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512" fill="currentColor">'
        '<path d="M264.5 5.2c14.9-6.9 32.1-6.9 47 0l218.6 101c8.5 3.9 13.9 12.4 13.9 21.8s-5.4 17.9-13.9 21.8l-218.6 101c-14.9 6.9-32.1 6.9-47 0L45.9 149.8C37.4 145.8 32 137.3 32 128s5.4-17.9 13.9-21.8L264.5 5.2z"/>'
        '<path opacity=".55" d="M476.9 209.6l53.2 24.6c8.5 3.9 13.9 12.4 13.9 21.8s-5.4 17.9-13.9 21.8l-218.6 101c-14.9 6.9-32.1 6.9-47 0L45.9 277.8C37.4 273.8 32 265.3 32 256s5.4-17.9 13.9-21.8l53.2-24.6 152 70.2c23.4 10.8 50.4 10.8 73.8 0l152-70.2z"/>'
        '<path opacity=".28" d="M324.9 407.8l152-70.2 53.2 24.6c8.5 3.9 13.9 12.4 13.9 21.8s-5.4 17.9-13.9 21.8l-218.6 101c-14.9 6.9-32.1 6.9-47 0L45.9 405.8C37.4 401.8 32 393.3 32 384s5.4-17.9 13.9-21.8l53.2-24.6 152 70.2c23.4 10.8 50.4 10.8 73.8 0z"/>'
        '</svg>',
  );

  // Original stroke glyphs for topic-list controls.
  static const DIconData filterLines = DIconData(
    'discourse-native-filterLines',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="3 5 18 14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M4 6h16M7 12h10M10 18h4"/></svg>',
  );

  static const DIconData sliders = DIconData(
    'discourse-native-sliders',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="2 3 20 18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M3 6h4m4 0h10M3 12h10m4 0h4M3 18h2m4 0h12"/><circle cx="9" cy="6" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="7" cy="18" r="2"/></svg>',
  );

  static const DIconData columns = DIconData(
    'discourse-native-columns',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M10 4v16"/></svg>',
  );

  static const Map<String, DIconData> byName = {
    'discourse-native-filterLines': filterLines,
    'discourse-native-sliders': sliders,
    'discourse-native-columns': columns,

    'discourse-native-filter-chevron': filterChevron,
    'discourse-native-bookmark': bookmark,
    'discourse-native-bookmark-check': bookmarkCheck,
    'discourse-native-bell': bell,
    'discourse-native-bell-ring': bellRing,
    'discourse-native-bell-off': bellOff,
    'discourse-native-chevron-down': chevronDown,
    'discourse-native-close-topic-pane': closeTopicPane,
    'discourse-native-topic': topic,
  };
}
