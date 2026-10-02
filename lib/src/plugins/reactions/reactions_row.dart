import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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
    // Not the controller: every post's reactor load and reaction write
    // notifies it, and a topic holds one row per post.
    return ListenableBuilder(
      listenable: controller.postChanges(siteUrl, post.id),
      builder: (context, _) => _buildPills(context, controller, emoji),
    );
  }

  Widget _buildPills(
    BuildContext context,
    ReactionsController? controller,
    PluginEmojiHost? emoji,
  ) {
    final post = this.post;
    final reactions = post.reactions!;
    if (reactions.isEmpty &&
        (!post.canReact || controller == null || emoji == null)) {
      return const SizedBox.shrink();
    }
    final session = controller?.beginPicker(siteUrl, post);
    final writeInFlight = controller?.writeInFlight(siteUrl, post.id) == true;
    if (MediaQuery.sizeOf(context).width < 600) {
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
                  size: DButtonSize.post,
                  variant: DButtonVariant.outline,
                  semanticLabel: context.l10n.showAllReactions(
                    (countLabel(count, CountNoun.reaction)).toString(),
                  ),
                  tooltip: context.l10n.showAllReactionsReactionsrow,
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DSpacing.controlGap,
                    children: [
                      for (final entry in reactions.entries.take(2))
                        SizedBox.square(
                          dimension: 16,
                          child: SiteEmojiImage(
                            siteUrl: siteUrl,
                            name: entry.id,
                            size: 16,
                            alt: ':${entry.id}:',
                          ),
                        ),
                    ],
                  ),
                  label: Text('$count'),
                  onPressed: () =>
                      _showSummary(context, controller, emoji, session),
                ),
              ),
            if (post.canReact && controller != null && emoji != null)
              PostReactionButton(
                key: ValueKey('post-reaction-button-${post.id}'),
                controller: controller,
                emoji: emoji,
                siteUrl: siteUrl,
                post: post,
                session: session,
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
            size: DToggleSize.post,
            siteUrl: siteUrl,
            reaction: entry.id,
            count: entry.count,
            selected: reactions.mine?.id == entry.id,
            onTapHint: _tapHint(post, entry.id),
            interactionOwner: controller ?? this,
            enabled: !writeInFlight,
            onToggle: post.canReact && controller != null
                ? () => controller.toggleFromPicker(session!, post, entry.id)
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
            session: session,
          ),
      ],
    );
  }

  Future<void> _showSummary(
    BuildContext context,
    ReactionsController? controller,
    PluginEmojiHost? emoji,
    ReactionPickerSession? session,
  ) {
    if (session != null && !controller!.isPickerCurrent(session)) {
      return Future.value();
    }
    final touch = context.isTouch;
    String? filter;
    var closing = false;
    if (controller != null) {
      unawaited(controller.load(siteUrl: siteUrl, postId: post.id));
    }
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: touch,
      fillAvailableHeight: touch,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: appL10n.postReactions,
        topBottomMaxHeightFactor: touch ? 1 : null,
        scrollWholeSheet: touch ? false : null,
        showCloseButton: false,
        children: [
          ComposerSheetHeader(title: appL10n.reactions),
          DSheetBody(
            child: StatefulBuilder(
              builder: (context, setSheetState) => ListenableBuilder(
                listenable: controller ?? const AlwaysStoppedAnimation(null),
                builder: (context, _) {
                  final current = controller == null
                      ? post
                      : controller.pickerPost(session!, post);
                  final reactions = current?.reactions;
                  if (current == null || reactions == null) {
                    // Account retirement, a 404 toggle or a refresh without
                    // the plugin removes this sheet's source. The pop waits
                    // for the frame because the navigator cannot change
                    // routes mid-build.
                    if (!closing) {
                      closing = true;
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => sheet.close(),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReactionPills(
                        padding: const EdgeInsets.only(top: 10),
                        children: [
                          for (final entry in reactions.entries)
                            DToggle(
                              key: ValueKey('post-reaction-filter-${entry.id}'),
                              size: DToggleSize.post,
                              variant: DToggleVariant.outline,
                              pressed: filter == entry.id,
                              semanticLabel: appL10n.namedReactions(
                                entry.count,
                                entry.id,
                              ),
                              onPressedChanged: (_) {
                                if (session != null &&
                                    !controller!.isPickerCurrent(session)) {
                                  return;
                                }
                                setSheetState(() {
                                  filter = filter == entry.id ? null : entry.id;
                                });
                              },
                              icon: Builder(
                                builder: (context) => SiteEmojiImage(
                                  siteUrl: siteUrl,
                                  name: entry.id,
                                  size: 16,
                                  alt: ':${entry.id}:',
                                ),
                              ),
                              child: Text('${entry.count}'),
                            ),
                          if (current.canReact &&
                              controller != null &&
                              emoji != null)
                            PostReactionButton(
                              controller: controller,
                              emoji: emoji,
                              siteUrl: siteUrl,
                              post: current,
                              session: session,
                            ),
                        ],
                      ),
                      if (controller != null) ...[
                        const SizedBox(height: DSpacing.md),
                        ReactorList(
                          siteUrl: siteUrl,
                          post: current,
                          filter: filter,
                          controller: controller,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _tapHint(Post post, String reaction) {
    if (!post.canReact) return null;
    return switch (post.reactions?.mine?.id) {
      final id when id == reaction => appL10n.removeYourReaction,
      null => appL10n.addThisReaction,
      _ => appL10n.changeYourReactionTo((reaction).toString()),
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
    // The list follows its source itself and redraws only when its own
    // snapshot changes.
    return ReactionUsersList(
      siteUrl: siteUrl,
      source: reactions.postChanges(siteUrl, post.id),
      query: (siteUrl: siteUrl, postId: post.id, filter: filter),
      select: () => (
        reactors: reactions.reactors(siteUrl, post.id, filter: filter),
        error: reactions.error(siteUrl, post.id, filter: filter),
      ),
      load: () =>
          reactions.load(siteUrl: siteUrl, postId: post.id, filter: filter),
    );
  }
}
