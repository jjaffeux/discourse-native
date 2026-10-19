import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/found_user.dart';
import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'post_mutation_feedback.dart';
import 'shell_controller.dart';

Future<void> showTopicChangeOwner({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required int topicId,
  required List<Post> selectedPosts,
  bool usesTopicSelection = true,
}) async {
  final current = capturePostMutationPresentation(context, controller, siteUrl);
  final target = controller.captureTopicPostOwnerTarget(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: usesTopicSelection ? null : selectedPosts.single.id,
  );
  final dialogKey = GlobalKey<_TopicChangeOwnerDialogState>();
  final outcome = await showDDialog<PostMutationOutcome>(
    context: context,
    dismissOnBarrier: false,
    canDismiss: () => !(dialogKey.currentState?._saving ?? false),
    builder: (context, dialog) => _TopicChangeOwnerDialog(
      key: dialogKey,
      controller: controller,
      onClose: (outcome) => dialog.close(outcome),
      target: target,
      selectedPosts: selectedPosts,
      usesTopicSelection: usesTopicSelection,
    ),
  );
  if (outcome != null && context.mounted) {
    showPostMutationFeedback(context, outcome, isCurrent: current);
  }
}

class _TopicChangeOwnerDialog extends StatefulWidget {
  const _TopicChangeOwnerDialog({
    super.key,
    required this.controller,
    required this.onClose,
    required this.target,
    required this.selectedPosts,
    required this.usesTopicSelection,
  });

  final ShellController controller;
  final ValueChanged<PostMutationOutcome?> onClose;
  final TopicPostOwnerTarget target;
  final List<Post> selectedPosts;
  final bool usesTopicSelection;

  @override
  State<_TopicChangeOwnerDialog> createState() =>
      _TopicChangeOwnerDialogState();
}

class _TopicChangeOwnerDialogState extends State<_TopicChangeOwnerDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<FoundUser> _users = const [];
  FoundUser? _selected;
  bool _searching = false;
  bool _saving = false;
  String? _error;
  bool _uncertain = false;
  PostMutationRecovery? _recovery;

  String get _oldUsername => widget.selectedPosts.first.username;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _selected = null;
      _error = null;
      if (value.trim().isEmpty) {
        _users = const [];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (value.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final users = await widget.controller.searchTopicPostOwnerUsers(
        widget.target,
        value,
      );
      if (!mounted || generation != _generation) return;
      final available = users
          .where((user) => user.username != _oldUsername)
          .toList();
      setState(() {
        _searching = false;
        _users = List.unmodifiable(available);
        if (_users.length == 1) _selected = _users.single;
      });
    });
  }

  Future<void> _changeOwner() async {
    final selected = _selected;
    if (_saving || _uncertain || _searching || selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final outcome = widget.usesTopicSelection
        ? await widget.controller.changeSelectedTopicPostOwner(
            widget.target,
            selected.username,
          )
        : await widget.controller.changeTopicPostOwner(
            widget.target,
            selected.username,
          );
    if (!mounted) return;
    if (outcome is PostMutationAccepted &&
            outcome.projection != PostProjectionFreshness.retired ||
        outcome is PostMutationNoChange) {
      _saving = false;
      widget.onClose(outcome);
      return;
    }
    setState(() {
      _saving = false;
      _uncertain = postMutationRequiresNewIntent(outcome);
      _recovery = postMutationRecoveryOf(outcome);
      _error = postMutationMessage(
        context,
        outcome,
        retiredMessage:
            context.l10n.yourConnectionChangedReopenChangeOwnerAndTryAgain,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.selectedPosts.length;
    return DDialogContent(
      key: const ValueKey('topic-change-owner-dialog'),
      semanticLabel: context.l10n.changePostOwner,
      showCloseButton: false,
      maxWidth: 528,
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text(context.l10n.changePostOwner)),
            DDialogDescription(
              child: Text(
                context.l10n.assignByToAnotherAccount(
                  count,
                  (_oldUsername).toString(),
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DInput(
                key: const ValueKey('topic-change-owner-search'),
                controller: _search,
                autofocus: true,
                enabled: !_saving,
                onChanged: _scheduleSearch,

                labelText: context.l10n.searchUsers,
                prefix: const DIcon(DIcons.magnifyingGlass),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _searching
                    ? const SizedBox.shrink()
                    : _users.isEmpty
                    ? Center(
                        child: Text(
                          _search.text.trim().isEmpty
                              ? context.l10n.searchForTheNewOwner
                              : context.l10n.noUsersFound,
                        ),
                      )
                    : DRadioGroup<FoundUser>.controlled(
                        groupValue: _selected,
                        enabled: !_saving,
                        onChanged: (value) {
                          // A query edit and a tap can arrive before rebuilding
                          // hides the old rows. Reject that retired choice now.
                          if (_saving ||
                              _searching ||
                              !_users.contains(value)) {
                            return;
                          }
                          setState(() => _selected = value);
                        },
                        child: ListView(
                          key: const ValueKey('topic-change-owner-results'),
                          children: [
                            for (final user in _users)
                              DRadioGroupItem<FoundUser>(
                                key: ValueKey(
                                  'topic-change-owner-user-${user.username}',
                                ),
                                value: user,
                                trailing: DAvatar(
                                  decorative: true,
                                  child: AvatarImage(
                                    url: user.avatarUrl,
                                    size: DAvatarSize.standard.dimension,
                                    fallback: DAvatarFallback(
                                      child: Text(
                                        user.username.characters.first
                                            .toUpperCase(),
                                      ),
                                    ),
                                  ),
                                ),
                                label: Text(user.name ?? user.username),
                                description: user.name == null
                                    ? null
                                    : Text('@${user.username}'),
                              ),
                          ],
                        ),
                      ),
              ),
              if (_error case final error?)
                DAlert(
                  key: const ValueKey('topic-change-owner-error'),
                  variant: DAlertVariant.destructive,
                  description: DAlertDescription(child: Text(error)),
                ),
            ],
          ),
        ),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.cancel),
              onPressed: _saving ? null : () => widget.onClose(null),
              variant: DButtonVariant.outline,
            ),
            if (_recovery case final recovery?)
              PostMutationRecoveryButton(
                recovery: recovery,
                onRefreshed: (projection) => setState(
                  () => _error = postMutationRefreshMessage(
                    context,
                    projection,
                    retiredMessage: context
                        .l10n
                        .yourConnectionChangedReopenChangeOwnerAndTryAgain,
                  ),
                ),
              ),
            DButton(
              key: const ValueKey('topic-change-owner-submit'),
              label: Text(context.l10n.changeOwner),
              onPressed:
                  !_saving && !_uncertain && !_searching && _selected != null
                  ? () => unawaited(_changeOwner())
                  : null,
              variant: DButtonVariant.primary,
              loading: _saving,
            ),
          ],
        ),
      ],
    );
  }
}
