import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import 'person_picker.dart';
import 'post_mutation_feedback.dart';
import 'shell_controller.dart';

/// Gives [selectedPosts] to whoever is pressed in the people picker, at once:
/// only people, as a group cannot own a post. What went wrong is toasted,
/// with a refresh where the outcome needs one.
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
  final oldUsername = selectedPosts.first.username;
  final pick = await showPersonPicker(
    context: context,
    title: appL10n.changePostOwner,
    ask: appL10n.changeOwnerTo,
    note: appL10n.chooseWhoPostsBelongTo(selectedPosts.length),
    groups: false,
    search: (term) async {
      if (term.isEmpty) return const [];
      final users = await controller.searchTopicPostOwnerUsers(target, term);
      return [
        for (final user in users)
          if (user.username != oldUsername)
            PersonPick.user(
              user.username,
              fullName: user.name,
              avatarUrl: user.avatarUrl,
            ),
      ];
    },
  );
  // The target was captured when the picker opened, so the write stands
  // even when the post it was opened from has scrolled or navigated away.
  if (pick == null) return;
  final outcome = usesTopicSelection
      ? await controller.changeSelectedTopicPostOwner(target, pick.name)
      : await controller.changeTopicPostOwner(target, pick.name);
  if (!context.mounted || !current()) return;
  if (outcome case PostMutationAccepted(
    projection: PostProjectionFreshness.fresh,
  )) {
    DToast.maybeOf(context)?.add(
      DToastOptions(
        description: appL10n.ownerChangedTo(pick.fullName ?? pick.name),
        type: DToastType.success,
      ),
    );
    return;
  }
  showPostMutationFeedback(context, outcome, isCurrent: current);
}
