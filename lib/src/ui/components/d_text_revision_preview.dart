import 'dart:typed_data';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_scroll_area.dart';

enum DTextRevisionKind { unchanged, removed, restored }

@immutable
class DTextRevisionRun {
  const DTextRevisionRun(this.text, this.kind);
  final String text;
  final DTextRevisionKind kind;
}

/// Bounded word comparison. Large replacements retain the common edges and
/// become one changed region instead of allocating an unbounded LCS matrix.
List<DTextRevisionRun> textRevisionRuns(String current, String saved) {
  if (current == saved) {
    return [DTextRevisionRun(current, DTextRevisionKind.unchanged)];
  }
  final token = RegExp(r'\s|[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]', unicode: true);
  final a = token.allMatches(current).map((m) => m[0]!).toList();
  final b = token.allMatches(saved).map((m) => m[0]!).toList();
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - tail - 1] == b[b.length - tail - 1]) {
    tail++;
  }
  final result = <DTextRevisionRun>[];
  var pending = StringBuffer();
  DTextRevisionKind? pendingKind;
  void flush() {
    if (pendingKind != null) {
      result.add(DTextRevisionRun(pending.toString(), pendingKind!));
    }
    pending = StringBuffer();
  }

  void add(String value, DTextRevisionKind kind) {
    if (value.isEmpty) return;
    if (pendingKind != kind) {
      flush();
      pendingKind = kind;
    }
    pending.write(value);
  }

  add(a.take(head).join(), DTextRevisionKind.unchanged);
  final n = a.length - head - tail;
  final m = b.length - head - tail;
  if (n * m > 200000) {
    add(a.sublist(head, head + n).join(), DTextRevisionKind.removed);
    add(b.sublist(head, head + m).join(), DTextRevisionKind.restored);
  } else {
    final width = m + 1;
    final lengths = Uint32List((n + 1) * width);
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lengths[i * width + j] = a[head + i] == b[head + j]
            ? lengths[(i + 1) * width + j + 1] + 1
            : (lengths[(i + 1) * width + j] > lengths[i * width + j + 1]
                  ? lengths[(i + 1) * width + j]
                  : lengths[i * width + j + 1]);
      }
    }
    var i = 0;
    var j = 0;
    while (i < n || j < m) {
      if (i < n && j < m && a[head + i] == b[head + j]) {
        add(a[head + i++], DTextRevisionKind.unchanged);
        j++;
      } else if (j < m &&
          (i == n ||
              lengths[i * width + j + 1] > lengths[(i + 1) * width + j])) {
        add(b[head + j++], DTextRevisionKind.restored);
      } else {
        add(a[head + i++], DTextRevisionKind.removed);
      }
    }
  }
  add(
    tail == 0 ? '' : a.sublist(a.length - tail).join(),
    DTextRevisionKind.unchanged,
  );
  flush();
  return List.unmodifiable(result);
}

/// Retains the live editor while showing the words a discard would remove or
/// restore in its place. The preview cannot edit the source or take focus.
/// [restoration] is supplied only after the caller successfully persists the
/// restored revision; reduced motion shows the completed revision immediately.
class DTextRevisionPreview extends StatefulWidget {
  const DTextRevisionPreview({
    super.key,
    required this.current,
    required this.saved,
    required this.active,
    required this.child,
    this.restoration,
    this.style,
    this.padding = EdgeInsets.zero,
    this.singleLine = false,
    this.constrainToChild = true,
  });

  static const restorationDuration = Duration(milliseconds: 700);
  final String current;
  final String saved;
  final bool active;
  final Widget child;
  final Animation<double>? restoration;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  final bool singleLine;

  /// False for an editor inside an outer scrolling page: its preview may grow
  /// with wrapped source text instead of clipping to the old editor height.
  final bool constrainToChild;

  @override
  State<DTextRevisionPreview> createState() => _DTextRevisionPreviewState();
}

class _DTextRevisionPreviewState extends State<DTextRevisionPreview> {
  List<DTextRevisionRun> _runs = const [];
  String? _current;
  String? _saved;

  Widget _preview(BuildContext context, double? progress) {
    if (_current != widget.current || _saved != widget.saved) {
      _current = widget.current;
      _saved = widget.saved;
      _runs = textRevisionRuns(widget.current, widget.saved);
    }
    final tokens = DTokens.of(context);
    final base = widget.style ?? Theme.of(context).textTheme.bodyLarge!;
    final text = Text.rich(
      TextSpan(
        children: [for (final run in _runs) _span(run, base, tokens, progress)],
      ),
      style: base,
      maxLines: widget.singleLine ? 1 : null,
      overflow: widget.singleLine ? TextOverflow.ellipsis : TextOverflow.clip,
    );
    return Padding(
      padding: widget.padding,
      child: widget.singleLine || !widget.constrainToChild
          ? text
          : DScrollArea(child: text),
    );
  }

  TextSpan _span(
    DTextRevisionRun run,
    TextStyle base,
    DTokens tokens,
    double? progress,
  ) {
    var text = run.text;
    if (progress != null && run.kind != DTextRevisionKind.unchanged) {
      final characters = text.characters;
      final share = run.kind == DTextRevisionKind.removed
          ? 1 - progress
          : progress;
      text = characters.take((characters.length * share).round()).toString();
    }
    final color = switch (run.kind) {
      DTextRevisionKind.unchanged =>
        (base.color ?? tokens.foreground).withValues(
          alpha: progress == null ? .45 : 1,
        ),
      DTextRevisionKind.removed => tokens.destructive,
      DTextRevisionKind.restored => tokens.success,
    };
    return TextSpan(
      text: text,
      semanticsLabel: text.isEmpty
          ? ''
          : switch (run.kind) {
              DTextRevisionKind.unchanged => text,
              DTextRevisionKind.removed => context.l10n.draftPreviewRemoved(
                text,
              ),
              DTextRevisionKind.restored => context.l10n.draftPreviewRestored(
                text,
              ),
            },
      style: base.copyWith(
        color: color,
        backgroundColor: run.kind == DTextRevisionKind.unchanged
            ? null
            : color.withValues(alpha: .14),
        decoration: run.kind == DTextRevisionKind.removed
            ? TextDecoration.lineThrough
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget? preview;
    if (widget.active) {
      preview = widget.restoration != null
          ? AnimatedBuilder(
              animation: widget.restoration!,
              builder: (context, _) => _preview(
                context,
                MediaQuery.disableAnimationsOf(context)
                    ? 1
                    : widget.restoration!.value,
              ),
            )
          : _preview(context, null);
    }
    return Stack(
      children: [
        ExcludeFocus(
          excluding: widget.active,
          child: ExcludeSemantics(
            excluding: widget.active,
            child: IgnorePointer(
              ignoring: widget.active,
              child: Opacity(
                opacity: widget.active ? 0 : 1,
                child: widget.child,
              ),
            ),
          ),
        ),
        if (preview != null)
          if (widget.constrainToChild)
            Positioned.fill(child: preview)
          else
            preview,
      ],
    );
  }
}

/// Observes preview intent within a Native action's existing visible bounds.
/// Pointer hover and descendant keyboard focus are combined without replacing
/// the action's focus, click handling, semantics, or geometry.
class DRevisionPreviewTarget extends StatefulWidget {
  const DRevisionPreviewTarget({
    super.key,
    required this.onChanged,
    required this.child,
  });
  final ValueChanged<bool> onChanged;
  final Widget child;
  @override
  State<DRevisionPreviewTarget> createState() => _DRevisionPreviewTargetState();
}

class _DRevisionPreviewTargetState extends State<DRevisionPreviewTarget> {
  bool _hover = false;
  bool _focus = false;
  void _update({bool? hover, bool? focus}) {
    final before = _hover || _focus;
    _hover = hover ?? _hover;
    _focus = focus ?? _focus;
    final after = _hover || _focus;
    if (before != after) widget.onChanged(after);
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) => _update(focus: value),
    child: MouseRegion(
      onEnter: (_) => _update(hover: true),
      onExit: (_) => _update(hover: false),
      child: widget.child,
    ),
  );
}
