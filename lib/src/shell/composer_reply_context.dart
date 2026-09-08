import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

/// Shows the reply destination with an optional excerpt of the cached post.
class ComposerReplyContext extends StatefulWidget {
  const ComposerReplyContext({super.key, required this.target});

  final ComposerTarget target;

  @override
  State<ComposerReplyContext> createState() => _ComposerReplyContextState();
}

class _ComposerReplyContextState extends State<ComposerReplyContext> {
  bool _expanded = false;
  Post? _excerptPost;
  String? _excerpt;

  String? _textFor(Post? post) {
    if (identical(post, _excerptPost)) return _excerpt;
    _excerptPost = post;
    if (post == null || post.hidden || post.isDeleted) return _excerpt = null;
    final fragment = html.parseFragment(post.cooked);
    for (final node in fragment.querySelectorAll('script, style')) {
      node.remove();
    }
    // Keep adjacent paragraphs from running together in the plain excerpt.
    for (final node in fragment.querySelectorAll('p, div, li, br')) {
      node.nodes.add(dom.Text(' '));
    }
    final text = (fragment.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return _excerpt = text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final store = ShellScope.read(context).store;
    return ValueListenableBuilder<TopicDetail?>(
      valueListenable: store.ref<TopicDetail>(target.siteUrl, target.topicId),
      builder: (context, topic, _) {
        final postNumber = target.replyToPostNumber ?? 1;
        final postId = topic?.stream
            .where(
              (id) =>
                  store.read<Post>(target.siteUrl, id)?.postNumber ==
                  postNumber,
            )
            .firstOrNull;
        if (postId == null) return _buildContext(context, null);
        return ValueListenableBuilder<Post?>(
          valueListenable: store.ref<Post>(target.siteUrl, postId),
          builder: (context, post, _) => _buildContext(context, _textFor(post)),
        );
      },
    );
  }

  Widget _buildContext(BuildContext context, String? excerpt) {
    final theme = Theme.of(context);
    final target = widget.target;
    final canExpand = excerpt != null;
    final expanded = _expanded && canExpand;
    final title = Row(
      children: [
        if (target.replyToUsername case final username?) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('·'),
          ),
        ],
        Expanded(
          child: TopicTitle(
            target.topicTitle,
            key: const ValueKey('composer-title'),
            siteUrl: target.siteUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (canExpand) ...[
          const SizedBox(width: 8),
          RotatedBox(
            quarterTurns: expanded ? 2 : 0,
            child: const DIcon(DIcons.chevronDown, size: 10),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Tooltip(
            message: target.topicTitle,
            child: Semantics(
              button: canExpand,
              expanded: canExpand ? expanded : null,
              child: InkWell(
                key: const ValueKey('composer-reply-context'),
                onTap: canExpand
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: context.isTouch ? 44 : 28,
                  child: title,
                ),
              ),
            ),
          ),
          if (expanded)
            Flexible(
              child: Container(
                key: const ValueKey('composer-context-excerpt'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.shell.divider, width: 2),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    excerpt,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
