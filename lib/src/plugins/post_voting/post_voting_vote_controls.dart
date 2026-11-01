import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_actions.dart';
import 'post_voting_data.dart';
import 'post_voting_services.dart';

class PostVotingVoteControls extends StatelessWidget {
  const PostVotingVoteControls({
    super.key,
    required this.reader,
    required this.postId,
    required this.services,
  });
  final PluginTopicReader reader;
  final int postId;
  final PostVotingServices services;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: services.actions,
    builder: (context, _) {
      if (!services.actions.available(reader)) return const SizedBox.shrink();
      final post = reader.post(postId),
          data = services.actions.displayedRecord(reader.siteUrl, postId);
      if (post == null ||
          data == null ||
          post.contentRedacted ||
          post.isDeleted) {
        return const SizedBox.shrink();
      }
      final state = services.actions.voteState(reader.siteUrl, postId);
      final guest = reader.currentUserId == null;
      final closed =
          reader.topic?.closed == true || reader.topic?.archived == true;
      final own = !guest && post.userId == reader.currentUserId;
      final enabled =
          !closed &&
          !own &&
          !state.pending &&
          !state.uncertain &&
          (guest || services.actions.canVote(reader, postId));
      Future<void> vote(PostVoteDirection direction) async {
        if (guest) {
          await services.connectAndVote(reader, postId, direction);
          return;
        }
        final error = await services.actions.vote(
          reader,
          postId,
          data.myVote == direction ? null : direction,
        );
        if (context.mounted && reader.isCurrent && error != null) {
          DToast.show(context, error, type: DToastType.error);
        }
      }

      final hint = own
          ? context.l10n.postVotingOwnVote
          : closed
          ? context.l10n.postVotingClosed
          : guest
          ? context.l10n.postVotingSignInToVote
          : null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          DToggle.iconOnly(
            key: ValueKey('post-voting-up-$postId'),
            variant: DToggleVariant.inline,
            icon: const RotatedBox(
              quarterTurns: 2,
              child: DIcon(DIcons.chevronDown),
            ),
            pressed: data.myVote == PostVoteDirection.up,
            enabled: enabled,
            semanticLabel: data.myVote == PostVoteDirection.up
                ? context.l10n.postVotingRemoveUpvote
                : context.l10n.postVotingUpvote,
            semanticHint: hint,
            onPressedChanged: enabled
                ? (_) => unawaited(vote(PostVoteDirection.up))
                : null,
          ),
          if (data.hasVotes == true)
            DButton(
              key: ValueKey('post-voting-count-$postId'),
              variant: DButtonVariant.ghost,
              tooltip: context.l10n.postVotingShowVoters,
              label: Text('${data.score ?? 0}'),
              onPressed: state.pending
                  ? null
                  : () => unawaited(
                      showPostVotingVoters(context, reader, postId, services),
                    ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text('${data.score ?? 0}'),
            ),
          DToggle.iconOnly(
            key: ValueKey('post-voting-down-$postId'),
            variant: DToggleVariant.inline,
            icon: const DIcon(DIcons.chevronDown),
            pressed: data.myVote == PostVoteDirection.down,
            enabled: enabled,
            semanticLabel: data.myVote == PostVoteDirection.down
                ? context.l10n.postVotingRemoveDownvote
                : context.l10n.postVotingDownvote,
            semanticHint: hint,
            onPressedChanged: enabled
                ? (_) => unawaited(vote(PostVoteDirection.down))
                : null,
          ),
          if (state.pending) const DSpinner(size: 12),
          if (state.uncertain)
            DButton.iconOnly(
              variant: DButtonVariant.ghost,
              icon: const DIcon(DIcons.arrowRotateRight),
              tooltip: context.l10n.postVotingRefreshStatus,
              onPressed: () =>
                  unawaited(services.actions.checkVote(reader, postId)),
            ),
        ],
      );
    },
  );
}

Future<void> showPostVotingVoters(
  BuildContext context,
  PluginTopicReader reader,
  int postId,
  PostVotingServices services,
) async {
  if (!services.actions.available(reader)) return;
  if (reader.currentUserId == null) {
    await services.accounts.connect(reader.siteUrl);
    return;
  }
  await showDDialog<void>(
    context: context,
    builder: (context, dialog) => DDialogContent(
      children: [
        DDialogTitle(child: Text(context.l10n.postVotingShowVoters)),
        Flexible(
          child: _Voters(reader: reader, postId: postId, services: services),
        ),
        DDialogFooter(
          children: [
            DButton(label: Text(context.l10n.close), onPressed: dialog.close),
          ],
        ),
      ],
    ),
  );
}

class _Voters extends StatefulWidget {
  const _Voters({
    required this.reader,
    required this.postId,
    required this.services,
  });
  final PluginTopicReader reader;
  final int postId;
  final PostVotingServices services;
  @override
  State<_Voters> createState() => _VotersState();
}

class _VotersState extends State<_Voters> {
  PostVotingVoters? _value;
  Object? _error;
  bool _loading = true;
  int _generation = 0;
  late final int _epoch;
  bool get _current =>
      widget.services.actions.available(widget.reader) &&
      _epoch == widget.services.actions.epochFor(widget.reader.siteUrl);
  void _changed() {
    if (mounted) {
      setState(() {
        if (!_current) {
          _value = null;
          ++_generation;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _epoch = widget.services.actions.epochFor(widget.reader.siteUrl);
    widget.reader.addListener(_changed);
    widget.services.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final lease = widget.services.requests.capture(widget.reader.siteUrl);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credentials = await widget.services.requests.credentialsFor(
        widget.reader.siteUrl,
      );
      if (!lease.isCurrent || !_current) return;
      final value = await widget.services.api.voters(
        siteUrl: widget.reader.siteUrl,
        postId: widget.postId,
        credentials: credentials,
      );
      if (mounted && generation == _generation && lease.isCurrent && _current) {
        setState(() => _value = value);
      }
    } catch (error) {
      if (mounted && generation == _generation && lease.isCurrent && _current) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.reader.removeListener(_changed);
    widget.services.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    if (_loading) return const Center(child: DSpinner());
    if (_error != null) {
      return DAlert(
        description: DAlertDescription(child: Text(postVotingError(_error!))),
        action: DAlertAction(
          child: DButton(label: Text(context.l10n.retry), onPressed: _load),
        ),
      );
    }
    final value = _value;
    if (value == null || value.total == 0) {
      return Text(context.l10n.postVotingNoVoters);
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final direction in PostVoteDirection.values) ...[
            DLabel(
              child: Text(
                direction == PostVoteDirection.up
                    ? context.l10n.postVotingUpvotes
                    : context.l10n.postVotingDownvotes,
              ),
            ),
            for (final item in value.users.where(
              (item) => item.direction == direction,
            ))
              UserCardTarget(
                siteUrl: widget.reader.siteUrl,
                username: item.user.username,
                child: Row(
                  spacing: 8,
                  children: [
                    DAvatar(
                      size: DAvatarSize.sm,
                      fallback: DAvatarFallback(
                        child: Text(
                          item.user.username.characters.first.toUpperCase(),
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        item.user.name?.isNotEmpty == true
                            ? item.user.name!
                            : item.user.username,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (value.total > value.users.length)
            Text(
              context.l10n.postVotingMoreVoters(
                value.total - value.users.length,
              ),
            ),
        ],
      ),
    );
  }
}
