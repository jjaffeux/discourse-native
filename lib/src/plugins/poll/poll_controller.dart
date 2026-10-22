// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'poll.dart';
import 'poll_data.dart';
import 'polls_api.dart';

enum PollVoteWriteKind {
  saved,
  acceptedRetired,
  unchanged,
  busy,
  inactive,
  refused,
  notSent,
  uncertain,
  uncertainRefreshFailed,
}

enum PollVoteRefusalReason { archived }

enum PollVoteNotSentReason { credentialsUnavailable, requestNotSent }

final class PollVoteWriteResult {
  const PollVoteWriteResult._(
    this.kind, {
    this.failure,
    this.refusalReason,
    this.notSentReason,
    this.recoveryFailure,
  });

  final PollVoteWriteKind kind;
  final WriteException? failure;
  final PollVoteRefusalReason? refusalReason;
  final PollVoteNotSentReason? notSentReason;

  /// A completed refresh cannot prove freshness through the host's void API.
  /// This records only a recovery exception that the host actually surfaced.
  final Object? recoveryFailure;
}

class PollController extends FrameSafeNotifier
    implements PluginCurrentUserObserver {
  PollController({
    required PollsApi api,
    required PluginRequestHost requests,
    required PluginPostHost posts,
    required PluginSiteStateHost siteState,
    required PluginFreshAccountHost freshAccount,
    required PluginAccountConnectionHost accounts,
  }) : _api = api,
       _requests = requests,
       _posts = posts,
       _siteState = siteState,
       _freshAccount = freshAccount,
       _accounts = accounts;

  final PollsApi _api;
  final PluginRequestHost _requests;
  final PluginPostHost _posts;
  final PluginSiteStateHost _siteState;
  final PluginFreshAccountHost _freshAccount;
  final PluginAccountConnectionHost _accounts;

  SiteConfig siteConfigFor(String siteUrl) => _siteState.siteConfigFor(siteUrl);

  PluginFreshAccountProfile? freshCurrentUserFor(String siteUrl) =>
      _freshAccount.profileFor(siteUrl);

  bool canCreatePollFor(String siteUrl) =>
      siteConfigFor(siteUrl).pollSettings.enabled &&
      _freshAccount.recordFor(siteUrl, pollCurrentUserDataKey)?.canCreatePoll ==
          true;

  bool isConnected(String siteUrl) => _accounts.isConnected(siteUrl);

  /// Binds a displayed ballot's actions to the account that rendered it.
  PluginSiteLease captureSiteSession(String siteUrl) =>
      _requests.capture(siteUrl);

  Future<String?> connect(String siteUrl) => _accounts.connect(siteUrl);

  Post? post(String siteUrl, int postId) => _posts.readPost(siteUrl, postId);

  bool writeInFlight(String siteUrl, int postId) =>
      _posts.writeInFlight(siteUrl, postId);

  Future<PollVoteWriteResult> castVote({
    required String siteUrl,
    required int topicId,
    required bool archived,
    required Post post,
    required Poll poll,
    required List<String> optionIds,
  }) => _writeVote(
    siteUrl: siteUrl,
    topicId: topicId,
    archived: archived,
    post: post,
    poll: poll,
    options: List.unmodifiable(optionIds),
  );

  Future<PollVoteWriteResult> removeVote({
    required String siteUrl,
    required int topicId,
    required bool archived,
    required Post post,
    required Poll poll,
  }) => _writeVote(
    siteUrl: siteUrl,
    topicId: topicId,
    archived: archived,
    post: post,
    poll: poll,
    options: null,
  );

  Future<PollVoteWriteResult> _writeVote({
    required String siteUrl,
    required int topicId,
    required bool archived,
    required Post post,
    required Poll poll,
    required List<String>? options,
  }) async {
    if (isDisposed) {
      return const PollVoteWriteResult._(PollVoteWriteKind.inactive);
    }
    if (!poll.isOpen) {
      return const PollVoteWriteResult._(PollVoteWriteKind.unchanged);
    }
    if (archived || _posts.topicArchived(siteUrl, topicId)) {
      return const PollVoteWriteResult._(
        PollVoteWriteKind.refused,
        refusalReason: PollVoteRefusalReason.archived,
      );
    }
    final lease = _requests.capture(siteUrl);
    if (!_posts.beginWrite(siteUrl, post.id)) {
      return const PollVoteWriteResult._(PollVoteWriteKind.busy);
    }
    notifySafely();
    try {
      final PluginWriteCredential credential;
      try {
        credential = await _requests.writeCredentialFor(siteUrl);
      } catch (error, stackTrace) {
        if (isDisposed || !lease.isCurrent) {
          return const PollVoteWriteResult._(PollVoteWriteKind.inactive);
        }
        final failure = error is WriteException
            ? error
            : WriteException(
                WriteFailure.unreachable,
                notSent: true,
                cause: error,
                causeStackTrace: stackTrace,
              );
        return PollVoteWriteResult._(
          PollVoteWriteKind.notSent,
          failure: failure,
          notSentReason: PollVoteNotSentReason.credentialsUnavailable,
        );
      }
      if (isDisposed || !lease.isCurrent) {
        return const PollVoteWriteResult._(PollVoteWriteKind.inactive);
      }
      if (credential.failure case final failure?) {
        return PollVoteWriteResult._(
          failure.failure == WriteFailure.unreachable
              ? PollVoteWriteKind.notSent
              : PollVoteWriteKind.refused,
          failure: failure,
          notSentReason: failure.failure == WriteFailure.unreachable
              ? PollVoteNotSentReason.credentialsUnavailable
              : null,
        );
      }
      final apiKey = credential.credentials!.apiKey!;

      final PollVoteResponse answer;
      var dispatched = false;
      try {
        answer = options == null
            ? await credential.credentials!.run(() {
                dispatched = true;
                return _api.removePollVote(
                  siteUrl: siteUrl,
                  apiKey: apiKey,
                  postId: post.id,
                  pollName: poll.name,
                );
              })
            : await credential.credentials!.run(() {
                dispatched = true;
                return _api.votePoll(
                  siteUrl: siteUrl,
                  apiKey: apiKey,
                  postId: post.id,
                  pollName: poll.name,
                  options: options,
                );
              });
      } on WriteException catch (error) {
        if (!dispatched || error.notSent) {
          return PollVoteWriteResult._(
            PollVoteWriteKind.notSent,
            failure: error,
            notSentReason: PollVoteNotSentReason.requestNotSent,
          );
        }
        if (error.failure != WriteFailure.unreachable) {
          return PollVoteWriteResult._(
            PollVoteWriteKind.refused,
            failure: error,
          );
        }
        return await _recover(siteUrl, topicId, post.id, apiKey, lease, error);
      } catch (error, stackTrace) {
        if (!dispatched) {
          return PollVoteWriteResult._(
            PollVoteWriteKind.notSent,
            failure: WriteException(
              WriteFailure.unreachable,
              notSent: true,
              cause: error,
              causeStackTrace: stackTrace,
            ),
            notSentReason: PollVoteNotSentReason.requestNotSent,
          );
        }
        return await _recover(
          siteUrl,
          topicId,
          post.id,
          apiKey,
          lease,
          WriteException(
            WriteFailure.unreachable,
            cause: error,
            causeStackTrace: stackTrace,
          ),
        );
      }

      if (isDisposed || !lease.isCurrent) {
        return const PollVoteWriteResult._(PollVoteWriteKind.acceptedRetired);
      }
      lease.commit(() {
        _posts.updatePluginRecord(
          siteUrl,
          post.id,
          pollsDataKey,
          (held) => (held ?? const Polls()).withPoll(answer.poll),
        );
      });
      return PollVoteWriteResult._(
        isDisposed || !lease.isCurrent
            ? PollVoteWriteKind.acceptedRetired
            : PollVoteWriteKind.saved,
      );
    } finally {
      lease.commit(() => _posts.endWrite(siteUrl, post.id));
      notifySafely();
    }
  }

  Future<PollVoteWriteResult> _recover(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    PluginSiteLease lease,
    WriteException failure,
  ) async {
    // Recovery admits a new request after the original write has completed.
    if (!isDisposed && lease.isCurrent) {
      try {
        await _posts.refreshPost(
          siteUrl: siteUrl,
          topicId: topicId,
          postId: postId,
          apiKey: apiKey,
          lease: lease,
        );
      } catch (error) {
        return PollVoteWriteResult._(
          PollVoteWriteKind.uncertainRefreshFailed,
          failure: failure,
          recoveryFailure: error,
        );
      }
    }
    return PollVoteWriteResult._(PollVoteWriteKind.uncertain, failure: failure);
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) => notifySafely();

  void forget(String siteUrl) => notifySafely();
}
