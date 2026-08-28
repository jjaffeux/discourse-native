// ignore_for_file: prefer_initializing_formals

import '../../data/discourse_api_contracts.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../models/post.dart';
import '../../models/site_config.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/composer_controller.dart';
import 'poll.dart';
import 'poll_data.dart';
import 'polls_api.dart';

/// What a native poll write learned.
///
/// [reconciled] means the write response was unreachable and the owning post
/// was read again. Presentation must discard its optimistic local selection,
/// even when the refetched saved selection happens to equal the old one.
final class PollVoteWriteResult {
  const PollVoteWriteResult.saved() : message = null, reconciled = false;

  const PollVoteWriteResult.reconciled() : message = null, reconciled = true;

  const PollVoteWriteResult.refused(this.message) : reconciled = false;

  final String? message;
  final bool reconciled;
}

/// Poll-owned session state and interaction workflows.
///
/// Core supplies only guarded request credentials and post-record mechanics.
/// Poll owns its endpoint, eligibility rules, write result, and namespaced
/// record transform.
class PollController extends FrameSafeNotifier
    implements PluginCurrentUserObserver {
  PollController({
    required PollsApi api,
    required PluginRequestHost requests,
    required PluginPostHost posts,
    required PluginSiteStateHost siteState,
    required PluginFreshAccountHost freshAccount,
    required PluginAccountConnectionHost accounts,
    required PluginComposerHost composerHost,
  }) : _api = api,
       _requests = requests,
       _posts = posts,
       _siteState = siteState,
       _freshAccount = freshAccount,
       _accounts = accounts,
       _composerHost = composerHost;

  final PollsApi _api;
  final PluginRequestHost _requests;
  final PluginPostHost _posts;
  final PluginSiteStateHost _siteState;
  final PluginFreshAccountHost _freshAccount;
  final PluginAccountConnectionHost _accounts;
  final PluginComposerHost _composerHost;

  SiteConfig siteConfigFor(String siteUrl) => _siteState.siteConfigFor(siteUrl);

  PluginFreshAccountProfile? freshCurrentUserFor(String siteUrl) =>
      _freshAccount.profileFor(siteUrl);

  bool canCreatePollFor(String siteUrl) =>
      _freshAccount.recordFor(siteUrl, pollCurrentUserDataKey)?.canCreatePoll ==
      true;

  bool isActiveComposer(ComposerController composer) =>
      !composer.isDisposed && _composerHost.isActive(composer);

  bool isConnected(String siteUrl) => _accounts.isConnected(siteUrl);

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
    if (!poll.isOpen) return const PollVoteWriteResult.saved();
    if (archived || _posts.topicArchived(siteUrl, topicId)) {
      return const PollVoteWriteResult.refused(
        'Voting is unavailable in archived topics.',
      );
    }
    if (!_posts.beginWrite(siteUrl, post.id)) {
      return const PollVoteWriteResult.reconciled();
    }
    notifySafely();
    final lease = _requests.capture(siteUrl);
    try {
      final credential = await _requests.writeCredentialFor(siteUrl);
      if (!lease.isCurrent) return const PollVoteWriteResult.saved();
      if (credential.failure case final failure?) {
        return PollVoteWriteResult.refused(failure.message);
      }
      final apiKey = credential.apiKey!;

      final PollVoteResponse answer;
      try {
        answer = options == null
            ? await _api.removePollVote(
                siteUrl: siteUrl,
                apiKey: apiKey,
                postId: post.id,
                pollName: poll.name,
              )
            : await _api.votePoll(
                siteUrl: siteUrl,
                apiKey: apiKey,
                postId: post.id,
                pollName: poll.name,
                options: options,
              );
      } on WriteException catch (error) {
        if (error.failure != WriteFailure.unreachable) {
          return PollVoteWriteResult.refused(error.message);
        }
        await _refresh(siteUrl, topicId, post.id, apiKey, lease);
        return const PollVoteWriteResult.reconciled();
      } catch (error, stackTrace) {
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'poll.vote',
          source: 'poll',
          handled: true,
          degraded: true,
        );
        await _refresh(siteUrl, topicId, post.id, apiKey, lease);
        return const PollVoteWriteResult.reconciled();
      }

      lease.commit(() {
        _posts.updatePluginRecord(
          siteUrl,
          post.id,
          pollsDataKey,
          (held) => (held ?? const Polls()).withPoll(answer.poll),
        );
      });
      return const PollVoteWriteResult.saved();
    } finally {
      lease.commit(() => _posts.endWrite(siteUrl, post.id));
      notifySafely();
    }
  }

  Future<void> _refresh(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    PluginSiteLease lease,
  ) => _posts.refreshPost(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: postId,
    apiKey: apiKey,
    lease: lease,
  );

  @override
  void pluginCurrentUserRefreshed(String siteUrl) => notifySafely();

  void forget(String siteUrl) => notifySafely();
}
