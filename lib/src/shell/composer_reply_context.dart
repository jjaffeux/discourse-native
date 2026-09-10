import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'composer_controller.dart';
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
        if (postId == null) return _buildContext(context, null, topic);
        return ValueListenableBuilder<Post?>(
          valueListenable: store.ref<Post>(target.siteUrl, postId),
          builder: (context, post, _) => _buildContext(context, post, topic),
        );
      },
    );
  }

  Widget _buildContext(BuildContext context, Post? post, TopicDetail? topic) {
    final theme = Theme.of(context);
    final target = widget.target;
    final excerpt = _textFor(post);
    final username = switch (post?.username ?? target.replyToUsername) {
      final value? when value.trim().isNotEmpty => value,
      _ => null,
    };
    final avatarUrl =
        post?.avatarUrl ??
        topic?.participants
            .where((participant) => participant.username == username)
            .firstOrNull
            ?.avatarUrl;
    final replyLabel = username == null
        ? 'Replying to this topic'
        : 'Replying to @$username';
    final postNumber = target.replyToPostNumber;
    final destination =
        '$replyLabel${postNumber == null ? '' : ' · #$postNumber'}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final lineHeight = MediaQuery.textScalerOf(context).scale(14) * 1.5;
        final showTopic = constraints.maxHeight >= lineHeight * 2 + 22;
        final headerHeight = math.min(
          constraints.maxHeight - 4,
          math.max(48.0, lineHeight * (showTopic ? 2 : 1) + 22),
        );
        // Leave room for a readable excerpt when the composer is resized short.
        final canExpand =
            excerpt != null && constraints.maxHeight >= headerHeight + 28;
        final expanded = _expanded && canExpand;
        final toggle = canExpand
            ? () => setState(() => _expanded = !_expanded)
            : null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DTooltip(
                message: '$destination\n${target.topicTitle}',
                child: Semantics(
                  expanded: canExpand ? expanded : null,
                  child: SizedBox(
                    height: headerHeight,
                    child: DItem(
                      key: const ValueKey('composer-reply-context'),
                      variant: DItemVariant.muted,
                      size: DItemSize.sm,
                      onPressed: toggle,
                      semanticLabel: '$destination, ${target.topicTitle}',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      children: [
                        DItemContent(
                          children: [
                            Row(
                              spacing: DSpacing.md,
                              children: [
                                ExcludeSemantics(
                                  child: username != null
                                      ? DAvatar.frame(
                                          child: SizedBox.square(
                                            dimension: 28,
                                            child: AvatarImage(
                                              key: const ValueKey(
                                                'composer-reply-avatar',
                                              ),
                                              url: avatarUrl,
                                              size: 28,
                                              fallback: ColoredBox(
                                                color: theme
                                                    .colorScheme
                                                    .surfaceContainerHigh,
                                                child: Center(
                                                  child: Text(
                                                    username.characters.first
                                                        .toUpperCase(),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.square(
                                          dimension: 28,
                                          child: Center(
                                            child: DIcon(
                                              DIcons.reply,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                ),
                                Expanded(
                                  child: DItemContent(
                                    spacing: 2,
                                    children: [
                                      ExcludeSemantics(
                                        child: DItemTitle(
                                          child: Row(
                                            children: [
                                              if (username == null)
                                                Flexible(
                                                  child: Text(
                                                    replyLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                )
                                              else ...[
                                                const Flexible(
                                                  child: Text(
                                                    'Replying to ',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Flexible(
                                                  child: Text(
                                                    '@$username',
                                                    key: const ValueKey(
                                                      'composer-reply-username',
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                              if (postNumber != null)
                                                Text(' · #$postNumber'),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (showTopic)
                                        ExcludeSemantics(
                                          child: DItemDescription(
                                            maxLines: 1,
                                            child: TopicTitle(
                                              target.topicTitle,
                                              key: const ValueKey(
                                                'composer-title',
                                              ),
                                              siteUrl: target.siteUrl,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (canExpand)
                                  ExcludeSemantics(
                                    child: RotatedBox(
                                      quarterTurns: expanded ? 2 : 0,
                                      child: DIcon(
                                        DIcons.chevronDown,
                                        size: 10,
                                        color: DTokens.of(
                                          context,
                                        ).mutedForeground,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
