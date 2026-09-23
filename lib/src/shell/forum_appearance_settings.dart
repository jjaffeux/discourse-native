import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/forum_background.dart';
import '../models/forum_font.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import 'forum_settings_controller.dart';
import 'forum_theme_editor.dart';
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
  Brightness? _editingBrightness;
  String? _error;
  int _revision = 0;
  ForumThemePreferences? _retry;
  ForumSettingsController get settings =>
      ShellScope.identityOf(context).forumSettings;

  Map<Brightness, ForumTheme> _palettes(ForumThemePreferences preferences) {
    if (!preferences.useCustomTheme) {
      preferences = ForumThemePreferences.defaults;
    }
    final forum = ShellScope.identityOf(
      context,
    ).siteAppearanceFor(widget.siteUrl);
    ForumTheme resolve(Brightness mode) {
      final palette = forum?.paletteForBrightness(mode);
      return preferences.palettes[mode] ??
          preferences.selectedTheme?.forBrightness(mode) ??
          (palette != null
              ? ForumTheme.fromPalette(palette)
              : forumThemePresets.first
                    .forBrightness(mode)
                    .copyWith(id: 'forum', name: 'Forum default'));
    }

    return {for (final mode in Brightness.values) mode: resolve(mode)};
  }

  ForumBackground _background(
    ForumThemePreferences preferences,
    Brightness mode,
  ) {
    if (!preferences.useCustomTheme) return const ForumBackground.appearance();
    final background =
        preferences.background ?? preferences.themeFor(mode)?.background;
    if (background == null) return const ForumBackground.appearance();
    if (background.useAccentTint) return background;
    return ForumBackground.appearance(
      strength: (background.strength * .45 / .22).clamp(0, 1),
      effect: background.effect,
      noiseIntensity: background.noiseIntensity,
      transparency: background.transparency,
    );
  }

  Future<void> _save(ForumThemePreferences preferences) async {
    final revision = ++_revision;
    setState(() {
      _error = null;
      _retry = preferences;
    });
    try {
      await settings.setThemes(widget.siteUrl, preferences);
      if (mounted && revision == _revision) _retry = null;
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = 'Could not save changes.');
      }
    }
  }

  ForumThemePreferences _seed(
    ForumThemePreferences preferences,
    Brightness mode,
  ) {
    var result = preferences.useCustomTheme
        ? preferences
        : ForumThemePreferences(customThemes: preferences.customThemes);
    for (final palette in _palettes(preferences).values) {
      result = result.withPalette(palette);
    }
    return result.withBackground(_background(preferences, mode));
  }

  void _removeTheme(String id) {
    var preferences = settings.themesFor(widget.siteUrl);
    if (preferences.useCustomTheme && preferences.selectedId == id) {
      for (final palette in _palettes(preferences).values) {
        preferences = preferences.withPalette(palette);
      }
    }
    unawaited(_save(preferences.remove(id)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final preferences = settings.themesFor(widget.siteUrl);
      final mode = settings.themeModeFor(widget.siteUrl);
      final activeBrightness = switch (mode) {
        AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };
      final brightness = _editingBrightness ?? activeBrightness;
      return SingleChildScrollView(
        key: const PageStorageKey('theme-settings-scroll'),
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 588),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 18,
              children: [
                Row(
                  spacing: 9,
                  children: [
                    ThemeIcon(
                      ThemeIcons.palette,
                      size: 16,
                      color: DTokens.of(context).mutedForeground,
                    ),
                    Expanded(
                      child: Semantics(
                        headingLevel: 1,
                        child: Text(
                          'Themes',
                          style: TextStyle(
                            fontSize: 22,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: DTokens.of(context).foreground,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                                : () => unawaited(_save(_retry!)),
                          ),
                        ],
                      ),
                    ),
                  ),
                DToggleGroup<AppThemeMode>(
                  key: const ValueKey('appearance-mode'),
                  values: [mode],
                  allowEmptySelection: false,
                  inset: true,
                  expanded: true,
                  semanticLabel: 'Appearance',
                  items: const [
                    DToggleGroupItem(
                      value: AppThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      child: Text('Light'),
                    ),
                    DToggleGroupItem(
                      value: AppThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      child: Text('Dark'),
                    ),
                    DToggleGroupItem(
                      value: AppThemeMode.system,
                      icon: Icon(Icons.desktop_windows_outlined),
                      child: Text('System'),
                    ),
                  ],
                  onChanged: (values) {
                    setState(() => _editingBrightness = null);
                    unawaited(
                      settings.setThemeMode(widget.siteUrl, values.single),
                    );
                  },
                ),
                ForumThemeEditor(
                  palettes: _palettes(preferences),
                  isForumDefault: !preferences.useCustomTheme,
                  onForumDefault: () =>
                      unawaited(_save(preferences.withCustomTheme(false))),
                  forumPalettes: _palettes(ForumThemePreferences.defaults),
                  background: _background(preferences, brightness),
                  brightness: brightness,
                  customThemes: preferences.customThemes,
                  onBrightnessChanged: (value) =>
                      setState(() => _editingBrightness = value),
                  onPresetSelected: (preset) => unawaited(
                    _save(
                      _seed(settings.themesFor(widget.siteUrl), brightness)
                          .withPalette(preset)
                          .withBackground(
                            preset.background ??
                                const ForumBackground.appearance(),
                          ),
                    ),
                  ),
                  onChanged: (palette) => unawaited(
                    _save(
                      _seed(
                        settings.themesFor(widget.siteUrl),
                        brightness,
                      ).withPalette(palette),
                    ),
                  ),
                  onBackgroundChanged: (background) => unawaited(
                    _save(
                      _seed(
                        settings.themesFor(widget.siteUrl),
                        brightness,
                      ).withBackground(background),
                    ),
                  ),
                  onDelete: _removeTheme,
                  onSave: (theme) async {
                    final current = settings.themesFor(widget.siteUrl);
                    await settings.setThemes(
                      widget.siteUrl,
                      ForumThemePreferences(
                        useCustomTheme: current.useCustomTheme,
                        selectedId: current.selectedId,
                        customThemes: [...current.customThemes, theme],
                        font: current.font,
                        palettes: current.palettes,
                        background: current.background,
                      ),
                    );
                  },
                ),
                SettingsSection(
                  title: 'Font',
                  icon: const Icon(Icons.text_fields),
                  child: DItemGroup(
                    spacing: 0,
                    children: [
                      for (final font in ForumFont.values) ...[
                        if (font != ForumFont.values.first)
                          const DItemSeparator(),
                        DItem(
                          key: ValueKey('appearance-font-${font.name}'),
                          selected: preferences.effectiveFont == font,
                          shape: DItemShape.fullWidth,
                          selectionStyle: DItemSelectionStyle.leadingAccent,
                          onPressed: () => unawaited(
                            _save(
                              _seed(preferences, brightness).withFont(font),
                            ),
                          ),
                          children: [
                            DItemContent(
                              children: [
                                Text(
                                  font.label,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  'The quick brown fox jumps over the lazy dog.',
                                  style: Theme.of(context).textTheme.bodyLarge!
                                      .copyWith(
                                        fontFamily:
                                            font.family ??
                                            ThemeData(
                                              platform: Theme.of(
                                                context,
                                              ).platform,
                                            ).textTheme.bodyLarge!.fontFamily,
                                        fontFamilyFallback:
                                            forumFontFamilyFallback(
                                              font.family,
                                            ) ??
                                            const [],
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
