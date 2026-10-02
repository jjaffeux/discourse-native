part of '../group_page.dart';

class _ManageSection extends StatelessWidget {
  const _ManageSection({
    super.key,
    required this.route,
    required this.group,
    required this.data,
    required this.onSelect,
    required this.onSave,
    required this.onLoadMore,
  });

  final GroupRoute route;
  final Group group;
  final GroupPageData data;
  final ValueChanged<GroupRoute> onSelect;
  final GroupManageSubmit? onSave;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!group.canManage) {
      return _GroupState(
        icon: DIcons.lock,
        title: context.l10n.youCannotManageThisGroup,
      );
    }
    final options = <_Subtab>[
      _Subtab(GroupRoute.profile, context.l10n.profile),
      if (!group.automatic)
        _Subtab(GroupRoute.membership, context.l10n.membership),
      _Subtab(GroupRoute.interaction, context.l10n.interaction),
      if (!group.automatic && data.isAdmin && data.smtpEnabled)
        _Subtab(GroupRoute.email, context.l10n.email),
      _Subtab(GroupRoute.categories, context.l10n.categories),
      if (data.taggingEnabled) _Subtab(GroupRoute.tags, context.l10n.tags),
      _Subtab(GroupRoute.logs, context.l10n.logs),
    ];
    final selected = options.any((option) => option.value == route.subsection)
        ? route.subsection!
        : GroupRoute.profile;

    void select(String subsection) => onSelect(
      GroupRoute.detail(
        group.name,
        section: GroupRoute.manage,
        subsection: subsection,
      ),
    );

    final content = selected == GroupRoute.logs
        ? _GroupLogs(
            page: data.logs,
            loading: data.sectionLoading,
            loadingMore: data.loadingMore,
            error: data.sectionError,
            onLoadMore: onLoadMore,
          )
        : FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: _GroupManageForm(
              key: ValueKey(
                'group-manage-form-${group.id}-$selected-'
                '${group.automatic}-${data.currentUserStaff}-${data.isAdmin}-'
                '${group.canAssociateGroups}',
              ),
              group: group,
              currentUserStaff: data.currentUserStaff,
              currentUserAdmin: data.isAdmin,
              subsection: selected,
              onSave: onSave,
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (ContentReadingLane.breakpointWidthOf(
              context,
              constraints.maxWidth,
            ) >=
            _groupDesktopBreakpoint) {
          return ContentReadingLaneWithSidebar(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sidebarWidth: 191,
            sidebar: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 190,
                  child: _SubsectionSidebar(
                    key: const ValueKey('group-manage-sidebar'),
                    title: context.l10n.groupSettings,
                    selected: selected,
                    options: options,
                    iconFor: _manageIcon,
                    onSelect: select,
                  ),
                ),
                DSeparator(
                  orientation: Axis.vertical,
                  space: 1,
                  color: Theme.of(context).shell.divider,
                ),
              ],
            ),
            child: content,
          );
        }
        return Column(
          children: [
            _MobileSubsectionPicker(
              key: const ValueKey('group-manage-picker'),
              title: context.l10n.groupSettings,
              selected: selected,
              options: options,
              iconFor: _manageIcon,
              sheetOptionKeyPrefix: 'group-manage-sheet',
              currentSectionKey: 'group-manage-current-section',
              onSelect: select,
            ),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

DIconData _manageIcon(String subsection) => switch (subsection) {
  GroupRoute.profile => DIcons.user,
  GroupRoute.membership => DIcons.users,
  GroupRoute.interaction => DIcons.comments,
  GroupRoute.email => DIcons.envelope,
  GroupRoute.categories => DIcons.folder,
  GroupRoute.tags => DIcons.tag,
  GroupRoute.logs => DIcons.farClock,
  _ => DIcons.gear,
};

class _GroupManageForm extends StatefulWidget {
  const _GroupManageForm({
    super.key,
    required this.group,
    required this.currentUserStaff,
    required this.currentUserAdmin,
    required this.subsection,
    required this.onSave,
  });

  final Group group;
  final bool currentUserStaff;
  final bool currentUserAdmin;
  final String subsection;
  final GroupManageSubmit? onSave;

  @override
  State<_GroupManageForm> createState() => _GroupManageFormState();
}

class _GroupManageFormState extends State<_GroupManageForm> {
  late final GroupManageController controller;

  @override
  void initState() {
    super.initState();
    controller = GroupManageController(
      group: widget.group,
      currentUserStaff: widget.currentUserStaff,
      currentUserAdmin: widget.currentUserAdmin,
      subsection: widget.subsection,
      onSubmit: widget.onSave,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final snapshot = controller.snapshot;
      return Column(
        children: [
          if (snapshot.error case final error?) _InlineError(message: error),
          Expanded(
            child: ContentReadingLane(
              basePadding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              builder: (context, lane) => ListView(
                key: PageStorageKey('group-manage-${widget.subsection}-scroll'),
                padding: lane.padding,
                children: [
                  Align(
                    alignment: lane.alignment,
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _manageFields(),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: DButton(
                              key: ValueKey('save-group-${widget.subsection}'),
                              label: Text(context.l10n.saveChanges),
                              loading: snapshot.submitting,
                              variant: DButtonVariant.primary,
                              onPressed: snapshot.canSubmit
                                  ? () => unawaited(controller.submit())
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _manageFields() => switch (widget.subsection) {
    GroupRoute.profile => _ProfileFields(
      canEdit: controller.canEditField,
      controllers: controller.textControllers,
      errors: controller.snapshot.fieldErrors,
    ),
    GroupRoute.membership => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormHeading(
          title: appL10n.membership,
          description: appL10n.chooseWhoCanDiscoverAndJoinThisGroup,
        ),
        DSelect<String>.controlled(
          isExpanded: true,
          key: const ValueKey('membership-admission'),
          value: controller.admission,
          label: Text(appL10n.whoCanJoin),
          entries: [
            DSelectOption(
              value: 'closed',
              label: appL10n.invitationOnly,
              child: Text(appL10n.invitationOnly),
            ),
            DSelectOption(
              value: 'request',
              label: appL10n.requestApproval,
              child: Text(appL10n.requestApproval),
            ),
            DSelectOption(
              value: 'free',
              label: appL10n.anyoneCanJoin,
              child: Text(appL10n.anyoneCanJoin),
            ),
          ],
          onChanged: (value) => controller.setAdmission(value ?? 'closed'),
          initialValue: controller.admission,
        ),
        DSwitchTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          title: DLabel(child: Text(appL10n.membersCanLeave)),
          value: controller.publicExit,
          onChanged: controller.setPublicExit,
        ),
        _LevelField(
          label: appL10n.groupVisibility,
          value: controller.visibility,
          onChanged: controller.canEditField('visibility_level')
              ? controller.setVisibility
              : null,
        ),
        _LevelField(
          label: appL10n.memberListVisibility,
          value: controller.membersVisibility,
          onChanged: controller.canEditField('members_visibility_level')
              ? controller.setMembersVisibility
              : null,
        ),
        _textField(
          'membership_request_template',
          appL10n.requestTemplate,
          lines: 4,
        ),
        _textField(
          'automatic_membership_email_domains',
          appL10n.automaticMembershipEmailDomains,
          hint: 'example.com|another.example',
        ),
        _textField(
          'associated_group_ids',
          appL10n.associatedGroupIDs,
          hint: '12, 35',
        ),
        _textField('grant_trust_level', appL10n.grantTrustLevel, numeric: true),
      ],
    ),
    GroupRoute.interaction => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormHeading(
          title: appL10n.interaction,
          description: appL10n.controlMentionsMessagesAndNotificationDefaults,
        ),
        _InteractionLevelField(
          label: appL10n.whoCanMentionThisGroup,
          value: controller.mentionable,
          onChanged: controller.setMentionable,
        ),
        _InteractionLevelField(
          label: appL10n.whoCanMessageThisGroup,
          value: controller.messageable,
          onChanged: controller.setMessageable,
        ),
        _LevelField(
          label: appL10n.defaultNotificationLevel,
          value: controller.defaultNotification,
          onChanged: controller.setDefaultNotification,
        ),
        DSwitchTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          title: DLabel(child: Text(appL10n.publishReadState)),
          subtitle: Text(appL10n.letMembersShareMessageReadState),
          value: controller.publishReadState,
          enabled: controller.canEditField('publish_read_state'),
          onChanged: controller.canEditField('publish_read_state')
              ? controller.setPublishReadState
              : null,
        ),
        _textField('incoming_email', appL10n.incomingEmailAddress),
      ],
    ),
    GroupRoute.email => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormHeading(
          title: appL10n.email,
          description: appL10n.configureTheMailboxUsedByThisGroup,
        ),
        DSwitchTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          title: DLabel(child: Text(appL10n.enableSMTP)),
          value: controller.smtpEnabled,
          enabled: controller.canEditField('smtp_enabled'),
          onChanged: controller.canEditField('smtp_enabled')
              ? controller.setSmtpEnabled
              : null,
        ),
        _textField('smtp_server', appL10n.sMTPServer),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _textField('smtp_port', appL10n.port, numeric: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _textField(
                'smtp_ssl_mode',
                appL10n.sSLMode,
                numeric: true,
              ),
            ),
          ],
        ),
        _textField('email_username', appL10n.username),
        _textField(
          'email_password',
          appL10n.password,
          obscure: true,
          hint: appL10n.leaveBlankToKeepTheExistingPassword,
        ),
        _textField('email_from_alias', appL10n.fromAlias),
        DSwitchTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          title: DLabel(child: Text(appL10n.allowRepliesFromUnknownSenders)),
          value: controller.allowUnknownSenderReplies,
          enabled: controller.canEditField(
            'allow_unknown_sender_topic_replies',
          ),
          onChanged:
              controller.canEditField('allow_unknown_sender_topic_replies')
              ? controller.setAllowUnknownSenderReplies
              : null,
        ),
      ],
    ),
    GroupRoute.categories => _ListNotificationFields(
      title: appL10n.categoryNotifications,
      description: appL10n.enterCommaSeparatedCategoryIDsForEachLevel,
      keys: groupCategoryKeys,
      controllers: controller.textControllers,
    ),
    GroupRoute.tags => _ListNotificationFields(
      title: appL10n.tagNotifications,
      description: appL10n.enterCommaSeparatedTagNamesForEachLevel,
      keys: groupTagKeys,
      controllers: controller.textControllers,
    ),
    _ => const SizedBox.shrink(),
  };

  Widget _textField(
    String key,
    String label, {
    String? hint,
    int lines = 1,
    bool numeric = false,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: lines > 1 && !obscure
        ? DTextarea(
            key: ValueKey('group-field-$key'),
            controller: controller.textController(key),
            minLines: lines,
            maxLines: lines,
            enabled: controller.canEditField(key),
            labelText: label,
            hintText: hint,
          )
        : DInput(
            key: ValueKey('group-field-$key'),
            controller: controller.textController(key),
            enabled: controller.canEditField(key),
            obscureText: obscure,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            labelText: label,
            hintText: hint,
          ),
  );
}

class _ProfileFields extends StatelessWidget {
  const _ProfileFields({
    required this.canEdit,
    required this.controllers,
    required this.errors,
  });

  final bool Function(String key) canEdit;
  final Map<String, TextEditingController> controllers;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, {int lines = 1, String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: lines > 1
              ? DTextarea(
                  key: ValueKey('group-field-$key'),
                  controller: controllers[key],
                  minLines: lines,
                  maxLines: lines,
                  enabled: canEdit(key),
                  labelText: label,
                  hintText: hint,
                  errorText: errors[key],
                )
              : DInput(
                  key: ValueKey('group-field-$key'),
                  controller: controllers[key],
                  enabled: canEdit(key),
                  labelText: label,
                  hintText: hint,
                  errorText: errors[key],
                ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormHeading(
          title: context.l10n.profile,
          description: context.l10n.theNameAndIdentityPeopleSeeAroundTheForum,
        ),
        field('name', context.l10n.groupName),
        field('full_name', context.l10n.fullName),
        field('bio_raw', context.l10n.aboutThisGroup, lines: 6),
        field('title', context.l10n.memberTitle),
        field('flair_icon', context.l10n.flairIcon, hint: 'shield-halved'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: field('flair_bg_color', context.l10n.flairBackground),
            ),
            const SizedBox(width: 12),
            Expanded(child: field('flair_color', context.l10n.flairForeground)),
          ],
        ),
      ],
    );
  }
}

class _ListNotificationFields extends StatelessWidget {
  const _ListNotificationFields({
    required this.title,
    required this.description,
    required this.keys,
    required this.controllers,
  });

  final String title;
  final String description;
  final List<String> keys;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FormHeading(title: title, description: description),
      for (final key in keys)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            style: Theme.of(context).textTheme.bodyMedium,
            key: ValueKey('group-field-$key'),
            controller: controllers[key],
            decoration: InputDecoration(labelText: _fieldLabel(key)),
          ),
        ),
    ],
  );
}

class _FormHeading extends StatelessWidget {
  const _FormHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DText(title, variant: DTextVariant.large, headingLevel: 2),
        const SizedBox(height: 4),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _LevelField extends StatelessWidget {
  const _LevelField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <int>{0, 1, 2, 3, 4, value}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DSelect<int>.controlled(
        isExpanded: true,
        value: value,
        enabled: onChanged != null,
        label: Text(label),
        entries: [
          for (final option in values)
            DSelectOption(
              value: option,
              label: _levelLabel(option),
              child: Text(_levelLabel(option)),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged?.call(next);
        },
        initialValue: value,
      ),
    );
  }
}

class _InteractionLevelField extends StatelessWidget {
  const _InteractionLevelField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <int>{0, 1, 2, 3, 4, 99, value}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DSelect<int>.controlled(
        isExpanded: true,
        value: value,
        label: Text(label),
        entries: [
          for (final option in values)
            DSelectOption(
              value: option,
              label: _levelLabel(option),
              child: Text(_levelLabel(option)),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
        initialValue: value,
      ),
    );
  }
}

class _GroupLogs extends StatelessWidget {
  const _GroupLogs({
    required this.page,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.onLoadMore,
  });

  final GroupLogsPage? page;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    late final Widget body;
    if (page == null) {
      body = error != null
          ? _GroupState(icon: DIcons.triangleExclamation, title: error!)
          : const SizedBox.shrink();
    } else if (page!.logs.isEmpty && !loading) {
      body = _GroupState(
        icon: DIcons.farClock,
        title: context.l10n.noGroupChangesHaveBeenRecorded,
      );
    } else {
      body = ContentReadingLane(
        basePadding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        builder: (context, lane) => ListView.separated(
          key: const PageStorageKey('group-logs-scroll'),
          padding: lane.padding,
          itemCount: page!.logs.length + (!page!.allLoaded ? 1 : 0),
          separatorBuilder: (_, _) => const DSeparator(space: 1),
          itemBuilder: (context, index) {
            if (index == page!.logs.length) {
              return _LoadMoreRow(loading: loadingMore, onPressed: onLoadMore);
            }
            final log = page!.logs[index];
            return Center(
              child: SizedBox(
                width: double.infinity,
                child: ListTile(
                  leading: const DIcon(DIcons.farClock, size: 17),
                  title: Text(_humanizeLog(log.action)),
                  subtitle: Text(
                    [
                      if (log.actingUser case final user?) '@${user.username}',
                      if (log.targetUser case final user?)
                        '→ @${user.username}',
                      ?log.subject,
                      if (log.previousValue != null || log.newValue != null)
                        '${log.previousValue ?? '—'} → ${log.newValue ?? '—'}',
                    ].join('  '),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentReadingLaneBox(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DText(
                context.l10n.logs,
                variant: DTextVariant.large,
                headingLevel: 2,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.membershipAndSettingsChangesForThisGroup,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}
