import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../../models/post.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/composer_controller.dart';
import '../../shell/external_link.dart';
import '../../shell/shell_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import 'poll.dart';
import 'poll_card.dart';
import 'poll_composer_editor.dart';
import 'poll_composer_pill.dart';
import 'poll_composer_sheet.dart';
import 'poll_data.dart';
import 'poll_icons.dart';
import 'poll_shell_extension.dart';

export 'poll_data.dart';

/// Discourse's bundled Poll plugin as an optional, payload-gated feature.
class PollPlugin
    implements
        SitePlugin,
        IconCatalogPlugin,
        SiteSettingsPlugin<PollSettings>,
        CurrentUserPlugin<PollCurrentUser>,
        PluginPermissionPlugin,
        ComposerMaximumOptionsPlugin,
        PostRecordPlugin<Polls>,
        PostBodyPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        TopicLivePlugin {
  const PollPlugin();

  @override
  String get name => 'poll';

  @override
  PluginIconCatalog get iconCatalog => pollIconCatalog;

  @override
  String get syntaxId => 'poll';

  @override
  PluginDataPersistenceCodec<PollSettings> get siteSettingsCodec =>
      pollSettingsPersistenceCodec;

  @override
  PollSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      PollSettings.fromWire(json);

  @override
  PluginDataPersistenceCodec<PollCurrentUser> get currentUserCodec =>
      pollCurrentUserPersistenceCodec;

  @override
  PollCurrentUser? readCurrentUser(Map<String, dynamic> json, String siteUrl) =>
      PollCurrentUser.fromWire(json);

  @override
  String get permissionId => 'create-poll';

  @override
  bool allowsPermission(PluginData currentUser, bool? recordPermission) =>
      currentUser.get(pollCurrentUserDataKey)?.canCreatePoll == true;

  @override
  int composerMaximumOptions(PluginData siteSettings) =>
      siteSettings.get(pollSettingsDataKey)?.maximumOptions ??
      PollSettings.defaultMaximumOptions;

  @override
  List<Object> parseComposerSyntax(String source) =>
      parsePollComposerBlocks(source);

  @override
  int startOf(Object value) => (value as PollComposerBlock).start;

  @override
  int endOf(Object value) => (value as PollComposerBlock).end;

  @override
  String sourceOf(Object value) => (value as PollComposerBlock).source;

  @override
  bool needsRawSource(
    Object value,
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => pollBlockNeedsRawSource(
    block: value as PollComposerBlock,
    value: document,
    suppressCollapsedCaret: suppressCollapsedCaret,
  );

  @override
  int caretAfter(Object value, String document) {
    final end = (value as PollComposerBlock).end;
    if (end >= document.length) return end;
    if (document.codeUnitAt(end) == 0x0D &&
        end + 1 < document.length &&
        document.codeUnitAt(end + 1) == 0x0A) {
      return end + 2;
    }
    return document.codeUnitAt(end) == 0x0A ? end + 1 : end;
  }

  @override
  TextEditingValue moveCaretAfter(Object value, TextEditingValue document) {
    final block = value as PollComposerBlock;
    final mutation = replaceVerifiedPoll(
      current: document,
      expectedDocument: document.text,
      expectedBlock: block,
      replacement: block.source,
    );
    return mutation.applied ? mutation.value : document;
  }

  @override
  bool get supportsHover => true;

  @override
  bool get protectsAdjacentDelete => true;

  @override
  bool get hidesCursorWhenSelected => true;

  @override
  List<InlineSpan> buildCollapsedSpans({
    required Object value,
    required TextStyle baseStyle,
    required Locale locale,
    required String? accountTimezone,
    required int maximumOptions,
    required GlobalKey pillKey,
    required bool highlighted,
    required bool hovered,
    required bool followedByLineBreak,
  }) => buildCollapsedPollSpans(
    block: value as PollComposerBlock,
    baseStyle: baseStyle,
    pillKey: pillKey,
    maximumOptions: maximumOptions,
    highlighted: highlighted,
    hovered: hovered,
    followedByLineBreak: followedByLineBreak,
  );

  @override
  Future<void> editComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  ) => openPollComposer(context, composer, block: value as PollComposerBlock);

  @override
  Future<void> removeComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  ) => removePollComposer(context, composer, value as PollComposerBlock);

  @override
  TextInputFormatter get inputFormatter => const PollComposerInputFormatter();

  @override
  PluginDataKey<Polls> get record => pollsDataKey;

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

  static String _channelFor(int topicId) => '/polls/$topicId';

  @override
  List<String> topicChannels(int topicId) => [_channelFor(topicId)];

  /// Only its own channel: every plugin's hook is asked about every message on
  /// every topic channel, and `post_id` is not a key one feature may read out
  /// of another's payload. Assign publishes one for a post-level assignment,
  /// which is nothing to do with a poll.
  @override
  List<int> stalePosts(String channel, Object? data) {
    if (!channel.startsWith('/polls/')) return const [];
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
