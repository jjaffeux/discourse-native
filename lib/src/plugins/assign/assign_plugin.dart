import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'assign_data.dart';
import 'assign_global_search.dart';
import 'assign_group_data.dart';
import 'assign_icons.dart';
import 'assign_notifications.dart';
import 'assign_services.dart';
import 'assign_user_menu.dart';
import 'assigned_group_view.dart';
import 'assignment.dart';
import 'assignment_actions.dart';
import 'assignment_sheet.dart';
import 'assignment_topic_list.dart';

export 'assign_data.dart';

/// Uses serializer presence as the feature gate; [AssignCurrentUser.canAssign]
/// controls only the target-scoped write affordance, never public assignment
/// visibility.
final class AssignPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        GlobalSearchPlugin,
        IconCatalogPlugin,
        SiteSettingsPlugin<AssignSettings>,
        CurrentUserPlugin<AssignCurrentUser>,
        GroupRecordPlugin<AssignGroupData>,
        GroupTabPlugin,
        PostRecordPlugin<Assignments>,
        TopicRecordPlugin<Assignments>,
        PostDecorationPlugin,
        PostHeaderPlugin,
        PostCardTonePlugin,
        TopicListMetadataPlugin,
        CompactTopicListMetadataPlugin,
        TopicPropertiesPlugin,
        TopicPropertiesRebuildPlugin,
        PostMenuPlugin,
        TopicLivePlugin,
        TopicLiveReloadPlugin,
        UserMenuSectionPlugin,
        NotificationFeedPlugin,
        NotificationTypePlugin,
        PostSmallActionPlugin {
  @override
  List<GlobalSearchContribution> get searchContributions => const [
    AssignGlobalSearch(),
  ];

  const AssignPlugin();

  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      runtimeType == AssignPlugin ? AssignPlugin.new : null;

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
  List<PluginNotificationFeedSource> get notificationFeeds => [
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
        label: appL10n.assignList,
        badge: unreadCount,
        notificationTypes: assignNotificationFeed.filterByTypes,
        linkWhenActive: fullListPath,
        builder: (buildContext, actions) => AssignUserMenuNotifications(
          siteUrl: context.siteUrl,
          onOpened: actions.onDismiss,
          unreadCount: unreadCount,
          viewAllPath: fullListPath,
        ),
        sliverBuilder: (buildContext, actions) =>
            AssignUserMenuNotifications.sliver(
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
      label: appL10n.assigned,
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
  Assignments? readTopic(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) => Assignments.fromTopicJson(json, siteUrl);

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
    final style = Theme.of(context).textTheme.labelMedium;
    final grouped = <(bool, String), List<Assignment>>{};
    for (final assignment in assignments.all) {
      grouped
          .putIfAbsent((
            assignment.assignee.isGroup,
            assignment.assignee.identifier,
          ), () => [])
          .add(assignment);
    }
    return [
      Text(context.l10n.assignedToAssignmenttopiclist, style: style),
      for (final group in grouped.values)
        Semantics(
          container: true,
          label: group
              .map(
                (assignment) => assignmentSummary(
                  assignment,
                  assignment.isPostAssignment
                      ? _postLabel(assignment.postNumber)
                      : context.l10n.topic,
                ),
              )
              .join('; '),
          child: ExcludeSemantics(
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AssignmentAssigneeAvatar(
                  assignee: group.first.assignee,
                  size: 20,
                ),
                Text(group.first.assignee.displayName, style: style),
                if (group.first.assignee.isGroup)
                  Text(context.l10n.groupAssignplugin, style: style),
                Text(
                  group
                      .map(
                        (assignment) => assignment.isPostAssignment
                            ? (_validPostNumber(assignment) == null
                                  ? 'post'
                                  : '#${assignment.postNumber}')
                            : 'topic',
                      )
                      .join(', '),
                  style: style,
                ),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  List<Widget> compactTopicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
    void Function({String? property}) onOpen,
  ) {
    final assignments = topic.plugins.get(assignmentsDataKey);
    if (assignments == null || !assignments.hasAssignments) return const [];
    return [
      AssignmentTopicListSummary(
        assignments: assignments,
        onOpen: () => onOpen(property: context.l10n.assignments),
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
    // The topic first, then each post in order, as the shortcut lists them.
    final all = [?direct, ...postAssignments];
    if (all.isEmpty && !canAssign) return const [];

    final navigation = PluginUiScope.maybe(
      context,
      assignGroupNavigationService,
    );
    final controller = PluginUiScope.maybe(
      context,
      assignmentControllerService,
    );

    Widget row(Assignment assignment) {
      final postId = assignment.postId;
      final postNumber = _validPostNumber(assignment);
      final rowTarget = !assignment.isPostAssignment
          ? target
          : postId == null || postId <= 0
          ? null
          : AssignmentTarget.post(postId, topicId: topic.id);
      return _TopicAssignmentRow(
        key: Key(
          assignment.isPostAssignment
              ? 'assign-topic-property-post-${postId ?? 'unknown'}'
              : 'assign-topic-property',
        ),
        siteUrl: siteUrl,
        target: rowTarget,
        assignment: assignment,
        postNumber: postNumber,
        canManage:
            rowTarget != null &&
            (identical(rowTarget, target)
                ? canAssign
                : _canAssignRecord(context, siteUrl, rowTarget, null)),
        writing:
            rowTarget != null &&
            controller?.isWriting(siteUrl, rowTarget) == true,
        onOpenTarget:
            assignment.isPostAssignment &&
                navigation != null &&
                postNumber != null
            ? () => navigation.openTopicPost(
                siteUrl: siteUrl,
                topicId: topic.id,
                postNumber: postNumber,
              )
            : null,
      );
    }

    void assignTopic(BuildContext anchor, {VoidCallback? before}) => unawaited(
      pickAssignee(
        context: anchor,
        siteUrl: siteUrl,
        target: target,
        existing: direct,
        before: before,
      ),
    );

    final first = all.firstOrNull;
    return [
      TopicPropertySection(
        label: appL10n.assignments,
        layout: TopicPropertySectionLayout.standalone,
        showHeader: false,
        values: [
          for (final (index, assignment) in all.indexed) ...[
            if (index > 0) const _AssignmentRule(),
            row(assignment),
          ],
          // Only posts given out: the topic can still be.
          if (direct == null && canAssign) ...[
            if (all.isNotEmpty) const _AssignmentRule(),
            Builder(
              builder: (anchor) => DItem(
                key: const Key('assign-topic-button'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 10,
                ),
                gap: 10,
                shape: DItemShape.menu,
                onPressed: () =>
                    assignTopic(anchor, before: DPopoverClose.maybeOf(anchor)),
                children: [
                  const DItemMedia(
                    variant: DItemMediaVariant.icon,
                    child: DIcon(DIcons.userPlus),
                  ),
                  DItemContent(
                    children: [DItemTitle(child: Text(appL10n.assignTopic))],
                  ),
                ],
              ),
            ),
          ],
        ],
        // Pressed with nothing assigned it picks who; otherwise the host opens
        // the section's details, which list every assignment.
        compactAction: TopicPropertyHeaderAction(
          key: const Key('assign-topic-header'),
          icon: first == null
              ? const DIcon(DIcons.userPlus)
              : AssignmentAssigneeAvatar(assignee: first.assignee, size: 18),
          label: switch (all.length) {
            0 => appL10n.assignTopic,
            1 => appL10n.assignedToName(first!.assignee.displayName),
            final count => appL10n.assignmentCount(count),
          },
          onSelected: all.isEmpty ? assignTopic : null,
        ),
        header: (anchorContext, showDetails) => Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (direct != null || canAssign)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: DButton(
                  key: const Key('assign-topic-header'),
                  icon: direct == null
                      ? const DIcon(DIcons.userPlus)
                      : AssignmentAssigneeAvatar(
                          assignee: direct.assignee,
                          size: DAvatarSize.sm.dimension,
                        ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          direct == null
                              ? appL10n.assignTopic
                              : direct.assignee.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (direct != null) ...[
                        const SizedBox(width: 6),
                        const DIcon(DIcons.chevronDown),
                      ],
                    ],
                  ),
                  tooltip: direct == null
                      ? appL10n.assignTopic
                      : appL10n.manageAssignmentTo(direct.assignee.displayName),
                  size: DButtonSize.regular,
                  variant: DButtonVariant.outline,
                  onPressed: direct != null
                      ? showDetails
                      : canAssign
                      ? () => assignTopic(anchorContext)
                      : null,
                ),
              ),
            if (postAssignments.isNotEmpty)
              DButton(
                key: const Key('assign-topic-header-details'),
                icon: const DIcon(DIcons.userPlus),
                label: Text(appL10n.assignedPost(postAssignments.length)),
                tooltip: appL10n.manageAssignments,
                size: DButtonSize.regular,
                variant: DButtonVariant.ghost,
                onPressed: showDetails,
              ),
          ],
        ),
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
  Color? postCardTone(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) => _assignmentOf(topic, post) == null
      ? null
      : DTokens.of(context).foreground;

  /// The first post is the topic, so its news says the topic's assignment;
  /// a post's own is said in a note box under what it says.
  @override
  List<Widget> postHeaders(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    if (post.postNumber != 1) return const [];
    final topicAssignments = topic.plugins.get(assignmentsDataKey);
    final direct = topicAssignments?.direct;
    if (direct == null) return const [];
    final target = AssignmentTarget.topic(topic.id);
    final details = assignmentDetails(direct);
    return [
      _assignmentPermissionBuilder(
        context: context,
        siteUrl: siteUrl,
        target: target,
        recordPermission: topicAssignments?.canAssign,
        builder: (canEdit) => DAlert.postNotice(
          key: const Key('assign-topic-news'),
          icon: AssignmentAssigneeAvatar(assignee: direct.assignee, size: 30),
          tone: DTokens.of(context).foreground,
          message: Text(appL10n.topicAssignedTo(direct.assignee.displayName)),
          body: details == null ? null : Text(details),
          action: canEdit
              ? DAlertAction(
                  child: AssignmentEditButton(
                    siteUrl: siteUrl,
                    target: target,
                    assignment: direct,
                    unassignedMessage: appL10n.unassignedFromTopic,
                  ),
                )
              : null,
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
    if (post.postNumber == 1) return const [];
    final assignment = _assignmentOf(topic, post);
    if (assignment == null) return const [];
    final target = AssignmentTarget.post(post.id, topicId: topic.id);
    return [
      _assignmentPermissionBuilder(
        context: context,
        siteUrl: siteUrl,
        target: target,
        recordPermission: post.plugins.get(assignmentsDataKey)?.canAssign,
        builder: (canEdit) => PostAssignmentNote(
          key: Key('assign-post-${post.id}-assignment'),
          siteUrl: siteUrl,
          target: target,
          assignment: assignment,
          postNumber: assignment.postNumber ?? post.postNumber,
          canEdit: canEdit,
        ),
      ),
    ];
  }

  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final context = menu.buildContext;
    final siteUrl = menu.siteUrl;
    final post = menu.post;
    final topic = menu.topic;
    // The only controller state this menu reads is the site's permission.
    // The assignment it names is the post's and topic's records, whose
    // changes already redraw this post; the controller would redraw every
    // post's action bar at the start and end of any post's write.
    final permissionChanges = PluginUiScope.maybe(
      context,
      assignmentControllerService,
    )?.permissionChanges(siteUrl);
    if (topic == null) {
      return PostMenuContribution(rebuildOn: permissionChanges);
    }
    // The first post is the topic, so it assigns the topic, as the shortcut
    // at the foot does.
    final first = post.postNumber == 1;
    final target = first
        ? AssignmentTarget.topic(topic.id)
        : AssignmentTarget.post(post.id, topicId: topic.id);
    final record = first
        ? topic.plugins.get(assignmentsDataKey)
        : post.plugins.get(assignmentsDataKey);
    if (!_canAssignRecord(context, siteUrl, target, record?.canAssign)) {
      return PostMenuContribution(rebuildOn: permissionChanges);
    }
    final existing = _assignmentOf(topic, post);

    PostAction action(DIconData icon, String label, VoidCallback invoke) =>
        PostAction(
          icon: icon,
          placement: PostActionPlacement.overflow,
          label: label,
          tooltip: label,
          onInvoke: invoke,
          onInvokeAnchored: (_) => invoke(),
        );

    void pick() => unawaited(
      pickAssignee(
        context: context,
        siteUrl: siteUrl,
        target: target,
        existing: existing,
      ),
    );

    return PostMenuContribution(
      rebuildOn: permissionChanges,
      entries: [
        if (existing == null)
          action(
            DIcons.userPlus,
            first ? appL10n.assignTopic : appL10n.assignPost,
            pick,
          )
        else ...[
          if (first) action(DIcons.userPen, appL10n.reassignTopic, pick),
          action(
            DNativeIcons.userMinus,
            first ? appL10n.unassignFromTopicAction : appL10n.unassignFromPost,
            () => unawaited(
              unassignAssignment(
                context: context,
                siteUrl: siteUrl,
                target: target,
                assignment: existing,
                message: first
                    ? appL10n.unassignedFromTopic
                    : appL10n.unassigned,
              ),
            ),
          ),
        ],
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
        'assigned' ||
        'assigned_group' => appL10n.assignedAssignplugin((who).toString()),
        'assigned_to_post' ||
        'assigned_group_to_post' => appL10n.assignedToAPost((who).toString()),
        'unassigned' ||
        'unassigned_group' => appL10n.unassignedAssignplugin((who).toString()),
        'unassigned_from_post' || 'unassigned_group_from_post' =>
          appL10n.unassignedFromAPost((who).toString()),
        'reassigned' ||
        'reassigned_group' => appL10n.reassigned((who).toString()),
        'details_change' => appL10n.changedAssignmentDetailsFor(
          (who).toString(),
        ),
        'note_change' => appL10n.changedAssignmentNoteFor((who).toString()),
        'status_change' => appL10n.changedAssignmentStatusFor((who).toString()),
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

/// What the topic or [post] is assigned to: the first post stands for the
/// topic. A full topic snapshot must prevent stale stored posts from
/// resurrecting assignments removed by a live refresh.
Assignment? _assignmentOf(TopicDetail topic, Post post) {
  final topicAssignments = topic.plugins.get(assignmentsDataKey);
  if (post.postNumber == 1) return topicAssignments?.direct;
  return topicAssignments == null
      ? post.plugins.get(assignmentsDataKey)?.direct
      : topicAssignments.forPost(post.id);
}

class _AssignmentRule extends StatelessWidget {
  const _AssignmentRule();

  @override
  Widget build(BuildContext context) =>
      DSeparator(space: 1, thickness: 1, color: DTokens.of(context).border);
}

/// One assignment in the topic's list: whose face, what was given to them
/// and their name as Discourse has it, then a round pencil to give it to
/// someone else and a round button in the danger tone to take it back.
class _TopicAssignmentRow extends StatelessWidget {
  const _TopicAssignmentRow({
    super.key,
    required this.siteUrl,
    required this.target,
    required this.assignment,
    required this.postNumber,
    required this.canManage,
    required this.writing,
    this.onOpenTarget,
  });

  final String siteUrl;
  final AssignmentTarget? target;
  final Assignment assignment;
  final int? postNumber;
  final bool canManage;
  final bool writing;
  final VoidCallback? onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final assignee = assignment.assignee;
    final isPost = assignment.isPostAssignment;
    final number = postNumber;
    final targetLabel = isPost ? _postLabel(number) : appL10n.topic;
    final target = this.target;
    final postId = assignment.postId;
    final open = onOpenTarget;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: assignmentSummary(assignment, targetLabel),
      child: DItem(
        key: open == null || postId == null
            ? null
            : Key('assign-post-$postId-target'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        gap: 12,
        shape: DItemShape.menu,
        onPressed: open,
        link: open != null,
        semanticLabel: open == null
            ? null
            : appL10n.openAssignplugin(targetLabel),
        children: [
          DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: ExcludeSemantics(
              child: AssignmentAssigneeAvatar(assignee: assignee, size: 36),
            ),
          ),
          DItemContent(
            spacing: 0,
            children: [
              ExcludeSemantics(
                child: Text(
                  !isPost
                      ? appL10n.assignedTopicTo
                      : number == null
                      ? appL10n.assignedPostTo
                      : appL10n.assignedPostNumberTo(number),
                  style: TextStyle(
                    fontSize: DiscourseTypography.xs,
                    color: tokens.mutedForeground,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  assigneeHandle(assignee),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DiscourseTypography.sm,
                    fontWeight: FontWeight.w600,
                    color: tokens.foreground,
                  ),
                ),
              ),
            ],
          ),
          if (canManage && target != null)
            DItemActions(
              children: [
                Builder(
                  builder: (anchor) => DButton.iconOnly(
                    key: postId == null
                        ? const Key('assign-topic-change')
                        : Key('assign-post-$postId-change'),
                    icon: const DIcon(DIcons.pencil),
                    tooltip: isPost
                        ? appL10n.reassignPost
                        : appL10n.reassignTopic,
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.filter,
                    shape: DButtonShape.pill,
                    onPressed: writing
                        ? null
                        : () => unawaited(
                            pickAssignee(
                              context: anchor,
                              siteUrl: siteUrl,
                              target: target,
                              existing: assignment,
                              before: DPopoverClose.maybeOf(anchor),
                            ),
                          ),
                  ),
                ),
                Builder(
                  builder: (anchor) => DButton.iconOnly(
                    key: postId == null
                        ? const Key('assign-topic-remove')
                        : Key('assign-post-$postId-remove'),
                    icon: const DIcon(DNativeIcons.userMinus),
                    tooltip: isPost
                        ? appL10n.unassignNameFromPost(assignee.displayName)
                        : appL10n.unassignFromTopic(assignee.displayName),
                    semanticLabel: !isPost
                        ? appL10n.unassignFromTopic(assignee.displayName)
                        : number == null
                        ? appL10n.unassignNameFromPost(assignee.displayName)
                        : appL10n.unassignNameFromPostNumber(
                            assignee.displayName,
                            number,
                          ),
                    variant: DButtonVariant.destructive,
                    // The danger tone itself at 18%, as the mockup's round
                    // unassign is, rather than the variant's lighter wash.
                    backgroundColor: tokens.destructive.withValues(
                      alpha: tokens.destructive.a * .18,
                    ),
                    size: DButtonSize.filter,
                    shape: DButtonShape.pill,
                    loading: writing,
                    onPressed: () => unawaited(
                      unassignAssignment(
                        context: anchor,
                        siteUrl: siteUrl,
                        target: target,
                        assignment: assignment,
                        message: !isPost
                            ? appL10n.unassignedFromTopic
                            : number == null
                            ? appL10n.unassigned
                            : appL10n.unassignedFromPostNumber(number),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
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
  // Not the controller: it notifies for every write, and a topic holds one
  // row per assigned post.
  return ListenableBuilder(
    listenable: controller.permissionChanges(siteUrl),
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

String _postLabel(int? postNumber) => postNumber == null
    ? appL10n.post
    : appL10n.postAssignplugin((postNumber).toString());

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
