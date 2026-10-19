import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/post_mutation_outcome.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

bool Function() capturePostMutationPresentation(
  BuildContext context,
  ShellController controller,
  String siteUrl,
) {
  final scoped = identical(ShellScope.maybeRead(context), controller);
  final tab = scoped
      ? ForumTabScope.tabOf(context)
      : controller.focusedTabContext;
  final destination = tab.currentContent?.destination.identity;
  final lease = controller.lifecycle.capture(siteUrl);
  return () =>
      context.mounted &&
      !controller.accountSessionDisposed &&
      lease.isCurrent &&
      tab.isCurrent &&
      tab.siteUrl == siteUrl &&
      tab.currentContent?.destination.identity == destination &&
      (!scoped ||
          identical(ShellScope.maybeRead(context), controller) &&
              ForumTabScope.tabOf(context).tabId == tab.tabId);
}

String _problemText(BuildContext context, PostMutationProblem problem) {
  if (problem.serverMessages.isNotEmpty) {
    return problem.serverMessages.join('\n');
  }
  final l10n = context.l10n;
  return switch (problem.kind) {
    PostMutationProblemKind.validation => l10n.thatWasnTAccepted,
    PostMutationProblemKind.rateLimited => switch (problem.retryAfter) {
      final wait? => l10n.tooFastTryAgainInS(wait.inSeconds.toString()),
      null => l10n.tooFastTryAgainInAMoment,
    },
    PostMutationProblemKind.forbidden ||
    PostMutationProblemKind.invalidTarget =>
      l10n.youCanTPostThatHereOrTheConnectionToThis,
    PostMutationProblemKind.conflict => l10n.someoneElseChangedThatFirst,
    PostMutationProblemKind.unavailable => l10n.couldnTReachTheSite,
    PostMutationProblemKind.busyPost =>
      l10n.anotherActionOnThisPostIsStillBeingSaved,
    PostMutationProblemKind.busyTopic =>
      l10n.anotherTopicActionIsStillFinishing,
    PostMutationProblemKind.permanentDeletionUnavailable =>
      l10n.thisPostCannotBePermanentlyDeleted,
    PostMutationProblemKind.recoveryRequired =>
      l10n.postMutationRecoveryRequired,
  };
}

String? postMutationMessage(
  BuildContext context,
  PostMutationOutcome outcome, {
  String? retiredMessage,
}) {
  final retired =
      retiredMessage ??
      context.l10n.yourConnectionChangedReopenTheActionAndTryAgain;
  return switch (outcome) {
    PostMutationAccepted(:final projection) => switch (projection) {
      PostProjectionFreshness.fresh => null,
      PostProjectionFreshness.stale =>
        context.l10n.postMutationSavedRefreshNeeded,
      PostProjectionFreshness.retired => retired,
    },
    PostMutationRefused(:final problem) ||
    PostMutationNotSent(:final problem) => _problemText(context, problem),
    PostMutationUncertain(:final projection) => switch (projection) {
      PostProjectionFreshness.fresh =>
        context.l10n.postMutationUncertainRefreshed,
      PostProjectionFreshness.stale =>
        context.l10n.postMutationUncertainRefreshNeeded,
      PostProjectionFreshness.retired => retired,
    },
    PostMutationRetired() => retired,
    PostMutationNoChange() => null,
  };
}

PostMutationRecovery? postMutationRecoveryOf(PostMutationOutcome outcome) =>
    switch (outcome) {
      PostMutationAccepted(:final recovery) ||
      PostMutationNotSent(:final recovery) => recovery,
      PostMutationUncertain(:final recovery) => recovery,
      _ => null,
    };

bool postMutationRequiresNewIntent(PostMutationOutcome outcome) =>
    outcome is PostMutationUncertain ||
    outcome is PostMutationNotSent && outcome.recovery != null;

String postMutationRefreshMessage(
  BuildContext context,
  PostProjectionFreshness projection, {
  String? retiredMessage,
}) => switch (projection) {
  PostProjectionFreshness.fresh => context.l10n.postMutationViewRefreshed,
  PostProjectionFreshness.stale => context.l10n.postMutationRefreshFailed,
  PostProjectionFreshness.retired =>
    retiredMessage ??
        context.l10n.yourConnectionChangedReopenTheActionAndTryAgain,
};

void showPostMutationFeedback(
  BuildContext context,
  PostMutationOutcome outcome, {
  required bool Function() isCurrent,
}) {
  if (!context.mounted || !isCurrent()) return;
  final message = postMutationMessage(context, outcome);
  if (message == null) return;
  final toaster = DToast.maybeOf(context);
  if (toaster == null) return;
  final recovery = postMutationRecoveryOf(outcome);
  final id = Object();
  var refreshing = false;
  final type =
      outcome is PostMutationAccepted ||
          outcome is PostMutationUncertain ||
          recovery != null
      ? DToastType.warning
      : DToastType.error;
  DToastOptions options(
    String text, {
    bool loading = false,
    bool finished = false,
  }) => DToastOptions(
    description: text,
    type: loading
        ? DToastType.loading
        : finished
        ? DToastType.info
        : type,
    duration: recovery == null || finished ? const Duration(seconds: 5) : null,
    action: recovery == null || finished
        ? null
        : DToastAction(
            label: context.l10n.refresh,
            onPressed: loading
                ? null
                : () async {
                    if (refreshing ||
                        !context.mounted ||
                        !isCurrent() ||
                        !recovery.isCurrent) {
                      return;
                    }
                    refreshing = true;
                    toaster.update(
                      id,
                      options(context.l10n.refreshing, loading: true),
                    );
                    final projection = await recovery.refresh();
                    refreshing = false;
                    if (!context.mounted || !isCurrent()) {
                      toaster.close(id);
                      return;
                    }
                    toaster.update(
                      id,
                      options(
                        postMutationRefreshMessage(context, projection),
                        finished: projection != PostProjectionFreshness.stale,
                      ),
                    );
                  },
          ),
  );
  toaster.add(options(message), id: id);
}

class PostMutationRecoveryButton extends StatefulWidget {
  const PostMutationRecoveryButton({
    super.key,
    required this.recovery,
    required this.onRefreshed,
  });
  final PostMutationRecovery recovery;
  final ValueChanged<PostProjectionFreshness> onRefreshed;

  @override
  State<PostMutationRecoveryButton> createState() =>
      _PostMutationRecoveryButtonState();
}

class _PostMutationRecoveryButtonState
    extends State<PostMutationRecoveryButton> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing || !widget.recovery.isCurrent) return;
    final recovery = widget.recovery;
    setState(() => _refreshing = true);
    final projection = await recovery.refresh();
    if (!mounted || !identical(recovery, widget.recovery)) return;
    setState(() => _refreshing = false);
    widget.onRefreshed(projection);
  }

  @override
  Widget build(BuildContext context) => DButton(
    key: const ValueKey('post-mutation-refresh'),
    label: Text(context.l10n.refresh),
    variant: DButtonVariant.outline,
    loading: _refreshing,
    onPressed: _refreshing || !widget.recovery.isCurrent
        ? null
        : () => unawaited(_refresh()),
  );
}
