import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

enum _Kind { import, export, part, partOf }

typedef _Edge = ({String source, int line, _Kind kind, String target});

final class _Unit {
  _Unit(this.edges, this.errors, this.libraryName, this.namedPart);

  final List<_Edge> edges;
  final List<String> errors;
  final String? libraryName;
  final ({String name, int line})? namedPart;
}

/// Checks declared local library access through imports, exports and parts.
///
/// Dependencies' private imports and external package internals are not followed.
/// Prefixes and combinators do not exempt forbidden libraries. Inferred API
/// types, callbacks and duplicated state are outside this check.
final class OwnerDependencyGraph {
  OwnerDependencyGraph(Map<String, String> sources) {
    for (final path in sources.keys.toList()..sort()) {
      final parsed = parseString(
        content: sources[path]!,
        path: path,
        throwIfDiagnostics: false,
      );
      final edges = <_Edge>[];
      final errors = <String>[
        for (final error in parsed.errors)
          '$path:${parsed.lineInfo.getLocation(error.offset).lineNumber}: '
              'malformed Dart source: ${error.message}',
      ];
      String? libraryName;
      ({String name, int line})? namedPart;
      void add(_Kind kind, StringLiteral literal) {
        final line = parsed.lineInfo.getLocation(literal.offset).lineNumber;
        try {
          final value = literal.stringValue;
          if (value == null) throw const FormatException('nonliteral URI');
          final target = _resolve(path, value);
          if (target != null) {
            edges.add((source: path, line: line, kind: kind, target: target));
          }
        } on FormatException catch (error) {
          errors.add('$path:$line: invalid local directive: $error');
        }
      }

      for (final directive in parsed.unit.directives) {
        switch (directive) {
          case ImportDirective():
            add(_Kind.import, directive.uri);
            for (final configuration in directive.configurations) {
              add(_Kind.import, configuration.uri);
            }
          case ExportDirective():
            add(_Kind.export, directive.uri);
            for (final configuration in directive.configurations) {
              add(_Kind.export, configuration.uri);
            }
          case PartDirective():
            add(_Kind.part, directive.uri);
          case PartOfDirective():
            final uri = directive.uri;
            if (uri != null) {
              add(_Kind.partOf, uri);
            } else if (directive.libraryName case final name?) {
              namedPart = (
                name: name.toSource(),
                line: parsed.lineInfo.getLocation(directive.offset).lineNumber,
              );
            }
          case LibraryDirective():
            libraryName = directive.name?.toSource();
        }
      }
      _units[path] = _Unit(edges, errors, libraryName, namedPart);
    }

    for (final entry in _units.entries) {
      final named = entry.value.namedPart;
      if (named != null) {
        final parents = _units.entries
            .where(
              (candidate) =>
                  candidate.value.libraryName == named.name &&
                  candidate.value.edges.any(
                    (edge) =>
                        edge.kind == _Kind.part && edge.target == entry.key,
                  ),
            )
            .map((candidate) => candidate.key)
            .toList();
        if (parents.length != 1) {
          entry.value.errors.add(
            '${entry.key}:${named.line}: named part-of ${named.name} must '
            'resolve to one local library; found ${parents.length} '
            '(${parents.join(', ')}).',
          );
        } else {
          entry.value.edges.add((
            source: entry.key,
            line: named.line,
            kind: _Kind.partOf,
            target: parents.single,
          ));
        }
      }
    }
    final declaredPartMemberships = [
      for (final unit in _units.values)
        for (final edge in unit.edges)
          if (edge.kind == _Kind.part || edge.kind == _Kind.partOf) edge,
    ];
    for (final edge in declaredPartMemberships) {
      _units[edge.target]?.edges.add((
        source: edge.source,
        line: edge.line,
        kind: edge.kind,
        target: edge.source,
      ));
    }
  }

  final _units = <String, _Unit>{};

  List<String> violations({
    required Iterable<String> owners,
    required Set<String> forbidden,
  }) {
    final violations = <String>[
      for (final path in forbidden.toList()..sort())
        if (!_units.containsKey(path))
          '$path\nMissing declared shell authority source. Update the boundary '
              'declaration to its owning library before checking owner access.',
    ];
    for (final owner in owners.toList()..sort()) {
      final visited = <(String, bool)>{};
      void visit(String path, bool ownLibrary, List<_Edge> trail) {
        if (!visited.add((path, ownLibrary))) return;
        final chain = [
          owner,
          for (final edge in trail)
            '--${edge.kind.name} at ${edge.source}:${edge.line}--> ${edge.target}',
        ].join('\n  ');
        const remedy =
            'Pass a narrow typed capability instead; keep the '
            'owner library outside ShellController and ShellScope.';
        if (forbidden.contains(path)) {
          violations.add('$chain\nForbidden shell authority. $remedy');
          return;
        }
        final unit = _units[path];
        if (unit == null) {
          violations.add(
            '$chain\nMissing expected local source. Restore the source or update '
            'its declared owner/dependency path before checking access.',
          );
          return;
        }
        for (final error in unit.errors) {
          violations.add(
            '$chain\n$error Repair the source before checking '
            'the dependency boundary.',
          );
        }
        for (final edge in unit.edges) {
          final member = edge.kind == _Kind.part || edge.kind == _Kind.partOf;
          if (edge.kind == _Kind.import && !ownLibrary) continue;
          visit(edge.target, ownLibrary && member, [...trail, edge]);
        }
      }

      visit(owner, true, []);
    }
    return violations;
  }

  static String? _resolve(String source, String value) {
    var uri = Uri.parse(value);
    if (uri.scheme == 'package') {
      final segments = uri.pathSegments;
      if (segments.firstOrNull != 'discourse_native') return null;
      uri = Uri(pathSegments: ['lib', ...segments.skip(1)]);
    } else if (uri.hasScheme) {
      if (uri.scheme == 'dart') return null;
      throw FormatException('unsupported URI $value');
    } else {
      if (uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
        throw FormatException('unsupported local URI $value');
      }
      uri = Uri(path: '/$source').resolveUri(uri);
    }
    final normalized = Uri(path: '/').resolveUri(uri).normalizePath();
    final path = normalized.pathSegments.join('/');
    if (!path.startsWith('lib/')) {
      throw FormatException('local dependency escapes lib: $value');
    }
    return path;
  }
}
