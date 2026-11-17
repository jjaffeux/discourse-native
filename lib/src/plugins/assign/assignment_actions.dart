import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import 'assign_services.dart';
import 'assignment.dart';
import 'assignment_controller.dart';
import 'assignment_sheet.dart';
import 'assignment_write_feedback.dart';

/// Who a topic or post goes to, picked in one press: the one pressed is the
/// assignee, and the write follows the sheet closing. A reassignment keeps
/// the assignment's note and status, which `showAssignmentEditor` edits.
///
/// [before] runs once everything the write needs is read from [context], so
/// a list the picker was opened from can put itself away first.
Future<void> pickAssignee({
  required BuildContext context,
  required String siteUrl,
  required AssignmentTarget target,
  Assignment? existing,
  VoidCallback? before,
}) async {
  final controller = PluginUiScope.require(
    context,
    assignmentControllerService,
  );
  final toast = DToast.maybeOf(context);
  final host = before == null
      ? context
      : Navigator.of(context, rootNavigator: true).context;
  before?.call();
  final session = controller.beginPicker(siteUrl, target);
  final topic = target.type == AssignmentTargetType.topic;
  final reassign = existing != null;
  final assignees = <PersonPick, AssignmentAssignee>{};
  PersonPick remember(AssignmentAssignee assignee) {
    final pick = personPickOf(assignee);
    assignees[pick] = assignee;
    return pick;
  }

  final chosen = existing == null ? null : remember(existing.assignee);
  Future<AssignmentSuggestions>? suggestions;
  final pick = await showPersonPicker(
    context: host,
    title: topic
        ? (reassign ? appL10n.reassignTopic : appL10n.assignTopic)
        : (reassign ? appL10n.reassignPost : appL10n.assignPost),
    ask: topic
        ? (reassign ? appL10n.reassignTopicTo : appL10n.assignTopicTo)
        : (reassign ? appL10n.reassignPostTo : appL10n.assignPostTo),
    note: topic
        ? appL10n.chooseWhoLooksAfterTopic
        : appL10n.chooseWhoLooksAfterPost,
    chosen: chosen,
    search: (term) async {
      if (!controller.isPickerCurrent(session)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final loaded = await (suggestions ??= controller.suggestions(
        session.siteUrl,
        session.target,
      ));
      final found = term.isEmpty
          ? loaded.initialAssignees
          : await controller.search(
              session.siteUrl,
              session.target,
              loaded,
              term,
            );
      return [for (final assignee in found) remember(assignee)];
    },
  );
  if (pick == null || pick == chosen) return;
  final assignee = assignees[pick];
  if (assignee == null || !controller.isPickerCurrent(session)) return;
  final result = await controller.assign(
    session.siteUrl,
    session.target,
    assignee,
    note: existing?.note,
    status: existing?.status,
  );
  if (toast == null || toast.isDisposed) return;
  if (assignmentWriteMessage(result) case final error?) {
    toast.add(DToastOptions(description: error, type: DToastType.error));
    return;
  }
  if (result.kind != AssignmentWriteKind.applied) return;
  toast.add(
    DToastOptions(
      description: topic
          ? appL10n.assignedTopicToName(assignee.displayName)
          : appL10n.assignedToName(assignee.displayName),
      type: DToastType.success,
    ),
  );
}

/// Takes [assignment] back from [target] and says [message], with a moment
/// to undo it.
Future<void> unassignAssignment({
  required BuildContext context,
  required String siteUrl,
  required AssignmentTarget target,
  required Assignment assignment,
  required String message,
}) async {
  final controller = PluginUiScope.maybe(context, assignmentControllerService);
  if (controller == null || controller.isWriting(siteUrl, target)) return;
  final toast = DToast.maybeOf(context);
  final result = await controller.unassignForUndo(siteUrl, target, assignment);
  if (toast?.isDisposed != false) return;
  if (assignmentWriteMessage(result.outcome) case final error?) {
    toast!.add(DToastOptions(description: error, type: DToastType.error));
    return;
  }
  final permit = result.permit;
  if (permit == null) return;
  toast!.add(
    DToastOptions(
      description: message,
      type: DToastType.success,
      action: DToastAction(
        label: appL10n.undo,
        dismissOnPressed: true,
        onPressed: () => unawaited(_restore(toast, controller, permit)),
      ),
    ),
  );
}

Future<void> _restore(
  DToastController toast,
  AssignmentController controller,
  AssignmentRestorePermit permit,
) async {
  final result = await controller.restoreAssignment(permit);
  final error = assignmentWriteMessage(result);
  if (error == null || toast.isDisposed) return;
  toast.add(DToastOptions(description: error, type: DToastType.error));
}

PersonPick personPickOf(AssignmentAssignee assignee) => switch (assignee) {
  AssignmentUser(:final username, :final name, :final avatarUrl) =>
    PersonPick.user(username, fullName: name, avatarUrl: avatarUrl),
  AssignmentGroup(:final name, :final fullName) => PersonPick.group(
    name,
    fullName: fullName,
  ),
};

/// Who an assignment is with as Discourse names them: a person by their
/// handle, a group by its name.
String assigneeHandle(AssignmentAssignee assignee) => switch (assignee) {
  AssignmentUser(:final username) => '@$username',
  AssignmentGroup(:final name) => name,
};

/// What is said about an assignment past who has it, when anything is.
String? assignmentDetails(Assignment assignment) {
  final parts = [
    if (assignment.status?.trim() case final status? when status.isNotEmpty)
      status,
    if (assignment.note?.trim() case final note? when note.isNotEmpty) note,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The pencil on an assignment, the same on the topic's and on a post's: it
/// gives the assignment to someone else, takes it back, or opens its note and
/// status.
class AssignmentEditButton extends StatelessWidget {
  const AssignmentEditButton({
    super.key,
    required this.siteUrl,
    required this.target,
    required this.assignment,
    required this.unassignedMessage,
  });

  final String siteUrl;
  final AssignmentTarget target;
  final Assignment assignment;
  final String unassignedMessage;

  @override
  Widget build(BuildContext context) {
    final topic = target.type == AssignmentTargetType.topic;
    final name = assignment.assignee.displayName;
    final statuses = PluginUiScope.maybe(
      context,
      assignmentControllerService,
    )?.statusOptions(siteUrl);
    final hasNote = assignment.note?.trim().isNotEmpty ?? false;
    return DDropdownMenu(
      content: DDropdownMenuContent(
        children: [
          DDropdownMenuItem(
            key: const ValueKey('assignment-reassign'),
            leading: const DIcon(DIcons.userPen),
            onPressed: () => unawaited(
              pickAssignee(
                context: context,
                siteUrl: siteUrl,
                target: target,
                existing: assignment,
              ),
            ),
            child: Text(topic ? appL10n.reassignTopic : appL10n.reassignPost),
          ),
          DDropdownMenuItem(
            key: const ValueKey('assignment-unassign'),
            leading: const DIcon(DNativeIcons.userMinus),
            onPressed: () => unawaited(
              unassignAssignment(
                context: context,
                siteUrl: siteUrl,
                target: target,
                assignment: assignment,
                message: unassignedMessage,
              ),
            ),
            child: Text(
              topic
                  ? appL10n.unassignFromTopic(name)
                  : appL10n.unassignNameFromPost(name),
            ),
          ),
          DDropdownMenuItem(
            key: const ValueKey('assignment-details'),
            leading: const DIcon(DIcons.pencil),
            onPressed: () => unawaited(
              showAssignmentEditor(
                context: context,
                siteUrl: siteUrl,
                target: target,
                existing: assignment,
              ),
            ),
            child: Text(
              statuses?.enabled == true
                  ? appL10n.editNoteAndStatus
                  : hasNote
                  ? appL10n.editNote
                  : appL10n.addANote,
            ),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, menu) => DButton.iconOnly(
          key: ValueKey('assignment-edit-${target.type.wireName}-${target.id}'),
          icon: const DIcon(DIcons.pencil),
          tooltip: appL10n.changeAssignmentAction,
          semanticLabel: appL10n.changeAssignmentAction,
          variant: DButtonVariant.ghost,
          density: DButtonDensity.postAction,
          size: DButtonSize.post,
          hasPopup: true,
          expanded: menu.open,
          focusNode: menu.focusNode,
          onPressed: menu.toggle,
        ),
      ),
    );
  }
}

/// Who a post is given to, after what it says and before what can be done
/// to it: their face, the post and their name said in full, their handle
/// under it, and the pencil, in the quiet note box.
class PostAssignmentNote extends StatelessWidget {
  const PostAssignmentNote({
    super.key,
    required this.siteUrl,
    required this.target,
    required this.assignment,
    required this.postNumber,
    required this.canEdit,
  });

  final String siteUrl;
  final AssignmentTarget target;
  final Assignment assignment;
  final int postNumber;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final assignee = assignment.assignee;
    final details = assignmentDetails(assignment);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _ReachPast(
        by: 8,
        child: DItem(
          variant: DItemVariant.note,
          padding: const EdgeInsets.all(8),
          gap: 12,
          semanticLabel: assignmentSummary(
            assignment,
            appL10n.postAssignplugin('$postNumber'),
          ),
          children: [
            DItemMedia(
              variant: DItemMediaVariant.avatar,
              child: AssignmentAssigneeAvatar(assignee: assignee, size: 36),
            ),
            DItemContent(
              spacing: 0,
              children: [
                ExcludeSemantics(
                  child: Text(
                    appL10n.postNumberAssignedTo(
                      postNumber,
                      assignee.displayName,
                    ),
                    style: TextStyle(
                      fontSize: DiscourseTypography.control,
                      color: DAlert.postNoticeColorOf(context),
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: Text(
                    assigneeHandle(assignee),
                    style: TextStyle(
                      fontSize: DiscourseTypography.preview,
                      color: tokens.mutedForeground,
                    ),
                  ),
                ),
                if (details != null)
                  ExcludeSemantics(
                    child: Text(
                      details,
                      style: TextStyle(
                        fontSize: DiscourseTypography.preview,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
            if (canEdit)
              AssignmentEditButton(
                siteUrl: siteUrl,
                target: target,
                assignment: assignment,
                unassignedMessage: appL10n.unassigned,
              ),
          ],
        ),
      ),
    );
  }
}

/// Widens [child] by [by] on either side of the column it is laid out in.
class _ReachPast extends StatelessWidget {
  const _ReachPast({required this.by, required this.child});

  final double by;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => OverflowBox(
      minWidth: constraints.maxWidth + by * 2,
      maxWidth: constraints.maxWidth + by * 2,
      fit: OverflowBoxFit.deferToChild,
      child: child,
    ),
  );
}
