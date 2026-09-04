import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/json.dart';
import '../../models/post.dart';
import '../../models/topic.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/inline_action.dart';
import '../../shell/pill.dart';
import '../../shell/post_action.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'assign_data.dart';
import 'assign_group_data.dart';
import 'assign_icons.dart';
import 'assign_notifications.dart';
import 'assign_services.dart';
import 'assign_user_menu.dart';
import 'assigned_group_view.dart';
import 'assignment.dart';
import 'assignment_controller.dart';
import 'assignment_sheet.dart';

export 'assign_data.dart';

/// Uses serializer presence as the feature gate; [canAssign] controls only the
/// target-scoped write affordance, never public assignment visibility.
final class AssignPlugin
    implements
        SitePlugin,
        IconCatalogPlugin,
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
        UserMenuSectionPlugin,
        NotificationFeedPlugin,
        NotificationTypePlugin,
        PostSmallActionPlugin {
  const AssignPlugin();

  static const String assignmentChannel = '/staff/topic-assignment';
  static const PluginUserMenuSectionId notificationsSection =
      PluginUserMenuSectionId(
        owner: PluginId('discourse-assign'),
        name: 'assign-list',
      );

  @override
  String get name => 'discourse-assign';

  @override
  PluginIconCatalog get iconCatalog => assignIconCatalog;

  @override
  List<PluginNotificationType> get notificationTypes => assignNotificationTypes;

  @override
  List<PluginNotificationFeedSource> get notificationFeeds => const [
    assignNotificationFeed,
  ];

  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) {
    if (context.user.canAssign != true ||
        context.user.canAssignGlobally != true) {
      return const [];
    }
    final unreadCount = context.unreadCountFor(
      AssignNotificationTypes.assigned,
    );
    final fullListPath =
        '/u/${Uri.encodeComponent(context.user.username)}/activity/assigned';
    return [
      PluginUserMenuSection(
        id: notificationsSection,
        icon: DIcons.userPlus,
        label: 'Assign list',
        badge: unreadCount,
        linkWhenActive: fullListPath,
        builder: (buildContext, actions) => AssignUserMenuNotifications(
          siteUrl: context.siteUrl,
          onOpened: actions.onDismiss,
          unreadCount: unreadCount,
          viewAllPath: fullListPath,
        ),
      ),
    ];
  }

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
    final controller = PluginUiScope.maybe(
      context,
      assignmentControllerService,
    );

    Widget postAssignmentRow(Assignment assignment) {
      final postId = assignment.postId;
      final postNumber = _validPostNumber(assignment);
      final postTarget = postId == null || postId <= 0
          ? null
          : AssignmentTarget.post(postId, topicId: topic.id);
      final canManage =
          postTarget != null &&
          _canAssignRecord(context, siteUrl, postTarget, null);
      final writing =
          postTarget != null &&
          controller?.isWriting(siteUrl, postTarget) == true;
      final targetLabel = _postLabel(postNumber);

      return _TopicAssignmentPropertyRow(
        key: Key('assign-topic-property-post-${postId ?? 'unknown'}'),
        assignment: assignment,
        targetLabel: targetLabel,
        postTargetKey: postId == null
            ? null
            : Key('assign-post-$postId-target'),
        onOpenTarget: navigation != null && postNumber != null
            ? () => navigation.openTopicPost(
                siteUrl: siteUrl,
                topicId: topic.id,
                postNumber: postNumber,
              )
            : null,
        onChange: canManage
            ? (anchorContext) => unawaited(
                showAssignmentEditor(
                  context: anchorContext,
                  anchorContext: anchorContext,
                  siteUrl: siteUrl,
                  target: postTarget,
                  existing: assignment,
                ),
              )
            : null,
        onRemove: canManage
            ? (anchorContext) => unawaited(
                _removeAssignment(
                  context: anchorContext,
                  siteUrl: siteUrl,
                  target: postTarget,
                  assignment: assignment,
                  targetLabel: targetLabel,
                ),
              )
            : null,
        changeKey: postId == null ? null : Key('assign-post-$postId-change'),
        removeKey: postId == null ? null : Key('assign-post-$postId-remove'),
        writing: writing,
      );
    }

    return [
      TopicPropertySection(
        label: 'Assignments',
        layout: TopicPropertySectionLayout.standalone,
        showHeader: false,
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
          else if (direct != null)
            _TopicAssignmentPropertyRow(
              key: const Key('assign-topic-property'),
              assignment: direct,
              targetLabel: 'Topic',
              onChange: canAssign
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
              onRemove: canAssign
                  ? (anchorContext) => unawaited(
                      _removeAssignment(
                        context: anchorContext,
                        siteUrl: siteUrl,
                        target: target,
                        assignment: direct,
                        targetLabel: 'Topic',
                      ),
                    )
                  : null,
              changeKey: const Key('assign-topic-change'),
              removeKey: const Key('assign-topic-remove'),
              writing: controller?.isWriting(siteUrl, target) == true,
            ),
          if (postAssignments.isNotEmpty)
            _PostAssignmentLedger(
              showTopDivider: direct != null || canAssign,
              rows: [
                for (final assignment in postAssignments)
                  postAssignmentRow(assignment),
              ],
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
  Widget build(BuildContext context) => Builder(
    builder: (anchorContext) => SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: DButton(
          key: const Key('assign-topic-button'),
          label: const Text('Assign topic'),
          icon: const DIcon(DIcons.userPlus),
          variant: DButtonVariant.primary,
          semanticLabel: 'Topic unassigned. Assign topic',
          borderRadius: BorderRadius.circular(9),
          onPressed: () => onTap(anchorContext),
        ),
      ),
    ),
  );
}

class _PostAssignmentLedger extends StatelessWidget {
  const _PostAssignmentLedger({
    required this.rows,
    required this.showTopDivider,
  });

  final List<Widget> rows;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTopDivider)
          Divider(height: 1, thickness: 1, color: dividerColor),
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index < rows.length - 1)
            Divider(height: 1, thickness: 1, color: dividerColor),
        ],
      ],
    );
  }
}

class _TopicAssignmentPropertyRow extends StatelessWidget {
  const _TopicAssignmentPropertyRow({
    super.key,
    required this.assignment,
    required this.targetLabel,
    this.postTargetKey,
    this.onOpenTarget,
    this.onChange,
    this.onRemove,
    this.changeKey,
    this.removeKey,
    this.writing = false,
  });

  final Assignment assignment;
  final String targetLabel;
  final Key? postTargetKey;
  final VoidCallback? onOpenTarget;
  final ValueChanged<BuildContext>? onChange;
  final ValueChanged<BuildContext>? onRemove;
  final Key? changeKey;
  final Key? removeKey;
  final bool writing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPost = assignment.isPostAssignment;
    final eyebrowStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final handleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    final actionTarget = isPost ? targetLabel : 'topic';
    final openTarget = onOpenTarget;
    final targetIsLink = isPost && openTarget != null;
    final identity = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                text: 'Assigned to',
                children: [
                  if (isPost) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: targetLabel,
                      style: targetIsLink
                          ? TextStyle(color: theme.colorScheme.primary)
                          : null,
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: eyebrowStyle,
            ),
            const SizedBox(height: 2),
            Text(
              '@${assignment.assignee.identifier}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: handleStyle,
            ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: assignmentSummary(assignment, targetLabel),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: isPost ? 7 : 4),
        child: Row(
          children: [
            ExcludeSemantics(
              child: AssignmentAssigneeAvatar(
                assignee: assignment.assignee,
                size: isPost ? 30 : 34,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: openTarget != null
                  ? Tooltip(
                      message: 'Open $targetLabel',
                      child: InlineAction.link(
                        key: postTargetKey,
                        onTap: openTarget,
                        semanticLabel: 'Open $targetLabel',
                        excludeChildSemantics: true,
                        borderRadius: BorderRadius.circular(4),
                        child: identity,
                      ),
                    )
                  : ExcludeSemantics(child: identity),
            ),
            if (onChange != null || onRemove != null) ...[
              const SizedBox(width: 5),
              Builder(
                builder: (anchorContext) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onChange != null)
                      if (isPost)
                        DButton.iconOnly(
                          key: changeKey,
                          icon: const DIcon(DIcons.arrowsRotate, size: 13),
                          tooltip: 'Change assignee',
                          semanticLabel: 'Change $actionTarget assignment',
                          variant: DButtonVariant.transparent,
                          size: DButtonSize.small,
                          onPressed: writing
                              ? null
                              : () => onChange!(anchorContext),
                        )
                      else
                        DButton(
                          key: changeKey,
                          label: const Text('Change'),
                          tooltip: 'Change assignee',
                          semanticLabel: 'Change topic assignment',
                          variant: DButtonVariant.transparent,
                          size: DButtonSize.small,
                          onPressed: writing
                              ? null
                              : () => onChange!(anchorContext),
                        ),
                    if (onRemove != null)
                      DButton.iconOnly(
                        key: removeKey,
                        icon: const DIcon(DIcons.xmark, size: 13),
                        tooltip: 'Remove assignment',
                        semanticLabel: 'Remove $actionTarget assignment',
                        variant: DButtonVariant.transparentDanger,
                        size: DButtonSize.small,
                        loading: writing,
                        onPressed: () => onRemove!(anchorContext),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _removeAssignment({
  required BuildContext context,
  required String siteUrl,
  required AssignmentTarget target,
  required Assignment assignment,
  required String targetLabel,
}) async {
  final controller = PluginUiScope.maybe(context, assignmentControllerService);
  if (controller == null || controller.isWriting(siteUrl, target)) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await controller.unassignForUndo(siteUrl, target, assignment);
  if (messenger == null || !messenger.mounted) return;
  if (result.error case final error?) {
    messenger.showSnackBar(SnackBar(content: Text(error)));
    return;
  }
  final permit = result.permit;
  if (permit == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text('$targetLabel assignment removed'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => unawaited(
          _restoreAssignment(
            messenger: messenger,
            controller: controller,
            permit: permit,
          ),
        ),
      ),
    ),
  );
}

Future<void> _restoreAssignment({
  required ScaffoldMessengerState messenger,
  required AssignmentController controller,
  required AssignmentRestorePermit permit,
}) async {
  final error = await controller.restoreAssignment(permit);
  if (error == null || !messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(error)));
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
