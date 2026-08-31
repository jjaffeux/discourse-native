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
  final Future<void> Function(GroupManageUpdate)? onSave;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!group.canManage) {
      return const _GroupState(
        icon: DIcons.lock,
        title: 'You cannot manage this group.',
      );
    }
    final options = <_Subtab>[
      const _Subtab(GroupRoute.profile, 'Profile'),
      if (!group.automatic) const _Subtab(GroupRoute.membership, 'Membership'),
      const _Subtab(GroupRoute.interaction, 'Interaction'),
      if (!group.automatic && data.smtpEnabled)
        const _Subtab(GroupRoute.email, 'Email'),
      const _Subtab(GroupRoute.categories, 'Categories'),
      if (data.taggingEnabled) const _Subtab(GroupRoute.tags, 'Tags'),
      const _Subtab(GroupRoute.logs, 'Logs'),
    ];
    final selected = options.any((option) => option.value == route.subsection)
        ? route.subsection!
        : GroupRoute.profile;

    return Column(
      children: [
        _Subtabs(
          selected: selected,
          options: options,
          onSelect: (subsection) => onSelect(
            GroupRoute.detail(
              group.name,
              section: GroupRoute.manage,
              subsection: subsection,
            ),
          ),
        ),
        Expanded(
          child: selected == GroupRoute.logs
              ? _GroupLogs(
                  page: data.logs,
                  loading: data.sectionLoading,
                  loadingMore: data.loadingMore,
                  error: data.sectionError,
                  onLoadMore: onLoadMore,
                )
              : _GroupManageForm(
                  key: ValueKey('group-manage-form-${group.id}-$selected'),
                  group: group,
                  subsection: selected,
                  saving: data.saving,
                  onSave: onSave,
                ),
        ),
      ],
    );
  }
}

class _GroupManageForm extends StatefulWidget {
  const _GroupManageForm({
    super.key,
    required this.group,
    required this.subsection,
    required this.saving,
    required this.onSave,
  });

  final Group group;
  final String subsection;
  final bool saving;
  final Future<void> Function(GroupManageUpdate)? onSave;

  @override
  State<_GroupManageForm> createState() => _GroupManageFormState();
}

class _GroupManageFormState extends State<_GroupManageForm> {
  final _formKey = GlobalKey<FormState>();
  late final GroupManageController controller;

  @override
  void initState() {
    super.initState();
    controller = GroupManageController(group: widget.group);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    await controller.save(widget.subsection, widget.onSave);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      builder: (context, lane) => Form(
        key: _formKey,
        child: ListView(
          key: PageStorageKey('group-manage-${widget.subsection}-scroll'),
          padding: lane.padding,
          children: [
            Align(
              alignment: lane.alignment,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _manageFields(),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DButton(
                        key: ValueKey('save-group-${widget.subsection}'),
                        label: const Text('Save changes'),
                        loading: widget.saving,
                        variant: DButtonVariant.primary,
                        onPressed: widget.onSave == null ? null : _save,
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
  );

  Widget _manageFields() => switch (widget.subsection) {
    GroupRoute.profile => _ProfileFields(
      group: widget.group,
      controllers: controller.textControllers,
    ),
    GroupRoute.membership => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Membership',
          description: 'Choose who can discover and join this group.',
        ),
        DropdownButtonFormField<String>(
          key: const ValueKey('membership-admission'),
          initialValue: controller.admission,
          decoration: const InputDecoration(labelText: 'Who can join?'),
          items: const [
            DropdownMenuItem(value: 'closed', child: Text('Invitation only')),
            DropdownMenuItem(value: 'request', child: Text('Request approval')),
            DropdownMenuItem(value: 'free', child: Text('Anyone can join')),
          ],
          onChanged: (value) => controller.setAdmission(value ?? 'closed'),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Members can leave'),
          value: controller.publicExit,
          onChanged: controller.setPublicExit,
        ),
        _LevelField(
          label: 'Group visibility',
          value: controller.visibility,
          onChanged: controller.setVisibility,
        ),
        _LevelField(
          label: 'Member-list visibility',
          value: controller.membersVisibility,
          onChanged: controller.setMembersVisibility,
        ),
        _textField('membership_request_template', 'Request template', lines: 4),
        _textField(
          'automatic_membership_email_domains',
          'Automatic membership email domains',
          hint: 'example.com|another.example',
        ),
        _textField(
          'associated_group_ids',
          'Associated group IDs',
          hint: '12, 35',
        ),
        _textField('grant_trust_level', 'Grant trust level', numeric: true),
      ],
    ),
    GroupRoute.interaction => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Interaction',
          description: 'Control mentions, messages, and notification defaults.',
        ),
        _InteractionLevelField(
          label: 'Who can mention this group?',
          value: controller.mentionable,
          onChanged: controller.setMentionable,
        ),
        _InteractionLevelField(
          label: 'Who can message this group?',
          value: controller.messageable,
          onChanged: controller.setMessageable,
        ),
        _LevelField(
          label: 'Default notification level',
          value: controller.defaultNotification,
          onChanged: controller.setDefaultNotification,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Publish read state'),
          subtitle: const Text('Let members share message read state.'),
          value: controller.publishReadState,
          onChanged: controller.setPublishReadState,
        ),
        _textField('incoming_email', 'Incoming email address'),
      ],
    ),
    GroupRoute.email => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Email',
          description: 'Configure the mailbox used by this group.',
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable SMTP'),
          value: controller.smtpEnabled,
          onChanged: controller.setSmtpEnabled,
        ),
        _textField('smtp_server', 'SMTP server'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _textField('smtp_port', 'Port', numeric: true)),
            const SizedBox(width: 12),
            Expanded(
              child: _textField('smtp_ssl_mode', 'SSL mode', numeric: true),
            ),
          ],
        ),
        _textField('email_username', 'Username'),
        _textField(
          'email_password',
          'Password',
          obscure: true,
          hint: 'Leave blank to keep the existing password',
        ),
        _textField('email_from_alias', 'From alias'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow replies from unknown senders'),
          value: controller.allowUnknownSenderReplies,
          onChanged: controller.setAllowUnknownSenderReplies,
        ),
      ],
    ),
    GroupRoute.categories => _ListNotificationFields(
      title: 'Category notifications',
      description: 'Enter comma-separated category IDs for each level.',
      keys: groupCategoryKeys,
      controllers: controller.textControllers,
    ),
    GroupRoute.tags => _ListNotificationFields(
      title: 'Tag notifications',
      description: 'Enter comma-separated tag names for each level.',
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
    child: TextFormField(
      key: ValueKey('group-field-$key'),
      controller: controller.textController(key),
      minLines: obscure ? 1 : lines,
      maxLines: obscure ? 1 : lines,
      obscureText: obscure,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

class _ProfileFields extends StatelessWidget {
  const _ProfileFields({required this.group, required this.controllers});

  final Group group;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, {int lines = 1, String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            key: ValueKey('group-field-$key'),
            controller: controllers[key],
            minLines: lines,
            maxLines: lines,
            enabled: key != 'name' || !group.automatic,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: key == 'name'
                ? (value) => value == null || value.trim().isEmpty
                      ? 'Enter a group name.'
                      : null
                : null,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Profile',
          description: 'The name and identity people see around the forum.',
        ),
        field('name', 'Group name'),
        field('full_name', 'Full name'),
        field('bio_raw', 'About this group', lines: 6),
        field('title', 'Member title'),
        field('flair_icon', 'Flair icon', hint: 'shield-halved'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field('flair_bg_color', 'Flair background')),
            const SizedBox(width: 12),
            Expanded(child: field('flair_color', 'Flair foreground')),
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
        Text(title, style: Theme.of(context).textTheme.titleLarge),
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
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <int>{0, 1, 2, 3, 4, value}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in values)
            DropdownMenuItem(value: option, child: Text(_levelLabel(option))),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
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
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in values)
            DropdownMenuItem(value: option, child: Text(_levelLabel(option))),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
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
    if (page == null) {
      if (error != null) {
        return _GroupState(icon: DIcons.triangleExclamation, title: error!);
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (page!.logs.isEmpty && !loading) {
      return const _GroupState(
        icon: DIcons.farClock,
        title: 'No group changes have been recorded.',
      );
    }
    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      builder: (context, lane) => ListView.separated(
        key: const PageStorageKey('group-logs-scroll'),
        padding: lane.padding,
        itemCount: page!.logs.length + (!page!.allLoaded ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == page!.logs.length) {
            return _LoadMoreRow(loading: loadingMore, onPressed: onLoadMore);
          }
          final log = page!.logs[index];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListTile(
                leading: const DIcon(DIcons.farClock, size: 17),
                title: Text(_humanizeLog(log.action)),
                subtitle: Text(
                  [
                    if (log.actingUser case final user?) '@${user.username}',
                    if (log.targetUser case final user?) '→ @${user.username}',
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
}
