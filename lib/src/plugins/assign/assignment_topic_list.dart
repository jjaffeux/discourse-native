import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'assignment.dart';
import 'assignment_sheet.dart';

/// Read-only assignment visibility is independent of permission to reassign.
class AssignmentTopicListSummary extends StatelessWidget {
  const AssignmentTopicListSummary({
    super.key,
    required this.assignments,
    required this.onOpen,
  });

  final Assignments assignments;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final all = assignments.all.toList(growable: false);
    if (all.isEmpty) return const SizedBox.shrink();
    final first = all.first;
    return Wrap(
      spacing: DSpacing.xs,
      runSpacing: DSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.l10n.assignedToAssignmenttopiclist,
          style: TextStyle(color: DTokens.of(context).mutedForeground),
        ),
        _Assignee(assignment: first),
        if (all.length > 1)
          DButton(
            onPressed: onOpen,
            size: DButtonSize.small,
            variant: DButtonVariant.ghost,
            semanticLabel: context.l10n.openTopicToViewAllAssignments(
              (all.length).toString(),
            ),
            tooltip: context.l10n.viewAllAssignmentsInTopic(
              (all.length).toString(),
            ),
            label: Text('+${all.length - 1}'),
          ),
      ],
    );
  }
}

class _Assignee extends StatelessWidget {
  const _Assignee({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final target = assignment.isPostAssignment
        ? assignment.postNumber == null
              ? 'post'
              : '#${assignment.postNumber}'
        : 'topic';
    return DTooltip(
      message: assignmentSummary(assignment, target),
      child: Semantics(
        container: true,
        label: assignmentSummary(assignment, target),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AssignmentAssigneeAvatar(assignee: assignment.assignee, size: 18),
              const SizedBox(width: DSpacing.xs),
              Flexible(
                child: Text(
                  assignment.assignee.displayName,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
              if (assignment.isPostAssignment) ...[
                const SizedBox(width: DSpacing.xs),
                Text(
                  target,
                  style: TextStyle(color: DTokens.of(context).mutedForeground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
