import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import 'topic_data_owner.dart';

final class FlagSiteContext {
  const FlagSiteContext({
    required this.connected,
    required this.catalog,
    required this.minimumMessageLength,
  });

  final bool connected;
  final SitePostActionCatalog catalog;
  final int minimumMessageLength;
}

final class FlagTransactions {
  FlagTransactions({
    required this.store,
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.topicData,
    required this.siteContextFor,
    required this.changed,
  });

  final Store store;
  final PostMutationsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final TopicDataOwner topicData;
  final FlagSiteContext Function(String siteUrl) siteContextFor;
  final void Function() changed;
  final Map<String, _FlagAccount> _accounts = {};
  bool _disposed = false;

  String get _obsolete =>
      appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;

  _FlagAccount _session(String siteUrl) {
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    final account = _FlagAccount(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      account.retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?.retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account.retire();
    }
    _accounts.clear();
  }

  Future<({AccountRequestCredentials? request, WriteException? failure})>
  _credentialForWrite(String siteUrl, SiteLease lease) async {
    try {
      final request = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      return request.apiKey == null
          ? (
              request: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (request: request, failure: null);
    } catch (error) {
      return (
        request: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  Future<String?> createPost(
    String siteUrl,
    Post post,
    PostFlagType flagType, {
    String? message,
  }) async {
    if (_disposed) return _obsolete;
    final context = siteContextFor(siteUrl);
    final held = store.read<Post>(siteUrl, post.id);
    PostFlagType? currentType;
    for (final type in context.catalog.postFlags) {
      if (type.id == flagType.id) {
        currentType = type;
        break;
      }
    }
    if (!context.connected) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (held == null ||
        held.hidden ||
        held.isDeleted ||
        held.actedFlagSummaries.isNotEmpty ||
        currentType == null ||
        !currentType.enabled ||
        !currentType.appliesToPost ||
        !held.canFlagWith(currentType.id)) {
      return appL10n.thisPostCanNoLongerBeFlagged;
    }

    final submittedMessage = currentType.requireMessage ? message ?? '' : null;
    final length = submittedMessage?.length ?? 0;
    final minimum = context.minimumMessageLength;
    if (currentType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return appL10n.yourMessageMustBeBetweenAndCharacters(
        (minimum).toString(),
        (PostFlagType.maximumMessageLength).toString(),
      );
    }

    final account = _session(siteUrl);
    final lease = account.lease;
    final releasePost = topicData
        .forLease(siteUrl, lease)
        ?.beginPostWrite(held.id);
    if (releasePost == null) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }
    try {
      final credential = await _credentialForWrite(siteUrl, lease);
      if (!account.isCurrent) {
        return _obsolete;
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        final flagActionTypeId = currentType.id;
        final fresh = await credential.request!.run(
          () => api.createPostFlag(
            siteUrl: siteUrl,
            apiKey: credential.request!.apiKey!,
            postId: held.id,
            postActionTypeId: flagActionTypeId,
            message: submittedMessage,
          ),
        );
        if (!account.isCurrent) {
          return _obsolete;
        }
        lease.commit(() {
          topicData.forLease(siteUrl, lease)?.acceptPostAction(fresh);
          if (account.isCurrent) changed();
        });
        return null;
      } on WriteException catch (error) {
        return error.message;
      } catch (error) {
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      lease.commit(releasePost);
    }
  }

  bool topicWriting(String siteUrl, int topicId) {
    final account = _accounts[siteUrl];
    return account != null &&
        account.isCurrent &&
        account.topics.containsKey(topicId);
  }

  Future<String?> createTopic(
    String siteUrl,
    TopicDetail topic,
    PostFlagType flagType, {
    String? message,
  }) async {
    if (_disposed) return _obsolete;
    final context = siteContextFor(siteUrl);
    final held = store.read<TopicDetail>(siteUrl, topic.id);
    final currentType = context.catalog.topicFlags
        .where((type) => type.id == flagType.id)
        .firstOrNull;
    if (!context.connected) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (held == null ||
        currentType == null ||
        !currentType.enabled ||
        !currentType.appliesToTopic ||
        !held.canFlagWith(currentType.id)) {
      return appL10n.thisTopicCanNoLongerBeFlagged;
    }

    final submittedMessage = currentType.requireMessage ? message ?? '' : null;
    final length = submittedMessage?.length ?? 0;
    final minimum = context.minimumMessageLength;
    if (currentType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return appL10n.yourMessageMustBeBetweenAndCharacters(
        (minimum).toString(),
        (PostFlagType.maximumMessageLength).toString(),
      );
    }

    final account = _session(siteUrl);
    final key = held.id;
    if (account.topics.containsKey(key)) {
      return appL10n.anotherFlagOnThisTopicIsStillBeingSaved;
    }
    final lease = account.lease;
    final attempt = Object();
    account.topics[key] = attempt;
    changed();
    try {
      final credential = await _credentialForWrite(siteUrl, lease);
      if (!account.isCurrent) {
        return _obsolete;
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        await credential.request!.run(
          () => api.createTopicFlag(
            siteUrl: siteUrl,
            apiKey: credential.request!.apiKey!,
            topicId: held.id,
            postActionTypeId: currentType.id,
            message: submittedMessage,
          ),
        );
        if (!account.isCurrent) {
          return _obsolete;
        }
        lease.commit(() {
          store.update<TopicDetail>(
            siteUrl,
            held.id,
            (current) => current.withTopicFlag(currentType.id),
          );
          if (account.isCurrent) changed();
        });
        return null;
      } on WriteException catch (error) {
        return error.message;
      } catch (error) {
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      if (identical(account.topics[key], attempt)) {
        account.topics.remove(key);
        if (account.isCurrent) changed();
      }
    }
  }
}

final class _FlagAccount {
  _FlagAccount(this.lease);

  final SiteLease lease;
  final Map<int, Object> topics = {};
  void Function()? detach;
  bool _retired = false;

  bool get isCurrent => !_retired && lease.isCurrent;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    topics.clear();
  }
}
