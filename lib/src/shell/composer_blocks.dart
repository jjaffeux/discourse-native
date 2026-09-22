import 'dart:math' as math;

import 'composer_todo_source.dart';

/// Structural units in source Markdown. Inline components stay inside text.
enum ComposerBlockKind {
  paragraph('Paragraph'),
  heading('Heading'),
  list('List'),
  todo('To-do'),
  quote('Quote'),
  code('Code'),
  divider('Divider'),
  component('Block'),
  opaque('Source block');

  const ComposerBlockKind(this.label);
  final String label;
}

/// A complete block extent supplied by an existing component parser.
class ComposerBlockAtom {
  const ComposerBlockAtom(this.start, this.end, {this.label = 'Block'});

  final int start;
  final int end;
  final String label;
}

class ComposerBodyBlock {
  const ComposerBodyBlock({
    required this.id,
    required this.start,
    required this.end,
    required this.kind,
    required this.source,
    required this.movable,
    this.componentLabel,
  });

  final int id;
  final int start;
  final int end;
  final ComposerBlockKind kind;
  final String source;
  final bool movable;
  final String? componentLabel;

  String get label => componentLabel ?? kind.label;

  String get excerpt {
    if (kind == ComposerBlockKind.component) return label;
    return source
        .replaceFirst(RegExp(r'^ {0,3}#{1,6}[ \t]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// A lossless, conservative top-level index. It does not serialize Markdown.
///
/// Unclosed/ambiguous containers are indexed but cannot themselves be moved.
/// Complete lists include their continuation paragraphs and nested children.
class ComposerBlockIndex {
  ComposerBlockIndex._(this.source, this.revision, this.blocks, this.atoms);

  factory ComposerBlockIndex.parse(
    String source, {
    int revision = 0,
    List<ComposerBlockAtom> atoms = const [],
    ComposerBlockIndex? previous,
  }) {
    atoms = [
      for (final atom in atoms)
        if (atom.start >= 0 &&
            atom.end <= source.length &&
            atom.end > atom.start)
          ComposerBlockAtom(
            atom.start,
            _trimLineEndings(source, atom.start, atom.end),
            label: atom.label,
          ),
    ];
    final spans = _BlockScanner(source, atoms).scan();
    var nextId = previous == null
        ? 0
        : previous.blocks.fold(0, (n, b) => math.max(n, b.id + 1));
    final used = <int>{};
    var prefix = 0;
    var oldSuffix = previous?.source.length ?? 0;
    var newSuffix = source.length;
    if (previous != null) {
      while (prefix < previous.source.length &&
          prefix < source.length &&
          previous.source.codeUnitAt(prefix) == source.codeUnitAt(prefix)) {
        prefix++;
      }
      while (oldSuffix > prefix &&
          newSuffix > prefix &&
          previous.source.codeUnitAt(oldSuffix - 1) ==
              source.codeUnitAt(newSuffix - 1)) {
        oldSuffix--;
        newSuffix--;
      }
    }
    final blocks = <ComposerBodyBlock>[];
    for (final span in spans) {
      final raw = source.substring(span.start, span.end);
      ComposerBodyBlock? retained;
      if (previous != null) {
        for (final old in previous.blocks) {
          if (used.contains(old.id) || old.kind != span.kind) continue;
          final mappedStart = old.start >= oldSuffix
              ? old.start + newSuffix - oldSuffix
              : old.start;
          final unchanged = old.end <= prefix || old.start >= oldSuffix;
          if (unchanged && mappedStart == span.start && old.source == raw) {
            retained = old;
            break;
          }
          // A local edit inside a single block retains its identity.
          if (old.start <= prefix &&
              old.end >= oldSuffix &&
              span.start == old.start &&
              span.end >= newSuffix) {
            retained = old;
            break;
          }
        }
      }
      final id = retained?.id ?? nextId++;
      used.add(id);
      blocks.add(
        ComposerBodyBlock(
          id: id,
          start: span.start,
          end: span.end,
          kind: span.kind,
          source: raw,
          movable: span.movable,
          componentLabel: span.label,
        ),
      );
    }
    return ComposerBlockIndex._(
      source,
      revision,
      List.unmodifiable(blocks),
      List.unmodifiable(atoms),
    );
  }

  final String source;
  final int revision;
  final List<ComposerBodyBlock> blocks;
  final List<ComposerBlockAtom> atoms;

  ComposerBlockIndex withRevision(int revision) =>
      ComposerBlockIndex._(source, revision, blocks, atoms);

  ComposerBodyBlock? byId(int id) {
    for (final block in blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  ComposerBodyBlock? atOffset(int offset) {
    if (offset < 0) return blocks.firstOrNull;
    for (final block in blocks) {
      if (offset <= block.end) return block;
    }
    return blocks.lastOrNull;
  }

  /// [gap] is an insertion boundary in the original list, from zero to length.
  /// Returns null for no-ops, locked blocks and semantically unsafe joins.
  ComposerBlockMove? move(int id, int gap) {
    final from = blocks.indexWhere((b) => b.id == id);
    if (from < 0 || gap < 0 || gap > blocks.length) return null;
    if (!blocks[from].movable || gap == from || gap == from + 1) return null;
    final ordered = [...blocks];
    final moved = ordered.removeAt(from);
    final to = gap > from ? gap - 1 : gap;
    ordered.insert(to, moved);

    final result = StringBuffer(source.substring(0, blocks.first.start));
    final positions = <int, int>{};
    final mappedAtoms = <ComposerBlockAtom>[];
    final newline = source.contains('\r\n') ? '\r\n' : '\n';
    for (var i = 0; i < ordered.length; i++) {
      final block = ordered[i];
      positions[block.id] = result.length;
      for (final atom in atoms) {
        if (atom.start >= block.start && atom.end <= block.end) {
          mappedAtoms.add(
            ComposerBlockAtom(
              result.length + atom.start - block.start,
              result.length + atom.end - block.start,
              label: atom.label,
            ),
          );
        }
      }
      result.write(block.source);
      if (i == ordered.length - 1) continue;
      final oldIndex = blocks.indexOf(block);
      final next = ordered[i + 1];
      final unchanged =
          oldIndex + 1 < blocks.length && blocks[oldIndex + 1].id == next.id;
      var separator = unchanged
          ? source.substring(block.end, next.start)
          : source.substring(blocks[i].end, blocks[i + 1].start);
      // Components and standalone to-dos have explicit boundaries. Consecutive
      // rows of either type stay distinct with just one line break.
      final minimumLineBreaks =
          (block.kind == ComposerBlockKind.component &&
                  next.kind == ComposerBlockKind.component) ||
              (block.kind == ComposerBlockKind.todo &&
                  next.kind == ComposerBlockKind.todo)
          ? 1
          : 2;
      if (!unchanged && '\n'.allMatches(separator).length < minimumLineBreaks) {
        separator = newline * minimumLineBreaks;
      }
      result.write(separator);
    }
    result.write(source.substring(blocks.last.end));
    final replacement = result.toString();
    final parsed = ComposerBlockIndex.parse(replacement, atoms: mappedAtoms);
    if (parsed.blocks.length != ordered.length) return null;
    for (var i = 0; i < ordered.length; i++) {
      if (parsed.blocks[i].source != ordered[i].source ||
          parsed.blocks[i].kind != ordered[i].kind ||
          parsed.blocks[i].movable != ordered[i].movable) {
        return null;
      }
    }
    final next = ComposerBlockIndex._(
      replacement,
      revision + 1,
      List.unmodifiable([
        for (var i = 0; i < ordered.length; i++)
          ComposerBodyBlock(
            id: ordered[i].id,
            start: parsed.blocks[i].start,
            end: parsed.blocks[i].end,
            kind: ordered[i].kind,
            source: ordered[i].source,
            movable: ordered[i].movable,
            componentLabel: ordered[i].componentLabel,
          ),
      ]),
      List.unmodifiable(mappedAtoms),
    );
    return ComposerBlockMove(this, next, moved.id, positions);
  }
}

int _trimLineEndings(String source, int start, int end) {
  while (end > start && (source[end - 1] == '\n' || source[end - 1] == '\r')) {
    end--;
  }
  return end;
}

class ComposerBlockMove {
  const ComposerBlockMove(
    this.before,
    this.after,
    this.blockId,
    this.positions,
  );

  final ComposerBlockIndex before;
  final ComposerBlockIndex after;
  final int blockId;
  final Map<int, int> positions;

  int mapOffset(int offset) {
    final block = before.atOffset(offset);
    if (block == null) return offset.clamp(0, after.source.length);
    return positions[block.id]! +
        (offset - block.start).clamp(0, block.source.length);
  }
}

class _Span {
  const _Span(
    this.start,
    this.end,
    this.kind, {
    this.movable = true,
    this.label,
  });
  final int start;
  final int end;
  final ComposerBlockKind kind;
  final bool movable;
  final String? label;
}

class _Line {
  const _Line(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
  bool get blank => text.trim().isEmpty;
}

class _BlockScanner {
  _BlockScanner(this.source, this.atoms) {
    var start = 0;
    while (start < source.length) {
      final newline = source.indexOf('\n', start);
      var end = newline < 0 ? source.length : newline;
      if (end > start && source[end - 1] == '\r') end--;
      lines.add(_Line(start, end, source.substring(start, end)));
      start = newline < 0 ? source.length : newline + 1;
    }
  }

  final String source;
  final List<ComposerBlockAtom> atoms;
  final List<_Line> lines = [];
  late final _todoStarts = {
    for (final todo in composerTodos(source))
      // Markdown lists retain their nested items and continuation paragraphs.
      // The slash command and typing shortcuts produce standalone to-do rows.
      if (source.substring(todo.start, todo.markerStart).trim().isEmpty)
        todo.start,
  };
  static final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
  static final _heading = RegExp(r'^ {0,3}#{1,6}(?:[ \t]+|$)');
  static final _setext = RegExp(r'^ {0,3}(?:=+|-+)[ \t]*$');
  static final _rule = RegExp(
    r'^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$',
  );
  static final _list = RegExp(r'^( {0,3})(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)');
  static final _quote = RegExp(r'^ {0,3}>');
  static final _indented = RegExp(r'^(?: {4}|\t)');
  static final _bbOpen = RegExp(
    r'^ {0,3}\[([a-zA-Z][\w-]*)(?:[= ][^\]]*)?\][ \t]*$',
  );
  static final _html = RegExp(r'^ {0,3}<(?:/?[A-Za-z]|!|\?)');
  static final _reference = RegExp(r'^ {0,3}\[[^\]]+\]:');

  List<_Span> scan() {
    final result = <_Span>[];
    var i = 0;
    while (i < lines.length) {
      if (lines[i].blank) {
        i++;
        continue;
      }
      final first = i;
      final text = lines[i].text;
      final atom = _atomAt(lines[i].start);
      if (atom != null) {
        while (i + 1 < lines.length && lines[i + 1].start < atom.end) {
          i++;
        }
        result.add(
          _Span(
            lines[first].start,
            lines[i].end,
            ComposerBlockKind.component,
            label: atom.label,
          ),
        );
        i++;
        continue;
      }
      final fence = _fence.firstMatch(text);
      if (fence != null) {
        final marker = fence[1]!;
        final close = RegExp(
          '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
        );
        i++;
        while (i < lines.length && !close.hasMatch(lines[i].text)) {
          i++;
        }
        final closed = i < lines.length;
        if (closed) i++;
        result.add(
          _Span(
            lines[first].start,
            lines[i - 1].end,
            ComposerBlockKind.code,
            movable: closed,
          ),
        );
        continue;
      }
      if (_todoStarts.contains(lines[i].start)) {
        result.add(_Span(lines[i].start, lines[i].end, ComposerBlockKind.todo));
        i++;
        continue;
      }
      final bb = _bbOpen.firstMatch(text);
      if (bb != null && !{'date', 'time', 'x'}.contains(bb[1]!.toLowerCase())) {
        final tag = bb[1]!;
        final pattern = RegExp(
          r'\[(/?)' + RegExp.escape(tag) + r'(?:[= ][^\]]*)?\]',
          caseSensitive: false,
        );
        var depth = 0;
        var closed = false;
        while (i < lines.length) {
          for (final m in pattern.allMatches(lines[i].text)) {
            depth += m[1]!.isEmpty ? 1 : -1;
            if (depth == 0) closed = true;
          }
          i++;
          if (closed) break;
        }
        result.add(
          _Span(
            lines[first].start,
            lines[i - 1].end,
            ComposerBlockKind.opaque,
            movable: false,
          ),
        );
        continue;
      }
      if (_html.hasMatch(text)) {
        // HTML block termination depends on its tag and dialect. Keep the
        // complete remainder opaque rather than expose unsafe interior gaps.
        result.add(
          _Span(
            lines[first].start,
            lines.last.end,
            ComposerBlockKind.opaque,
            movable: false,
          ),
        );
        break;
      }
      if (_heading.hasMatch(text) || _rule.hasMatch(text)) {
        result.add(
          _Span(
            lines[i].start,
            lines[i].end,
            _heading.hasMatch(text)
                ? ComposerBlockKind.heading
                : ComposerBlockKind.divider,
          ),
        );
        i++;
        continue;
      }
      if (_list.hasMatch(text) ||
          _quote.hasMatch(text) ||
          _indented.hasMatch(text)) {
        final kind = _list.hasMatch(text)
            ? ComposerBlockKind.list
            : _quote.hasMatch(text)
            ? ComposerBlockKind.quote
            : ComposerBlockKind.code;
        i++;
        while (i < lines.length) {
          if (lines[i].blank) {
            var next = i + 1;
            while (next < lines.length && lines[next].blank) {
              next++;
            }
            if (next == lines.length) break;
            final following = lines[next].text;
            final continues = kind == ComposerBlockKind.list
                ? (_list.hasMatch(following) ||
                      RegExp(r'^(?: {2,}|\t)').hasMatch(following))
                : kind == ComposerBlockKind.quote
                ? _quote.hasMatch(following)
                : _indented.hasMatch(following);
            if (!continues) break;
            i = next;
          } else if (_heading.hasMatch(lines[i].text) ||
              _rule.hasMatch(lines[i].text) ||
              _atomAt(lines[i].start) != null ||
              (_bbOpen.hasMatch(lines[i].text) &&
                  !_todoStarts.contains(lines[i].start)) ||
              _html.hasMatch(lines[i].text)) {
            break;
          }
          i++;
        }
        result.add(_Span(lines[first].start, lines[i - 1].end, kind));
        continue;
      }
      i++;
      var kind = ComposerBlockKind.paragraph;
      while (i < lines.length && !lines[i].blank) {
        if (_setext.hasMatch(lines[i].text)) {
          kind = ComposerBlockKind.heading;
          i++;
          break;
        }
        if (_interrupts(i)) break;
        i++;
      }
      result.add(
        _Span(
          lines[first].start,
          lines[i - 1].end,
          _reference.hasMatch(text) ? ComposerBlockKind.opaque : kind,
          movable: !_reference.hasMatch(text),
        ),
      );
    }
    return _protectInlineContainers(result);
  }

  // An unregistered BBCode container can start in the middle of a paragraph
  // and cross blank lines. Protect every intersecting block as one unit;
  // otherwise its closing tag could be dragged away from its opening tag.
  List<_Span> _protectInlineContainers(List<_Span> spans) {
    final tags = RegExp(r'\[(/?)([a-zA-Z][\w-]*)(?:[= ][^\]]*)?\]');
    final open = <(String, int)>[];
    final ranges = <(int, int)>[];
    for (final tag in tags.allMatches(source)) {
      final covering = spans
          .where((span) => span.start <= tag.start && span.end >= tag.end)
          .firstOrNull;
      if (covering?.kind == ComposerBlockKind.code ||
          covering?.kind == ComposerBlockKind.component) {
        continue;
      }
      final name = tag[2]!.toLowerCase();
      if (name == 'date' || name == 'time') continue;
      if (tag[1]!.isEmpty) {
        open.add((name, tag.start));
      } else {
        final start = open.lastIndexWhere((entry) => entry.$1 == name);
        if (start >= 0) {
          ranges.add((open[start].$2, tag.end));
          open.removeRange(start, open.length);
        }
      }
    }
    for (final range in ranges) {
      final first = spans.indexWhere((span) => span.end > range.$1);
      final last = spans.lastIndexWhere((span) => span.start < range.$2);
      if (first < 0 || last <= first) continue;
      final protected = _Span(
        spans[first].start,
        spans[last].end,
        ComposerBlockKind.opaque,
        movable: false,
      );
      spans.replaceRange(first, last + 1, [protected]);
    }
    return spans;
  }

  bool _interrupts(int i) =>
      _heading.hasMatch(lines[i].text) ||
      _fence.hasMatch(lines[i].text) ||
      _quote.hasMatch(lines[i].text) ||
      _list.hasMatch(lines[i].text) ||
      _todoStarts.contains(lines[i].start) ||
      _rule.hasMatch(lines[i].text) ||
      (_bbOpen.hasMatch(lines[i].text) &&
          !{
            'date',
            'time',
          }.contains(_bbOpen.firstMatch(lines[i].text)![1]!.toLowerCase())) ||
      _html.hasMatch(lines[i].text) ||
      _atomAt(lines[i].start) != null;

  ComposerBlockAtom? _atomAt(int start) {
    ComposerBlockAtom? accepted;
    for (final atom in atoms) {
      if (atom.start != start ||
          atom.end <= start ||
          atom.end > source.length) {
        continue;
      }
      // Component parsers sometimes include separators. They belong to the
      // structural index, not the movable payload.
      var end = atom.end;
      while (end > start &&
          (source[end - 1] == '\n' || source[end - 1] == '\r')) {
        end--;
      }
      if (end < source.length && source[end] != '\n' && source[end] != '\r') {
        continue;
      }
      if (accepted == null || end > accepted.end) {
        accepted = ComposerBlockAtom(start, end, label: atom.label);
      }
    }
    return accepted;
  }
}
