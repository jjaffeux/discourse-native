import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart' show TopicMutationsApi;
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../data/write_credential.dart';
import '../data/write_failure.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/group_route.dart';
import '../models/post.dart';
import 'topic_data_owner.dart';
import 'topic_feed_controller.dart';

final class MessageArchiveTransactions {
  MessageArchiveTransactions({
    required this.store,
    required this.credentials,
    required this.lifecycle,
    required this.topics,
    required this.topicData,
    required this.instanceAt,
    required this.topicFeeds,
  });

  final Store store;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final TopicMutationsApi topics;
  final TopicDataOwner topicData;
  final DiscourseInstance? Function(String siteUrl) instanceAt;
  final TopicFeedController topicFeeds;
  final Set<String> _writes = {};
  bool _disposed = false;

  Future<String?> update(String siteUrl, int topicId, bool archived) async {
    final instance = instanceAt(siteUrl);
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (_disposed ||
        instance?.isConnected != true ||
        instance?.user?.canSendPrivateMessages != true ||
        held?.privateMessage != true) {
      return appL10n.thisMessageCanNoLongerBeMoved;
    }
    if (held!.messageArchived == archived) return null;
    final key = '$siteUrl#$topicId';
    if (!_writes.add(key)) {
      return appL10n.anotherInboxActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await readWriteCredential(
        AccountRequestSession(siteUrl, lease),
        credentials,
        withClientId: true,
      );
      if (!lease.isCurrent || _disposed) return appL10n.theAccountHasChanged;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || _disposed) return appL10n.theAccountHasChanged;
      await credential.request!.run(
        () => topics.updateMessageArchived(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          archived: archived,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || _disposed) return appL10n.theAccountHasChanged;
      topicData.forLease(siteUrl, lease)?.acceptArchive(topicId, archived);
      // Core moves it for the user and each of its groups they belong to. The
      // account's message groups can predate a group's first message; the
      // topic names its groups as they are.
      refreshFolders(
        siteUrl,
        personal: MessageListMode.values,
        group: MessageListMode.values,
        groupNames: {
          ...instance!.user!.messageGroupNames,
          ...held.allowedMessageGroups,
        },
      );
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() => _writes.remove(key));
    }
  }

  void refreshFolders(
    String siteUrl, {
    SiteLease? lease,
    required Iterable<MessageListMode> personal,
    required Iterable<MessageListMode> group,
    required Iterable<String> groupNames,
  }) {
    final instance = instanceAt(siteUrl);
    final username = instance?.user?.username;
    if (instance == null || username == null) return;
    void refresh(String destinationId, String path) {
      if (_disposed || (lease != null && !lease.isCurrent)) return;
      if (topicFeeds.feedFor(siteUrl, destinationId) == null) return;
      unawaited(
        topicFeeds.load(
          instance: instance,
          destinationId: destinationId,
          path: path,
          incoming: null,
          force: true,
        ),
      );
    }

    for (final mode in personal) {
      refresh(ContentRoute.messages(mode: mode).id, mode.feedPathFor(username));
    }
    final groupModes = [
      for (final mode in group)
        if (mode.supportsGroup) mode,
    ];
    final pageTabs = <String?>[
      if (groupModes.contains(MessageListMode.inbox)) ...[
        null,
        GroupRoute.inbox,
      ],
      if (groupModes.contains(MessageListMode.archive)) GroupRoute.archive,
    ];
    for (final name in groupNames) {
      try {
        for (final mode in groupModes) {
          refresh(
            ContentRoute.messages(groupName: name, mode: mode).id,
            mode.feedPathFor(username, groupName: name),
          );
        }
        for (final subsection in pageTabs) {
          final route = GroupRoute.detail(
            name,
            section: GroupRoute.messages,
            subsection: subsection,
          );
          refresh(route.id, route.topicFeedPath(username)!);
        }
      } on ArgumentError {
        continue;
      }
    }
  }

  void forget(String siteUrl) {
    _writes.removeWhere((key) => key.startsWith('$siteUrl#'));
  }

  void dispose() {
    _disposed = true;
    _writes.clear();
  }
}
