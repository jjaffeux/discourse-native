import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_settings_controller.dart';
import 'forum_theme_editor.dart';
import 'forum_theme_preview.dart';
import 'shell_scope.dart';

class ForumAppearanceSettings extends StatefulWidget {
  const ForumAppearanceSettings({super.key, required this.siteUrl});
  final String siteUrl;

  @override
  State<ForumAppearanceSettings> createState() =>
      _ForumAppearanceSettingsState();
}

class _ForumAppearanceSettingsState extends State<ForumAppearanceSettings> {
  String _tab = 'library';
  String _query = '';
  ForumTheme? _draft;
  GlobalKey _editorKey = GlobalKey();
  bool _saving = false;
  String? _error;

  ForumSettingsController get settings =>
      ShellScope.identityOf(context).forumSettings;

  Future<void> _save(ForumThemePreferences value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await settings.setThemes(widget.siteUrl, value);
      if (mounted) {
        setState(() {
          _tab = 'library';
          _draft = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save theme. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final preferences = settings.themesFor(widget.siteUrl);
      final shell = ShellScope.of(context);
      final forum = shell.siteAppearanceFor(widget.siteUrl);
      final mode = settings.themeModeFor(widget.siteUrl);
      final brightness = switch (mode) {
        AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };
      final selected = _tab == 'custom' ? _draft : preferences.selectedTheme;
      final palette =
          selected?.resolve(
            brightness,
            forumPalette:
                forum?.paletteForBrightness(brightness) ??
                forum?.base ??
                forum?.alternate,
          ) ??
          forum?.paletteForBrightness(brightness);
      final previewTheme =
          (palette == null
                  ? (brightness == Brightness.dark
                        ? AppTheme.dark
                        : AppTheme.light)
                  : AppTheme.fromPalette(palette))
              .copyWith(platform: Theme.of(context).platform);
      return LayoutBuilder(
        builder: (context, constraints) {
          final split =
              constraints.maxWidth >= 720 &&
              MediaQuery.textScalerOf(context).scale(14) < 24;
          final controls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.lg,
            children: [
              DField(
                children: [
                  const DFieldLabel(child: Text('Color mode')),
                  DSelect<AppThemeMode>.controlled(
                    key: const ValueKey('appearance-theme-select'),
                    semanticLabel: 'Color mode',
                    value: mode,
                    isExpanded: true,
                    entries: const [
                      DSelectOption(
                        value: AppThemeMode.system,
                        label: 'System',
                        child: Text('System'),
                      ),
                      DSelectOption(
                        value: AppThemeMode.light,
                        label: 'Light',
                        child: Text('Light'),
                      ),
                      DSelectOption(
                        value: AppThemeMode.dark,
                        label: 'Dark',
                        child: Text('Dark'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(settings.setThemeMode(widget.siteUrl, value));
                      }
                    },
                  ),
                ],
              ),
              DToggle(
                key: const ValueKey('forum-default-theme'),
                pressed: preferences.selectedTheme == null && _tab != 'custom',
                enabled: !_saving,
                variant: DToggleVariant.outline,
                icon: const DIcon(DIcons.house),
                selectedIcon: const DIcon(DIcons.check),
                onPressedChanged: (_) =>
                    unawaited(_save(preferences.select(null))),
                child: const Row(
                  children: [Expanded(child: Text('Forum default'))],
                ),
              ),
              DTabs<String>.controlled(
                value: _tab,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _tab = value;
                    if (_tab == 'custom' && _draft == null) {
                      _draft =
                          preferences.selectedTheme ?? forumThemePresets[1];
                    }
                  });
                },
                children: const [
                  DTabList<String>(
                    variant: DTabListVariant.line,
                    children: [
                      DTabTrigger(value: 'library', child: Text('Themes')),
                      DTabTrigger(value: 'custom', child: Text('Custom')),
                    ],
                  ),
                ],
              ),
              if (_error != null)
                DAlert(
                  variant: DAlertVariant.destructive,
                  description: DAlertDescription(child: Text(_error!)),
                ),
              if (_tab == 'library') ...[
                DInput(
                  key: const ValueKey('theme-search'),
                  semanticLabel: 'Search themes',
                  hintText: 'Search themes',
                  value: _query,
                  onChanged: (value) => setState(() => _query = value),
                ),
                _library(preferences),
              ] else
                ForumThemeEditor(
                  key: _editorKey,
                  initialTheme: _draft ?? forumThemePresets[1],
                  customThemes: preferences.customThemes,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _draft = value),
                  onSave: (value) => _save(preferences.save(value)),
                ),
            ],
          );
          final preview = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.md,
            children: [
              const DLabel(child: Text('Preview')),
              ForumThemePreview(theme: previewTheme, siteUrl: widget.siteUrl),
            ],
          );
          if (!split) {
            return SingleChildScrollView(
              key: const ValueKey('forum-appearance-scroll'),
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DSpacing.xl,
                children: [controls, preview],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                  child: controls,
                ),
              ),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 24, 24),
                  child: preview,
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _library(ForumThemePreferences preferences) {
    final themes = [...forumThemePresets, ...preferences.customThemes]
        .where(
          (theme) => theme.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 320 &&
                MediaQuery.textScalerOf(context).scale(14) < 18
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - DSpacing.sm * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DSpacing.lg,
          children: [
            if (themes.isEmpty) const Text('No themes found.'),
            Wrap(
              spacing: DSpacing.sm,
              runSpacing: DSpacing.sm,
              children: [
                for (final theme in themes)
                  SizedBox(
                    width: width,
                    child: DToggle(
                      key: ValueKey('forum-theme-${theme.id}'),
                      semanticLabel: theme.name,
                      selectedIcon: const DIcon(DIcons.check),
                      pressed: preferences.selectedId == theme.id,
                      enabled: !_saving,
                      variant: DToggleVariant.outline,
                      onPressedChanged: (_) =>
                          unawaited(_save(preferences.select(theme.id))),
                      child: Row(
                        spacing: DSpacing.sm,
                        children: [
                          ThemeSwatch(theme: theme),
                          Flexible(child: Text(theme.name)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (preferences.selectedTheme case final selected?)
              Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  DButton(
                    label: Text(
                      selected.id.startsWith('custom-')
                          ? 'Edit theme'
                          : 'Customize',
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _draft = selected;
                            _editorKey = GlobalKey();
                            _tab = 'custom';
                          }),
                  ),
                  if (selected.id.startsWith('custom-'))
                    DButton(
                      label: const Text('Delete theme'),
                      onPressed: _saving
                          ? null
                          : () => unawaited(
                              _save(preferences.remove(selected.id)),
                            ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({super.key, required this.theme});
  final ForumTheme theme;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in [theme.secondary, theme.tertiary, theme.primary])
          SizedBox(width: 7, height: 16, child: ColoredBox(color: color)),
      ],
    ),
  );
}
