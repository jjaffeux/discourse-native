import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/json.dart';
import '../../models/post.dart';
import '../../models/topic.dart';
import '../../shell/pill.dart';
import '../../shell/post_action.dart';
import '../../shell/shell_scope.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../site_plugin_api.dart';
import 'assignment.dart';
import 'assignment_sheet.dart';

/// Native presentation and mutation affordances for `discourse-assign`.
///
/// The serializer record is the feature gate. In particular, [canAssign] is
/// never used to hide public assignment state: it controls only the write
/// affordance for the exact topic or post whose serializer supplied it.
final class AssignPlugin
    implements
        SitePlugin,
        PostRecordPlugin<Assignments>,
        TopicRecordPlugin<Assignments>,
        PostDecorationPlugin,
        TopicListMetadataPlugin,
        TopicHeaderPlugin,
        PostMenuPlugin,
        TopicLivePlugin,
        TopicLiveReloadPlugin,
        PostSmallActionPlugin {
  const AssignPlugin();

  static const String assignmentChannel = '/staff/topic-assignment';

  @override
  String get name => 'discourse-assign';

  @override
  PluginDataKey<Assignments> get record => assignmentsDataKey;

  @override
  Assignments? readPost(Map<String, dynamic> json, String siteUrl) =>
      Assignments.fromPostJson(json, siteUrl);

  @override
  Assignments? readTopic(Map<String, dynamic> json, String siteUrl) =>
      Assignments.fromTopicJson(json, siteUrl);

  @override
  Assignments? mergeAfterPostEdit(Assignments? held, Assignments? incoming) =>
      incoming ?? held;

  @override
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  ) {
    final assignments = topic.plugins.get(assignmentsDataKey);
    if (assignments == null || !assignments.hasAssignments) return const [];
    final style = Theme.of(context).textTheme.bodySmall;
    return [
      for (final assignment in assignments.all)
        Semantics(
          container: true,
          label: assignmentSummary(
            assignment,
            assignment.isPostAssignment
                ? _postLabel(assignment.postNumber)
                : 'Topic',
          ),
          child: ExcludeSemantics(
            child: Pill(
              label: _compactLabel(assignment),
              baseStyle: style,
              leading: DIcon(
                assignment.assignee.isGroup ? DIcons.users : DIcons.userPlus,
                size: Pill.iconBoxFor(style),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  List<Widget> topicHeader(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final assignments = topic.plugins.get(assignmentsDataKey);
    final canAssign = _canAssignRecord(
      context,
      siteUrl,
      assignments?.canAssign,
    );
    final hasAssignments = assignments?.hasAssignments == true;
    if (!hasAssignments && !canAssign) {
      return const [];
    }

    final assignmentCount = assignments?.all.length ?? 0;
    final summary = hasAssignments
        ? 'View $assignmentCount '
              '${assignmentCount == 1 ? 'assignment' : 'assignments'}'
        : 'Assign this topic';

    void openAssignments() {
      if (!hasAssignments) {
        unawaited(
          showAssignmentEditor(
            context: context,
            siteUrl: siteUrl,
            target: AssignmentTarget.topic(topic.id),
          ),
        );
        return;
      }
      unawaited(
        _showAssignments(
          context: context,
          siteUrl: siteUrl,
          topic: topic,
          assignments: assignments!,
          canAssign: canAssign,
        ),
      );
    }

    return [
      Semantics(
        button: true,
        label: summary,
        onTap: openAssignments,
        child: ExcludeSemantics(
          child: DButton.iconOnly(
            key: const Key('assign-topic-header'),
            icon: const DIcon(DIcons.userPlus),
            tooltip: hasAssignments ? 'View assignments' : 'Assign topic',
            onPressed: openAssignments,
            variant: DButtonVariant.flat,
          ),
        ),
      ),
    ];
  }

  @override
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    final topicAssignments = topic.plugins.get(assignmentsDataKey);
    final postAssignments = post.plugins.get(assignmentsDataKey);

    if (post.postNumber == 1) {
      if (topicAssignments == null || !topicAssignments.hasAssignments) {
        return const [];
      }
      return [
        _AssignmentRows(
          key: const Key('assign-first-post-assignments'),
          rows: [
            if (topicAssignments.direct case final direct?)
              _AssignmentRowData(
                assignment: direct,
                label: 'Topic',
                onTap:
                    _canAssignRecord(
                      context,
                      siteUrl,
                      topicAssignments.canAssign,
                    )
                    ? () => showAssignmentEditor(
                        context: context,
                        siteUrl: siteUrl,
                        target: AssignmentTarget.topic(topic.id),
                        existing: direct,
                      )
                    : null,
              ),
            for (final assignment in topicAssignments.postAssignments.values)
              _AssignmentRowData(
                assignment: assignment,
                label: _postLabel(assignment.postNumber),
              ),
          ],
        ),
      ];
    }

    // Once a full topic Assign snapshot exists it is authoritative for the
    // indirect post map. This matters after a live unassign: an older Post in
    // the store must not resurrect the assignment the refreshed topic removed.
    final assignment = topicAssignments == null
        ? postAssignments?.direct
        : topicAssignments.forPost(post.id);
    if (assignment == null) return const [];
    final canEdit = _canAssignRecord(
      context,
      siteUrl,
      postAssignments?.canAssign,
    );
    return [
      _AssignmentRows(
        key: Key('assign-post-${post.id}-assignment'),
        rows: [
          _AssignmentRowData(
            assignment: assignment,
            label: _postLabel(assignment.postNumber ?? post.postNumber),
            onTap: canEdit
                ? () => showAssignmentEditor(
                    context: context,
                    siteUrl: siteUrl,
                    target: AssignmentTarget.post(post.id, topicId: topic.id),
                    existing: assignment,
                  )
                : null,
          ),
        ],
      ),
    ];
  }

  @override
  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post,
  ) {
    // Assign treats the first post as the topic target. Never expose a Post
    // write for it, even if a malformed or older serializer says can_assign.
    if (post.postNumber == 1) return PostMenuContribution.none;
    final postAssignments = post.plugins.get(assignmentsDataKey);
    if (!_canAssignRecord(context, siteUrl, postAssignments?.canAssign)) {
      return PostMenuContribution.none;
    }
    final controller = ShellScope.maybeRead(context);
    final topic = controller?.currentTopic;
    if (topic == null) return PostMenuContribution.none;
    final aggregate = topic.plugins.get(assignmentsDataKey);
    final existing = aggregate == null
        ? postAssignments?.direct
        : aggregate.forPost(post.id);
    final currentUser = controller?.currentInstance?.url == siteUrl
        ? controller?.currentInstance?.user
        : null;
    final assignedToCurrentUser = switch (existing?.assignee) {
      final AssignmentUser assignee when currentUser != null =>
        (assignee.id != null && assignee.id == currentUser.id) ||
            assignee.username.toLowerCase() ==
                currentUser.username.toLowerCase(),
      _ => false,
    };

    return PostMenuContribution(
      entries: [
        PostAction(
          icon: existing == null ? DIcons.userPlus : DIcons.pencil,
          // Core's Assign button is collapsed unless the post is assigned to
          // the current reader, in which case the quick action stays visible.
          placement: assignedToCurrentUser
              ? PostActionPlacement.toolbar
              : PostActionPlacement.overflow,
          label: existing == null ? 'Assign post' : 'Edit assignment',
          tooltip: existing == null
              ? 'Assign this post'
              : 'Edit this post assignment',
          onInvoke: () => unawaited(
            showAssignmentEditor(
              context: context,
              siteUrl: siteUrl,
              target: AssignmentTarget.post(post.id, topicId: topic.id),
              existing: existing,
            ),
          ),
        ),
      ],
    );
  }

  @override
  List<String> topicChannels(int topicId) => const [assignmentChannel];

  @override
  List<int> stalePosts(String channel, Object? data) => const [];

  @override
  bool staleTopic(int topicId, String channel, Object? data) {
    if (channel != assignmentChannel || data is! Map) return false;
    return jsonIntOrNull(data['topic_id']) == topicId;
  }

  @override
  PluginSmallAction? smallAction(Post post) {
    final code = post.actionCode;
    if (code == null || !_smallActionCodes.contains(code)) return null;
    final who = post.actionCodeWho ?? 'them';
    return PluginSmallAction(
      icon: _smallActionIcon(code),
      phrase: switch (code) {
        'assigned' || 'assigned_group' => 'assigned $who',
        'assigned_to_post' ||
        'assigned_group_to_post' => 'assigned $who to a post',
        'unassigned' || 'unassigned_group' => 'unassigned $who',
        'unassigned_from_post' ||
        'unassigned_group_from_post' => 'unassigned $who from a post',
        'reassigned' || 'reassigned_group' => 'reassigned $who',
        'details_change' => 'changed assignment details for $who',
        'note_change' => 'changed assignment note for $who',
        'status_change' => 'changed assignment status for $who',
        _ => code,
      },
    );
  }

  static const Set<String> _smallActionCodes = {
    'assigned',
    'assigned_group',
    'assigned_to_post',
    'assigned_group_to_post',
    'unassigned',
    'unassigned_group',
    'unassigned_from_post',
    'unassigned_group_from_post',
    'reassigned',
    'reassigned_group',
    'details_change',
    'note_change',
    'status_change',
  };

  static DIconData _smallActionIcon(String code) {
    if (code.startsWith('unassigned')) return DIcons.circleMinus;
    if (code == 'details_change' ||
        code == 'note_change' ||
        code == 'status_change') {
      return DIcons.pencil;
    }
    if (code.contains('group')) return DIcons.users;
    return DIcons.userPlus;
  }
}

class _AssignmentRowData {
  const _AssignmentRowData({
    required this.assignment,
    required this.label,
    this.onTap,
  });

  final Assignment assignment;
  final String label;
  final VoidCallback? onTap;
}

class _AssignmentRows extends StatelessWidget {
  const _AssignmentRows({super.key, required this.rows});

  final List<_AssignmentRowData> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          AssignmentDetailRow(
            assignment: rows[index].assignment,
            targetLabel: rows[index].label,
            onTap: rows[index].onTap,
          ),
        ],
      ],
    ),
  );
}

Future<void> _showAssignments({
  required BuildContext context,
  required String siteUrl,
  required TopicDetail topic,
  required Assignments assignments,
  required bool canAssign,
}) => showShellSheet<void>(
  context: context,
  title: 'Assignments',
  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
  builder: (sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (assignments.direct case final direct?)
        AssignmentDetailRow(
          assignment: direct,
          targetLabel: 'Topic',
          onTap: canAssign
              ? () {
                  Navigator.of(sheetContext).pop();
                  unawaited(
                    showAssignmentEditor(
                      context: context,
                      siteUrl: siteUrl,
                      target: AssignmentTarget.topic(topic.id),
                      existing: direct,
                    ),
                  );
                }
              : null,
        ),
      for (final assignment in assignments.postAssignments.values) ...[
        const SizedBox(height: 8),
        AssignmentDetailRow(
          assignment: assignment,
          targetLabel: _postLabel(assignment.postNumber),
        ),
      ],
      if (assignments.direct == null && canAssign) ...[
        if (assignments.postAssignments.isNotEmpty) const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('assign-topic-from-overview'),
          onPressed: () {
            Navigator.of(sheetContext).pop();
            unawaited(
              showAssignmentEditor(
                context: context,
                siteUrl: siteUrl,
                target: AssignmentTarget.topic(topic.id),
              ),
            );
          },
          icon: const DIcon(DIcons.userPlus),
          label: const Text('Assign topic'),
        ),
      ],
    ],
  ),
);

bool _canAssignRecord(
  BuildContext context,
  String siteUrl,
  bool? targetCanAssign,
) =>
    ShellScope.maybeRead(context)
        ?.canAssignForTarget(siteUrl, targetCanAssign) ??
    targetCanAssign == true;

String _postLabel(int? postNumber) =>
    postNumber == null ? 'Post' : 'Post #$postNumber';

String _compactLabel(Assignment assignment) {
  final prefix = assignment.isPostAssignment
      ? '${_postLabel(assignment.postNumber)} · '
      : '';
  final status = assignment.status?.trim();
  final note = assignment.note?.trim();
  return [
    '$prefix${assignment.assignee.displayName}',
    if (status != null && status.isNotEmpty) status,
    if (note != null && note.isNotEmpty) note,
  ].join(' · ');
}
