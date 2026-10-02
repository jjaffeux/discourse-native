import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/user_preferences.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
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
  static String get _forumDefaultTimezoneLabel => appL10n.forumDefault;
  static const DIconData _preferencesIcon = DIconData(
    'sliders',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 5H3"/><path d="M12 19H3"/><path d="M14 3v4"/><path d="M16 17v4"/><path d="M21 12h-9"/><path d="M21 19h-5"/><path d="M21 5h-7"/><path d="M8 10v4"/><path d="M8 12H3"/></svg>',
  );

  final TextEditingController _timezone = TextEditingController();
  final FocusNode _timezoneFocus = FocusNode();
  late final List<String> _timezoneNames;
  late final List<DComboboxOption<String>> _timezoneEntries;

  ShellController? _shell;
  PreferencesController? _preferences;
  bool _hydrationScheduled = false;

  @override
  void initState() {
    super.initState();
    _timezoneNames = TimezoneEnvironment.instance.timezoneNames.toList()
      ..sort();
    // Keep the IANA options stable across edits and page rebuilds.
    _timezoneEntries = List.unmodifiable([
      DComboboxOption(value: '', label: _forumDefaultTimezoneLabel),
      for (final name in _timezoneNames)
        DComboboxOption(value: name, label: name),
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
        return _UnavailablePreferences(
          message: context.l10n.reconnectToThisForumToLoadPreferences,
        );
      }
      if (state == null) _scheduleHydration();
      return _LoadingPreferences(host: instance.host);
    }

    final siteUrl = widget.siteUrl;
    final session = shell.lifecycle.capture(siteUrl);
    final accountIdentity = state!.accountIdentity;
    bool ownsView() =>
        mounted &&
        identical(_shell, shell) &&
        widget.siteUrl == siteUrl &&
        session.isCurrent &&
        shell.preferences.stateFor(siteUrl)?.accountIdentity == accountIdentity;
    void edit(
      PreferenceSection section,
      UserPreferences Function(UserPreferences) change,
    ) {
      if (ownsView()) shell.preferences.edit(siteUrl, section, change);
    }

    void useDeviceTimezone() {
      if (ownsView()) _useDeviceTimezone(edit);
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
              onEdit: edit,
            ),
          );
    final sections = _sectionsFor(draft, pluginSections);
    final dirty = sections.any(state.dirty);
    final canSave =
        instance?.isConnected == true && editable && dirty && !state.saving;

    return _SectionScroller(
      key: ValueKey((
        shell.preferences,
        siteUrl,
        session.session,
        accountIdentity,
      )),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DIcon(
                  _preferencesIcon,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Text(
                  context.l10n.preferences,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: DiscourseTypography.xxl,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _StatusAnnouncement(state: state, pluginSections: pluginSections),
            if (state.error != null ||
                state.loading ||
                state.savedSection != null)
              const SizedBox(height: 16),
            for (final section in sections) ...[
              _PreferenceSectionHeading(
                key: ValueKey('preferences-section-${section.keyName}'),
                title: _sectionTitle(section, pluginSections),
                icon: _sectionIcon(section, pluginSections),
              ),
              const SizedBox(height: 9),
              _buildSection(
                draft,
                section,
                editable,
                pluginSections,
                edit,
                useDeviceTimezone,
              ),
              const SizedBox(height: 22),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DButton(
                key: const ValueKey('preferences-save'),
                label: Text(context.l10n.saveChanges),
                semanticLabel: state.saving
                    ? context.l10n.savingPreferences
                    : context.l10n.savePreferences,
                onPressed: canSave
                    ? () {
                        if (ownsView()) {
                          unawaited(_saveAll(shell, instance!, sections));
                        }
                      }
                    : null,
                loading: state.saving,
                loadingLabel: Text(context.l10n.savingChanges),
                variant: DButtonVariant.primary,
                size: DButtonSize.regular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    UserPreferences draft,
    PreferenceSection section,
    bool editable,
    List<PluginUserPreferenceSection> pluginSections,
    PluginUserPreferenceEdit onEdit,
    VoidCallback onUseDeviceTimezone,
  ) => switch (section) {
    PreferenceSection.profile => _ProfileForm(
      timezone: _timezone,
      timezoneFocus: _timezoneFocus,
      selectedTimezone: draft.timezone,
      timezoneNames: _timezoneNames,
      timezoneEntries: _timezoneEntries,
      deviceTimezone: TimezoneEnvironment.instance.deviceTimezone,
      enabled: editable,
      onTimezoneChanged: (timezone) => onEdit(
        PreferenceSection.profile,
        (current) => current.copyWith(timezone: timezone),
      ),
      onUseDeviceTimezone: onUseDeviceTimezone,
    ),
    PreferenceSection.notifications => _NotificationsForm(
      preferences: draft,
      enabled: editable,
      onChanged: (change) => onEdit(PreferenceSection.notifications, change),
    ),
    PreferenceSection.tracking => _TrackingForm(
      preferences: draft,
      enabled: editable && draft.canChangeTrackingPreferences,
      onChanged: (change) => onEdit(PreferenceSection.tracking, change),
    ),
    PreferenceSection.interface => _InterfaceForm(
      preferences: draft,
      enabled: editable,
      onBookmarkChanged: (preference) => onEdit(
        PreferenceSection.interface,
        (current) => current.copyWith(bookmarkAutoDeletePreference: preference),
      ),
    ),
    _ =>
      _pluginSection(section, pluginSections)?.content ??
          const SizedBox.shrink(),
  };

  Future<void> _saveAll(
    ShellController shell,
    DiscourseInstance instance,
    List<PreferenceSection> sections,
  ) async {
    for (final section in sections) {
      if (shell.preferences.stateFor(widget.siteUrl)?.dirty(section) != true) {
        continue;
      }
      if (!await shell.preferences.save(instance, section)) return;
    }
  }

  void _useDeviceTimezone(PluginUserPreferenceEdit onEdit) {
    final zone = TimezoneEnvironment.instance.deviceTimezone;
    if (zone == null) return;
    _timezone.value = TextEditingValue(
      text: zone,
      selection: TextSelection.collapsed(offset: zone.length),
    );
    onEdit(
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
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 588),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );
}

class _PreferenceSectionHeading extends StatelessWidget {
  const _PreferenceSectionHeading({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final DIconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        children: [
          ExcludeSemantics(
            child: DIcon(
              icon,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
          size: DControlSize.preference,
          isExpanded: true,
          key: ValueKey((
            'like-notification-frequency',
            preferences.likeNotificationFrequency,
          )),
          value: preferences.likeNotificationFrequency,
          label: Text(context.l10n.likeNotifications),
          description: Text(
            context.l10n.chooseWhenLikesShouldCreateANotification,
          ),
          entries: [
            DSelectOption(
              value: 0,
              label: context.l10n.always,
              child: Text(context.l10n.always),
            ),
            DSelectOption(
              value: 1,
              label: context.l10n.firstTimeAndDaily,
              child: Text(context.l10n.firstTimeAndDaily),
            ),
            DSelectOption(
              value: 2,
              label: context.l10n.firstTime,
              child: Text(context.l10n.firstTime),
            ),
            DSelectOption(
              value: 3,
              label: context.l10n.never,
              child: Text(context.l10n.never),
            ),
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
        const SizedBox(height: 18),
        DSwitchTile(
          size: DSwitchSize.preference,
          key: const ValueKey('notify-on-linked-posts'),
          contentPadding: EdgeInsets.zero,
          title: DLabel(
            enabled: enabled,
            child: Text(context.l10n.notifyMeAboutRepliesToLinkedPosts),
          ),
          subtitle: Text(
            context.l10n.getANotificationWhenSomeoneRepliesToAPostYouLinked,
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
          size: DControlSize.preference,
          isExpanded: true,
          key: ValueKey((
            'new-topic-duration',
            preferences.newTopicDurationMinutes,
          )),
          value: preferences.newTopicDurationMinutes,
          label: Text(context.l10n.considerTopicsNew),
          description: Text(
            context.l10n.controlsWhichTopicsAppearAsNewToThisAccount,
          ),
          entries: [
            DSelectOption(
              value: -1,
              label: context.l10n.untilIViewThem,
              child: Text(context.l10n.untilIViewThem),
            ),
            DSelectOption(
              value: 1440,
              label: context.l10n.forOneDay,
              child: Text(context.l10n.forOneDay),
            ),
            DSelectOption(
              value: 2880,
              label: context.l10n.forTwoDays,
              child: Text(context.l10n.forTwoDays),
            ),
            DSelectOption(
              value: 10080,
              label: context.l10n.forOneWeek,
              child: Text(context.l10n.forOneWeek),
            ),
            DSelectOption(
              value: 20160,
              label: context.l10n.forTwoWeeks,
              child: Text(context.l10n.forTwoWeeks),
            ),
            DSelectOption(
              value: -2,
              label: context.l10n.sinceMyLastVisit,
              child: Text(context.l10n.sinceMyLastVisit),
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
        const SizedBox(height: 18),
        DSelect<int>.controlled(
          size: DControlSize.preference,
          isExpanded: true,
          key: ValueKey((
            'auto-track-duration',
            preferences.autoTrackTopicsAfterMsecs,
          )),
          value: preferences.autoTrackTopicsAfterMsecs,
          label: Text(context.l10n.automaticallyTrackTopics),
          description: Text(
            context.l10n.trackATopicAfterYouHaveReadItForThisLong,
          ),
          entries: [
            DSelectOption(
              value: -1,
              label: context.l10n.never,
              child: Text(context.l10n.never),
            ),
            DSelectOption(
              value: 0,
              label: context.l10n.immediately,
              child: Text(context.l10n.immediately),
            ),
            DSelectOption(
              value: 30000,
              label: context.l10n.after30Seconds,
              child: Text(context.l10n.after30Seconds),
            ),
            DSelectOption(
              value: 60000,
              label: context.l10n.after1Minute,
              child: Text(context.l10n.after1Minute),
            ),
            DSelectOption(
              value: 120000,
              label: context.l10n.after2Minutes,
              child: Text(context.l10n.after2Minutes),
            ),
            DSelectOption(
              value: 180000,
              label: context.l10n.after3Minutes,
              child: Text(context.l10n.after3Minutes),
            ),
            DSelectOption(
              value: 240000,
              label: context.l10n.after4Minutes,
              child: Text(context.l10n.after4Minutes),
            ),
            DSelectOption(
              value: 300000,
              label: context.l10n.after5Minutes,
              child: Text(context.l10n.after5Minutes),
            ),
            DSelectOption(
              value: 600000,
              label: context.l10n.after10Minutes,
              child: Text(context.l10n.after10Minutes),
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
        const SizedBox(height: 18),
        DSelect<int>.controlled(
          size: DControlSize.preference,
          isExpanded: true,
          key: ValueKey((
            'reply-notification-level',
            preferences.notificationLevelWhenReplying,
          )),
          value: preferences.notificationLevelWhenReplying,
          label: Text(context.l10n.whenIReplyToATopic),
          description: Text(
            context.l10n.chooseTheNotificationLevelAppliedAfterAReply,
          ),
          entries: [
            DSelectOption(
              value: 3,
              label: context.l10n.watchTheTopic,
              child: Text(context.l10n.watchTheTopic),
            ),
            DSelectOption(
              value: 2,
              label: context.l10n.trackTheTopic,
              child: Text(context.l10n.trackTheTopic),
            ),
            DSelectOption(
              value: 1,
              label: context.l10n.keepTheCurrentLevel,
              child: Text(context.l10n.keepTheCurrentLevel),
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
  final List<DComboboxOption<String>> timezoneEntries;
  final String? deviceTimezone;
  final bool enabled;
  final ValueChanged<String> onTimezoneChanged;
  final VoidCallback onUseDeviceTimezone;

  @override
  Widget build(BuildContext context) {
    return _PreferenceCard(
      children: [
        DField(
          children: [
            DFieldLabel(child: Text(context.l10n.timezone)),
            DCombobox<String>.controlled(
              key: const ValueKey('preferences-timezone'),
              textController: timezone,
              focusNode: timezoneFocus,
              enabled: enabled,
              value: selectedTimezone,
              options: timezoneEntries,
              anchor: DComboboxInput<String>(
                semanticLabel: context.l10n.timezone,
              ),
              content: DComboboxContent(
                children: [
                  DComboboxEmpty<String>(
                    child: Text(context.l10n.noTimezonesFound),
                  ),
                  const DComboboxList<String>(),
                ],
              ),
              onChanged: enabled
                  ? (value, reason) {
                      if (value == null) {
                        _restoreSelectedTimezone();
                      } else {
                        onTimezoneChanged(value);
                      }
                    }
                  : null,
            ),
            DFieldDescription(
              child: Text(
                context.l10n.typeToFilterIANATimezonesUsedForDatesAndReminders,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DFieldDescription(
          child: Text(
            deviceTimezone == null
                ? context.l10n.deviceTimezoneIsUnavailable
                : context.l10n.deviceTimezone((deviceTimezone).toString()),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: DButton(
            key: const ValueKey('preferences-use-device-timezone'),
            label: Text(context.l10n.useDeviceTimezone),
            onPressed: enabled && deviceTimezone != null
                ? onUseDeviceTimezone
                : null,
            icon: const DIcon(DIcons.globe),
            variant: DButtonVariant.outline,
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
          size: DControlSize.preference,
          isExpanded: true,
          key: ValueKey((
            'bookmark-auto-delete',
            preferences.bookmarkAutoDeletePreference,
          )),
          value: preferences.bookmarkAutoDeletePreference,
          label: Text(context.l10n.automaticallyDeleteBookmarks),
          description: Text(
            context.l10n.chooseWhatHappensAfterABookmarkReminder,
          ),
          entries: [
            DSelectOption(
              value: BookmarkAutoDeletePreference.never,
              label: context.l10n.never,
              child: Text(context.l10n.never),
            ),
            DSelectOption(
              value: BookmarkAutoDeletePreference.whenReminderSent,
              label: context.l10n.afterTheReminderIsSent,
              child: Text(context.l10n.afterTheReminderIsSent),
            ),
            DSelectOption(
              value: BookmarkAutoDeletePreference.onOwnerReply,
              label: context.l10n.whenTheTopicOwnerReplies,
              child: Text(context.l10n.whenTheTopicOwnerReplies),
            ),
            DSelectOption(
              value: BookmarkAutoDeletePreference.clearReminder,
              label: context.l10n.whenTheReminderIsCleared,
              child: Text(context.l10n.whenTheReminderIsCleared),
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
      spacing: 16,
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
        context.l10n.preferencesSaved(
          (_sectionTitle(section, pluginSections)).toString(),
        ),
        _StatusKind.success,
      ),
      PreferencesState(loading: true) => (
        context.l10n.refreshingPreferences,
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
    label: context.l10n.loadingPreferencesFrom((host).toString()),
    child: ExcludeSemantics(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DSpinner(),
            const SizedBox(height: 16),
            Text(context.l10n.loadingPreferences),
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
                  label: Text(context.l10n.tryAgain),
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
      PreferenceSection.profile => appL10n.profile,
      PreferenceSection.notifications => appL10n.notifications,
      PreferenceSection.tracking => appL10n.tracking,
      PreferenceSection.interface => appL10n.interface,
      _ => section.name,
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
      _ => DIcons.gear,
    };
