import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_scope.dart';
import 'reaction.dart';
import 'reaction_picker.dart';
import 'reaction_pill.dart';
import 'reactions_controller.dart';
import 'reactions_services.dart';

export 'reaction_pill.dart' show ReactionPill, ReactionPills;

/// What people gave a post, under the post itself.
///
/// Topic owns the post-reaction records and API callbacks. The row, pills,
/// hover panel, touch sheet and reactor rows are shared with chat through
/// [ReactionPills], [ReactionPill] and [ReactionUsersList].
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
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

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
    PluginEmojiHost? emoji,
  ) {
    final reactions = post.reactions!;
    final writeInFlight = controller?.writeInFlight(siteUrl, post.id) == true;
    return ReactionPills(
      children: [
        for (final entry in reactions.entries)
          ReactionPill(
            key: ValueKey('post-reaction-${post.id}-${entry.id}'),
            siteUrl: siteUrl,
            reaction: entry.id,
            count: entry.count,
            selected: reactions.mine?.id == entry.id,
            onTapHint: _tapHint(entry.id),
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
          ReactionPickerButton(
            key: ValueKey('post-reaction-picker-${post.id}'),
            enabled: !writeInFlight,
            onOpenPicker: (pickerContext) => showPostReactionPicker(
              pickerContext,
              controller,
              emoji,
              siteUrl,
              post,
            ),
          ),
      ],
    );
  }

  String _tapHint(String reaction) {
    if (!post.canReact) return 'show who reacted';
    return switch (post.reactions?.mine?.id) {
      final id when id == reaction => 'remove your reaction',
      null => 'add this reaction',
      _ => 'change your reaction to $reaction',
    };
  }
}

/// Topic's adapter into the shared reactor-list presentation.
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
