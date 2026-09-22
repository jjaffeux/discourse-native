import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/forum_font.dart';
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
  Brightness? _editorBrightness;
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

  Future<void> _saveFont(ForumFont font) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await settings.setThemes(
        widget.siteUrl,
        settings.themesFor(widget.siteUrl).withFont(font),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save font. Try again.');
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
      final previewBrightness = _tab == 'custom'
          ? _editorBrightness ?? brightness
          : brightness;
      final selected = _tab == 'custom' ? _draft : preferences.selectedTheme;
      final palette =
          selected?.resolve(
            previewBrightness,
            forumPalette:
                forum?.paletteForBrightness(previewBrightness) ??
                forum?.base ??
                forum?.alternate,
          ) ??
          forum?.paletteForBrightness(previewBrightness);
      final previewTheme =
          (palette == null
                  ? AppTheme.forBrightness(
                      previewBrightness,
                      fontFamily: preferences.font.family,
                    )
                  : AppTheme.fromPalette(
                      palette,
                      fontFamily: preferences.font.family,
                    ))
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
                  LayoutBuilder(
                    builder: (context, bounds) => DToggleGroup<AppThemeMode>(
                      key: const ValueKey('appearance-theme-select'),
                      values: [mode],
                      inset: true,
                      allowEmptySelection: false,
                      orientation:
                          bounds.maxWidth < 300 &&
                              MediaQuery.textScalerOf(context).scale(14) > 20
                          ? Axis.vertical
                          : Axis.horizontal,
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
                          icon: DIcon(DIcons.display),
                          child: Text('System'),
                        ),
                      ],
                      onChanged: (values) => unawaited(
                        settings.setThemeMode(widget.siteUrl, values.single),
                      ),
                    ),
                  ),
                ],
              ),
              DField(
                children: [
                  const DFieldLabel(child: Text('Font')),
                  DItemGroup(
                    spacing: 0,
                    children: [
                      for (final font in ForumFont.values) ...[
                        if (font != ForumFont.values.first)
                          const DItemSeparator(),
                        DItem(
                          key: ValueKey('appearance-font-${font.name}'),
                          selected: preferences.font == font,
                          enabled: !_saving,
                          shape: DItemShape.fullWidth,
                          selectionStyle: DItemSelectionStyle.leadingAccent,
                          onPressed: () => unawaited(_saveFont(font)),
                          children: [
                            DItemContent(
                              children: [
                                Text(
                                  font.label,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  'The quick brown fox jumps over the lazy dog.',
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: Theme.of(context).textTheme.bodyLarge!
                                      .copyWith(
                                        fontFamily:
                                            font.family ??
                                            ThemeData(
                                              platform: Theme.of(
                                                context,
                                              ).platform,
                                            ).textTheme.bodyLarge!.fontFamily,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              DCard(
                spacing: 0,
                child: DItem(
                  key: const ValueKey('forum-default-theme'),
                  shape: DItemShape.card,
                  selected:
                      preferences.selectedTheme == null && _tab != 'custom',
                  enabled: !_saving,
                  variant: DItemVariant.outline,
                  selectionStyle: DItemSelectionStyle.outline,
                  onPressed: () => unawaited(_save(preferences.select(null))),
                  children: const [
                    DItemMedia(
                      variant: DItemMediaVariant.icon,
                      child: DIcon(DIcons.house),
                    ),
                    DItemContent(
                      children: [
                        DItemTitle(child: Text('Forum default')),
                        DItemDescription(
                          child: Text('Follow this forum’s colors.'),
                        ),
                      ],
                    ),
                  ],
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
                          preferences.selectedTheme ?? forumThemePresets.first;
                      _editorBrightness = brightness;
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
                _library(preferences, brightness),
              ] else
                ForumThemeEditor(
                  key: _editorKey,
                  initialTheme: _draft ?? forumThemePresets.first,
                  customThemes: preferences.customThemes,
                  enabled: !_saving,
                  initialBrightness: _editorBrightness ?? brightness,
                  onBrightnessChanged: (value) =>
                      setState(() => _editorBrightness = value),
                  onChanged: (value) => setState(() => _draft = value),
                  onSave: (value) => _save(preferences.save(value)),
                ),
            ],
          );
          final preview = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.md,
            children: [
              Text(
                selected?.name ?? 'Forum default',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ThemePaletteStrip(theme: previewTheme),
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
                child: ColoredBox(
                  color: DTokens.of(context).muted.withValues(alpha: .35),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(DSpacing.xl),
                    child: preview,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _library(ForumThemePreferences preferences, Brightness brightness) {
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
                    child: DCard(
                      spacing: 0,
                      child: DItem(
                        key: ValueKey('forum-theme-${theme.id}'),
                        selected: preferences.selectedId == theme.id,
                        enabled: !_saving,
                        variant: DItemVariant.outline,
                        selectionStyle: DItemSelectionStyle.outline,
                        shape: DItemShape.card,
                        size: DItemSize.sm,
                        onPressed: () =>
                            unawaited(_save(preferences.select(theme.id))),
                        children: [
                          ThemeThumbnail(
                            theme: theme.forBrightness(brightness),
                          ),
                          DItemContent(
                            children: [
                              DItemTitle(maxLines: 2, child: Text(theme.name)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (preferences.selectedTheme case final selected?
                when selected.id.startsWith('custom-'))
              Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  DButton(
                    label: const Text('Edit theme'),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _draft = selected;
                            _editorBrightness = brightness;
                            _editorKey = GlobalKey();
                            _tab = 'custom';
                          }),
                  ),
                  DButton(
                    label: const Text('Delete theme'),
                    onPressed: _saving
                        ? null
                        : () =>
                              unawaited(_save(preferences.remove(selected.id))),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Decorative miniature, not an interactive replacement for a Native control.
class ThemeThumbnail extends StatelessWidget {
  const ThemeThumbnail({super.key, required this.theme});
  final ForumTheme theme;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 44,
      height: 36,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DTokens.of(context).radius),
        child: ColoredBox(
          color: theme.secondary,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 9,
                  child: ColoredBox(
                    color: Color.lerp(theme.secondary, theme.tertiary, .2)!,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 3,
                    children: [
                      for (var i = 0; i < 4; i++)
                        FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: i.isEven ? 1 : .6,
                          child: SizedBox(
                            height: 3,
                            child: ColoredBox(
                              color: i == 0
                                  ? theme.tertiary
                                  : theme.primary.withValues(alpha: .24),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ThemePaletteStrip extends StatelessWidget {
  const ThemePaletteStrip({super.key, required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.extension<DTokens>() ?? DTokens.fromTheme(theme);
    final discourse = theme.extension<DiscourseColors>()!;
    return Wrap(
      spacing: DSpacing.sm,
      runSpacing: DSpacing.sm,
      children: [
        for (final color in [
          tokens.background,
          tokens.foreground,
          theme.colorScheme.primary,
          theme.colorScheme.secondary,
          discourse.success,
          theme.colorScheme.error,
          discourse.love,
        ])
          Semantics(
            label:
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            child: SizedBox(
              width: 24,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: DTokens.of(context).border),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
