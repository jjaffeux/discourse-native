import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../foundation/icons/d_native_icons.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/composer_upload.dart';
import '../models/discourse_instance.dart';
import '../models/user_preferences.dart';
import '../plugin_api/site_plugin_api.dart';
import 'composer/upload_picker.dart';
import 'content_reading_lane.dart';
import 'header_preferences.dart';
import 'preference_fields.dart';
import 'preferences_avatar_row.dart';
import 'preferences_controller.dart';
import 'preferences_users_section.dart';
import 'settings_section_tabs.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({
    super.key,
    required this.siteUrl,
    this.pickPicture = pickProfilePicture,
  });

  final String siteUrl;

  /// Asks the device for one image; null when the reader backs out.
  final Future<ComposerUploadFile?> Function() pickPicture;

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  static String get _forumDefaultTimezoneLabel => appL10n.forumDefault;
  final TextEditingController _timezone = TextEditingController();
  final FocusNode _timezoneFocus = FocusNode();
  final TextEditingController _bio = TextEditingController();
  late final List<String> _timezoneNames;
  late final List<DComboboxOption<String>> _timezoneEntries;

  ShellController? _shell;
  PreferencesController? _preferences;
  bool _hydrationScheduled = false;
  PreferenceSection _selectedSection = PreferenceSection.profile;
  String? _pictureError;

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
    _bio.clear();
    _pictureError = null;
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
      if (!ownsView() || instance == null) return;
      shell.preferences.edit(siteUrl, section, change);
      unawaited(shell.preferences.saveAutomatically(instance, section));
    }

    void useDeviceTimezone() {
      if (ownsView()) _useDeviceTimezone(edit);
    }

    // Free text is held in the draft until the reader saves it.
    void editBio(String bio) {
      if (!ownsView()) return;
      shell.preferences.edit(
        siteUrl,
        PreferenceSection.about,
        (current) => current.copyWith(bioRaw: bio),
      );
    }

    Future<void> changePicture() async {
      if (!ownsView() || instance == null) return;
      setState(() => _pictureError = null);
      final ComposerUploadFile? file;
      try {
        file = await widget.pickPicture();
      } catch (_) {
        if (ownsView()) {
          setState(
            () => _pictureError = appL10n.couldnTOpenAPictureFromThisDevice,
          );
        }
        return;
      }
      if (file == null || !ownsView()) return;
      unawaited(shell.profileAvatar.upload(instance, file));
    }

    void useDefaultPicture() {
      if (!ownsView() || instance == null) return;
      setState(() => _pictureError = null);
      unawaited(shell.profileAvatar.useDefault(instance));
    }

    void saveBio() {
      if (!ownsView() || instance == null) return;
      unawaited(shell.preferences.save(instance, PreferenceSection.about));
    }

    void saveMutedUsers() {
      if (!ownsView() || instance == null) return;
      unawaited(shell.preferences.save(instance, PreferenceSection.users));
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
    final selected = sections.contains(_selectedSection)
        ? _selectedSection
        : sections.first;
    final dirty = sections.any(state.dirty);
    final canSave =
        instance?.isConnected == true && editable && dirty && !state.saving;

    return DPageSurface.headed(
      icon: DNativeIcons.sliders,
      title: Text(context.l10n.preferences),
      controls: SettingsSectionTabs<PreferenceSection>(
        value: selected,
        sections: [
          for (final section in sections)
            (
              value: section,
              label: _sectionTitle(section, pluginSections),
              key: ValueKey('preferences-section-${section.keyName}'),
            ),
        ],
        onChanged: (section) => setState(() => _selectedSection = section),
      ),
      child: _SectionScroller(
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
              _StatusAnnouncement(state: state, pluginSections: pluginSections),
              if (state.error != null ||
                  state.loading ||
                  state.saving ||
                  state.savedSection != null)
                const SizedBox(height: 16),
              const SizedBox(height: 22),
              _buildSection(
                draft,
                selected,
                editable,
                pluginSections,
                edit,
                useDeviceTimezone,
                // A reader who may neither upload nor give a picture up has
                // nothing to do here.
                draft.canEditAvatar &&
                        (draft.canUploadAvatar ||
                            draft.uploadedAvatarId != null)
                    ? PreferencesAvatarRow(
                        siteUrl: siteUrl,
                        canUpload: draft.canUploadAvatar,
                        hasUploadedPicture: draft.uploadedAvatarId != null,
                        enabled: editable && instance?.isConnected == true,
                        pickerError: _pictureError,
                        onChange: changePicture,
                        onUseDefault: useDefaultPicture,
                      )
                    : null,
                _BioEditing(
                  controller: _bio,
                  enabled: editable && draft.canChangeBio,
                  managedBySite: !draft.canChangeBio,
                  saving: state.saving && state.dirty(PreferenceSection.about),
                  onChanged: editBio,
                  onSave:
                      instance?.isConnected == true &&
                          state.dirty(PreferenceSection.about) &&
                          !state.saving
                      ? saveBio
                      : null,
                ),
                PreferencesUsersSection(
                  preferences: draft,
                  enabled: editable && instance?.isConnected == true,
                  searchUsers: (term) async => ownsView()
                      ? shell.composerIdentities.searchUsers(
                          siteUrl: siteUrl,
                          topicId: null,
                          term: term,
                        )
                      : const [],
                  muted: MutedUsersEditing(
                    saving:
                        state.saving && state.dirty(PreferenceSection.users),
                    // Held in the draft until the reader saves the list.
                    onChanged: (usernames) {
                      if (!ownsView()) return;
                      shell.preferences.edit(
                        siteUrl,
                        PreferenceSection.users,
                        (current) =>
                            current.copyWith(mutedUsernames: usernames),
                      );
                    },
                    onSave:
                        state.dirty(PreferenceSection.users) && !state.saving
                        ? saveMutedUsers
                        : null,
                  ),
                  ignored: IgnoredUsersEditing(
                    siteUrl: siteUrl,
                    transactions: shell.ignoredUsers,
                    onIgnore: (username, duration) async =>
                        ownsView() &&
                        instance != null &&
                        await shell.ignoredUsers.ignore(
                          instance,
                          username,
                          duration,
                        ),
                    onStopIgnoring: (username) {
                      if (!ownsView() || instance == null) return;
                      unawaited(
                        shell.ignoredUsers.stopIgnoring(instance, username),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (selected == PreferenceSection.interface) ...[
                const HeaderTuningPreferences(),
                const SizedBox(height: 22),
              ],
              if (state.error != null && dirty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DButton(
                    key: const ValueKey('preferences-save'),
                    label: Text(context.l10n.retry),
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
    Widget? avatar,
    _BioEditing bio,
    Widget users,
  ) => switch (section) {
    PreferenceSection.profile => _ProfileForm(
      timezone: _timezone,
      timezoneFocus: _timezoneFocus,
      selectedTimezone: draft.timezone,
      timezoneEntries: _timezoneEntries,
      deviceTimezone: TimezoneEnvironment.instance.deviceTimezone,
      enabled: editable,
      onTimezoneChanged: (timezone) => onEdit(
        PreferenceSection.profile,
        (current) => current.copyWith(timezone: timezone),
      ),
      onUseDeviceTimezone: onUseDeviceTimezone,
      avatar: avatar,
      bio: bio,
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
    PreferenceSection.users => users,
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
    final draft = _preferences?.stateFor(widget.siteUrl)?.draft;
    if (draft == null) return;
    _synchronizeTimezone(draft.timezone);
    _synchronizeBio(draft.bioRaw);
  }

  /// Typing writes the draft before this runs, so the two differ only when
  /// the draft moved underneath the field: a load, another account, or the
  /// site's own spelling of a saved bio.
  void _synchronizeBio(String value) {
    if (_bio.text == value) return;
    _bio.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  List<PreferenceSection> _sectionsFor(
    UserPreferences preferences,
    List<PluginUserPreferenceSection> pluginSections,
  ) => [
    PreferenceSection.profile,
    PreferenceSection.notifications,
    if (preferences.canChangeTrackingPreferences) PreferenceSection.tracking,
    PreferenceSection.interface,
    PreferenceSection.users,
    for (final plugin in pluginSections) plugin.section,
  ];

  @override
  void dispose() {
    _preferences?.removeListener(_handlePreferencesChanged);
    _timezoneFocus.removeListener(_restoreSelectedTimezoneAfterFiltering);
    _timezone.dispose();
    _timezoneFocus.dispose();
    _bio.dispose();
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
      padding: lane.padding.add(
        EdgeInsets.only(bottom: DScrollChrome.bottomInsetOf(context)),
      ),
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
    return PreferenceCard(
      children: [
        PreferenceSelect<int>(
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
            child: Text(context.l10n.notifyWhenSomeoneLinksToMyPosts),
          ),
          subtitle: Text(context.l10n.turnOffLinkNotifications),
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
    return PreferenceCard(
      children: [
        PreferenceSelect<int>(
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
        PreferenceSelect<int>(
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
        PreferenceSelect<int>(
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
    required this.timezoneEntries,
    required this.deviceTimezone,
    required this.enabled,
    required this.onTimezoneChanged,
    required this.onUseDeviceTimezone,
    required this.avatar,
    required this.bio,
  });

  final TextEditingController timezone;
  final FocusNode timezoneFocus;
  final String selectedTimezone;
  final List<DComboboxOption<String>> timezoneEntries;
  final String? deviceTimezone;
  final bool enabled;
  final ValueChanged<String> onTimezoneChanged;
  final VoidCallback onUseDeviceTimezone;
  final Widget? avatar;
  final _BioEditing bio;

  @override
  Widget build(BuildContext context) {
    return PreferenceCard(
      children: [
        if (avatar case final avatar?) ...[avatar, const SizedBox(height: 18)],
        DField(
          orientation: MediaQuery.textScalerOf(context).scale(14) > 21
              ? DFieldOrientation.vertical
              : DFieldOrientation.responsive,
          responsiveBreakpoint: 520,
          children: [
            DFieldContent(
              children: [
                DFieldLabel(child: Text(context.l10n.timezone)),
                DFieldDescription(
                  child: Text(
                    context
                        .l10n
                        .typeToFilterIANATimezonesUsedForDatesAndReminders,
                  ),
                ),
              ],
            ),
            DFieldControl(
              label: context.l10n.timezone,
              expand: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 250),
                child: DCombobox<String>.controlled(
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
        const SizedBox(height: 18),
        DField(
          enabled: bio.enabled,
          children: [
            DFieldContent(
              children: [
                DFieldLabel(child: Text(context.l10n.aboutMe)),
                DFieldDescription(
                  child: Text(
                    bio.managedBySite
                        ? context.l10n.aboutMeIsManagedByThisSiteSSignIn
                        : context.l10n.aboutMeDescription,
                  ),
                ),
              ],
            ),
            DFieldControl(
              label: context.l10n.aboutMe,
              child: DTextarea(
                key: const ValueKey('preferences-bio'),
                controller: bio.controller,
                enabled: bio.enabled,
                minLines: 4,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
                onChanged: bio.onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            key: const ValueKey('preferences-bio-save'),
            label: Text(context.l10n.save),
            semanticLabel: context.l10n.saveAboutMe,
            onPressed: bio.enabled ? bio.onSave : null,
            loading: bio.saving,
            loadingLabel: Text(context.l10n.saving),
            variant: DButtonVariant.primary,
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

/// What the profile form needs to edit the bio, whose text lives on the page
/// so it survives the form rebuilding under it.
final class _BioEditing {
  const _BioEditing({
    required this.controller,
    required this.enabled,
    required this.managedBySite,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool managedBySite;
  final bool saving;
  final ValueChanged<String> onChanged;

  /// Null while there is nothing to save or a write is already pending.
  final VoidCallback? onSave;
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
    return PreferenceCard(
      children: [
        PreferenceSelect<BookmarkAutoDeletePreference>(
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
            for (final preference in BookmarkAutoDeletePreference.values)
              DSelectOption(
                value: preference,
                label: preference.label,
                child: Text(preference.label),
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
      PreferencesState(pendingWrites: > 0) => (
        context.l10n.savingPreferences,
        _StatusKind.progress,
      ),
      PreferencesState(savedSection: final section?) => (
        context.l10n.preferencesSaved(
          (_sectionTitle(section, pluginSections)).toString(),
        ),
        _StatusKind.success,
      ),
      PreferencesState(loading: true) => (
        context.l10n.refreshingPreferences,
        _StatusKind.refresh,
      ),
      _ => (null, null),
    };
    if (message == null || kind == null) return const SizedBox.shrink();
    if (kind == _StatusKind.refresh) {
      return DSkeletonRegion(
        semanticsLabel: message,
        color: skeletonFill(context),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              DSkeleton(width: 16, height: 16),
              SizedBox(width: 12),
              Expanded(child: DSkeleton(height: 14)),
            ],
          ),
        ),
      );
    }

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
      _StatusKind.progress || _StatusKind.refresh => (
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

enum _StatusKind { error, success, progress, refresh }

class _LoadingPreferences extends StatelessWidget {
  const _LoadingPreferences({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) => DPageSurface.headed(
    icon: DNativeIcons.sliders,
    title: Text(context.l10n.preferences),
    child: _SectionScroller(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: DSkeletonRegion(
        color: skeletonFill(context),
        semanticsLabel: context.l10n.loadingPreferencesFrom((host).toString()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final width in [64.0, 112.0, 88.0, 80.0])
                  DSkeleton(width: width, height: 32),
              ],
            ),
            const SizedBox(height: 38),
            const DSkeleton(width: 104, height: 16),
            const SizedBox(height: 12),
            const DSkeleton(height: 12),
            const SizedBox(height: 16),
            const DSkeleton(width: 250, height: 36),
            const SizedBox(height: 12),
            const DSkeleton(width: 200, height: 12),
            const SizedBox(height: 8),
            const DSkeleton(width: 160, height: 32),
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
      PreferenceSection.about => appL10n.aboutMe,
      PreferenceSection.notifications => appL10n.notifications,
      PreferenceSection.tracking => appL10n.tracking,
      PreferenceSection.interface => appL10n.interface,
      PreferenceSection.users => appL10n.users,
      _ => section.name,
    };
