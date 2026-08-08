import 'dart:math' as math;
import 'dart:ui';

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';
import 'package:flutter/foundation.dart';

import '../models/site_appearance.dart';

/// The theme and color-scheme IDs needed to ask Discourse for its compiled
/// color stylesheets.
@immutable
class SiteAppearanceSelection {
  const SiteAppearanceSelection({
    required this.themeId,
    required this.baseSchemeId,
    required this.alternateSchemeId,
    required this.mode,
  });

  final int themeId;

  /// `-1` asks Discourse to use the selected theme's own light/base scheme.
  final int baseSchemeId;

  /// Null means the selected theme has no distinct alternate scheme.
  final int? alternateSchemeId;
  final SiteAppearanceMode mode;

  @override
  bool operator ==(Object other) =>
      other is SiteAppearanceSelection &&
      other.themeId == themeId &&
      other.baseSchemeId == baseSchemeId &&
      other.alternateSchemeId == alternateSchemeId &&
      other.mode == mode;

  @override
  int get hashCode =>
      Object.hash(themeId, baseSchemeId, alternateSchemeId, mode);
}

/// Resolves the same server-stored theme preferences that Discourse's
/// application layout uses, without depending on its HTML structure.
///
/// [site] is the body of `/site.json`. [user] is the optional body of the
/// signed-in reader's `/u/{username}.json`; when absent, site defaults win.
/// Missing modern metadata makes appearance an unsupported optional feature.
SiteAppearanceSelection? resolveSiteAppearanceSelection({
  required Object? site,
  Object? user,
}) {
  final siteMap = _stringMap(site);
  if (siteMap == null) return null;

  final themes = <_ThemeChoice>[];
  for (final value in _objectList(siteMap['user_themes'])) {
    final json = _stringMap(value);
    final id = _jsonInt(json?['theme_id']);
    if (json == null || id == null) continue;
    themes.add(
      _ThemeChoice(
        id: id,
        isDefault: json['default'] == true,
        baseSchemeId: _jsonInt(json['color_scheme_id']),
        alternateSchemeId: _jsonInt(json['dark_color_scheme_id']),
        limitsSchemes: json['only_theme_color_schemes'] == true,
      ),
    );
  }
  if (themes.isEmpty) return null;

  final userOptions = _userOptions(user);
  final requestedThemeId = _objectList(
    userOptions?['theme_ids'],
  ).map(_jsonInt).whereType<int>().firstOrNull;
  final defaultTheme = themes.where((theme) => theme.isDefault).firstOrNull;
  final theme =
      themes.where((theme) => theme.id == requestedThemeId).firstOrNull ??
      defaultTheme ??
      themes.first;

  final schemes = <int, _SchemeChoice>{};
  for (final value in _objectList(siteMap['user_color_schemes'])) {
    final json = _stringMap(value);
    final id = _jsonInt(json?['id']);
    if (json == null || id == null) continue;
    schemes[id] = _SchemeChoice(id: id, themeId: _jsonInt(json['theme_id']));
  }

  bool accepts(int id, int? themeDefault) {
    if (id == themeDefault) return true;
    final scheme = schemes[id];
    if (scheme == null) return false;
    return !theme.limitsSchemes || scheme.themeId == theme.id;
  }

  final requestedBase = _jsonInt(userOptions?['color_scheme_id']);
  final baseSchemeId =
      requestedBase != null && accepts(requestedBase, theme.baseSchemeId)
      ? requestedBase
      : theme.baseSchemeId ?? -1;

  final requestedAlternate = _jsonInt(userOptions?['dark_scheme_id']);
  final alternateFallback =
      theme.alternateSchemeId ??
      (theme.limitsSchemes ? theme.baseSchemeId : null);
  final alternateSchemeId =
      requestedAlternate != null &&
          accepts(requestedAlternate, theme.alternateSchemeId)
      ? requestedAlternate
      : alternateFallback;
  final distinctAlternate =
      alternateSchemeId == null ||
          alternateSchemeId == -1 ||
          alternateSchemeId == baseSchemeId
      ? null
      : alternateSchemeId;

  final mode = distinctAlternate == null
      ? SiteAppearanceMode.base
      : switch (_jsonInt(userOptions?['interface_color_mode'])) {
          2 => SiteAppearanceMode.base,
          3 => SiteAppearanceMode.alternate,
          _ => SiteAppearanceMode.followSystem,
        };

  return SiteAppearanceSelection(
    themeId: theme.id,
    baseSchemeId: baseSchemeId,
    alternateSchemeId: distinctAlternate,
    mode: mode,
  );
}

Map<String, Object?>? _userOptions(Object? value) {
  final root = _stringMap(value);
  if (root == null) return null;
  final nestedUser = _stringMap(root['user']);
  return _stringMap(nestedUser?['user_option'] ?? root['user_option']);
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) return null;
  try {
    return Map<String, Object?>.from(value);
  } on Object {
    return null;
  }
}

List<Object?> _objectList(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

int? _jsonInt(Object? value) => switch (value) {
  int() => value,
  String() => int.tryParse(value),
  _ => null,
};

final class _ThemeChoice {
  const _ThemeChoice({
    required this.id,
    required this.isDefault,
    required this.baseSchemeId,
    required this.alternateSchemeId,
    required this.limitsSchemes,
  });

  final int id;
  final bool isDefault;
  final int? baseSchemeId;
  final int? alternateSchemeId;
  final bool limitsSchemes;
}

final class _SchemeChoice {
  const _SchemeChoice({required this.id, required this.themeId});

  final int id;
  final int? themeId;
}

const Set<String> _appearanceVariables = {
  '--scheme-type',
  '--primary',
  '--secondary',
  '--tertiary',
  '--quaternary',
  '--header_background',
  '--header_primary',
  '--metadata-color',
  '--content-border-color',
  '--highlight',
  '--danger',
  '--success',
  '--love',
  '--d-selected',
  '--d-selected-text-color',
  '--d-hover',
  '--primary-very-low',
  '--primary-low',
  '--primary-low-mid',
  '--primary-medium',
  '--primary-high',
  '--primary-very-high',
  '--secondary-very-high',
  '--tertiary-low',
  '--quaternary-low',
  '--highlight-low',
  '--danger-low',
  '--mention-background-color',
  '--hljs-bg',
  '--inline-code-bg',
  '--hljs-keyword',
  '--hljs-string',
  '--hljs-comment',
  '--hljs-number',
  '--hljs-title',
  '--hljs-name',
  '--hljs-meta',
  '--hljs-attribute',
  '--hljs-attr',
};

/// Parses one generated Discourse color-definition stylesheet.
///
/// Only declarations on top-level, globally-applicable `:root` rules are
/// considered. Later declarations win as they do in CSS, including the theme
/// color definitions that Discourse appends after its core rule.
ResolvedSitePalette? parseSiteAppearanceStylesheet(String source) {
  final StyleSheet sheet;
  try {
    sheet = css.parse(source, errors: []);
  } catch (_) {
    return null;
  }

  final variables = <String, List<_CascadedValue>>{};
  for (final node in sheet.topLevels) {
    if (node is! RuleSet || !_hasGlobalRoot(node)) continue;
    for (final node in node.declarationGroup.declarations) {
      if (node is! Declaration ||
          !_appearanceVariables.contains(node.property)) {
        continue;
      }
      final value = _declarationValue(node);
      if (value == null) continue;
      (variables[node.property] ??= []).add(
        _CascadedValue(value, important: node.important),
      );
    }
  }

  final resolver = _VariableResolver(variables);
  Color? color(String name) {
    for (final value in resolver.resolveCandidates(name)) {
      final parsed = _parseColor(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  final schemeType = resolver
      .resolveCandidates('--scheme-type')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value == 'light' || value == 'dark')
      .firstOrNull;
  final brightness = switch (schemeType) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => null,
  };
  if (brightness == null) return null;

  final primary = color('--primary');
  final secondary = color('--secondary');
  final tertiary = color('--tertiary');
  if (primary == null || secondary == null || tertiary == null) return null;

  final json = <String, dynamic>{
    'brightness': brightness.name,
    'primary': primary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'tertiary': tertiary.toARGB32(),
  };
  void add(String field, String variable) {
    final value = color(variable);
    if (value != null) json[field] = value.toARGB32();
  }

  const fields = <String, String>{
    'quaternary': '--quaternary',
    'headerBackground': '--header_background',
    'headerPrimary': '--header_primary',
    'metadataColor': '--metadata-color',
    'contentBorderColor': '--content-border-color',
    'highlight': '--highlight',
    'danger': '--danger',
    'success': '--success',
    'love': '--love',
    'selected': '--d-selected',
    'selectedForeground': '--d-selected-text-color',
    'hover': '--d-hover',
    'primaryVeryLow': '--primary-very-low',
    'primaryLow': '--primary-low',
    'primaryLowMid': '--primary-low-mid',
    'primaryMedium': '--primary-medium',
    'primaryHigh': '--primary-high',
    'primaryVeryHigh': '--primary-very-high',
    'secondaryVeryHigh': '--secondary-very-high',
    'tertiaryLow': '--tertiary-low',
    'quaternaryLow': '--quaternary-low',
    'highlightLow': '--highlight-low',
    'dangerLow': '--danger-low',
    'mentionBackground': '--mention-background-color',
    'codeBlockBackground': '--hljs-bg',
    'inlineCodeBackground': '--inline-code-bg',
    'codeKeyword': '--hljs-keyword',
    'codeString': '--hljs-string',
    'codeComment': '--hljs-comment',
  };
  for (final MapEntry(:key, :value) in fields.entries) {
    add(key, value);
  }

  void addFirst(String field, Iterable<String> variables) {
    for (final variable in variables) {
      final value = color(variable);
      if (value != null) {
        json[field] = value.toARGB32();
        return;
      }
    }
  }

  addFirst('codeNumber', const ['--hljs-number', '--hljs-title']);
  addFirst('codeName', const ['--hljs-name', '--hljs-title']);
  addFirst('codeMeta', const [
    '--hljs-meta',
    '--hljs-attribute',
    '--hljs-attr',
  ]);

  return ResolvedSitePalette.fromJson(json);
}

String? _declarationValue(Declaration declaration) {
  final source = declaration.span.text;
  final colon = source.indexOf(':');
  if (colon < 0) return null;
  var value = source.substring(colon + 1).trim();
  if (value.endsWith(';')) value = value.substring(0, value.length - 1).trim();
  if (declaration.important) {
    value = value.replaceFirst(
      RegExp(r'\s*!important\s*$', caseSensitive: false),
      '',
    );
  }
  return value.trim();
}

bool _hasGlobalRoot(RuleSet rule) =>
    rule.selectorGroup?.selectors.any(_isGlobalRoot) ?? false;

bool _isGlobalRoot(Selector selector) {
  final sequences = selector.simpleSelectorSequences;
  if (sequences.length == 1) {
    final simple = sequences.single.simpleSelector;
    return simple is PseudoClassSelector && simple.name == 'root';
  }
  if (sequences.length != 2 ||
      sequences.any((sequence) => !sequence.isCombinatorNone)) {
    return false;
  }
  final simple = sequences.map((sequence) => sequence.simpleSelector).toList();
  return simple.any(
        (selector) => selector is ElementSelector && selector.name == 'html',
      ) &&
      simple.any(
        (selector) =>
            selector is PseudoClassSelector && selector.name == 'root',
      );
}

final class _CascadedValue {
  const _CascadedValue(this.value, {required this.important});

  final String value;
  final bool important;
}

final class _VariableResolver {
  _VariableResolver(this.values);

  static const int _maxDepth = 16;
  static const int _maxCandidatesPerPriority = 16;
  static const int _maxSubstitutionsPerCandidate = 32;
  static const int _maxExpandedValueLength = 2048;

  final Map<String, List<_CascadedValue>> values;
  final Map<String, List<_CascadedValue>> _orderedCandidateCache = {};

  Iterable<String> resolveCandidates(String name) sync* {
    for (final candidate in _orderedCandidates(name)) {
      final result = _substitute(
        candidate.value,
        {name},
        1,
        _ResolutionBudget(_maxSubstitutionsPerCandidate),
      );
      if (result != null) yield result;
    }
  }

  String? _resolveVariable(
    String name,
    Set<String> active,
    int depth,
    _ResolutionBudget budget,
  ) {
    if (depth >= _maxDepth || !active.add(name)) return null;
    try {
      for (final candidate in _orderedCandidates(name)) {
        final result = _substitute(candidate.value, active, depth + 1, budget);
        if (result != null) return result;
      }
      return null;
    } finally {
      active.remove(name);
    }
  }

  List<_CascadedValue> _orderedCandidates(String name) =>
      _orderedCandidateCache.putIfAbsent(name, () {
        final candidates = values[name] ?? const <_CascadedValue>[];
        return List.unmodifiable([
          ..._boundedPriorityCandidates(candidates, important: true),
          ..._boundedPriorityCandidates(candidates, important: false),
        ]);
      });

  List<_CascadedValue> _boundedPriorityCandidates(
    List<_CascadedValue> candidates, {
    required bool important,
  }) {
    _CascadedValue? oldest;
    for (final candidate in candidates) {
      if (candidate.important == important) oldest ??= candidate;
    }
    if (oldest == null) return const [];

    final selected = <_CascadedValue>[];
    for (final candidate in candidates.reversed) {
      if (candidate.important != important) continue;
      selected.add(candidate);
      if (selected.length == _maxCandidatesPerPriority) break;
    }

    // Core definitions precede theme overrides. Retain that oldest safety net
    // even when an adversarial cascade exceeds the candidate cap.
    if (!selected.any((candidate) => identical(candidate, oldest))) {
      selected.removeLast();
      selected.add(oldest);
    }
    return selected;
  }

  String? _substitute(
    String source,
    Set<String> active,
    int depth,
    _ResolutionBudget budget,
  ) {
    if (depth >= _maxDepth || source.length > _maxExpandedValueLength) {
      return null;
    }
    var result = source;
    while (true) {
      final match = RegExp(
        r'var\s*\(',
        caseSensitive: false,
      ).firstMatch(result);
      if (match == null) return result;
      if (!budget.consume()) return null;
      final open = result.indexOf('(', match.start);
      final close = _matchingParenthesis(result, open);
      if (close == null) return null;
      final arguments = result.substring(open + 1, close);
      final comma = _topLevelComma(arguments);
      final name = (comma == null ? arguments : arguments.substring(0, comma))
          .trim();
      if (!name.startsWith('--')) return null;
      var replacement = _resolveVariable(name, active, depth + 1, budget);
      if (replacement == null && comma != null) {
        replacement = _substitute(
          arguments.substring(comma + 1),
          active,
          depth + 1,
          budget,
        );
      }
      if (replacement == null) return null;
      final expandedLength =
          result.length - (close + 1 - match.start) + replacement.length;
      if (expandedLength > _maxExpandedValueLength) return null;
      result = result.replaceRange(match.start, close + 1, replacement);
    }
  }
}

final class _ResolutionBudget {
  _ResolutionBudget(this.remainingSubstitutions);

  int remainingSubstitutions;

  bool consume() {
    if (remainingSubstitutions == 0) return false;
    remainingSubstitutions--;
    return true;
  }
}

int? _matchingParenthesis(String source, int open) {
  var depth = 0;
  String? quote;
  for (var index = open; index < source.length; index++) {
    final character = source[index];
    if (quote != null) {
      if (character == '\\') {
        index++;
      } else if (character == quote) {
        quote = null;
      }
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
    } else if (character == '(') {
      depth++;
    } else if (character == ')' && --depth == 0) {
      return index;
    }
  }
  return null;
}

int? _topLevelComma(String source) {
  var depth = 0;
  String? quote;
  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (quote != null) {
      if (character == '\\') {
        index++;
      } else if (character == quote) {
        quote = null;
      }
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
    } else if (character == '(') {
      depth++;
    } else if (character == ')') {
      depth--;
    } else if (character == ',' && depth == 0) {
      return index;
    }
  }
  return null;
}

Color? _parseColor(String source) {
  final value = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .trim()
      .toLowerCase();
  final named = _namedColors[value];
  if (named != null) return named;

  final hex = RegExp(r'^#([0-9a-f]+)$').firstMatch(value)?.group(1);
  if (hex != null) return _hexColor(hex);

  final function = RegExp(r'^(rgba?|hsla?)\((.*)\)$').firstMatch(value);
  if (function == null) return null;
  final name = function.group(1)!;
  final arguments = function.group(2)!;
  return name.startsWith('rgb') ? _rgbColor(arguments) : _hslColor(arguments);
}

const Map<String, Color> _namedColors = {
  'transparent': Color(0x00000000),
  'black': Color(0xFF000000),
  'silver': Color(0xFFC0C0C0),
  'gray': Color(0xFF808080),
  'grey': Color(0xFF808080),
  'white': Color(0xFFFFFFFF),
  'maroon': Color(0xFF800000),
  'red': Color(0xFFFF0000),
  'purple': Color(0xFF800080),
  'fuchsia': Color(0xFFFF00FF),
  'green': Color(0xFF008000),
  'lime': Color(0xFF00FF00),
  'olive': Color(0xFF808000),
  'yellow': Color(0xFFFFFF00),
  'navy': Color(0xFF000080),
  'blue': Color(0xFF0000FF),
  'teal': Color(0xFF008080),
  'aqua': Color(0xFF00FFFF),
  'orange': Color(0xFFFFA500),
};

Color? _hexColor(String value) {
  int? pair(String digits) => int.tryParse(digits, radix: 16);
  return switch (value.length) {
    3 => switch ((pair(value[0] * 2), pair(value[1] * 2), pair(value[2] * 2))) {
      (final r?, final g?, final b?) => Color.fromARGB(255, r, g, b),
      _ => null,
    },
    4 => switch ((
      pair(value[0] * 2),
      pair(value[1] * 2),
      pair(value[2] * 2),
      pair(value[3] * 2),
    )) {
      (final r?, final g?, final b?, final a?) => Color.fromARGB(a, r, g, b),
      _ => null,
    },
    6 => switch ((
      pair(value.substring(0, 2)),
      pair(value.substring(2, 4)),
      pair(value.substring(4, 6)),
    )) {
      (final r?, final g?, final b?) => Color.fromARGB(255, r, g, b),
      _ => null,
    },
    8 => switch ((
      pair(value.substring(0, 2)),
      pair(value.substring(2, 4)),
      pair(value.substring(4, 6)),
      pair(value.substring(6, 8)),
    )) {
      (final r?, final g?, final b?, final a?) => Color.fromARGB(a, r, g, b),
      _ => null,
    },
    _ => null,
  };
}

Color? _rgbColor(String source) {
  final components = _functionalComponents(source);
  if (components == null) return null;
  final red = _rgbComponent(components.channels[0]);
  final green = _rgbComponent(components.channels[1]);
  final blue = _rgbComponent(components.channels[2]);
  final alpha = _alphaComponent(components.alpha);
  if (red == null || green == null || blue == null || alpha == null) {
    return null;
  }
  return Color.fromARGB(alpha, red, green, blue);
}

Color? _hslColor(String source) {
  final components = _functionalComponents(source);
  if (components == null) return null;
  final hue = _hue(components.channels[0]);
  final saturation = _percentage(components.channels[1]);
  final lightness = _percentage(components.channels[2]);
  final alpha = _alphaComponent(components.alpha);
  if (hue == null || saturation == null || lightness == null || alpha == null) {
    return null;
  }

  final chroma = (1 - (2 * lightness - 1).abs()) * saturation;
  final sector = hue / 60;
  final x = chroma * (1 - (sector % 2 - 1).abs());
  final (r1, g1, b1) = switch (sector.floor() % 6) {
    0 => (chroma, x, 0.0),
    1 => (x, chroma, 0.0),
    2 => (0.0, chroma, x),
    3 => (0.0, x, chroma),
    4 => (x, 0.0, chroma),
    _ => (chroma, 0.0, x),
  };
  final match = lightness - chroma / 2;
  return Color.fromARGB(
    alpha,
    ((r1 + match) * 255).round().clamp(0, 255),
    ((g1 + match) * 255).round().clamp(0, 255),
    ((b1 + match) * 255).round().clamp(0, 255),
  );
}

({List<String> channels, String? alpha})? _functionalComponents(String source) {
  if (source.contains(',')) {
    final parts = source.split(',').map((part) => part.trim()).toList();
    if (parts.length != 3 && parts.length != 4) return null;
    return (channels: parts.take(3).toList(), alpha: parts.elementAtOrNull(3));
  }

  final slash = source.split('/');
  if (slash.length > 2) return null;
  final channels = slash.first.trim().split(RegExp(r'\s+'));
  if (channels.length != 3) return null;
  return (
    channels: channels,
    alpha: slash.length == 2 ? slash.last.trim() : null,
  );
}

int? _rgbComponent(String source) {
  final value = source.trim();
  if (value.endsWith('%')) {
    final percent = _finiteDouble(value.substring(0, value.length - 1));
    return percent == null ? null : (percent * 2.55).round().clamp(0, 255);
  }
  final number = _finiteDouble(value);
  return number?.round().clamp(0, 255);
}

int? _alphaComponent(String? source) {
  if (source == null) return 255;
  final value = source.trim();
  final parsed = _finiteDouble(
    value.endsWith('%') ? value.substring(0, value.length - 1) : value,
  );
  if (parsed == null) return null;
  final number = value.endsWith('%')
      ? parsed.clamp(0, 100) / 100
      : parsed.clamp(0, 1);
  return (number * 255).round();
}

double? _percentage(String source) {
  final value = source.trim();
  if (!value.endsWith('%')) return null;
  final parsed = _finiteDouble(value.substring(0, value.length - 1));
  return parsed == null ? null : parsed.clamp(0, 100) / 100;
}

double? _finiteDouble(String source) {
  final value = double.tryParse(source);
  return value == null || !value.isFinite ? null : value;
}

double? _hue(String source) {
  final value = source.trim();
  final match = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(deg|grad|rad|turn)?$',
  ).firstMatch(value);
  if (match == null) return null;
  final number = double.parse(match.group(1)!);
  final degrees = switch (match.group(2)) {
    'grad' => number * 0.9,
    'rad' => number * 180 / math.pi,
    'turn' => number * 360,
    _ => number,
  };
  return (degrees % 360 + 360) % 360;
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) => index < length ? this[index] : null;
}
