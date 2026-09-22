import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'reaction.dart';
import 'reaction_picker.dart';
import 'reactions_controller.dart';
import 'reactions_services.dart';

class ReactionsRow extends StatelessWidget {
  const ReactionsRow({
    super.key,
    required this.siteUrl,
    required this.post,
    this.controller,
    this.emoji,
  });

  final String siteUrl;
  final Post post;
  final ReactionsController? controller;
  final PluginEmojiHost? emoji;

  @override
  Widget build(BuildContext context) {
    final reactions = post.reactions;
    if (reactions == null) return const SizedBox.shrink();

    final controller =
        this.controller ??
        PluginUiScope.maybe(context, reactionsControllerService);
    final emoji =
        this.emoji ?? PluginUiScope.maybe(context, reactionsEmojiHostService);
    if (controller == null) return _buildPills(context, null, emoji);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildPills(context, controller, emoji),
    );
  }

  Widget _buildPills(
    BuildContext context,
    ReactionsController? controller,
    PluginEmojiHost? emoji, {
    bool summarize = true,
    Post? currentPost,
  }) {
    final post = currentPost ?? this.post;
    final reactions = post.reactions!;
    if (reactions.isEmpty &&
        (!post.canReact || controller == null || emoji == null)) {
      return const SizedBox.shrink();
    }
    final writeInFlight = controller?.writeInFlight(siteUrl, post.id) == true;
    if (summarize && MediaQuery.sizeOf(context).width < 600) {
      final count = reactions.entries.fold<int>(
        0,
        (total, entry) => total + entry.count,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          spacing: DSpacing.controlGap,
          children: [
            if (!reactions.isEmpty)
              Flexible(
                child: DButton(
                  key: ValueKey('post-reaction-summary-${post.id}'),
                  size: DButtonSize.large,
                  variant: DButtonVariant.outline,
                  semanticLabel: '$count reactions. Show all reactions',
                  tooltip: 'Show all reactions',
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DSpacing.controlGap,
                    children: [
                      for (final entry in reactions.entries.take(2))
                        SizedBox.square(
                          dimension: DToggle.iconDimensionFor(
                            DToggleSize.large,
                          ),
                          child: SiteEmojiImage(
                            siteUrl: siteUrl,
                            name: entry.id,
                            size: DToggle.iconDimensionFor(DToggleSize.large),
                            alt: ':${entry.id}:',
                          ),
                        ),
                    ],
                  ),
                  label: Text('$count'),
                  onPressed: () => _showSummary(context, controller, emoji),
                ),
              ),
            if (post.canReact && controller != null && emoji != null)
              PostReactionButton(
                key: ValueKey('post-reaction-button-${post.id}'),
                controller: controller,
                emoji: emoji,
                siteUrl: siteUrl,
                post: post,
              ),
          ],
        ),
      );
    }
    return ReactionPills(
      padding: const EdgeInsets.only(top: 10),
      children: [
        for (final entry in reactions.entries)
          ReactionPill(
            key: ValueKey('post-reaction-${post.id}-${entry.id}'),
            size: DToggleSize.large,
            siteUrl: siteUrl,
            reaction: entry.id,
            count: entry.count,
            selected: reactions.mine?.id == entry.id,
            onTapHint: _tapHint(post, entry.id),
            interactionOwner: controller ?? this,
            enabled: !writeInFlight,
            onToggle: post.canReact && controller != null
                ? () => controller.toggle(post, entry.id, siteUrl: siteUrl)
                : null,
            loadReactors: controller == null
                ? () async {}
                : () => controller.load(
                    siteUrl: siteUrl,
                    postId: post.id,
                    filter: entry.id,
                  ),
            reactorsBuilder: controller == null
                ? (_) => const SizedBox.shrink()
                : (_) => ReactorList(
                    siteUrl: siteUrl,
                    post: post,
                    filter: entry.id,
                    controller: controller,
                  ),
          ),
        if (post.canReact && controller != null && emoji != null)
          PostReactionButton(
            key: ValueKey('post-reaction-button-${post.id}'),
            controller: controller,
            emoji: emoji,
            siteUrl: siteUrl,
            post: post,
          ),
      ],
    );
  }

  Future<void> _showSummary(
    BuildContext context,
    ReactionsController? controller,
    PluginEmojiHost? emoji,
  ) {
    if (controller != null) {
      unawaited(controller.load(siteUrl: siteUrl, postId: post.id));
    }
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: 'Post reactions',
        children: [
          const DSheetHeader(children: [DSheetTitle(child: Text('Reactions'))]),
          DSheetBody(
            child: ListenableBuilder(
              listenable: controller ?? const AlwaysStoppedAnimation(null),
              builder: (context, _) {
                final current = controller?.post(siteUrl, post.id) ?? post;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPills(
                      context,
                      controller,
                      emoji,
                      summarize: false,
                      currentPost: current,
                    ),
                    if (controller != null) ...[
                      const SizedBox(height: DSpacing.md),
                      ReactorList(
                        siteUrl: siteUrl,
                        post: current,
                        controller: controller,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _tapHint(Post post, String reaction) {
    if (!post.canReact) return null;
    return switch (post.reactions?.mine?.id) {
      final id when id == reaction => 'remove your reaction',
      null => 'add this reaction',
      _ => 'change your reaction to $reaction',
    };
  }
}

class ReactorList extends StatelessWidget {
  const ReactorList({
    super.key,
    required this.siteUrl,
    required this.post,
    this.filter,
    this.controller,
  });

  final String siteUrl;
  final Post post;
  final String? filter;
  final ReactionsController? controller;

  @override
  Widget build(BuildContext context) {
    final reactions =
        controller ?? PluginUiScope.maybe(context, reactionsControllerService);
    if (reactions == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: reactions,
      builder: (context, _) => ReactionUsersList(
        siteUrl: siteUrl,
        source: reactions,
        query: (siteUrl: siteUrl, postId: post.id, filter: filter),
        select: () => (
          reactors: reactions.reactors(siteUrl, post.id, filter: filter),
          error: reactions.error(siteUrl, post.id, filter: filter),
        ),
        load: () =>
            reactions.load(siteUrl: siteUrl, postId: post.id, filter: filter),
      ),
    );
  }
}
