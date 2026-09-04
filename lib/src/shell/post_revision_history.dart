import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/post.dart';
import '../models/post_revision.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_html.dart';
import 'relative_time.dart';
import 'route_aware_selection_area.dart';
import 'shell_sheet.dart';

typedef PostRevisionLoader =
    Future<PostRevision?> Function(int? revisionNumber);
typedef PostRevisionCategoryLabel = String Function(int? categoryId);

Future<void> showPostRevisionHistory({
  required BuildContext context,
  required String siteUrl,
  required Post post,
  required PostRevisionLoader loadRevision,
  PostRevisionCategoryLabel? categoryLabel,
}) async {
  final controller = _PostRevisionHistoryController(loadRevision);
  unawaited(controller.load(null));
  try {
    await showShellSheet<void>(
      context: context,
      title: post.version > 100
          ? 'Edit history (last 100 revisions)'
          : 'Edit history',
      dialogOnDesktop: true,
      desktopDialogConstraints: const BoxConstraints(
        minWidth: 720,
        maxWidth: 960,
        maxHeight: 720,
      ),
      builder: (context) => _PostRevisionHistoryBody(
        controller: controller,
        siteUrl: siteUrl,
        categoryLabel: categoryLabel,
      ),
      footerBuilder: (context) =>
          _PostRevisionHistoryFooter(controller: controller),
    );
  } finally {
    controller.dispose();
  }
}

class PostRevisionIndicator extends StatelessWidget {
  const PostRevisionIndicator({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final count = post.editCount;
    if (count == 0) return const SizedBox.shrink();
    final updated = post.updatedAt;
    final age = updated == null ? null : relativeTime(updated);
    final tooltip = age == null
        ? (count == 1 ? '1 edit' : '$count edits')
        : 'Last edited ${age == 'now' ? 'now' : '$age ago'}';

    return Semantics(
      label: count == 1 ? '1 edit' : '$count edits',
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          key: ValueKey('post-revision-indicator-${post.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DIcon(DIcons.pencil, size: 12),
              const SizedBox(width: 4),
              Text('$count'),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostRevisionHistoryController extends ChangeNotifier {
  _PostRevisionHistoryController(this._loader);

  final PostRevisionLoader _loader;
  PostRevision? revision;
  bool loading = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;

  Future<void> load(int? revisionNumber) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final fetched = await _loader(revisionNumber);
      if (_disposed || generation != _generation) return;
      if (fetched == null) {
        error = 'Your connection changed. Reopen edit history and try again.';
      } else {
        revision = fetched;
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = "Couldn't load edit history.";
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}

enum _PostRevisionViewMode { inline, sideBySide, markdown }

class _PostRevisionHistoryBody extends StatefulWidget {
  const _PostRevisionHistoryBody({
    required this.controller,
    required this.siteUrl,
    required this.categoryLabel,
  });

  final _PostRevisionHistoryController controller;
  final String siteUrl;
  final PostRevisionCategoryLabel? categoryLabel;

  @override
  State<_PostRevisionHistoryBody> createState() =>
      _PostRevisionHistoryBodyState();
}

class _PostRevisionHistoryBodyState extends State<_PostRevisionHistoryBody> {
  static const double _compactBreakpoint = 600;

  _PostRevisionViewMode _mode = _PostRevisionViewMode.sideBySide;

  _PostRevisionHistoryController get controller => widget.controller;
  String get siteUrl => widget.siteUrl;
  PostRevisionCategoryLabel? get categoryLabel => widget.categoryLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < _compactBreakpoint;
      final mode = compact ? _PostRevisionViewMode.inline : _mode;
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final revision = controller.revision;
          if (revision == null && controller.loading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          if (revision == null) {
            return _RevisionError(
              message: controller.error ?? "Couldn't load edit history.",
              onRetry: controller.loading ? null : () => controller.load(null),
            );
          }

          return RouteAwareSelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.loading)
                  const LinearProgressIndicator(minHeight: 2),
                if (controller.error case final error?) ...[
                  _InlineError(message: error),
                  const SizedBox(height: 12),
                ],
                _RevisionAttribution(revision: revision),
                if (!compact) ...[
                  const SizedBox(height: 16),
                  _RevisionModePicker(
                    mode: mode,
                    onChanged: (value) => setState(() => _mode = value),
                  ),
                ],
                if (revision.titleChanges case final titleChanges?) ...[
                  const SizedBox(height: 20),
                  const _SectionLabel('Topic title'),
                  const SizedBox(height: 6),
                  _RevisionDiffView(
                    key: const ValueKey('post-revision-title-diff'),
                    diff: titleChanges,
                    mode: mode == _PostRevisionViewMode.markdown
                        ? _PostRevisionViewMode.sideBySide
                        : mode,
                    siteUrl: siteUrl,
                    previousHidden: revision.previousHidden,
                    currentHidden: revision.currentHidden,
                  ),
                ],
                if (revision.userChanges case final change?) ...[
                  const SizedBox(height: 16),
                  _ValueChangeRow(
                    label: 'Author',
                    previous: change.previous?.displayName ?? 'Unknown',
                    current: change.current?.displayName ?? 'Unknown',
                  ),
                ],
                if (revision.replyToPostNumberChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Reply to',
                    previous: _replyLabel(change.previous),
                    current: _replyLabel(change.current),
                  ),
                ],
                if (revision.categoryIdChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Category',
                    previous: _categoryName(change.previous),
                    current: _categoryName(change.current),
                  ),
                ],
                if (revision.tagsChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Tags',
                    previous: _listLabel(change.previous),
                    current: _listLabel(change.current),
                  ),
                ],
                if (revision.wikiChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Wiki',
                    previous: _yesNo(change.previous),
                    current: _yesNo(change.current),
                  ),
                ],
                if (revision.postTypeChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Post type',
                    previous: _postType(change.previous),
                    current: _postType(change.current),
                  ),
                ],
                if (revision.localeChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Language',
                    previous: change.previous ?? 'None',
                    current: change.current ?? 'None',
                  ),
                ],
                if (revision.archetypeChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Topic type',
                    previous: change.previous ?? 'None',
                    current: change.current ?? 'None',
                  ),
                ],
                if (revision.featuredLinkChanges case final change?) ...[
                  const SizedBox(height: 12),
                  _ValueChangeRow(
                    label: 'Featured link',
                    previous: change.previous ?? 'None',
                    current: change.current ?? 'None',
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionLabel('Post'),
                const SizedBox(height: 8),
                if (revision.diffError)
                  const _InlineError(
                    message: 'This revision is too complex to compare.',
                  )
                else if (revision.diffHidden)
                  const _HiddenDiff()
                else if (revision.bodyChanges case final bodyChanges?)
                  _RevisionDiffView(
                    key: const ValueKey('post-revision-body-diff'),
                    diff: bodyChanges,
                    mode: mode,
                    siteUrl: siteUrl,
                    previousHidden: revision.previousHidden,
                    currentHidden: revision.currentHidden,
                  )
                else
                  Text(
                    'The post body did not change in this revision.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );

  String _categoryName(int? id) =>
      categoryLabel?.call(id) ??
      (id == null ? 'Uncategorized' : 'Category $id');

  static String _replyLabel(PostRevisionReplyTarget? target) {
    if (target == null) return 'None';
    final username = target.username;
    return username == null
        ? '#${target.postNumber}'
        : '#${target.postNumber} @$username';
  }

  static String _listLabel(List<String>? values) =>
      values == null || values.isEmpty ? 'None' : values.join(', ');

  static String _yesNo(bool? value) => switch (value) {
    true => 'Yes',
    false => 'No',
    null => 'Unknown',
  };

  static String _postType(int? value) => switch (value) {
    Post.regularPostType => 'Regular',
    Post.moderatorPostType => 'Moderator',
    Post.whisperPostType => 'Whisper',
    final value? => 'Type $value',
    null => 'Unknown',
  };
}

class _RevisionModePicker extends StatelessWidget {
  const _RevisionModePicker({required this.mode, required this.onChanged});

  final _PostRevisionViewMode mode;
  final ValueChanged<_PostRevisionViewMode> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: SegmentedButton<_PostRevisionViewMode>(
      key: const ValueKey('post-revision-mode-picker'),
      showSelectedIcon: false,
      selected: {mode},
      onSelectionChanged: (selected) => onChanged(selected.single),
      segments: const [
        ButtonSegment(
          value: _PostRevisionViewMode.inline,
          label: Text('Inline'),
        ),
        ButtonSegment(
          value: _PostRevisionViewMode.sideBySide,
          label: Text('Side by side'),
        ),
        ButtonSegment(
          value: _PostRevisionViewMode.markdown,
          label: Text('Markdown'),
        ),
      ],
    ),
  );
}

class _RevisionDiffView extends StatefulWidget {
  const _RevisionDiffView({
    super.key,
    required this.diff,
    required this.mode,
    required this.siteUrl,
    required this.previousHidden,
    required this.currentHidden,
  });

  final PostRevisionDiff diff;
  final _PostRevisionViewMode mode;
  final String siteUrl;
  final bool previousHidden;
  final bool currentHidden;

  @override
  State<_RevisionDiffView> createState() => _RevisionDiffViewState();
}

/// The diff HTML is parsed once per revision, not per build: a view-mode
/// toggle, a hidden-revision toggle or a theme change must not re-parse a
/// large edit.
class _RevisionDiffViewState extends State<_RevisionDiffView> {
  String? _fragmentsSource;
  ({String previous, String current})? _fragments;
  String? _rowsSource;
  List<({String previous, String current})> _rows = const [];

  @override
  Widget build(BuildContext context) => switch (widget.mode) {
    _PostRevisionViewMode.inline => _inline(),
    _PostRevisionViewMode.sideBySide => _sideBySide(),
    _PostRevisionViewMode.markdown => _markdown(),
  };

  Widget _inline() {
    final html = widget.diff.inline ?? widget.diff.sideBySide;
    if (html == null) return const SizedBox.shrink();
    return Opacity(
      opacity: widget.previousHidden || widget.currentHidden ? 0.5 : 1,
      child: CookedHtml(
        key: const ValueKey('post-revision-diff-inline'),
        html: html,
        siteUrl: widget.siteUrl,
        revisionDiff: true,
      ),
    );
  }

  Widget _sideBySide() {
    final html = widget.diff.sideBySide;
    if (!identical(html, _fragmentsSource)) {
      _fragmentsSource = html;
      _fragments = _sideBySideFragments(html);
    }
    final fragments = _fragments;
    if (fragments == null) return _inline();
    return _RevisionColumns(
      key: const ValueKey('post-revision-diff-side-by-side'),
      previous: fragments.previous,
      current: fragments.current,
      siteUrl: widget.siteUrl,
      previousHidden: widget.previousHidden,
      currentHidden: widget.currentHidden,
    );
  }

  Widget _markdown() {
    final html = widget.diff.sideBySideMarkdown;
    if (!identical(html, _rowsSource)) {
      _rowsSource = html;
      _rows = _markdownDiffRows(html);
    }
    final rows = _rows;
    if (rows.isEmpty) return _sideBySide();
    return _RevisionMarkdownTable(
      key: const ValueKey('post-revision-diff-markdown'),
      rows: rows,
      siteUrl: widget.siteUrl,
      previousHidden: widget.previousHidden,
      currentHidden: widget.currentHidden,
    );
  }
}

class _RevisionColumns extends StatelessWidget {
  const _RevisionColumns({
    super.key,
    required this.previous,
    required this.current,
    required this.siteUrl,
    required this.previousHidden,
    required this.currentHidden,
  });

  final String previous;
  final String current;
  final String siteUrl;
  final bool previousHidden;
  final bool currentHidden;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _RevisionColumnHeadings(),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _RevisionPane(
              html: previous,
              siteUrl: siteUrl,
              hidden: previousHidden,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _RevisionPane(
              html: current,
              siteUrl: siteUrl,
              hidden: currentHidden,
            ),
          ),
        ],
      ),
    ],
  );
}

class _RevisionColumnHeadings extends StatelessWidget {
  const _RevisionColumnHeadings();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        Expanded(child: Text('Previous', style: style)),
        const SizedBox(width: 16),
        Expanded(child: Text('Current', style: style)),
      ],
    );
  }
}

class _RevisionPane extends StatelessWidget {
  const _RevisionPane({
    required this.html,
    required this.siteUrl,
    required this.hidden,
  });

  final String html;
  final String siteUrl;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: hidden ? 0.5 : 1,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).shell.divider),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CookedHtml(html: html, siteUrl: siteUrl, revisionDiff: true),
    ),
  );
}

class _RevisionMarkdownTable extends StatelessWidget {
  const _RevisionMarkdownTable({
    super.key,
    required this.rows,
    required this.siteUrl,
    required this.previousHidden,
    required this.currentHidden,
  });

  final List<({String previous, String current})> rows;
  final String siteUrl;
  final bool previousHidden;
  final bool currentHidden;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _RevisionColumnHeadings(),
      const SizedBox(height: 6),
      for (final (index, row) in rows.indexed)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RevisionMarkdownCell(
                html: row.previous,
                siteUrl: siteUrl,
                hidden: previousHidden,
                top: index == 0,
              ),
            ),
            Expanded(
              child: _RevisionMarkdownCell(
                html: row.current,
                siteUrl: siteUrl,
                hidden: currentHidden,
                top: index == 0,
              ),
            ),
          ],
        ),
    ],
  );
}

class _RevisionMarkdownCell extends StatelessWidget {
  const _RevisionMarkdownCell({
    required this.html,
    required this.siteUrl,
    required this.hidden,
    required this.top,
  });

  final String html;
  final String siteUrl;
  final bool hidden;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: hidden ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.code.blockBackground,
          border: Border(
            top: top ? BorderSide(color: theme.shell.divider) : BorderSide.none,
            right: BorderSide(color: theme.shell.divider),
            bottom: BorderSide(color: theme.shell.divider),
            left: BorderSide(color: theme.shell.divider),
          ),
        ),
        child: CookedHtml(
          html: '<div style="white-space: pre-wrap">$html</div>',
          siteUrl: siteUrl,
          revisionDiff: true,
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

({String previous, String current})? _sideBySideFragments(String? html) {
  if (html == null || html.isEmpty) return null;
  final elements = html_parser
      .parseFragment(html)
      .nodes
      .whereType<dom.Element>()
      .where((element) => element.classes.contains('revision-content'))
      .toList(growable: false);
  if (elements.length < 2) return null;
  return (previous: elements[0].innerHtml, current: elements[1].innerHtml);
}

List<({String previous, String current})> _markdownDiffRows(String? html) {
  if (html == null || html.isEmpty) return const [];
  final rows = <({String previous, String current})>[];
  for (final row in html_parser.parseFragment(html).querySelectorAll('tr')) {
    // `Element.children` rebuilds itself out of `nodes` on every read.
    final cells = row.nodes
        .whereType<dom.Element>()
        .where((element) => element.localName == 'td')
        .toList(growable: false);
    if (cells.length < 2) continue;
    rows.add((previous: cells[0].innerHtml, current: cells[1].innerHtml));
  }
  return rows;
}

class _RevisionAttribution extends StatelessWidget {
  const _RevisionAttribution({required this.revision});

  final PostRevision revision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = revision.createdAt;
    final age = date == null ? null : relativeTime(date);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DIcon(
          DIcons.pencil,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                revision.editorDisplayName.isEmpty
                    ? 'Unknown editor'
                    : revision.editorDisplayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (age != null)
                Text(
                  age == 'now' ? 'now' : '$age ago',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (revision.editReason case final reason?)
                Text(
                  reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValueChangeRow extends StatelessWidget {
  const _ValueChangeRow({
    required this.label,
    required this.previous,
    required this.current,
  });

  final String label;
  final String previous;
  final String current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        const SizedBox(height: 5),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              previous,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const Text('→'),
            Text(
              current,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.discourse.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _HiddenDiff extends StatelessWidget {
  const _HiddenDiff();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DIcon(
        DIcons.farEyeSlash,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      const Expanded(
        child: Text('The differences in this revision are hidden.'),
      ),
    ],
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}

class _RevisionError extends StatelessWidget {
  const _RevisionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _InlineError(message: message),
      const SizedBox(height: 12),
      DButton(
        label: const Text('Retry'),
        onPressed: onRetry,
        size: DButtonSize.small,
      ),
    ],
  );
}

class _PostRevisionHistoryFooter extends StatelessWidget {
  const _PostRevisionHistoryFooter({required this.controller});

  final _PostRevisionHistoryController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final revision = controller.revision;
      if (revision == null) return const SizedBox.shrink();
      final enabled = !controller.loading;
      final first = revision.firstRevision;
      final previous = revision.previousRevision;
      final next = revision.nextRevision;
      final last = revision.lastRevision;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            revision.comparisonLabel,
            key: const ValueKey('post-revision-comparison'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final firstAction =
                  enabled && first != null && revision.currentRevision > first
                  ? () => controller.load(first)
                  : null;
              final previousAction = enabled && previous != null
                  ? () => controller.load(previous)
                  : null;
              final nextAction = enabled && next != null
                  ? () => controller.load(next)
                  : null;
              final latestAction =
                  enabled && last != null && revision.currentRevision < last
                  ? () => controller.load(last)
                  : null;
              if (constraints.maxWidth < 420) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    DButton.iconOnly(
                      icon: const Icon(Icons.first_page, size: 18),
                      tooltip: 'First',
                      onPressed: firstAction,
                      size: DButtonSize.small,
                    ),
                    DButton.iconOnly(
                      icon: const Icon(Icons.navigate_before, size: 18),
                      tooltip: 'Previous',
                      onPressed: previousAction,
                      size: DButtonSize.small,
                    ),
                    DButton.iconOnly(
                      icon: const Icon(Icons.navigate_next, size: 18),
                      tooltip: 'Next',
                      onPressed: nextAction,
                      size: DButtonSize.small,
                    ),
                    DButton.iconOnly(
                      icon: const Icon(Icons.last_page, size: 18),
                      tooltip: 'Latest',
                      onPressed: latestAction,
                      size: DButtonSize.small,
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DButton(
                    label: const Text('First'),
                    onPressed: firstAction,
                    size: DButtonSize.small,
                  ),
                  const SizedBox(width: 6),
                  DButton(
                    label: const Text('Previous'),
                    onPressed: previousAction,
                    size: DButtonSize.small,
                  ),
                  const Spacer(),
                  DButton(
                    label: const Text('Next'),
                    onPressed: nextAction,
                    size: DButtonSize.small,
                  ),
                  const SizedBox(width: 6),
                  DButton(
                    label: const Text('Latest'),
                    onPressed: latestAction,
                    size: DButtonSize.small,
                  ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}
