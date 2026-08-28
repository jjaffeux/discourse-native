import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_revision.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_html.dart';
import 'relative_time.dart';
import 'shell_sheet.dart';

typedef PostRevisionLoader =
    Future<PostRevision?> Function(int? revisionNumber);
typedef PostRevisionCategoryLabel = String Function(int? categoryId);

/// Opens core's post-history comparison without navigating away from a topic.
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

/// Core's compact pencil-and-count post metadata indicator.
class PostRevisionIndicator extends StatelessWidget {
  const PostRevisionIndicator({
    super.key,
    required this.post,
    required this.onPressed,
  });

  final Post post;
  final VoidCallback? onPressed;

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
      label:
          '${count == 1 ? '1 edit' : '$count edits'}. '
          '${onPressed == null ? 'Edit history unavailable' : 'View edit history'}',
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          key: ValueKey('post-revision-indicator-${post.id}'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(32, 28),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          icon: const DIcon(DIcons.pencil, size: 12),
          label: Text('$count'),
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

class _PostRevisionHistoryBody extends StatelessWidget {
  const _PostRevisionHistoryBody({
    required this.controller,
    required this.siteUrl,
    required this.categoryLabel,
  });

  final _PostRevisionHistoryController controller;
  final String siteUrl;
  final PostRevisionCategoryLabel? categoryLabel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
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

      return SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.loading) const LinearProgressIndicator(minHeight: 2),
            if (controller.error case final error?) ...[
              _InlineError(message: error),
              const SizedBox(height: 12),
            ],
            _RevisionAttribution(revision: revision),
            if (revision.titleChanges?.inline case final title?) ...[
              const SizedBox(height: 20),
              const _SectionLabel('Topic title'),
              const SizedBox(height: 6),
              CookedHtml(html: title, siteUrl: siteUrl),
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
            else if (revision.bodyChanges?.inline case final body?)
              CookedHtml(html: body, siteUrl: siteUrl)
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DButton(
                label: const Text('First'),
                onPressed:
                    enabled && first != null && revision.currentRevision > first
                    ? () => controller.load(first)
                    : null,
                size: DButtonSize.small,
              ),
              const SizedBox(width: 6),
              DButton(
                label: const Text('Previous'),
                onPressed: enabled && previous != null
                    ? () => controller.load(previous)
                    : null,
                size: DButtonSize.small,
              ),
              const Spacer(),
              DButton(
                label: const Text('Next'),
                onPressed: enabled && next != null
                    ? () => controller.load(next)
                    : null,
                size: DButtonSize.small,
              ),
              const SizedBox(width: 6),
              DButton(
                label: const Text('Latest'),
                onPressed:
                    enabled && last != null && revision.currentRevision < last
                    ? () => controller.load(last)
                    : null,
                size: DButtonSize.small,
              ),
            ],
          ),
        ],
      );
    },
  );
}
