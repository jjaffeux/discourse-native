import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/json.dart';
import '../../models/post.dart';
import '../../models/topic.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/pill.dart';
import '../../shell/post_action.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'assign_data.dart';
import 'assign_group_data.dart';
import 'assign_notifications.dart';
import 'assign_services.dart';
import 'assigned_group_view.dart';
import 'assignment.dart';
import 'assignment_sheet.dart';

export 'assign_data.dart';

/// Uses serializer presence as the feature gate; [canAssign] controls only the
/// target-scoped write affordance, never public assignment visibility.
final class AssignPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<AssignSettings>,
        CurrentUserPlugin<AssignCurrentUser>,
        GroupRecordPlugin<AssignGroupData>,
        GroupTabPlugin,
        PostRecordPlugin<Assignments>,
        TopicRecordPlugin<Assignments>,
        PostDecorationPlugin,
        TopicListMetadataPlugin,
        TopicPropertiesPlugin,
        TopicPropertiesRebuildPlugin,
        PostMenuPlugin,
        TopicLivePlugin,
        TopicLiveReloadPlugin,
        NotificationTypePlugin,
        PostSmallActionPlugin {
  const AssignPlugin();

  static const String assignmentChannel = '/staff/topic-assignment';

  @override
  String get name => 'discourse-assign';

  @override
  List<PluginNotificationType> get notificationTypes => assignNotificationTypes;

  @override
  PluginDataPersistenceCodec<AssignSettings> get siteSettingsCodec =>
      assignSettingsPersistenceCodec;

  @override
  AssignSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      AssignSettings.fromWire(json);

  @override
  PluginDataPersistenceCodec<AssignCurrentUser> get currentUserCodec =>
      assignCurrentUserPersistenceCodec;

  @override
  AssignCurrentUser? readCurrentUser(
    Map<String, dynamic> json,
    String siteUrl,
  ) => AssignCurrentUser.fromWire(json);

  @override
  PluginDataKey<AssignGroupData> get groupRecord => assignGroupDataKey;

  @override
  AssignGroupData? readGroup(Map<String, dynamic> json, String siteUrl) =>
      AssignGroupData.fromWire(json);

  @override
  PluginGroupTab? groupTab(PluginGroupContext group) {
    final record = group.groupData.get(assignGroupDataKey);
    final user = group.currentUserData.get(assignCurrentUserDataKey);
    if (record?.canShowAssignedTab != true ||
        record!.assignableLevel <= 0 ||
        !group.canSeeMembers ||
        user?.canAssignGlobally != true) {
      return null;
    }
    return PluginGroupTab(
      section: 'assigned',
      label: 'Assigned',
      icon: DIcons.userPlus,
      count: record.assignmentCount,
    );
  }

  @override
  Widget? groupContent(BuildContext context, PluginGroupContext group) {
    if (group.route.pluginOwner != name || group.route.section != 'assigned') {
      return null;
    }
    return AssignedGroupView(
      siteUrl: group.siteUrl,
      groupName: group.groupName,
      subsection: group.route.subsection,
    );
  }

  @override
  Listenable? groupListenable(BuildContext context, PluginGroupContext group) =>
      PluginUiScope.maybe(context, assignedGroupControllerService);

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
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final assignments = topic.plugins.get(assignmentsDataKey);
    final target = AssignmentTarget.topic(topic.id);
    final canAssign = _canAssignRecord(
      context,
      siteUrl,
      target,
      assignments?.canAssign,
    );
    final direct = assignments?.direct;
    final postAssignments = [...?assignments?.postAssignments.values]
      ..sort(_comparePostAssignments);
    if (direct == null && postAssignments.isEmpty && !canAssign) {
      return const [];
    }

    final navigation = PluginUiScope.maybe(
      context,
      assignGroupNavigationService,
    );
    return [
      TopicPropertySection(
        label: 'Assignments',
        layout: TopicPropertySectionLayout.standalone,
        values: [
          if (direct == null && canAssign)
            _AssignTopicButton(
              key: const Key('assign-topic-property'),
              onTap: (anchorContext) => unawaited(
                showAssignmentEditor(
                  context: anchorContext,
                  anchorContext: anchorContext,
                  siteUrl: siteUrl,
                  target: target,
                ),
              ),
            )
          else
            _TopicAssignmentPropertyRow(
              key: const Key('assign-topic-property'),
              targetLabel: 'Topic',
              assignment: direct,
              actionLabel: canAssign ? 'Edit topic assignment' : null,
              actionIcon: canAssign ? DIcons.pencil : null,
              onTap: canAssign
                  ? (anchorContext) => unawaited(
                      showAssignmentEditor(
                        context: anchorContext,
                        anchorContext: anchorContext,
                        siteUrl: siteUrl,
                        target: target,
                        existing: direct,
                      ),
                    )
                  : null,
            ),
          for (final assignment in postAssignments)
            _TopicAssignmentPropertyRow(
              key: Key(
                'assign-topic-property-post-${assignment.postId ?? 'unknown'}',
              ),
              targetLabel: _postLabel(_validPostNumber(assignment)),
              assignment: assignment,
              actionLabel:
                  navigation != null && _validPostNumber(assignment) != null
                  ? 'Open ${_postLabel(_validPostNumber(assignment))}'
                  : null,
              actionIcon:
                  navigation != null && _validPostNumber(assignment) != null
                  ? DIcons.chevronRight
                  : null,
              onTap: navigation != null && _validPostNumber(assignment) != null
                  ? (_) => navigation.openTopicPost(
                      siteUrl: siteUrl,
                      topicId: topic.id,
                      postNumber: _validPostNumber(assignment)!,
                    )
                  : null,
            ),
        ],
      ),
    ];
  }

  @override
  Listenable? topicPropertiesRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => PluginUiScope.maybe(context, assignmentControllerService);

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
        _assignmentPermissionBuilder(
          context: context,
          siteUrl: siteUrl,
          target: AssignmentTarget.topic(topic.id),
          recordPermission: topicAssignments.canAssign,
          builder: (canEdit) => _AssignmentRows(
            key: const Key('assign-first-post-assignments'),
            rows: [
              if (topicAssignments.direct case final direct?)
                _AssignmentRowData(
                  assignment: direct,
                  label: 'Topic',
                  onTap: canEdit
                      ? (anchorContext) => unawaited(
                          showAssignmentEditor(
                            context: anchorContext,
                            anchorContext: anchorContext,
                            siteUrl: siteUrl,
                            target: AssignmentTarget.topic(topic.id),
                            existing: direct,
                          ),
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
        ),
      ];
    }

    // A full topic snapshot must prevent stale stored posts from resurrecting
    // assignments removed by a live refresh.
    final assignment = topicAssignments == null
        ? postAssignments?.direct
        : topicAssignments.forPost(post.id);
    if (assignment == null) return const [];
    return [
      _assignmentPermissionBuilder(
        context: context,
        siteUrl: siteUrl,
        target: AssignmentTarget.post(post.id, topicId: topic.id),
        recordPermission: postAssignments?.canAssign,
        builder: (canEdit) => _AssignmentRows(
          key: Key('assign-post-${post.id}-assignment'),
          rows: [
            _AssignmentRowData(
              assignment: assignment,
              label: _postLabel(assignment.postNumber ?? post.postNumber),
              onTap: canEdit
                  ? (anchorContext) => unawaited(
                      showAssignmentEditor(
                        context: anchorContext,
                        anchorContext: anchorContext,
                        siteUrl: siteUrl,
                        target: AssignmentTarget.post(
                          post.id,
                          topicId: topic.id,
                        ),
                        existing: assignment,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    ];
  }

  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final context = menu.buildContext;
    final siteUrl = menu.siteUrl;
    final post = menu.post;
    // Assign treats the first post as the topic target, never a post target.
    if (post.postNumber == 1) return PostMenuContribution.none;
    final postAssignments = post.plugins.get(assignmentsDataKey);
    final topic = menu.topic;
    final assignmentController = PluginUiScope.maybe(
      context,
      assignmentControllerService,
    );
    if (topic == null ||
        !_canAssignRecord(
          context,
          siteUrl,
          AssignmentTarget.post(post.id, topicId: topic.id),
          postAssignments?.canAssign,
        )) {
      return PostMenuContribution(rebuildOn: assignmentController);
    }
    final aggregate = topic.plugins.get(assignmentsDataKey);
    final existing = aggregate == null
        ? postAssignments?.direct
        : aggregate.forPost(post.id);
    final currentUser = menu.currentUser;
    final assignedToCurrentUser = switch (existing?.assignee) {
      final AssignmentUser assignee when currentUser != null =>
        (assignee.id != null && assignee.id == currentUser.id) ||
            assignee.username.toLowerCase() ==
                currentUser.username.toLowerCase(),
      _ => false,
    };

    void openEditor({Rect? anchor}) => unawaited(
      showAssignmentEditor(
        context: context,
        anchor: anchor,
        siteUrl: siteUrl,
        target: AssignmentTarget.post(post.id, topicId: topic.id),
        existing: existing,
      ),
    );

    return PostMenuContribution(
      rebuildOn: assignmentController,
      entries: [
        PostAction(
          icon: existing == null ? DIcons.userPlus : DIcons.pencil,
          placement: assignedToCurrentUser
              ? PostActionPlacement.toolbar
              : PostActionPlacement.overflow,
          label: existing == null ? 'Assign post' : 'Edit assignment',
          tooltip: existing == null
              ? 'Assign this post'
              : 'Edit this post assignment',
          onInvoke: openEditor,
          onInvokeAnchored: (anchor) => openEditor(anchor: anchor),
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
  final ValueChanged<BuildContext>? onTap;
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
          Builder(
            builder: (anchorContext) => AssignmentDetailRow(
              assignment: rows[index].assignment,
              targetLabel: rows[index].label,
              onTap: rows[index].onTap == null
                  ? null
                  : () => rows[index].onTap!(anchorContext),
            ),
          ),
        ],
      ],
    ),
  );
}

class _AssignTopicButton extends StatelessWidget {
  const _AssignTopicButton({super.key, required this.onTap});

  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    const shape = StadiumBorder();
    return Align(
      alignment: Alignment.centerLeft,
      child: Builder(
        builder: (anchorContext) => Semantics(
          button: true,
          label: 'Topic unassigned. Assign topic',
          onTap: () => onTap(anchorContext),
          child: ExcludeSemantics(
            child: Tooltip(
              message: 'Assign topic',
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('assign-topic-button'),
                  onTap: () => onTap(anchorContext),
                  mouseCursor: SystemMouseCursors.click,
                  customBorder: shape,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DIcon(DIcons.userPlus, size: 11, color: color),
                        const SizedBox(width: 4),
                        Text(
                          'Assign',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicAssignmentPropertyRow extends StatelessWidget {
  const _TopicAssignmentPropertyRow({
    super.key,
    required this.targetLabel,
    required this.assignment,
    required this.actionLabel,
    required this.actionIcon,
    required this.onTap,
  });

  final String targetLabel;
  final Assignment? assignment;
  final String? actionLabel;
  final DIconData? actionIcon;
  final ValueChanged<BuildContext>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assigneeLabel = assignment?.assignee.displayName ?? 'Unassigned';
    final semanticLabel = [
      if (assignment case final assignment?)
        assignmentSummary(assignment, targetLabel)
      else
        '$targetLabel unassigned',
      ?actionLabel,
    ].join('. ');

    return Builder(
      builder: (anchorContext) {
        final invoke = onTap == null ? null : () => onTap!(anchorContext);
        return Semantics(
          container: true,
          button: invoke != null,
          label: semanticLabel,
          onTap: invoke,
          child: ExcludeSemantics(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: invoke,
                mouseCursor: invoke == null ? null : SystemMouseCursors.click,
                hoverColor: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DIcon(
                        assignment?.assignee.isGroup == true
                            ? DIcons.users
                            : DIcons.userPlus,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          '$targetLabel · $assigneeLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (actionIcon case final actionIcon?) ...[
                        const SizedBox(width: 6),
                        DIcon(
                          actionIcon,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _assignmentPermissionBuilder({
  required BuildContext context,
  required String siteUrl,
  required AssignmentTarget target,
  required bool? recordPermission,
  required Widget Function(bool canAssign) builder,
}) {
  final controller = PluginUiScope.maybe(context, assignmentControllerService);
  if (controller == null) return builder(recordPermission == true);
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => builder(controller.canAssign(siteUrl, target)),
  );
}

bool _canAssignRecord(
  BuildContext context,
  String siteUrl,
  AssignmentTarget target,
  bool? targetCanAssign,
) {
  final controller = PluginUiScope.maybe(context, assignmentControllerService);
  if (controller == null) return targetCanAssign == true;
  return controller.canAssign(siteUrl, target);
}

String _postLabel(int? postNumber) =>
    postNumber == null ? 'Post' : 'Post #$postNumber';

int _comparePostAssignments(Assignment left, Assignment right) {
  final leftNumber = _validPostNumber(left);
  final rightNumber = _validPostNumber(right);
  if (leftNumber != rightNumber) {
    if (leftNumber == null) return 1;
    if (rightNumber == null) return -1;
    return leftNumber.compareTo(rightNumber);
  }
  return (left.postId ?? 0).compareTo(right.postId ?? 0);
}

int? _validPostNumber(Assignment assignment) {
  final postNumber = assignment.postNumber;
  return postNumber != null && postNumber > 0 ? postNumber : null;
}

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
