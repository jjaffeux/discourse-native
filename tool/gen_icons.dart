library;

import 'dart:io';

const List<(String, String)> _spriteFiles = [
  ('', 'fontawesome/solid.svg'),
  ('far-', 'fontawesome/regular.svg'),
  ('fab-', 'fontawesome/brands.svg'),
  ('', 'discourse-additional.svg'),
];

const String _output = 'lib/src/theme/d_icons.dart';
const String _manifest = 'tool/icons.txt';

void main(List<String> args) {
  final root = _discourseRoot(args);
  stdout.writeln('Reading sprites from $root');

  final symbols = _readSprites(root);
  final (names, aliases) = _readManifest();

  final missing = names.where((n) => !symbols.containsKey(n)).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Not in the sprites: ${missing.join(', ')}');
    stderr.writeln(
      'Check the spelling against SvgSprite::SVG_ICONS, or the icon may only '
      'exist in a newer Discourse than the checkout above.',
    );
    exit(1);
  }
  final danglingAliases = aliases.entries.where(
    (e) => !names.contains(e.value),
  );
  for (final alias in danglingAliases) {
    stderr.writeln(
      'Alias "${alias.key}" points at "${alias.value}", which is not listed.',
    );
    exit(1);
  }

  for (final name in names) {
    final unresolved = _unresolvedRefs(symbols[name]!.$2);
    if (unresolved.isEmpty) continue;
    // discourse-additional.svg has symbols that `<use href="#plus">` a sibling
    // symbol, which only works while they share a document. Lifting one out on
    // its own would draw nothing, so say so instead of writing a blank icon.
    stderr.writeln(
      '"$name" refers to ${unresolved.join(', ')}, which is defined outside '
      'the symbol. Inline it in tool/gen_icons.dart before listing this icon.',
    );
    exit(1);
  }

  File(_output).writeAsStringSync(_render(names, aliases, symbols));
  stdout.writeln(
    'Wrote $_output — ${names.length} icons, '
    '${aliases.length} aliases, ${File(_output).lengthSync() ~/ 1024}KB',
  );
}

String _discourseRoot(List<String> args) {
  final flag = args
      .where((a) => a.startsWith('--discourse='))
      .map((a) => a.substring('--discourse='.length))
      .firstOrNull;
  final candidates = [
    ?flag,
    ?Platform.environment['DISCOURSE_PATH'],
    ...Directory('..')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path)
        .where((p) => p.contains('discourse')),
  ];

  for (final candidate in candidates) {
    final marker = File(
      '$candidate/vendor/assets/svg-icons/fontawesome/solid.svg',
    );
    if (marker.existsSync()) return candidate;
  }

  stderr.writeln(
    'No Discourse checkout found. Pass --discourse=/path/to/discourse, or set '
    'DISCOURSE_PATH.',
  );
  exit(1);
}

Map<String, (String, String)> _readSprites(String root) {
  final symbols = <String, (String, String)>{};

  for (final (prefix, path) in _spriteFiles) {
    final file = File('$root/vendor/assets/svg-icons/$path');
    if (!file.existsSync()) {
      stderr.writeln('Missing sprite: ${file.path}');
      exit(1);
    }
    final source = file.readAsStringSync();

    // The sprites are flat lists of non-nested <symbol> elements, so scanning
    // for the next closing tag is enough — no XML parser needed, and no
    // dependency for a script that only ever runs by hand.
    final open = RegExp(r'<symbol\b([^>]*)>');
    for (final match in open.allMatches(source)) {
      final attributes = match.group(1)!;
      final id = _attribute(attributes, 'id');
      final viewBox = _attribute(attributes, 'viewBox');
      if (id == null || viewBox == null) continue;

      final close = source.indexOf('</symbol>', match.end);
      if (close == -1) continue;

      // `<title>` is what Discourse strips too; it would render as a tooltip
      // string we never want.
      final inner = source
          .substring(match.end, close)
          .replaceAll(RegExp(r'<title>.*?</title>', dotAll: true), '')
          .trim();

      symbols['$prefix$id'] = (viewBox, inner);
    }
  }

  return symbols;
}

String? _attribute(String attributes, String name) =>
    RegExp('$name="([^"]*)"').firstMatch(attributes)?.group(1) ??
    RegExp("$name='([^']*)'").firstMatch(attributes)?.group(1);

Set<String> _unresolvedRefs(String inner) {
  final defined = RegExp(
    r'\bid="([^"]*)"',
  ).allMatches(inner).map((m) => m.group(1)!).toSet();
  final referenced = RegExp(
    r'(?:href="#|url\(#)([^")]*)',
  ).allMatches(inner).map((m) => m.group(1)!).toSet();
  return referenced.difference(defined);
}

(List<String>, Map<String, String>) _readManifest() {
  final names = <String>[];
  final aliases = <String, String>{};

  for (final raw in File(_manifest).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.contains('=')) {
      final [alias, target] = line.split('=').map((p) => p.trim()).toList();
      aliases[alias] = target;
    } else {
      names.add(line);
    }
  }

  return (names, aliases);
}

String _render(
  List<String> names,
  Map<String, String> aliases,
  Map<String, (String, String)> symbols,
) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED BY tool/gen_icons.dart — DO NOT EDIT.')
    ..writeln('//')
    ..writeln('// Symbols taken from Discourse\'s vendor/assets/svg-icons/.')
    ..writeln('// Font Awesome Free by @fontawesome - https://fontawesome.com')
    ..writeln('// License - https://fontawesome.com/license/free')
    ..writeln('// (Icons: CC BY 4.0, Fonts: SIL OFL 1.1, Code: MIT License)')
    ..writeln()
    ..writeln("import 'd_icon.dart';")
    ..writeln()
    ..writeln('/// Every icon in `tool/icons.txt`, as [DIconData].')
    ..writeln('abstract final class DIcons {');

  for (final name in names) {
    final (viewBox, inner) = symbols[name]!;
    buffer
      ..writeln('  static const DIconData ${_identifier(name)} = DIconData(')
      ..writeln("    '$name',")
      ..writeln("    '${_svg(viewBox, inner)}',")
      ..writeln('  );')
      ..writeln();
  }

  buffer
    ..writeln('  /// Icons by the name Discourse uses, aliases included, for')
    ..writeln('  /// the places where a name arrives as a string.')
    ..writeln('  static const Map<String, DIconData> byName = {');
  for (final name in names) {
    buffer.writeln("    '$name': ${_identifier(name)},");
  }
  for (final MapEntry(key: alias, value: target) in aliases.entries) {
    buffer.writeln("    '$alias': ${_identifier(target)},");
  }
  buffer
    ..writeln('  };')
    ..writeln('}');

  return buffer.toString();
}

String _svg(String viewBox, String inner) {
  final markup =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox" '
      'fill="currentColor">$inner</svg>';
  return markup
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(RegExp(r'\s*\n\s*'), '');
}

String _identifier(String name) {
  final parts = name.split('-');
  return [
    parts.first,
    ...parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)),
  ].join();
}
