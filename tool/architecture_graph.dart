// Reports how lib/ libraries depend on each other.
//
//   dart run tool/architecture_graph.dart [lib/some/entry.dart ...]
//
// `test/architecture_layer_contract_test.dart` holds the enforced limits.
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Declared imports and exports between libraries, with parts folded into the
/// library that owns them, because Dart compiles those as one unit.
const _shellController = 'lib/src/shell/shell_controller.dart';

final class LibraryGraph {
  LibraryGraph._(this.edges, this.widgetLibraries);

  factory LibraryGraph.fromSources(Map<String, String> sources) {
    final parsed = {
      for (final entry in sources.entries)
        entry.key: parseString(
          content: entry.value,
          path: entry.key,
          throwIfDiagnostics: false,
        ).unit,
    };
    final ownerOf = <String, String>{};
    for (final entry in parsed.entries) {
      for (final directive in entry.value.directives) {
        if (directive is PartDirective) {
          final part = _resolve(entry.key, directive.uri.stringValue!);
          if (part != null) ownerOf[part] = entry.key;
        }
      }
    }
    String owner(String path) {
      var current = path;
      while (ownerOf.containsKey(current)) {
        current = ownerOf[current]!;
      }
      return current;
    }

    final edges = SplayTreeMap<String, Set<String>>();
    for (final entry in parsed.entries) {
      final source = owner(entry.key);
      final targets = edges.putIfAbsent(source, SplayTreeSet<String>.new);
      for (final directive in entry.value.directives) {
        final uri = switch (directive) {
          ImportDirective() => directive.uri.stringValue,
          ExportDirective() => directive.uri.stringValue,
          _ => null,
        };
        if (uri == null) continue;
        final target = _resolve(entry.key, uri);
        if (target != null && parsed.containsKey(target)) {
          targets.add(owner(target));
        }
      }
    }
    final widgetLibraries = {
      for (final entry in parsed.entries)
        for (final declaration
            in entry.value.declarations.whereType<ClassDeclaration>())
          if (_widgetBases.any(
            (declaration.extendsClause?.superclass.toSource() ?? '').startsWith,
          ))
            owner(entry.key),
    };
    return LibraryGraph._(edges, widgetLibraries);
  }

  /// Generated localizations are excluded: every library reaches them through
  /// `l10n/strings.dart` and they import nothing from the application.
  factory LibraryGraph.load([List<String> roots = const ['lib']]) {
    final sources = <String, String>{};
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        final path = entity.path.replaceAll('\\', '/');
        if (entity is File &&
            path.endsWith('.dart') &&
            !path.contains('/l10n/generated/')) {
          sources[path] = entity.readAsStringSync();
        }
      }
    }
    return LibraryGraph.fromSources(sources);
  }

  final SplayTreeMap<String, Set<String>> edges;

  /// Libraries that declare a widget or a widget's state.
  final Set<String> widgetLibraries;

  static const _widgetBases = [
    'StatelessWidget',
    'StatefulWidget',
    'InheritedWidget',
    'InheritedNotifier',
    'InheritedModel',
    'RenderObjectWidget',
    'LeafRenderObjectWidget',
    'SingleChildRenderObjectWidget',
    'MultiChildRenderObjectWidget',
    'State<',
  ];

  static String? _resolve(String source, String value) {
    var uri = Uri.parse(value);
    if (uri.scheme == 'package') {
      final segments = uri.pathSegments;
      if (segments.first != 'discourse_native') return null;
      uri = Uri(pathSegments: ['lib', ...segments.skip(1)]);
      return uri.path;
    }
    if (uri.hasScheme) return null;
    return Uri(
      path: '/$source',
    ).resolveUri(uri).normalizePath().pathSegments.join('/');
  }

  /// `lib/src/models/topic.dart` is `models`; the kit barrel counts as `ui` and
  /// each bundled plugin as `plugins`.
  static String areaOf(String path) {
    final segments = path.split('/');
    if (path == 'lib/discourse_ui.dart') return 'ui';
    if (segments.length >= 3 && segments[1] == 'src') return segments[2];
    return 'root';
  }

  Set<String> closureOf(String entry) {
    final seen = {entry};
    final pending = [entry];
    while (pending.isNotEmpty) {
      for (final target in edges[pending.removeLast()] ?? const <String>{}) {
        if (seen.add(target)) pending.add(target);
      }
    }
    return seen;
  }

  /// Libraries that must be recompiled when [path]'s public API changes.
  Set<String> dependentsOf(String path) {
    final reverse = <String, Set<String>>{};
    for (final entry in edges.entries) {
      for (final target in entry.value) {
        reverse.putIfAbsent(target, () => {}).add(entry.key);
      }
    }
    final seen = {path};
    final pending = [path];
    while (pending.isNotEmpty) {
      for (final source in reverse[pending.removeLast()] ?? const <String>{}) {
        if (seen.add(source)) pending.add(source);
      }
    }
    return seen;
  }

  /// Import cycles, largest first.
  List<List<String>> cycles() {
    final index = <String, int>{};
    final low = <String, int>{};
    final stack = <String>[];
    final onStack = <String>{};
    final result = <List<String>>[];
    var next = 0;

    void visit(String node) {
      index[node] = low[node] = next++;
      stack.add(node);
      onStack.add(node);
      for (final target in edges[node] ?? const <String>{}) {
        if (!index.containsKey(target)) {
          visit(target);
          low[node] = math.min(low[node]!, low[target]!);
        } else if (onStack.contains(target)) {
          low[node] = math.min(low[node]!, index[target]!);
        }
      }
      if (low[node] != index[node]) return;
      final members = <String>[];
      while (true) {
        final member = stack.removeLast();
        onStack.remove(member);
        members.add(member);
        if (member == node) break;
      }
      if (members.length > 1) result.add(members..sort());
    }

    for (final node in edges.keys) {
      if (!index.containsKey(node)) visit(node);
    }
    return result..sort((a, b) => b.length.compareTo(a.length));
  }

  /// Pairs of layers with an import in each direction, as `a <-> b`.
  Set<String> mutualLayerPairs() {
    final directed = <(String, String)>{
      for (final entry in edges.entries)
        for (final target in entry.value)
          if (_layers.contains(areaOf(entry.key)) &&
              _layers.contains(areaOf(target)) &&
              areaOf(entry.key) != areaOf(target))
            (areaOf(entry.key), areaOf(target)),
    };
    return SplayTreeSet.of({
      for (final (from, to) in directed)
        if (from.compareTo(to) < 0 && directed.contains((to, from)))
          '$from <-> $to',
    });
  }

  /// Widget libraries that compile whenever [entry] compiles.
  Set<String> widgetLibrariesReachedBy(String entry) =>
      closureOf(entry).intersection(widgetLibraries);

  /// Libraries under `lib/` that compile whenever [entry] compiles.
  Set<String> applicationLibrariesReachedBy(String entry) =>
      closureOf(entry).where((library) => library.startsWith('lib/')).toSet();

  /// For each `*_test.dart` under `test/`, how many application libraries it
  /// compiles. Most of a test's reach comes through shared helpers, so the
  /// graph must be loaded with `test` among its roots.
  List<int> testFileReach() => [
    for (final path in edges.keys)
      if (path.startsWith('test/') && path.endsWith('_test.dart'))
        applicationLibrariesReachedBy(path).length,
  ];

  static const _layers = {
    'foundation',
    'models',
    'theme',
    'ui',
    'data',
    'plugin_api',
    'shell',
    'styleguide',
    'plugins',
  };

  /// Every edge from one area to another, as `source -> target`.
  Set<String> edgesBetween(String from, String to) => {
    for (final entry in edges.entries)
      if (areaOf(entry.key) == from)
        for (final target in entry.value)
          if (areaOf(target) == to) '${entry.key} -> $target',
  };
}

void main(List<String> entries) {
  final graph = LibraryGraph.load();
  final cycles = graph.cycles();
  stdout.writeln('libraries ${graph.edges.length}');
  stdout.writeln('largest cycle ${cycles.isEmpty ? 0 : cycles.first.length}');
  stdout.writeln('cycles ${cycles.map((cycle) => cycle.length).toList()}');
  stdout.writeln(
    'libraries in cycles '
    '${cycles.fold<int>(0, (sum, cycle) => sum + cycle.length)}',
  );
  stdout.writeln('mutual layer pairs ${graph.mutualLayerPairs().toList()}');
  stdout.writeln(
    'widget libraries reached by ShellController '
    '${graph.widgetLibrariesReachedBy(_shellController).length}',
  );
  final testReach = LibraryGraph.load(const ['lib', 'test']).testFileReach();
  stdout.writeln(
    'mean application libraries per test file '
    '${(testReach.fold<int>(0, (sum, reach) => sum + reach) / testReach.length).round()} '
    'over ${testReach.length} files',
  );
  final targets = entries.isNotEmpty
      ? entries
      : const [
          'lib/src/foundation/calendar_day.dart',
          'lib/src/models/topic.dart',
          'lib/src/models/site_config.dart',
          'lib/src/theme/app_theme.dart',
          'lib/discourse_ui.dart',
          'lib/src/data/discourse_api.dart',
          'lib/src/plugin_api/site_plugin_api.dart',
          'lib/src/shell/shell_controller.dart',
          'lib/discourse_plugin_sdk.dart',
        ];
  for (final target in targets) {
    stdout.writeln(
      '$target reaches ${graph.closureOf(target).length}, '
      'invalidated by ${graph.dependentsOf(target).length}',
    );
  }
}
