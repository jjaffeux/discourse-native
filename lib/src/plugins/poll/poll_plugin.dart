import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../models/content_route.dart';
import '../../models/post.dart';
import '../../models/sidebar.dart';
import '../../shell/composer_controller.dart';
import '../../shell/external_link.dart';
import '../../shell/shell_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../site_plugin.dart';
import 'poll.dart';
import 'poll_card.dart';
import 'poll_composer_editor.dart';
import 'poll_composer_parser.dart';
import 'poll_composer_sheet.dart';

/// Discourse's bundled Poll plugin as an optional, payload-gated feature.
class PollPlugin implements SitePlugin<Polls> {
  const PollPlugin();

  @override
  String get name => 'poll';

  @override
  Type get record => Polls;

  @override
  Polls? readPost(Map<String, dynamic> json, String siteUrl) =>
      Polls.fromJson(json, siteUrl);

  @override
  Widget? postBodyElement(String siteUrl, Post post, dom.Element element) {
    if (!element.classes.contains('poll')) return null;
    final name = element.attributes['data-poll-name'];
    if (name == null || name.isEmpty) {
      return PollFallbackCard.fromCooked(element, siteUrl: siteUrl);
    }
    final poll = post.polls?[name];
    return poll == null
        ? PollFallbackCard.fromCooked(element, siteUrl: siteUrl)
        : _PostPollCard(siteUrl: siteUrl, post: post, poll: poll);
  }

  @override
  Widget? postFooter(String siteUrl, Post post) => null;

  @override
  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post,
  ) => PostMenuContribution.none;

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) {
    final controller = ShellScope.maybeRead(context);
    if (controller == null ||
        !controller.canCreatePollFor(composer.target.siteUrl) ||
        composer.loadingBody) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.list,
        label: 'Add poll',
        onInvoke: () => unawaited(openPollComposer(context, composer)),
      ),
    ];
  }

  /// Poll definitions are serialized on edit, and absence means removal.
  @override
  Polls? mergeAfterPostEdit(Polls? held, Polls? incoming) => incoming;

  @override
  List<SidebarSection> sidebarSections(BuildContext context) => const [];

  @override
  Listenable? sidebarListenable(BuildContext context) => null;

  @override
  Widget? content(BuildContext context, ContentRoute route) => null;

  @override
  List<String> topicChannels(int topicId) => ['/polls/$topicId'];

  @override
  List<int> stalePosts(String channel, Object? data) {
    if (data is! Map<Object?, Object?>) return const [];
    return switch (data['post_id']) {
      final num id => [id.toInt()],
      _ => const [],
    };
  }
}

/// Opens Poll's composer projection for a new block or one existing occurrence.
Future<void> openPollComposer(
  BuildContext context,
  ComposerController composer, {
  PollComposerBlock? block,
}) async {
  final controller = ShellScope.maybeRead(context);
  if (controller == null ||
      !identical(controller.visibleComposer, composer) ||
      (block == null &&
          !controller.canCreatePollFor(composer.target.siteUrl))) {
    return;
  }

  final expectedDocument = composer.text.text;
  final expectedSelection = composer.text.selection;
  final config = controller.siteConfigFor(composer.target.siteUrl);
  final freshUser = controller.freshCurrentUserFor(composer.target.siteUrl);
  final draft = block == null
      ? PollComposerDraft.newPoll(
          name: nextPollName(expectedDocument),
          defaultPublic: config.pollDefaultPublic,
        )
      : PollComposerDraft.fromBlock(
          block,
          maximumOptions: config.pollMaximumOptions,
        );

  final originalPollNames = {
    for (final original in parsePollComposerBlocks(composer.originalRaw ?? ''))
      original.name,
  };
  final published =
      block != null &&
      composer.target.isEdit &&
      originalPollNames.contains(block.name);
  final editingPostId = composer.target.editingPostId;
  final voters = block == null || editingPostId == null
      ? null
      : controller.store
            .read<Post>(composer.target.siteUrl, editingPostId)
            ?.polls?[block.name]
            ?.voters;

  bool stillCurrent() =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), controller) &&
      identical(controller.visibleComposer, composer) &&
      composer.text.text == expectedDocument;

  final action = await showPollComposerSheet(
    context: context,
    draft: draft,
    maximumOptions: config.pollMaximumOptions,
    isStaff: freshUser?.staff == true,
    isPublished: published,
    voterCount: voters,
    isCurrent: stillCurrent,
  );
  if (action == null || !context.mounted) return;
  if (!stillCurrent()) {
    _pollComposerMessage(
      context,
      'The composer changed while this poll was open. Nothing was changed.',
    );
    return;
  }

  if (action.type == PollComposerSheetActionType.editRaw && block != null) {
    composer.text.expandPollAsRaw(block);
    composer.focus.requestFocus();
    return;
  }

  final PollComposerMutation mutation;
  switch (action.type) {
    case PollComposerSheetActionType.apply:
      final replacement = action.draft!.serialize();
      if (block != null && replacement == block.source) {
        composer.focus.requestFocus();
        return;
      }
      mutation = block == null
          ? insertVerifiedPoll(
              current: composer.text.value,
              expectedDocument: expectedDocument,
              expectedSelection: expectedSelection,
              markup: replacement,
            )
          : replaceVerifiedPoll(
              current: composer.text.value,
              expectedDocument: expectedDocument,
              expectedBlock: block,
              replacement: replacement,
            );
    case PollComposerSheetActionType.remove:
      if (block == null) return;
      mutation = removeVerifiedPoll(
        current: composer.text.value,
        expectedDocument: expectedDocument,
        expectedBlock: block,
      );
    case PollComposerSheetActionType.editRaw:
      return;
  }

  if (!mutation.applied) {
    _pollComposerMessage(context, mutation.message!);
    return;
  }
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

/// Removes one poll occurrence from the composer through the same verified
/// source mutation used by the editor sheet.
Future<void> removePollComposer(
  BuildContext context,
  ComposerController composer,
  PollComposerBlock block,
) async {
  final controller = ShellScope.maybeRead(context);
  if (controller == null || !identical(controller.visibleComposer, composer)) {
    return;
  }

  final expectedDocument = composer.text.text;
  final originalPollNames = {
    for (final original in parsePollComposerBlocks(composer.originalRaw ?? ''))
      original.name,
  };
  final published =
      composer.target.isEdit && originalPollNames.contains(block.name);
  final editingPostId = composer.target.editingPostId;
  final voters = editingPostId == null
      ? null
      : controller.store
            .read<Post>(composer.target.siteUrl, editingPostId)
            ?.polls?[block.name]
            ?.voters;

  bool stillCurrent() =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), controller) &&
      identical(controller.visibleComposer, composer) &&
      composer.text.text == expectedDocument;

  if (published) {
    final confirmed = await confirmPublishedPollRemoval(
      context,
      voterCount: voters,
    );
    if (!confirmed) return;
  }
  if (!stillCurrent()) {
    if (context.mounted) {
      _pollComposerMessage(
        context,
        'The composer changed before this poll could be removed. Nothing was changed.',
      );
    }
    return;
  }
  if (!context.mounted) return;

  final mutation = removeVerifiedPoll(
    current: composer.text.value,
    expectedDocument: expectedDocument,
    expectedBlock: block,
  );
  if (!mutation.applied) {
    _pollComposerMessage(context, mutation.message!);
    return;
  }
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void _pollComposerMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

class _PostPollCard extends StatelessWidget {
  const _PostPollCard({
    required this.siteUrl,
    required this.post,
    required this.poll,
  });

  final String siteUrl;
  final Post post;
  final Poll poll;

  @override
  Widget build(BuildContext context) {
    // A poll depends on shell state that does not rewrite the Post itself:
    // session-fresh group membership and the per-post write lease. Subscribe
    // here so restricted cards unlock after the session read and every card on
    // the post disables while any one of them is saving.
    final controller = ShellScope.maybeOf(context);
    final route = controller?.currentContent;
    final topicId = route?.topicId;
    final instance = controller?.instances
        .where((instance) => instance.url == siteUrl)
        .firstOrNull;
    final freshUser = controller?.freshCurrentUserFor(siteUrl);
    final archived = topicId == null
        ? false
        : controller?.store.read<TopicDetail>(siteUrl, topicId)?.archived ==
              true;
    final postUrl = topicId == null
        ? null
        : '$siteUrl/t/${_slug(route?.slug)}/$topicId/${post.postNumber}';

    Future<void> vote(Poll target, List<String> options) async {
      final result = await controller?.castPollVote(
        post,
        target,
        options,
        siteUrl: siteUrl,
      );
      if (result?.message case final message?) {
        throw _PollWriteRefused(message);
      }
      if (result?.reconciled == true) throw const _PollVoteReconciled();
    }

    Future<void> remove(Poll target) async {
      final result = await controller?.removePollVote(
        post,
        target,
        siteUrl: siteUrl,
      );
      if (result?.message case final message?) {
        throw _PollWriteRefused(message);
      }
      if (result?.reconciled == true) throw const _PollVoteReconciled();
    }

    return PollCard(
      poll: poll,
      siteUrl: siteUrl,
      signedIn: instance?.isConnected == true,
      currentUserGroups: freshUser?.groups,
      archived: archived,
      pending: controller?.postWriteInFlight(post.id, siteUrl: siteUrl) == true,
      onVote: controller == null ? null : vote,
      onRemoveVote: controller == null ? null : remove,
      onVoteError: (error) {
        if (!context.mounted) return;
        final text = switch (error) {
          _PollVoteReconciled() => null,
          final _PollWriteRefused refusal => refusal.message,
          _ => "Couldn't save that vote.",
        };
        if (text == null) return;
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(text)));
      },
      onVoteOnWeb: postUrl == null
          ? null
          : () => unawaited(openExternalLink(postUrl)),
      onConnectAccount:
          controller == null || instance == null || instance.isConnected
          ? null
          : () => unawaited(_connect(context, controller)),
    );
  }

  static String _slug(String? slug) =>
      slug == null || slug.isEmpty ? 'topic' : slug;

  static Future<void> _connect(
    BuildContext context,
    ShellController controller,
  ) async {
    await controller.connectCurrentInstance();
    if (!context.mounted ||
        !identical(ShellScope.maybeRead(context), controller)) {
      return;
    }
    final error = controller.connectError;
    if (error != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _PollWriteRefused implements Exception {
  const _PollWriteRefused(this.message);

  final String message;
}

class _PollVoteReconciled implements Exception {
  const _PollVoteReconciled();
}
