import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'preferences_controller.dart';
import 'select.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// The connected account's server-backed preference editor.
///
/// The controller owns the draft so navigating between sections, rebuilding,
/// and failed writes never reset a reader's edits. This widget owns only the
/// currently visible section and the filter affordance for the timezone menu.
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

  ShellController? _shell;
  PreferencesController? _preferences;
  PreferenceSection _selectedSection = PreferenceSection.notifications;

  @override
  void initState() {
    super.initState();
    _timezoneNames = TimezoneEnvironment.instance.timezoneNames.toList()
      ..sort();
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
      return _LoadingPreferences(host: instance.host);
    }

    final selected = _visibleSection(draft);
    final editable = draft.canEdit;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 232,
                child: _SectionRail(
                  sections: _sectionsFor(draft),
                  selected: selected,
                  onSelected: _selectSection,
                ),
              ),
              VerticalDivider(
                width: 1,
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
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DSelectField<PreferenceSection>(
                    key: ValueKey(('preferences-section', selected)),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Preference section',
                    ),
                    items: [
                      for (final section in _sectionsFor(draft))
                        DropdownMenuItem(
                          value: section,
                          child: Text(_sectionTitle(section)),
                        ),
                    ],
                    onChanged: (section) {
                      if (section != null) _selectSection(section);
                    },
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
                  ),
                ],
              ),
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
  ) {
    final dirty = state.dirty(section);
    final canSave =
        instance?.isConnected == true && editable && dirty && !state.saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(section: section),
        const SizedBox(height: 24),
        _StatusAnnouncement(state: state),
        if (state.error != null || state.loading || state.savedSection != null)
          const SizedBox(height: 16),
        switch (section) {
          PreferenceSection.profile => _ProfileForm(
            timezone: _timezone,
            timezoneFocus: _timezoneFocus,
            selectedTimezone: draft.timezone,
            timezoneNames: _timezoneNames,
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
        },
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: DButton(
            key: ValueKey('preferences-save-${section.name}'),
            label: const Text('Save changes'),
            semanticLabel: state.saving
                ? 'Saving preferences'
                : 'Save ${_sectionTitle(section)} preferences',
            onPressed: canSave ? () => _save(shell, instance!, section) : null,
            loading: state.saving,
            loadingLabel: const Text('Saving changes…'),
            variant: DButtonVariant.primary,
          ),
        ),
      ],
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

  PreferenceSection _visibleSection(UserPreferences preferences) {
    if (_selectedSection == PreferenceSection.tracking &&
        !preferences.canChangeTrackingPreferences) {
      return PreferenceSection.notifications;
    }
    return _selectedSection;
  }

  List<PreferenceSection> _sectionsFor(UserPreferences preferences) => [
    PreferenceSection.profile,
    PreferenceSection.notifications,
    if (preferences.canChangeTrackingPreferences) PreferenceSection.tracking,
    PreferenceSection.interface,
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
  Widget build(BuildContext context) =>
      SingleChildScrollView(primary: true, padding: padding, child: child);
}

class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<PreferenceSection> sections;
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
    required this.selected,
    required this.onTap,
  });

  final PreferenceSection section;
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
                  child: DIcon(
                    _sectionIcon(section),
                    size: 18,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _sectionTitle(section),
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.section});

  final PreferenceSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            _sectionTitle(section),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _sectionDescription(section),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
        DSelectField<int>(
          key: ValueKey((
            'like-notification-frequency',
            preferences.likeNotificationFrequency,
          )),
          initialValue: preferences.likeNotificationFrequency,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Like notifications',
            helperText: 'Choose when likes should create a notification.',
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Always')),
            DropdownMenuItem(value: 1, child: Text('First time and daily')),
            DropdownMenuItem(value: 2, child: Text('First time')),
            DropdownMenuItem(value: 3, child: Text('Never')),
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
        ),
        const SizedBox(height: 20),
        SwitchListTile.adaptive(
          key: const ValueKey('notify-on-linked-posts'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify me about replies to linked posts'),
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
        DSelectField<int>(
          key: ValueKey((
            'new-topic-duration',
            preferences.newTopicDurationMinutes,
          )),
          initialValue: preferences.newTopicDurationMinutes,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Consider topics new',
            helperText: 'Controls which topics appear as new to this account.',
          ),
          items: const [
            DropdownMenuItem(value: -1, child: Text('Until I view them')),
            DropdownMenuItem(value: 1440, child: Text('For one day')),
            DropdownMenuItem(value: 2880, child: Text('For two days')),
            DropdownMenuItem(value: 10080, child: Text('For one week')),
            DropdownMenuItem(value: 20160, child: Text('For two weeks')),
            DropdownMenuItem(value: -2, child: Text('Since my last visit')),
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
        ),
        const SizedBox(height: 20),
        DSelectField<int>(
          key: ValueKey((
            'auto-track-duration',
            preferences.autoTrackTopicsAfterMsecs,
          )),
          initialValue: preferences.autoTrackTopicsAfterMsecs,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Automatically track topics',
            helperText: 'Track a topic after you have read it for this long.',
          ),
          items: const [
            DropdownMenuItem(value: -1, child: Text('Never')),
            DropdownMenuItem(value: 0, child: Text('Immediately')),
            DropdownMenuItem(value: 30000, child: Text('After 30 seconds')),
            DropdownMenuItem(value: 60000, child: Text('After 1 minute')),
            DropdownMenuItem(value: 120000, child: Text('After 2 minutes')),
            DropdownMenuItem(value: 180000, child: Text('After 3 minutes')),
            DropdownMenuItem(value: 240000, child: Text('After 4 minutes')),
            DropdownMenuItem(value: 300000, child: Text('After 5 minutes')),
            DropdownMenuItem(value: 600000, child: Text('After 10 minutes')),
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
        ),
        const SizedBox(height: 20),
        DSelectField<int>(
          key: ValueKey((
            'reply-notification-level',
            preferences.notificationLevelWhenReplying,
          )),
          initialValue: preferences.notificationLevelWhenReplying,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'When I reply to a topic',
            helperText: 'Choose the notification level applied after a reply.',
          ),
          items: const [
            DropdownMenuItem(value: 3, child: Text('Watch the topic')),
            DropdownMenuItem(value: 2, child: Text('Track the topic')),
            DropdownMenuItem(value: 1, child: Text('Keep the current level')),
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
    required this.deviceTimezone,
    required this.enabled,
    required this.onTimezoneChanged,
    required this.onUseDeviceTimezone,
  });

  final TextEditingController timezone;
  final FocusNode timezoneFocus;
  final String selectedTimezone;
  final List<String> timezoneNames;
  final String? deviceTimezone;
  final bool enabled;
  final ValueChanged<String> onTimezoneChanged;
  final VoidCallback onUseDeviceTimezone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          dropdownMenuEntries: [
            const DropdownMenuEntry(
              value: '',
              label: _PreferencesPageState._forumDefaultTimezoneLabel,
            ),
            for (final name in timezoneNames)
              DropdownMenuEntry(value: name, label: name),
          ],
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
        Text(
          deviceTimezone == null
              ? 'Device timezone is unavailable.'
              : 'Device timezone: $deviceTimezone',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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
        DSelectField<BookmarkAutoDeletePreference>(
          key: ValueKey((
            'bookmark-auto-delete',
            preferences.bookmarkAutoDeletePreference,
          )),
          initialValue: preferences.bookmarkAutoDeletePreference,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Automatically delete bookmarks',
            helperText: 'Choose what happens after a bookmark reminder.',
          ),
          items: const [
            DropdownMenuItem(
              value: BookmarkAutoDeletePreference.never,
              child: Text('Never'),
            ),
            DropdownMenuItem(
              value: BookmarkAutoDeletePreference.whenReminderSent,
              child: Text('After the reminder is sent'),
            ),
            DropdownMenuItem(
              value: BookmarkAutoDeletePreference.onOwnerReply,
              child: Text('When the topic owner replies'),
            ),
            DropdownMenuItem(
              value: BookmarkAutoDeletePreference.clearReminder,
              child: Text('When the reminder is cleared'),
            ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onBookmarkChanged(value);
                }
              : null,
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
    final theme = Theme.of(context);
    return Material(
      color: theme.shell.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.shell.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _StatusAnnouncement extends StatelessWidget {
  const _StatusAnnouncement({required this.state});

  final PreferencesState state;

  @override
  Widget build(BuildContext context) {
    final (message, kind) = switch (state) {
      PreferencesState(error: final error?) => (error, _StatusKind.error),
      PreferencesState(savedSection: final section?) => (
        '${_sectionTitle(section)} preferences saved.',
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

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (kind == _StatusKind.progress)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                DIcon(icon!, size: 16, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
            CircularProgressIndicator(strokeWidth: 2),
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

String _sectionTitle(PreferenceSection section) => switch (section) {
  PreferenceSection.profile => 'Profile',
  PreferenceSection.notifications => 'Notifications',
  PreferenceSection.tracking => 'Tracking',
  PreferenceSection.interface => 'Interface',
};

String _sectionDescription(PreferenceSection section) => switch (section) {
  PreferenceSection.profile =>
    'Set the account timezone used for dates and reminders.',
  PreferenceSection.notifications =>
    'Choose which forum activity should notify this account.',
  PreferenceSection.tracking =>
    'Choose when topics become new, tracked, or watched.',
  PreferenceSection.interface =>
    'Choose the default bookmark cleanup behavior.',
};

DIconData _sectionIcon(PreferenceSection section) => switch (section) {
  PreferenceSection.profile => DIcons.user,
  PreferenceSection.notifications => DIcons.bell,
  PreferenceSection.tracking => DIcons.list,
  PreferenceSection.interface => DIcons.display,
};
