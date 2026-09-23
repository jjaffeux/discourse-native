import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../models/forum_theme.dart';
import '../../models/forum_theme_share.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icons.dart';
import '../forum_appearance_settings.dart'
    show ThemeThumbnail, ThemePaletteStrip;
import '../forum_settings_controller.dart';
import '../shell_scope.dart';

Widget? forumThemeOneboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.localName != 'pre') return null;
  final code = element.children
      .where((child) => child.localName == 'code')
      .firstOrNull;
  if (code == null ||
      (!code.classes.contains('lang-${ForumThemeShare.language}') &&
          !code.classes.contains('language-${ForumThemeShare.language}') &&
          element.attributes['data-code-wrap'] != ForumThemeShare.language)) {
    return null;
  }
  final theme = ForumThemeShare.decode(code.text);
  if (theme == null) {
    return const DAlert(
      variant: DAlertVariant.destructive,
      description: DAlertDescription(
        child: Text(
          'This shared theme is incomplete or invalid. Ask for a new copy.',
        ),
      ),
    );
  }
  return ForumThemeOnebox(theme: theme, siteUrl: siteUrl);
}

/// The same compact, self-contained theme card in posts, quotes and chat.
class ForumThemeOnebox extends StatefulWidget {
  const ForumThemeOnebox({
    super.key,
    required this.theme,
    required this.siteUrl,
    this.settings,
  });

  final ForumTheme theme;
  final String? siteUrl;

  /// A local settings store can be supplied for a standalone preview.
  final ForumSettingsController? settings;

  @override
  State<ForumThemeOnebox> createState() => _ForumThemeOneboxState();
}

class _ForumThemeOneboxState extends State<ForumThemeOnebox> {
  bool _busy = false;
  bool _canUndo = false;
  String? _previousId;
  String? _error;
  int _operation = 0;
  Brightness? _previewBrightness;

  @override
  void didUpdateWidget(ForumThemeOnebox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme ||
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.settings != widget.settings) {
      _operation++;
      _busy = false;
      _canUndo = false;
      _previousId = null;
      _error = null;
      _previewBrightness = null;
    }
  }

  Future<void> _use(
    ForumSettingsController settings,
    String site, {
    bool undo = false,
  }) async {
    if (_busy) return;
    final operation = ++_operation;
    final theme = widget.theme;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? previousId;
      if (undo) {
        final current = settings.themesFor(site);
        if (ForumThemeShare.matches(current.selectedTheme, theme)) {
          await settings.setThemes(site, current.select(_previousId));
        }
      } else {
        final previous = await settings.importTheme(site, theme);
        previousId = previous.selectedId;
      }
      if (mounted && operation == _operation) {
        setState(() {
          _previousId = previousId;
          _canUndo = !undo;
        });
      }
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(() => _error = 'Could not save theme. Try again.');
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        widget.settings ?? ShellScope.maybeIdentityOf(context)?.forumSettings;
    if (settings == null) return _card(context, null);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => _card(context, settings),
    );
  }

  Widget _card(BuildContext context, ForumSettingsController? settings) {
    final host = Theme.of(context);
    final brightness = _previewBrightness ?? host.brightness;
    final preview = AppTheme.fromPalette(widget.theme.resolve(brightness));
    final tokens = DTokens.of(context);
    final site = widget.siteUrl;
    final using =
        settings != null &&
        site != null &&
        ForumThemeShare.matches(
          settings.themesFor(site).selectedTheme,
          widget.theme,
        );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 410),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) >= 23;
            final thumbnail = Semantics(
              image: true,
              label: '${widget.theme.name} forum appearance preview',
              child: ColoredBox(
                color: preview.shell.sidebar,
                child: Padding(
                  padding: const EdgeInsets.all(DSpacing.md),
                  child: SizedBox(
                    width: stacked
                        ? null
                        : constraints.maxWidth >= 380
                        ? 122
                        : 66,
                    height: 108,
                    child: FittedBox(child: ThemeThumbnail(theme: preview)),
                  ),
                ),
              ),
            );
            final details = Padding(
              padding: const EdgeInsets.all(DSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom theme',
                    style: host.textTheme.bodySmall?.copyWith(
                      color: tokens.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: DSpacing.xs),
                  Text(widget.theme.name, style: host.textTheme.titleMedium),
                  const SizedBox(height: DSpacing.sm),
                  Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: DSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: SizedBox(
                          width: 100,
                          height: 14,
                          child: FittedBox(
                            child: ThemePaletteStrip(theme: preview),
                          ),
                        ),
                      ),
                      DToggleGroup<Brightness>(
                        key: const ValueKey('shared-theme-appearance'),
                        semanticLabel: 'Theme preview appearance',
                        values: [brightness],
                        allowEmptySelection: false,
                        variant: DToggleVariant.outline,
                        size: DToggleSize.small,
                        spacing: 0,
                        items: const [
                          DToggleGroupItem.iconOnly(
                            value: Brightness.light,
                            icon: Icon(Icons.light_mode_outlined),
                            semanticLabel: 'Preview light theme',
                            tooltip: 'Light preview',
                          ),
                          DToggleGroupItem.iconOnly(
                            value: Brightness.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            semanticLabel: 'Preview dark theme',
                            tooltip: 'Dark preview',
                          ),
                        ],
                        onChanged: (values) =>
                            setState(() => _previewBrightness = values.single),
                      ),
                    ],
                  ),
                  const SizedBox(height: DSpacing.md),
                  Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: DSpacing.controlGap,
                    children: [
                      DButton(
                        key: const ValueKey('use-shared-theme'),
                        label: Text(using ? 'Using theme' : 'Use theme'),
                        icon: DIcon(using ? DIcons.check : DIcons.chevronRight),
                        iconPosition: using
                            ? DButtonIconPosition.start
                            : DButtonIconPosition.end,
                        loading: _busy,
                        loadingSemanticLabel: 'Saving theme',
                        tooltip: settings == null || site == null
                            ? 'Open this theme in a connected forum.'
                            : null,
                        onPressed:
                            using || settings == null || site == null || _busy
                            ? null
                            : () => _use(settings, site),
                      ),
                      if (using && _canUndo)
                        DButton(
                          label: const Text('Undo'),
                          variant: DButtonVariant.transparentBackground,
                          onPressed: _busy
                              ? null
                              : () => _use(settings, site, undo: true),
                        ),
                    ],
                  ),
                ],
              ),
            );
            return DCard(
              spacing: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stacked)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [thumbnail, details],
                    )
                  else
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          thumbnail,
                          Expanded(child: details),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(DSpacing.md),
                      child: DAlert(
                        variant: DAlertVariant.destructive,
                        description: DAlertDescription(child: Text(_error!)),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
