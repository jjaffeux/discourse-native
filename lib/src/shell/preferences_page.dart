import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/user_preferences.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'content_reading_lane.dart';
import 'preferences_controller.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  static const double _wideBreakpoint = 760;
  static const String _forumDefaultTimezoneLabel = 'Forum default';

  final TextEditingController _timezone = TextEditingController();
  final FocusNode _timezoneFocus = FocusNode();
  late final List<String> _timezoneNames;
  late final List<DropdownMenuEntry<String>> _timezoneEntries;

  ShellController? _shell;
  PreferencesController? _preferences;
  bool _hydrationScheduled = false;
  PreferenceSection _selectedSection = PreferenceSection.notifications;

  @override
  void initState() {
    super.initState();
    _timezoneNames = TimezoneEnvironment.instance.timezoneNames.toList()
      ..sort();
    // `DropdownMenu` materialises a button per entry; the IANA list is built
    // once here rather than on every rebuild of the card.
    _timezoneEntries = List.unmodifiable([
      const DropdownMenuEntry(value: '', label: _forumDefaultTimezoneLabel),
      for (final name in _timezoneNames)
        DropdownMenuEntry(value: name, label: name),
    ]);
    _timezoneFocus.addListener(_restoreSelectedTimezoneAfterFiltering);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    if (identical(shell, _shell)) return;
    _preferences?.removeListener(_handlePreferencesChanged);
    _shell = shell;
    _preferences = shell.preferences..addListener(_handlePreferencesChanged);
    _handlePreferencesChanged();
    _hydrate(shell);
  }

  @override
  void didUpdateWidget(PreferencesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl == widget.siteUrl) return;
    _selectedSection = PreferenceSection.notifications;
    _timezone.clear();
    _handlePreferencesChanged();
    final shell = _shell;
    if (shell != null) _hydrate(shell);
  }

  void _hydrate(ShellController shell, {bool refresh = false}) {
    final instance = shell.instanceFor(widget.siteUrl);
    if (instance == null) return;
    unawaited(shell.preferences.load(instance, refresh: refresh));
  }

  void _scheduleHydration() {
    if (_hydrationScheduled) return;
    _hydrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrationScheduled = false;
      if (!mounted) return;
      final shell = _shell;
      if (shell != null && shell.preferences.stateFor(widget.siteUrl) == null) {
        _hydrate(shell);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.identityOf(context);
    return ListenableBuilder(
      listenable: shell.preferences,
      builder: (context, _) => ListenableBuilder(
        listenable: TimezoneEnvironment.instance,
        builder: (context, _) => _buildPage(context, shell),
      ),
    );
  }

  Widget _buildPage(BuildContext context, ShellController shell) {
    final state = shell.preferences.stateFor(widget.siteUrl);
    final instance = shell.instanceFor(widget.siteUrl);
    final draft = state?.draft;

    if (draft == null) {
      if (state?.error case final error?) {
        return _UnavailablePreferences(
          message: error,
          onRetry: instance?.isConnected == true
              ? () => _hydrate(shell, refresh: true)
              : null,
        );
      }
      if (instance == null || !instance.isConnected) {
        return const _UnavailablePreferences(
          message: 'Reconnect to this forum to load preferences.',
        );
      }
      if (state == null) _scheduleHydration();
      return _LoadingPreferences(host: instance.host);
    }

    final editable = draft.canEdit;
    final pluginSections = instance?.user == null
        ? const <PluginUserPreferenceSection>[]
        : shell.plugins.registry.userPreferenceSections(
            context,
            PluginUserPreferenceContext(
              siteUrl: widget.siteUrl,
              preferences: draft,
              siteSettings: instance!.config.plugins,
              currentUserData: instance.user!.plugins,
              currentUserIsAdmin: instance.user!.admin,
              editable: editable,
              onEdit: (change) => shell.preferences.edit(
                widget.siteUrl,
                PreferenceSection.chat,
                change,
              ),
            ),
          );
    final sections = _sectionsFor(draft, pluginSections);
    final selected = _visibleSection(sections);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 232,
                child: _SectionRail(
                  sections: sections,
                  pluginSections: pluginSections,
                  selected: selected,
                  onSelected: _selectSection,
                ),
              ),
              DSeparator(
                orientation: Axis.vertical,
                space: 1,
                thickness: 1,
                color: Theme.of(context).shell.divider,
              ),
              Expanded(
                child: _SectionScroller(
                  key: ValueKey((state!.accountIdentity, selected)),
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: _buildSection(
                      context,
                      shell,
                      instance,
                      state,
                      draft,
                      selected,
                      editable,
                      pluginSections,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return _SectionScroller(
          key: ValueKey((state!.accountIdentity, selected)),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DSelect<PreferenceSection>.controlled(
                  isExpanded: true,
                  key: ValueKey(('preferences-section', selected)),
                  value: selected,
                  label: const Text('Preference section'),
                  entries: [
                    for (final section in sections)
                      DSelectOption(
                        value: section,
                        label: _sectionTitle(section, pluginSections),
                        child: Text(_sectionTitle(section, pluginSections)),
                      ),
                  ],
                  onChanged: (section) {
                    if (section != null) _selectSection(section);
                  },
                  initialValue: selected,
                ),
                const SizedBox(height: 28),
                _buildSection(
                  context,
                  shell,
                  instance,
                  state,
                  draft,
                  selected,
                  editable,
                  pluginSections,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    ShellController shell,
    DiscourseInstance? instance,
    PreferencesState state,
    UserPreferences draft,
    PreferenceSection section,
    bool editable,
    List<PluginUserPreferenceSection> pluginSections,
  ) {
    final dirty = state.dirty(section);
    final canSave =
        instance?.isConnected == true && editable && dirty && !state.saving;

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusAnnouncement(state: state, pluginSections: pluginSections),
          if (state.error != null ||
              state.loading ||
              state.savedSection != null)
            const SizedBox(height: 16),
          switch (section) {
            PreferenceSection.profile => _ProfileForm(
              timezone: _timezone,
              timezoneFocus: _timezoneFocus,
              selectedTimezone: draft.timezone,
              timezoneNames: _timezoneNames,
              timezoneEntries: _timezoneEntries,
              deviceTimezone: TimezoneEnvironment.instance.deviceTimezone,
              enabled: editable,
              onTimezoneChanged: (timezone) => shell.preferences.edit(
                widget.siteUrl,
                PreferenceSection.profile,
                (current) => current.copyWith(timezone: timezone),
              ),
              onUseDeviceTimezone: _useDeviceTimezone,
            ),
            PreferenceSection.notifications => _NotificationsForm(
              preferences: draft,
              enabled: editable,
              onChanged: (change) => shell.preferences.edit(
                widget.siteUrl,
                PreferenceSection.notifications,
                change,
              ),
            ),
            PreferenceSection.tracking => _TrackingForm(
              preferences: draft,
              enabled: editable && draft.canChangeTrackingPreferences,
              onChanged: (change) => shell.preferences.edit(
                widget.siteUrl,
                PreferenceSection.tracking,
                change,
              ),
            ),
            PreferenceSection.interface => _InterfaceForm(
              preferences: draft,
              enabled: editable,
              onBookmarkChanged: (preference) => shell.preferences.edit(
                widget.siteUrl,
                PreferenceSection.interface,
                (current) =>
                    current.copyWith(bookmarkAutoDeletePreference: preference),
              ),
            ),
            PreferenceSection.chat =>
              _pluginSection(PreferenceSection.chat, pluginSections)?.content ??
                  const SizedBox.shrink(),
          },
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: DButton(
              key: ValueKey('preferences-save-${section.name}'),
              label: const Text('Save changes'),
              semanticLabel: state.saving
                  ? 'Saving preferences'
                  : 'Save ${_sectionTitle(section, pluginSections)} preferences',
              onPressed: canSave
                  ? () => _save(shell, instance!, section)
                  : null,
              loading: state.saving,
              loadingLabel: const Text('Saving changes…'),
              variant: DButtonVariant.primary,
            ),
          ),
        ],
      ),
    );
  }

  void _save(
    ShellController shell,
    DiscourseInstance instance,
    PreferenceSection section,
  ) {
    unawaited(shell.preferences.save(instance, section));
  }

  void _useDeviceTimezone() {
    final zone = TimezoneEnvironment.instance.deviceTimezone;
    if (zone == null) return;
    _timezone.value = TextEditingValue(
      text: zone,
      selection: TextSelection.collapsed(offset: zone.length),
    );
    final shell = _shell;
    if (shell == null) return;
    shell.preferences.edit(
      widget.siteUrl,
      PreferenceSection.profile,
      (current) => current.copyWith(timezone: zone),
    );
  }

  void _synchronizeTimezone(String value) {
    if (_timezoneFocus.hasFocus) return;
    final label = value.isEmpty ? _forumDefaultTimezoneLabel : value;
    if (_timezone.text == label) return;
    _timezone.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
  }

  void _restoreSelectedTimezoneAfterFiltering() {
    if (_timezoneFocus.hasFocus) return;
    final value = _preferences?.stateFor(widget.siteUrl)?.draft?.timezone;
    if (value != null) _synchronizeTimezone(value);
  }

  void _handlePreferencesChanged() {
    final value = _preferences?.stateFor(widget.siteUrl)?.draft?.timezone;
    if (value != null) _synchronizeTimezone(value);
  }

  PreferenceSection _visibleSection(List<PreferenceSection> sections) =>
      sections.contains(_selectedSection)
      ? _selectedSection
      : PreferenceSection.notifications;

  List<PreferenceSection> _sectionsFor(
    UserPreferences preferences,
    List<PluginUserPreferenceSection> pluginSections,
  ) => [
    PreferenceSection.profile,
    PreferenceSection.notifications,
    if (preferences.canChangeTrackingPreferences) PreferenceSection.tracking,
    PreferenceSection.interface,
    for (final plugin in pluginSections) plugin.section,
  ];

  void _selectSection(PreferenceSection section) {
    if (_selectedSection == section) return;
    setState(() => _selectedSection = section);
  }

  @override
  void dispose() {
    _preferences?.removeListener(_handlePreferencesChanged);
    _timezoneFocus.removeListener(_restoreSelectedTimezoneAfterFiltering);
    _timezone.dispose();
    _timezoneFocus.dispose();
    super.dispose();
  }
}

class _SectionScroller extends StatelessWidget {
  const _SectionScroller({
    super.key,
    required this.padding,
    required this.child,
  });

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    basePadding: padding,
    builder: (context, lane) => SingleChildScrollView(
      primary: true,
      padding: lane.padding,
      child: Align(alignment: lane.alignment, child: child),
    ),
  );
}

class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.sections,
    required this.pluginSections,
    required this.selected,
    required this.onSelected,
  });

  final List<PreferenceSection> sections;
  final List<PluginUserPreferenceSection> pluginSections;
  final PreferenceSection selected;
  final ValueChanged<PreferenceSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final section in sections)
          _SectionRailItem(
            section: section,
            title: _sectionTitle(section, pluginSections),
            icon: _sectionIcon(section, pluginSections),
            selected: selected == section,
            onTap: () => onSelected(section),
          ),
      ],
    );
  }
}

class _SectionRailItem extends StatelessWidget {
  const _SectionRailItem({
    required this.section,
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final PreferenceSection section;
  final String title;
  final DIconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.shell.selectedForeground
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          key: ValueKey('preferences-section-${section.name}'),
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? theme.shell.selected : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: DIcon(icon, size: 18, color: foreground),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsForm extends StatelessWidget {
  const _NotificationsForm({
    required this.preferences,
    required this.enabled,
    required this.onChanged,
  });

  final UserPreferences preferences;
  final bool enabled;
  final ValueChanged<UserPreferences Function(UserPreferences)> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PreferenceCard(
      children: [
        DSelect<int>.controlled(
          isExpanded: true,
          key: ValueKey((
            'like-notification-frequency',
            preferences.likeNotificationFrequency,
          )),
          value: preferences.likeNotificationFrequency,
          label: const Text('Like notifications'),
          description: const Text(
            'Choose when likes should create a notification.',
          ),
          entries: const [
            DSelectOption(value: 0, label: 'Always', child: Text('Always')),
            DSelectOption(
              value: 1,
              label: 'First time and daily',
              child: Text('First time and daily'),
            ),
            DSelectOption(
              value: 2,
              label: 'First time',
              child: Text('First time'),
            ),
            DSelectOption(value: 3, label: 'Never', child: Text('Never')),
          ],
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  onChanged(
                    (current) =>
                        current.copyWith(likeNotificationFrequency: value),
                  );
                }
              : null,
          initialValue: preferences.likeNotificationFrequency,
          enabled: enabled,
        ),
        const SizedBox(height: 20),
        DSwitchTile(
          key: const ValueKey('notify-on-linked-posts'),
          contentPadding: EdgeInsets.zero,
          title: DLabel(
            enabled: enabled,
            child: const Text('Notify me about replies to linked posts'),
          ),
          subtitle: const Text(
            'Get a notification when someone replies to a post you linked.',
          ),
          value: preferences.notifyOnLinkedPosts,
          onChanged: enabled
              ? (value) => onChanged(
                  (current) => current.copyWith(notifyOnLinkedPosts: value),
                )
              : null,
        ),
      ],
    );
  }
}

class _TrackingForm extends StatelessWidget {
  const _TrackingForm({
    required this.preferences,
    required this.enabled,
    required this.onChanged,
  });

  final UserPreferences preferences;
  final bool enabled;
  final ValueChanged<UserPreferences Function(UserPreferences)> onChanged;

  @override
  Widget build(BuildContext context) {
    return _PreferenceCard(
      children: [
        DSelect<int>.controlled(
          isExpanded: true,
          key: ValueKey((
            'new-topic-duration',
            preferences.newTopicDurationMinutes,
          )),
          value: preferences.newTopicDurationMinutes,
          label: const Text('Consider topics new'),
          description: const Text(
            'Controls which topics appear as new to this account.',
          ),
          entries: const [
            DSelectOption(
              value: -1,
              label: 'Until I view them',
              child: Text('Until I view them'),
            ),
            DSelectOption(
              value: 1440,
              label: 'For one day',
              child: Text('For one day'),
            ),
            DSelectOption(
              value: 2880,
              label: 'For two days',
              child: Text('For two days'),
            ),
            DSelectOption(
              value: 10080,
              label: 'For one week',
              child: Text('For one week'),
            ),
            DSelectOption(
              value: 20160,
              label: 'For two weeks',
              child: Text('For two weeks'),
            ),
            DSelectOption(
              value: -2,
              label: 'Since my last visit',
              child: Text('Since my last visit'),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  onChanged(
                    (current) =>
                        current.copyWith(newTopicDurationMinutes: value),
                  );
                }
              : null,
          initialValue: preferences.newTopicDurationMinutes,
          enabled: enabled,
        ),
        const SizedBox(height: 20),
        DSelect<int>.controlled(
          isExpanded: true,
          key: ValueKey((
            'auto-track-duration',
            preferences.autoTrackTopicsAfterMsecs,
          )),
          value: preferences.autoTrackTopicsAfterMsecs,
          label: const Text('Automatically track topics'),
          description: const Text(
            'Track a topic after you have read it for this long.',
          ),
          entries: const [
            DSelectOption(value: -1, label: 'Never', child: Text('Never')),
            DSelectOption(
              value: 0,
              label: 'Immediately',
              child: Text('Immediately'),
            ),
            DSelectOption(
              value: 30000,
              label: 'After 30 seconds',
              child: Text('After 30 seconds'),
            ),
            DSelectOption(
              value: 60000,
              label: 'After 1 minute',
              child: Text('After 1 minute'),
            ),
            DSelectOption(
              value: 120000,
              label: 'After 2 minutes',
              child: Text('After 2 minutes'),
            ),
            DSelectOption(
              value: 180000,
              label: 'After 3 minutes',
              child: Text('After 3 minutes'),
            ),
            DSelectOption(
              value: 240000,
              label: 'After 4 minutes',
              child: Text('After 4 minutes'),
            ),
            DSelectOption(
              value: 300000,
              label: 'After 5 minutes',
              child: Text('After 5 minutes'),
            ),
            DSelectOption(
              value: 600000,
              label: 'After 10 minutes',
              child: Text('After 10 minutes'),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  onChanged(
                    (current) =>
                        current.copyWith(autoTrackTopicsAfterMsecs: value),
                  );
                }
              : null,
          initialValue: preferences.autoTrackTopicsAfterMsecs,
          enabled: enabled,
        ),
        const SizedBox(height: 20),
        DSelect<int>.controlled(
          isExpanded: true,
          key: ValueKey((
            'reply-notification-level',
            preferences.notificationLevelWhenReplying,
          )),
          value: preferences.notificationLevelWhenReplying,
          label: const Text('When I reply to a topic'),
          description: const Text(
            'Choose the notification level applied after a reply.',
          ),
          entries: const [
            DSelectOption(
              value: 3,
              label: 'Watch the topic',
              child: Text('Watch the topic'),
            ),
            DSelectOption(
              value: 2,
              label: 'Track the topic',
              child: Text('Track the topic'),
            ),
            DSelectOption(
              value: 1,
              label: 'Keep the current level',
              child: Text('Keep the current level'),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  onChanged(
                    (current) =>
                        current.copyWith(notificationLevelWhenReplying: value),
                  );
                }
              : null,
          initialValue: preferences.notificationLevelWhenReplying,
          enabled: enabled,
        ),
      ],
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.timezone,
    required this.timezoneFocus,
    required this.selectedTimezone,
    required this.timezoneNames,
    required this.timezoneEntries,
    required this.deviceTimezone,
    required this.enabled,
    required this.onTimezoneChanged,
    required this.onUseDeviceTimezone,
  });

  final TextEditingController timezone;
  final FocusNode timezoneFocus;
  final String selectedTimezone;
  final List<String> timezoneNames;
  final List<DropdownMenuEntry<String>> timezoneEntries;
  final String? deviceTimezone;
  final bool enabled;
  final ValueChanged<String> onTimezoneChanged;
  final VoidCallback onUseDeviceTimezone;

  @override
  Widget build(BuildContext context) {
    return _PreferenceCard(
      children: [
        DropdownMenu<String>(
          key: const ValueKey('preferences-timezone'),
          controller: timezone,
          focusNode: timezoneFocus,
          enabled: enabled,
          initialSelection: selectedTimezone,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          label: const Text('Timezone'),
          helperText:
              'Type to filter IANA timezones used for dates and reminders.',
          dropdownMenuEntries: timezoneEntries,
          onSelected: enabled
              ? (value) {
                  if (value == null) {
                    _restoreSelectedTimezone();
                  } else {
                    onTimezoneChanged(value);
                  }
                }
              : null,
        ),
        const SizedBox(height: 12),
        DFieldDescription(
          child: Text(
            deviceTimezone == null
                ? 'Device timezone is unavailable.'
                : 'Device timezone: $deviceTimezone',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: DButton(
            key: const ValueKey('preferences-use-device-timezone'),
            label: const Text('Use device timezone'),
            onPressed: enabled && deviceTimezone != null
                ? onUseDeviceTimezone
                : null,
            icon: const DIcon(DIcons.globe, size: 16),
            variant: DButtonVariant.standard,
            size: DButtonSize.small,
          ),
        ),
      ],
    );
  }

  void _restoreSelectedTimezone() {
    final label = selectedTimezone.isEmpty
        ? _PreferencesPageState._forumDefaultTimezoneLabel
        : selectedTimezone;
    timezone.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
  }
}

class _InterfaceForm extends StatelessWidget {
  const _InterfaceForm({
    required this.preferences,
    required this.enabled,
    required this.onBookmarkChanged,
  });

  final UserPreferences preferences;
  final bool enabled;
  final ValueChanged<BookmarkAutoDeletePreference> onBookmarkChanged;

  @override
  Widget build(BuildContext context) {
    return _PreferenceCard(
      children: [
        DSelect<BookmarkAutoDeletePreference>.controlled(
          isExpanded: true,
          key: ValueKey((
            'bookmark-auto-delete',
            preferences.bookmarkAutoDeletePreference,
          )),
          value: preferences.bookmarkAutoDeletePreference,
          label: const Text('Automatically delete bookmarks'),
          description: const Text(
            'Choose what happens after a bookmark reminder.',
          ),
          entries: const [
            DSelectOption(
              value: BookmarkAutoDeletePreference.never,
              label: 'Never',
              child: Text('Never'),
            ),
            DSelectOption(
              value: BookmarkAutoDeletePreference.whenReminderSent,
              label: 'After the reminder is sent',
              child: Text('After the reminder is sent'),
            ),
            DSelectOption(
              value: BookmarkAutoDeletePreference.onOwnerReply,
              label: 'When the topic owner replies',
              child: Text('When the topic owner replies'),
            ),
            DSelectOption(
              value: BookmarkAutoDeletePreference.clearReminder,
              label: 'When the reminder is cleared',
              child: Text('When the reminder is cleared'),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onBookmarkChanged(value);
                }
              : null,
          initialValue: preferences.bookmarkAutoDeletePreference,
          enabled: enabled,
        ),
      ],
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DCard(
      spacing: 20,
      children: [
        DCardContent(
          // Existing section adapters retain their 8/12/20px local spacing.
          child: DFieldGroup(spacing: 0, children: children),
        ),
      ],
    );
  }
}

class _StatusAnnouncement extends StatelessWidget {
  const _StatusAnnouncement({
    required this.state,
    required this.pluginSections,
  });

  final PreferencesState state;
  final List<PluginUserPreferenceSection> pluginSections;

  @override
  Widget build(BuildContext context) {
    final (message, kind) = switch (state) {
      PreferencesState(error: final error?) => (error, _StatusKind.error),
      PreferencesState(savedSection: final section?) => (
        '${_sectionTitle(section, pluginSections)} preferences saved.',
        _StatusKind.success,
      ),
      PreferencesState(loading: true) => (
        'Refreshing preferences…',
        _StatusKind.progress,
      ),
      _ => (null, null),
    };
    if (message == null || kind == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final (icon, foreground, background) = switch (kind) {
      _StatusKind.error => (
        DIcons.triangleExclamation,
        theme.colorScheme.error,
        theme.colorScheme.errorContainer,
      ),
      _StatusKind.success => (
        DIcons.check,
        theme.colorScheme.onPrimaryContainer,
        theme.colorScheme.primaryContainer,
      ),
      _StatusKind.progress => (
        null,
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHigh,
      ),
    };

    return DAlert(
      variant: kind == _StatusKind.error
          ? DAlertVariant.destructive
          : DAlertVariant.normal,
      backgroundColor: background,
      foregroundColor: foreground,
      descriptionColor: foreground,
      borderColor: foreground.withValues(alpha: foreground.a * .2),
      icon: kind == _StatusKind.progress
          ? const SizedBox.square(dimension: 16, child: DSpinner())
          : DIcon(icon!, size: 16),
      description: DAlertDescription(child: Text(message)),
    );
  }
}

enum _StatusKind { error, success, progress }

class _LoadingPreferences extends StatelessWidget {
  const _LoadingPreferences({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: 'Loading preferences from $host.',
    child: const ExcludeSemantics(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DSpinner(),
            SizedBox(height: 16),
            Text('Loading preferences…'),
          ],
        ),
      ),
    ),
  );
}

class _UnavailablePreferences extends StatelessWidget {
  const _UnavailablePreferences({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(
                DIcons.triangleExclamation,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                DButton(
                  key: const ValueKey('preferences-retry'),
                  label: const Text('Try again'),
                  onPressed: onRetry,
                  variant: DButtonVariant.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

PluginUserPreferenceSection? _pluginSection(
  PreferenceSection section,
  List<PluginUserPreferenceSection> pluginSections,
) {
  for (final plugin in pluginSections) {
    if (plugin.section == section) return plugin;
  }
  return null;
}

String _sectionTitle(
  PreferenceSection section,
  List<PluginUserPreferenceSection> pluginSections,
) =>
    _pluginSection(section, pluginSections)?.title ??
    switch (section) {
      PreferenceSection.profile => 'Profile',
      PreferenceSection.notifications => 'Notifications',
      PreferenceSection.tracking => 'Tracking',
      PreferenceSection.interface => 'Interface',
      PreferenceSection.chat => 'Chat',
    };

DIconData _sectionIcon(
  PreferenceSection section,
  List<PluginUserPreferenceSection> pluginSections,
) =>
    _pluginSection(section, pluginSections)?.icon ??
    switch (section) {
      PreferenceSection.profile => DIcons.user,
      PreferenceSection.notifications => DIcons.bell,
      PreferenceSection.tracking => DIcons.list,
      PreferenceSection.interface => DIcons.display,
      PreferenceSection.chat => DIcons.comment,
    };
