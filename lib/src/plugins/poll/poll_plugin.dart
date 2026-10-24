import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'poll.dart';
import 'poll_card.dart';
import 'poll_composer.dart';
import 'poll_controller.dart';
import 'poll_data.dart';
import 'poll_global_search.dart';
import 'poll_icons.dart';
import 'poll_services.dart';

export 'poll_data.dart';

class PollPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        CompactEmojiPlugin,
        GlobalSearchPlugin,
        IconCatalogPlugin,
        SiteSettingsPlugin<PollSettings>,
        CurrentUserPlugin<PollCurrentUser>,
        PostRecordPlugin<Polls>,
        PostBodyPlugin,
        CookedElementPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        TopicLivePlugin {
  @override
  List<GlobalSearchContribution> get searchContributions => const [
    PollGlobalSearch(),
  ];

  const PollPlugin();

  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      runtimeType == PollPlugin ? PollPlugin.new : null;

  @override
  bool compactEmojiAncestor(dom.Element element) =>
      element.classes.contains('poll');

  @override
  String get name => 'poll';

  @override
  PluginIconCatalog get iconCatalog => pollIconCatalog;

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
  ) => createPollComposerSyntaxPolicy(context);

  @override
  PluginDataKey<Polls> get record => pollsDataKey;

  @override
  Polls? readPost(Map<String, dynamic> json, String siteUrl) =>
      Polls.fromJson(json, siteUrl);

  @override
  Widget? postBodyElement(PluginPostBodyContext body, dom.Element element) {
    if (!element.classes.contains('poll')) return null;
    final siteUrl = body.siteUrl;
    final post = body.post;
    final name = element.attributes['data-poll-name'];
    if (name == null || name.isEmpty) {
      return PollFallbackCard.fromCooked(element, siteUrl: siteUrl);
    }
    final poll = post.polls?[name];
    return poll == null
        ? PollFallbackCard.fromCooked(element, siteUrl: siteUrl)
        : _PostPollCard(
            siteUrl: siteUrl,
            post: post,
            poll: poll,
            topic: body.topic,
            controller: PluginUiScope.maybe(
              body.buildContext,
              pollControllerService,
            ),
          );
  }

  /// Cooked fragments carry definitions, never voting authority or totals.
  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      element.classes.contains('poll')
      ? PollFallbackCard.fromCooked(element, siteUrl: siteUrl)
      : null;

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) => pollComposerToolbar(context, editor);

  /// Poll definitions are serialized on edit, and absence means removal.
  @override
  Polls? mergeAfterPostEdit(Polls? held, Polls? incoming) => incoming;

  static String _channelFor(int topicId) => '/polls/$topicId';

  @override
  List<String> topicChannels(int topicId) => [_channelFor(topicId)];

  // Plugin hooks receive every topic channel; payload fields are not authority.
  @override
  List<int> stalePosts(String channel, Object? data) {
    if (!channel.startsWith('/polls/')) return const [];
    if (data is! Map<Object?, Object?>) return const [];
    final postId = liveRefreshId(data['post_id']);
    return postId == null ? const [] : [postId];
  }
}

class _PostPollCard extends StatelessWidget {
  const _PostPollCard({
    required this.siteUrl,
    required this.post,
    required this.poll,
    required this.topic,
    required this.controller,
  });

  final String siteUrl;
  final Post post;
  final Poll poll;
  final PluginContainingTopic? topic;
  final PollController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return _buildCard(context, null);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildCard(context, controller),
    );
  }

  Widget _buildCard(BuildContext context, PollController? controller) {
    final topic = this.topic;
    final session = controller?.captureSiteSession(siteUrl);
    final freshUser = controller?.freshCurrentUserFor(siteUrl);
    final postUrl = topic == null
        ? null
        : '$siteUrl/t/${_slug(topic.slug)}/${topic.id}/${post.postNumber}';

    Future<void> vote(Poll target, List<String> options) async {
      if (controller == null ||
          topic == null ||
          !context.mounted ||
          !session!.isCurrent) {
        return;
      }
      final result = await controller.castVote(
        siteUrl: siteUrl,
        topicId: topic.id,
        archived: topic.archived,
        post: post,
        poll: target,
        optionIds: options,
      );
      _completeWrite(result);
    }

    Future<void> remove(Poll target) async {
      if (controller == null ||
          topic == null ||
          !context.mounted ||
          !session!.isCurrent) {
        return;
      }
      final result = await controller.removeVote(
        siteUrl: siteUrl,
        topicId: topic.id,
        archived: topic.archived,
        post: post,
        poll: target,
      );
      _completeWrite(result);
    }

    return PollCard(
      poll: poll,
      siteUrl: siteUrl,
      signedIn: controller?.isConnected(siteUrl) == true,
      currentUserGroups: freshUser?.groups,
      archived: topic?.archived == true,
      pending: controller?.writeInFlight(siteUrl, post.id) == true,
      onVote: controller == null || topic == null ? null : vote,
      onRemoveVote: controller == null || topic == null ? null : remove,
      onVoteError: (error) {
        if (!context.mounted || session?.isCurrent != true) return;
        final text = switch (error) {
          _PollVoteReset() => null,
          final _PollWriteRefused refusal => refusal.message,
          _ => context.l10n.couldnTSaveThatVote,
        };
        if (text == null) return;
        DToast.show(context, text, type: DToastType.error);
      },
      onVoteOnWeb: postUrl == null
          ? null
          : () => unawaited(openExternalLink(postUrl)),
      onConnectAccount: controller == null || controller.isConnected(siteUrl)
          ? null
          : () => unawaited(_connect(context, controller, siteUrl)),
    );
  }

  static String _slug(String? slug) =>
      slug == null || slug.isEmpty ? 'topic' : slug;

  static void _completeWrite(PollVoteWriteResult result) {
    switch (result.kind) {
      case PollVoteWriteKind.saved:
      case PollVoteWriteKind.acceptedRetired:
      case PollVoteWriteKind.unchanged:
      case PollVoteWriteKind.inactive:
        return;
      case PollVoteWriteKind.refused:
        throw _PollWriteRefused(
          result.refusalReason == PollVoteRefusalReason.archived
              ? appL10n.votingIsUnavailableInArchivedTopics
              : result.failure!.message,
        );
      case PollVoteWriteKind.notSent:
        if (result.notSentReason ==
                PollVoteNotSentReason.credentialsUnavailable ||
            result.failure!.failure != WriteFailure.unreachable) {
          throw _PollWriteRefused(result.failure!.message);
        }
        throw const _PollVoteReset();
      case PollVoteWriteKind.busy:
      case PollVoteWriteKind.uncertain:
        throw const _PollVoteReset();
      case PollVoteWriteKind.uncertainRefreshFailed:
        throw result.recoveryFailure!;
    }
  }

  static Future<void> _connect(
    BuildContext context,
    PollController controller,
    String siteUrl,
  ) async {
    final error = await controller.connect(siteUrl);
    if (!context.mounted ||
        !identical(
          PluginUiScope.maybe(context, pollControllerService),
          controller,
        )) {
      return;
    }
    if (error != null) {
      DToast.show(context, error, type: DToastType.error);
    }
  }
}

class _PollWriteRefused implements Exception {
  const _PollWriteRefused(this.message);

  final String message;
}

class _PollVoteReset implements Exception {
  const _PollVoteReset();
}
