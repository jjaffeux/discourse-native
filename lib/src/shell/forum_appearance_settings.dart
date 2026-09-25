import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../data/stored_forum_base.dart';
import '../models/app_settings.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import '../theme/discourse_typography.dart';
import 'forum_settings_controller.dart';
import 'forum_theme_clipboard.dart';
import 'forum_theme_editor.dart';
import 'forum_theme_picker.dart';
import 'settings_section.dart';
import 'shell_scope.dart';
import 'theme_icons.dart';

class ForumAppearanceSettings extends StatefulWidget {
  const ForumAppearanceSettings({super.key, required this.siteUrl});
  final String siteUrl;
  @override
  State<ForumAppearanceSettings> createState() =>
      _ForumAppearanceSettingsState();
}

class _ForumAppearanceSettingsState extends State<ForumAppearanceSettings> {
  /// The mode the Theme section shows, and the app with it, until the
  /// appearance changes or the page closes.
  Brightness? _shownBrightness;

  /// The theme being edited. It is saved only from the editor.
  ForumTheme? _editing;
  bool _creating = false;

  /// The editor's latest draft, which the app shows until Save or Cancel.
  ForumTheme? _draft;
  String? _error;
  int _revision = 0;
  Future<void> Function()? _retry;

  /// Held for [dispose], which can no longer look it up.
  late ForumSettingsController settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = ShellScope.identityOf(context).forumSettings;
  }

  @override
  void dispose() {
    // The app goes back to the saved mode and theme with the page.
    settings.preview(widget.siteUrl, this);
    super.dispose();
  }

  void _preview() => settings.preview(
    widget.siteUrl,
    this,
    brightness: _shownBrightness,
    draft: _draft,
  );

  void _show(Brightness? brightness) {
    setState(
      () => _shownBrightness = brightness == _activeBrightness()
          ? null
          : brightness,
    );
    _preview();
  }

  void _edit(ForumTheme? theme, {bool creating = false}) {
    if (theme != null) {
      final effects = settings.shared.effects;
      final light = theme.forBrightness(Brightness.light);
      final dark = theme.forBrightness(Brightness.dark);
      theme = ForumTheme.fromJson({
        ...light.copyWith(background: light.background ?? effects).toJson(),
        'alternate': dark
            .copyWith(background: dark.background ?? effects)
            .toJson(),
      }, id: theme.id);
    }
    setState(() {
      _editing = _draft = theme;
      _creating = creating;
      if (theme == null) _shownBrightness = null;
    });
    _preview();
  }

  /// Read when a choice lands rather than captured at build: two choices made
  /// before the page redraws must both be kept.
  ForumThemePreferences get _preferences => settings.themesFor(widget.siteUrl);

  /// Every other connected forum, which the colours chosen here can be
  /// copied to.
  List<String> _otherForums() {
    final site = requireStoredForumBase(widget.siteUrl);
    return [
      if (site != ForumSettingsController.homeSite)
        ForumSettingsController.homeSite,
      for (final instance in ShellScope.identityOf(context).instances)
        if (requireStoredForumBase(instance.url) != site) instance.url,
    ];
  }

  Brightness _activeBrightness() =>
      switch (settings.themeModeFor(widget.siteUrl)) {
        AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };

  Brightness _brightness() => _shownBrightness ?? _activeBrightness();

  /// The forum's own palette for each mode, or the neutral preset where the
  /// forum has not published one.
  Map<Brightness, ForumTheme> _forumPalettes() {
    final forum = widget.siteUrl == ForumSettingsController.homeSite
        ? null
        : ShellScope.identityOf(context).siteAppearanceFor(widget.siteUrl);
    return {
      for (final mode in Brightness.values)
        mode: switch (forum?.paletteForBrightness(mode)) {
          final palette? => ForumTheme.fromPalette(palette),
          null =>
            forumThemePresets.first
                .forBrightness(mode)
                .copyWith(
                  id: 'forum',
                  name: widget.siteUrl == ForumSettingsController.homeSite
                      ? 'Home default'
                      : 'Forum default',
                ),
        },
    };
  }

  ForumTheme _forumTheme() {
    final forum = _forumPalettes();
    return ForumTheme.fromJson({
      ...forum[Brightness.light]!.toJson(),
      'alternate': forum[Brightness.dark]!.toJson(),
    }, id: 'forum');
  }

  Future<void> _attempt(Future<void> Function() save) async {
    final revision = ++_revision;
    setState(() {
      _error = null;
      _retry = save;
    });
    try {
      await save();
      if (mounted && revision == _revision) _retry = null;
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = 'Could not save changes.');
      }
    }
  }

  Future<void> _save(ForumThemePreferences preferences) =>
      _attempt(() => settings.setThemes(widget.siteUrl, preferences));

  Widget _themeScope(List<String> others) {
    final site = requireStoredForumBase(widget.siteUrl);
    final forumName = site == ForumSettingsController.homeSite
        ? 'Home'
        : ShellScope.identityOf(context).instances
                  .where(
                    (instance) => requireStoredForumBase(instance.url) == site,
                  )
                  .firstOrNull
                  ?.title ??
              Uri.parse(site).host;
    return Row(
      children: [
        Expanded(child: _HeadingNote('Applies to $forumName only.')),
        if (others.isNotEmpty) ...[
          const SizedBox(width: DSpacing.md),
          DButton(
            key: const ValueKey('theme-use-everywhere'),
            label: const Text('Use on every forum'),
            variant: DButtonVariant.outline,
            size: DButtonSize.small,
            onPressed: () => unawaited(_useEverywhere(others)),
          ),
        ],
      ],
    );
  }

  Future<void> _useEverywhere(List<String> forums) => _attempt(() async {
    await settings.useThemesIn(widget.siteUrl, forums);
    if (mounted) DToast.show(context, 'Every forum now uses these colours.');
  });

  void _newTheme({String? base}) {
    final available = [
      _forumTheme(),
      ...forumThemePresets,
      ..._preferences.customThemes,
    ];
    final selected =
        available.where((theme) => theme.id == base).firstOrNull ??
        _preferences.themeFor(_brightness()) ??
        _forumTheme();
    Map<String, dynamic> part(Brightness mode) => {
      ...selected.forBrightness(mode).toJson(),
      'name': 'New theme',
    };
    _edit(
      ForumTheme.fromJson({
        ...part(Brightness.light),
        'alternate': part(Brightness.dark),
      }, id: 'custom-${DateTime.now().microsecondsSinceEpoch}'),
      creating: true,
    );
  }

  Future<void> _saveEdit(ForumTheme theme) async {
    await settings.setThemes(widget.siteUrl, _preferences.save(theme));
    if (mounted) _edit(null);
  }

  void _duplicate(ForumTheme theme) {
    final copy = '${theme.name} copy';
    final name = copy.length <= 48 ? copy : copy.substring(0, 48).trimRight();
    unawaited(
      _save(
        _preferences.add(
          ForumTheme.fromJson({
            ...theme.toJson(),
            'name': name,
            if (theme.alternate case final alternate?)
              'alternate': {...alternate.toJson(), 'name': name},
          }, id: 'custom-${DateTime.now().microsecondsSinceEpoch}'),
        ),
      ),
    );
  }

  Future<void> _delete(ForumTheme theme) async {
    final preferences = _preferences;
    final inUse =
        preferences.source == ForumThemeSource.custom &&
        preferences.customId == theme.id;
    final confirmed = await showDAlertDialog<bool>(
      context: context,
      builder: (context, close) => DAlertDialogContent(
        semanticLabel: 'Delete theme',
        children: [
          DAlertDialogHeader(
            title: Text('Delete “${theme.name}”?'),
            description: Text(
              inUse
                  ? 'This removes the theme from your saved themes. The '
                        'forum’s own colours are used until you choose '
                        'another.'
                  : 'This removes the theme from your saved themes. Your '
                        'current appearance will stay as it is.',
            ),
          ),
          const DAlertDialogFooter(
            children: [
              DAlertDialogCancel<bool>(label: Text('Cancel'), result: false),
              DAlertDialogAction<bool>(
                label: Text('Delete'),
                result: true,
                variant: DButtonVariant.destructive,
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      unawaited(_save(_preferences.remove(theme.id)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final preferences = settings.themesFor(widget.siteUrl);
      final mode = settings.themeModeFor(widget.siteUrl);
      final brightness = _brightness();
      final fontFamily = settings.shared.font.family;
      final others = _otherForums();
      final editing = _editing;
      return SingleChildScrollView(
        key: const PageStorageKey('theme-settings-scroll'),
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 18,
              children: [
                if (_error != null)
                  DAlert(
                    description: DAlertDescription(
                      child: Row(
                        children: [
                          Expanded(child: Text(_error!)),
                          DButton(
                            label: const Text('Retry'),
                            variant: DButtonVariant.outline,
                            onPressed: _retry == null
                                ? null
                                : () => unawaited(_attempt(_retry!)),
                          ),
                        ],
                      ),
                    ),
                  ),
                DToggleGroup<AppThemeMode>(
                  key: const ValueKey('appearance-mode'),
                  values: [mode],
                  multiple: false,
                  allowEmptySelection: false,
                  expanded: true,
                  inset: true,
                  onChanged: (values) {
                    if (values.isEmpty) return;
                    final value = values.first;
                    unawaited(settings.setThemeMode(widget.siteUrl, value));
                    _show(null);
                  },
                  items: const [
                    DToggleGroupItem(
                      value: AppThemeMode.light,
                      child: Text('Light'),
                    ),
                    DToggleGroupItem(
                      value: AppThemeMode.dark,
                      child: Text('Dark'),
                    ),
                    DToggleGroupItem(
                      value: AppThemeMode.system,
                      child: Text('Auto'),
                    ),
                  ],
                ),
                if (editing != null)
                  ForumThemeEditor(
                    key: ValueKey(('theme-editor', editing.id)),
                    theme: editing,
                    creating: _creating,
                    brightness: brightness,
                    onChanged: (draft) {
                      _draft = draft;
                      _preview();
                    },
                    onSave: _saveEdit,
                    onCancel: () => _edit(null),
                  )
                else
                  SettingsSection(
                    title: 'Theme',
                    icon: const ThemeIcon(ThemeIcons.preset),
                    child: ForumThemePicker(
                      key: const ValueKey('theme-picker'),
                      preferences: preferences,
                      forum: _forumTheme(),
                      brightness: brightness,
                      fontFamily: fontFamily,
                      onForum: () => unawaited(
                        _save(_preferences.withSource(ForumThemeSource.forum)),
                      ),
                      onPreset: (mode, id) =>
                          unawaited(_save(_preferences.withPreset(mode, id))),
                      onTheme: (id) =>
                          unawaited(_save(_preferences.useTheme(id))),
                      onNewTheme: ({base}) => _newTheme(base: base),
                      onEdit: _edit,
                      onDuplicate: _duplicate,
                      onCopy: (theme) =>
                          unawaited(copyForumTheme(context, theme)),
                      onDelete: (theme) => unawaited(_delete(theme)),
                    ),
                  ),
                if (editing == null) _themeScope(others),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A section heading's muted note on what its choice reaches.
class _HeadingNote extends StatelessWidget {
  const _HeadingNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: DiscourseTypography.xs,
      height: DiscourseTypography.lineHeightCaption,
      color: DTokens.of(context).mutedForeground,
    ),
  );
}
