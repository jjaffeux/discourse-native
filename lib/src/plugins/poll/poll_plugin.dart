import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../../models/post.dart';
import '../../plugin_api/site_plugin_api.dart';
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
import 'poll_shell_extension.dart';

export 'poll_data.dart';

const pollComposerSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('poll'),
  name: 'poll',
);

/// Discourse's bundled Poll plugin as an optional, payload-gated feature.
class PollPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<PollSettings>,
        CurrentUserPlugin<PollCurrentUser>,
        PostRecordPlugin<Polls>,
        PostBodyPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        TopicLivePlugin {
  const PollPlugin();

  @override
  String get name => 'poll';

  @override
  ComposerSyntaxKind get composerSyntaxKind => pollComposerSyntaxKind;

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
  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) {
    final initial = context.initialState;
    return PollComposerSyntaxPolicy(
      settings: initial.siteSettings.pollSettings,
      settingsReader: () => context.readState().siteSettings.pollSettings,
      freshUserReader: () =>
          context.readState().freshCurrentUser.pollCurrentUser,
      freshUserIsStaffReader: () => context.readState().freshCurrentUserIsStaff,
      editingPollsReader: () => context.readState().editingPost.polls,
    );
  }

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
    ComposerEditorHost editor,
  ) {
    final policy = editor.syntaxPolicy<PollComposerSyntaxPolicy>(
      pollComposerSyntaxKind,
    );
    if (policy == null || editor.loadingBody || !policy.canCreate(editor)) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.list,
        label: 'Add poll',
        onInvoke: () => unawaited(openPollComposer(context, editor, policy)),
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

/// Poll's complete parser, projection configuration, and authoring policy for
/// one open composer.
final class PollComposerSyntaxPolicy implements ComposerSyntaxPolicy {
  const PollComposerSyntaxPolicy({
    this.settings = const PollSettings(),
    this.settingsReader,
    this.freshUserReader,
    this.freshUserIsStaffReader,
    this.editingPollsReader,
  });

  final PollSettings settings;
  final PollSettings Function()? settingsReader;
  final PollCurrentUser? Function()? freshUserReader;
  final bool Function()? freshUserIsStaffReader;
  final Polls? Function()? editingPollsReader;

  @override
  ComposerSyntaxKind get kind => pollComposerSyntaxKind;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final block in parsePollComposerBlocks(source))
      PollComposerSyntaxProjection(policy: this, block: block),
  ];

  @override
  Object get projectionState => settings.maximumOptions;

  @override
  TextInputFormatter get inputFormatter => const PollComposerInputFormatter();

  PollSettings get currentSettings => settingsReader?.call() ?? settings;

  /// Creation is intentionally based on the refreshed session. A persisted
  /// permission must never authorize a new poll while current.json is pending.
  bool canCreate(ComposerEditorHost editor) =>
      editor.isCurrent && freshUserReader?.call()?.canCreatePoll == true;

  bool get freshUserIsStaff => freshUserIsStaffReader?.call() == true;

  int? voterCount(ComposerEditorHost editor, PollComposerBlock block) =>
      editingPollsReader?.call()?[block.name]?.voters;
}

/// One lossless Poll occurrence. The typed parsed block never enters core.
final class PollComposerSyntaxProjection
    implements ComposerSyntaxProjection, PollComposerProjectionData {
  const PollComposerSyntaxProjection({
    required this.policy,
    required this.block,
  });

  final PollComposerSyntaxPolicy policy;
  final PollComposerBlock block;

  @override
  PollComposerBlock get pollBlock => block;

  @override
  int get start => block.start;

  @override
  int get end => block.end;

  @override
  String get source => block.source;

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => pollBlockNeedsRawSource(
    block: block,
    value: document,
    suppressCollapsedCaret: suppressCollapsedCaret,
  );

  @override
  int caretAfter(String document) {
    if (end >= document.length) return end;
    if (document.codeUnitAt(end) == 0x0D &&
        end + 1 < document.length &&
        document.codeUnitAt(end + 1) == 0x0A) {
      return end + 2;
    }
    return document.codeUnitAt(end) == 0x0A ? end + 1 : end;
  }

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) {
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
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) =>
      buildCollapsedPollSpans(
        block: block,
        baseStyle: context.baseStyle,
        pillKey: context.pillKey,
        maximumOptions: policy.settings.maximumOptions,
        highlighted: context.highlighted,
        hovered: context.hovered,
        followedByLineBreak: context.followedByLineBreak,
      );

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      openPollComposer(context, editor, policy, block: block);

  @override
  Future<void> remove(BuildContext context, ComposerEditorHost editor) =>
      removePollComposer(context, editor, policy, block);
}

/// Opens Poll's composer projection for a new block or one existing occurrence.
Future<void> openPollComposer(
  BuildContext context,
  ComposerEditorHost editor,
  PollComposerSyntaxPolicy policy, {
  PollComposerBlock? block,
}) async {
  if (!editor.isCurrent || (block == null && !policy.canCreate(editor))) {
    return;
  }

  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final expectedSelection = expectedValue.selection;
  final settings = policy.currentSettings;
  final draft = block == null
      ? PollComposerDraft.newPoll(
          name: nextPollName(expectedDocument),
          defaultPublic: settings.defaultPublic,
        )
      : PollComposerDraft.fromBlock(
          block,
          maximumOptions: settings.maximumOptions,
        );

  final originalPollNames = {
    for (final original in parsePollComposerBlocks(editor.originalRaw ?? ''))
      original.name,
  };
  final published =
      block != null && editor.isEdit && originalPollNames.contains(block.name);
  final voters = block == null ? null : policy.voterCount(editor, block);

  bool stillCurrent() =>
      context.mounted &&
      editor.isCurrent &&
      editor.value.text == expectedDocument &&
      (block != null || policy.canCreate(editor));

  final action = await showPollComposerSheet(
    context: context,
    draft: draft,
    maximumOptions: settings.maximumOptions,
    isStaff: policy.freshUserIsStaff,
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
        editor.requestFocus();
        return;
      }
      mutation = block == null
          ? insertVerifiedPoll(
              current: editor.value,
              expectedDocument: expectedDocument,
              expectedSelection: expectedSelection,
              markup: replacement,
            )
          : replaceVerifiedPoll(
              current: editor.value,
              expectedDocument: expectedDocument,
              expectedBlock: block,
              replacement: replacement,
            );
    case PollComposerSheetActionType.remove:
      if (block == null) return;
      mutation = removeVerifiedPoll(
        current: editor.value,
        expectedDocument: expectedDocument,
        expectedBlock: block,
      );
  }

  if (!mutation.applied) {
    _pollComposerMessage(context, mutation.message!);
    return;
  }
  if (!editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    _pollComposerMessage(
      context,
      'The composer changed while this poll was open. Nothing was changed.',
    );
    return;
  }
  editor.requestFocus();
}

/// Removes one poll occurrence from the composer through the same verified
/// source mutation used by the editor sheet.
Future<void> removePollComposer(
  BuildContext context,
  ComposerEditorHost editor,
  PollComposerSyntaxPolicy policy,
  PollComposerBlock block,
) async {
  if (!editor.isCurrent) return;

  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final originalPollNames = {
    for (final original in parsePollComposerBlocks(editor.originalRaw ?? ''))
      original.name,
  };
  final published = editor.isEdit && originalPollNames.contains(block.name);
  final voters = policy.voterCount(editor, block);

  bool stillCurrent() =>
      context.mounted &&
      editor.isCurrent &&
      editor.value.text == expectedDocument;

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
    current: editor.value,
    expectedDocument: expectedDocument,
    expectedBlock: block,
  );
  if (!mutation.applied) {
    _pollComposerMessage(context, mutation.message!);
    return;
  }
  if (!editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    _pollComposerMessage(
      context,
      'The composer changed before this poll could be removed. Nothing was changed.',
    );
    return;
  }
  editor.requestFocus();
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
