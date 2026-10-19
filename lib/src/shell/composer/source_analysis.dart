import 'package:flutter/foundation.dart' show setEquals;

import 'components/list_source.dart';
import 'components/todo_source.dart';
import 'markdown_highlight.dart';

/// Reuses list and todo parsing for one exact source within one editor.
final class ComposerSourceAnalysis {
  ComposerSourceAnalysis(this.source, {this._codeRanges});

  final String source;
  final CodeRanges? _codeRanges;
  late final _structural = _ListAnalysis(source, const {}, _codeRanges);
  _ListAnalysis? _configured;

  List<ComposerListItem> listItems({Set<String> referenceMarkers = const {}}) =>
      _listsFor(referenceMarkers).items;

  List<ComposerTodo> todos({Set<String> referenceMarkers = const {}}) =>
      _listsFor(referenceMarkers).todos;

  _ListAnalysis _listsFor(Set<String> referenceMarkers) {
    if (referenceMarkers.isEmpty) return _structural;
    final configured = _configured;
    if (configured != null &&
        setEquals(configured.referenceMarkers, referenceMarkers)) {
      return configured;
    }
    return _configured = _ListAnalysis(source, referenceMarkers, _codeRanges);
  }
}

final class _ListAnalysis {
  _ListAnalysis(this.source, Set<String> referenceMarkers, this.codeRanges)
    : referenceMarkers = Set.unmodifiable(referenceMarkers);

  final String source;
  final Set<String> referenceMarkers;
  final CodeRanges? codeRanges;

  late final items = List<ComposerListItem>.unmodifiable(
    composerListItems(source, referenceMarkers: referenceMarkers),
  );
  late final todos = List<ComposerTodo>.unmodifiable(
    composerTodos(
      source,
      codeRanges: codeRanges,
      referenceMarkers: referenceMarkers,
      listItems: items,
    ),
  );
}
