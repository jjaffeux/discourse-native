import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/discourse_ui.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../models/forum_background.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_presets.dart';

class ForumThemeEditor extends StatefulWidget {
  const ForumThemeEditor({
    super.key,
    required this.initialTheme,
    required this.customThemes,
    required this.onChanged,
    required this.onSave,
    this.enabled = true,
    this.initialBrightness,
    this.onBrightnessChanged,
  });

  final ForumTheme initialTheme;
  final List<ForumTheme> customThemes;
  final ValueChanged<ForumTheme> onChanged;
  final Future<void> Function(ForumTheme) onSave;
  final bool enabled;
  final Brightness? initialBrightness;
  final ValueChanged<Brightness>? onBrightnessChanged;

  @override
  State<ForumThemeEditor> createState() => _ForumThemeEditorState();
}

class _ForumThemeEditorState extends State<ForumThemeEditor> {
  static const _roles = {
    'secondary': 'Background',
    'primary': 'Text',
    'tertiary': 'Accent',
    'quaternary': 'Highlight',
    'success': 'Success',
    'danger': 'Attention',
    'love': 'Reactions',
  };
  late String _id;
  late final TextEditingController _name;
  late Brightness _brightness;
  late final Map<Brightness, _AppearanceDraft> _appearances;
  _AppearanceDraft get _appearance => _appearances[_brightness]!;
  String? _notice;
  bool _transferring = false;
  static const _jsonTypes = [
    selector.XTypeGroup(
      label: 'JSON theme',
      extensions: ['json'],
      mimeTypes: ['application/json'],
      uniformTypeIdentifiers: ['public.json'],
    ),
  ];
  final _random = Random();

  String _newId() => 'custom-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final theme = widget.initialTheme;
    _id = theme.id.startsWith('custom-') ? theme.id : _newId();
    _name = TextEditingController(
      text: theme.id.startsWith('custom-')
          ? theme.name
          : '${theme.name} custom',
    );
    _brightness = widget.initialBrightness ?? theme.brightness;
    _appearances = {
      for (final mode in Brightness.values)
        mode: _AppearanceDraft(theme.forBrightness(mode), _roles.keys),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    for (final appearance in _appearances.values) {
      appearance.dispose();
    }
    super.dispose();
  }

  ForumTheme? get _theme {
    try {
      return ForumTheme.fromJson({
        ..._appearance.toJson(_name.text, _brightness),
        'alternate': _appearances[_otherBrightness]!.toJson(
          _name.text,
          _otherBrightness,
        ),
      }, id: _id);
    } on FormatException {
      return null;
    }
  }

  Brightness get _otherBrightness =>
      _brightness == Brightness.light ? Brightness.dark : Brightness.light;

  void _changeBrightness(Brightness? brightness) {
    if (brightness == null || brightness == _brightness) return;
    _brightness = brightness;
    _changed('');
    widget.onBrightnessChanged?.call(brightness);
  }

  void _changed(String _) {
    for (final entry in _appearance.colors.entries) {
      final color = ForumTheme.parseHex(entry.value.text);
      if (color != null) _appearance.lastColors[entry.key] = color;
    }
    setState(() => _notice = null);
    final theme = _theme;
    if (theme != null) widget.onChanged(theme);
  }

  void _usePalette(ForumTheme theme, {bool imported = false}) {
    if (imported) {
      _id = _newId();
      _name.text = theme.name;
      _brightness = theme.brightness;
      for (final mode in Brightness.values) {
        _appearances[mode]!.load(theme.forBrightness(mode), baseId: null);
      }
      widget.onBrightnessChanged?.call(_brightness);
    } else {
      _appearance.load(theme.forBrightness(_brightness), baseId: theme.id);
    }
    _changed('');
  }

  void _surprise() {
    final base = forumThemePresets[_random.nextInt(forumThemePresets.length)]
        .forBrightness(_brightness);
    final accents = ['#47798B', '#9772A5', '#C28B45', '#4E8E7D', '#AB6674']
        .where(
          (color) =>
              color != _appearance.colors['tertiary']!.text.toUpperCase(),
        )
        .toList();
    _appearance.baseId = base.id;
    _brightness = base.brightness;
    final colors = base.toJson()['colors'] as Map<String, String>;
    for (final entry in _appearance.colors.entries) {
      entry.value.text = colors[entry.key]!;
    }
    _appearance.colors['tertiary']!.text =
        accents[_random.nextInt(accents.length)];
    _changed('');
  }

  Future<void> _import() async {
    setState(() {
      _transferring = true;
      _notice = null;
    });
    try {
      final file = await selector.openFile(acceptedTypeGroups: _jsonTypes);
      if (file == null || !mounted) return;
      if (await file.length() > 65536) throw const FormatException();
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) throw const FormatException();
      final theme = ForumTheme.fromJson(value, id: 'import');
      if (mounted) _usePalette(theme, imported: true);
    } on FormatException {
      if (mounted) setState(() => _notice = 'Choose a valid theme JSON file.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not read theme file.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _export() async {
    final theme = _theme;
    if (theme == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final stem = theme.name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final filename = '${stem.isEmpty ? 'theme' : stem}.json';
    final bytes = Uint8List.fromList(
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(theme.toJson())}\n',
      ),
    );
    setState(() {
      _transferring = true;
      _notice = null;
    });
    try {
      if (!kIsWeb &&
          {
            TargetPlatform.macOS,
            TargetPlatform.windows,
            TargetPlatform.linux,
          }.contains(defaultTargetPlatform)) {
        final location = await selector.getSaveLocation(
          suggestedName: filename,
          acceptedTypeGroups: _jsonTypes,
        );
        if (location == null || !mounted) return;
        await selector.XFile.fromData(
          bytes,
          name: filename,
          mimeType: 'application/json',
        ).saveTo(location.path);
        if (mounted) setState(() => _notice = 'Theme exported.');
      } else {
        await sharing.SharePlus.instance.share(
          sharing.ShareParams(
            files: [
              sharing.XFile.fromData(
                bytes,
                name: filename,
                mimeType: 'application/json',
              ),
            ],
            fileNameOverrides: [filename],
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not export theme.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final valid = theme != null;
    final enabled = widget.enabled && !_transferring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        DInput(
          key: const ValueKey('custom-theme-name'),
          labelText: 'Name',
          controller: _name,
          maxLength: 48,
          enabled: enabled,
          errorText: _name.text.trim().isEmpty ? 'Enter a name.' : null,
          onChanged: _changed,
        ),
        DTabs<Brightness>.controlled(
          value: _brightness,
          enabled: enabled,
          onChanged: _changeBrightness,
          children: [
            const DTabList<Brightness>(
              variant: DTabListVariant.line,
              children: [
                DTabTrigger(
                  key: ValueKey('custom-theme-light-tab'),
                  value: Brightness.light,
                  child: Text('Light'),
                ),
                DTabTrigger(
                  key: ValueKey('custom-theme-dark-tab'),
                  value: Brightness.dark,
                  child: Text('Dark'),
                ),
              ],
            ),
            DTabPanel(
              key: ValueKey(_brightness),
              value: _brightness,
              child: _appearanceControls(enabled, theme),
            ),
          ],
        ),
        if (!valid)
          const DAlert(
            description: DAlertDescription(
              child: Text(
                'Enter a name and valid colors in both appearance tabs.',
              ),
            ),
          ),
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: DSpacing.controlGap,
          overflowSpacing: DSpacing.sm,
          children: [
            Wrap(
              spacing: DSpacing.controlGap,
              runSpacing: DSpacing.sm,
              children: [
                DButton(
                  variant: DButtonVariant.outline,
                  label: const Text('Import'),
                  onPressed: enabled ? _import : null,
                ),
                DButton(
                  variant: DButtonVariant.outline,
                  label: const Text('Export'),
                  onPressed: enabled && valid ? _export : null,
                ),
                DButton(
                  variant: DButtonVariant.outline,
                  label: const Text('Surprise me'),
                  onPressed: enabled ? _surprise : null,
                ),
              ],
            ),
            DButton(
              key: const ValueKey('save-custom-theme'),
              variant: DButtonVariant.primary,
              label: const Text('Save theme'),
              onPressed: enabled && valid ? () => widget.onSave(theme) : null,
            ),
          ],
        ),
        if (_notice != null)
          Text(_notice!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _appearanceControls(bool enabled, ForumTheme? theme) {
    final presets = [...forumThemePresets, ...widget.customThemes];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        _backgroundControls(enabled),
        DSelect<String>.controlled(
          semanticLabel: 'Start from',
          value: presets.any((p) => p.id == _appearance.baseId)
              ? _appearance.baseId
              : null,
          label: const Text('Start from'),
          isExpanded: true,
          entries: [
            for (final preset in presets)
              DSelectOption(
                value: preset.id,
                label: preset.name,
                child: Text(preset.name),
              ),
          ],
          onChanged: enabled
              ? (id) {
                  if (id != null) {
                    _usePalette(presets.firstWhere((p) => p.id == id));
                  }
                }
              : null,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(14) < 21
                ? 2
                : 1;
            return Wrap(
              spacing: DSpacing.md,
              runSpacing: DSpacing.md,
              children: [
                for (final entry in _appearance.colors.entries)
                  SizedBox(
                    width:
                        (constraints.maxWidth - DSpacing.md * (columns - 1)) /
                        columns,
                    child: DInput(
                      key: ValueKey('custom-theme-${entry.key}'),
                      controller: entry.value,
                      labelText: _roles[entry.key],
                      semanticLabel: '${_roles[entry.key]} color',
                      prefix: DColorPicker(
                        semanticLabel:
                            'Choose ${_roles[entry.key]!.toLowerCase()} color',
                        value:
                            ForumTheme.parseHex(entry.value.text) ??
                            _appearance.lastColors[entry.key]!,
                        onChanged: enabled
                            ? (color) {
                                entry.value.text = ForumTheme.hex(color);
                                _changed('');
                              }
                            : null,
                      ),
                      textDirection: TextDirection.ltr,
                      enabled: enabled,
                      autocorrect: false,
                      maxLength: 7,
                      errorText: ForumTheme.parseHex(entry.value.text) == null
                          ? 'Use #RRGGBB.'
                          : null,
                      onChanged: _changed,
                    ),
                  ),
              ],
            );
          },
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DToggle(
            key: const ValueKey('custom-theme-darker-sidebars'),
            pressed: _appearance.darkerSidebars,
            enabled: enabled,
            variant: DToggleVariant.outline,
            onPressedChanged: (value) {
              _appearance.darkerSidebars = value;
              _changed('');
            },
            child: const Text('Darker sidebars'),
          ),
        ),
        const Text('Use darker backgrounds for forum and chat navigation.'),
        if (theme != null && _contrast(theme) < 4.5)
          const DAlert(
            description: DAlertDescription(
              child: Text('Text contrast is below 4.5:1.'),
            ),
          ),
      ],
    );
  }

  void _changeBackground(ForumBackground background) {
    _appearance.background = background;
    _appearance.backgroundEdited = true;
    _appearance.windowGradient = false;
    _changed('');
  }

  Widget _backgroundControls(bool enabled) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final hsl = HSLColor.fromColor(_appearance.background.color);
    final accent = hsl
        .withLightness(
          theme.brightness == Brightness.dark
              ? max(.6, hsl.lightness)
              : min(.42, hsl.lightness),
        )
        .toColor();
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values,
          tokens.copyWith(colors: tokens.colors.copyWith(primary: accent)),
        ],
      ),
      child: DField(
        children: [
          const DFieldLabel(child: Text('Background')),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.sm,
            children: [
              Column(
                children: [
                  SizedBox(
                    height: 136,
                    child: DSlider(
                      key: const ValueKey('custom-theme-strength'),
                      variant: DSliderVariant.filled,
                      orientation: Axis.vertical,
                      value: _appearance.background.strength * 100,
                      semanticLabel: 'Background strength',
                      semanticFormatterCallback: (value) => '${value.round()}%',
                      onChanged: enabled
                          ? (value) => _changeBackground(
                              _appearance.background.copyWith(
                                strength: value / 100,
                              ),
                            )
                          : null,
                    ),
                  ),
                  Text('${(_appearance.background.strength * 100).round()}%'),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DSpacing.sm,
                  children: [
                    DColorPicker.inline(
                      value: _appearance.background.color,
                      semanticLabel: 'Background color palette',
                      onChanged: enabled
                          ? (color) => _changeBackground(
                              _appearance.background.copyWith(color: color),
                            )
                          : null,
                    ),
                    Text(
                      ForumTheme.hex(_appearance.background.color),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              IntrinsicWidth(
                child: DToggleGroup<ForumBackgroundEffect>(
                  scrollable: false,
                  key: const ValueKey('custom-theme-background-effect'),
                  orientation: Axis.vertical,
                  variant: DToggleVariant.outline,
                  values: [_appearance.background.effect],
                  allowEmptySelection: false,
                  enabled: enabled,
                  items: const [
                    DToggleGroupItem.iconOnly(
                      value: ForumBackgroundEffect.normal,
                      icon: Icon(Icons.crop_square_rounded),
                      semanticLabel: 'Normal background',
                      tooltip: 'Normal',
                    ),
                    DToggleGroupItem.iconOnly(
                      value: ForumBackgroundEffect.lava,
                      icon: Icon(Icons.blur_on_rounded),
                      semanticLabel: 'Lava lamp background',
                      tooltip: 'Lava lamp',
                    ),
                    DToggleGroupItem.iconOnly(
                      value: ForumBackgroundEffect.noise,
                      icon: Icon(Icons.grain_rounded),
                      semanticLabel: 'Noise background',
                      tooltip: 'Noise',
                    ),
                  ],
                  onChanged: (values) => _changeBackground(
                    _appearance.background.copyWith(effect: values.single),
                  ),
                  onItemActivated: (effect) {
                    if (effect == _appearance.background.effect &&
                        !_appearance.backgroundEdited) {
                      _changeBackground(
                        _appearance.background.copyWith(effect: effect),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          if (_appearance.background.effect == ForumBackgroundEffect.noise)
            DField(
              children: [
                DFieldLabel(
                  child: Text(
                    'Noise intensity · ${(_appearance.background.noiseIntensity * 100).round()}%',
                  ),
                ),
                DSlider(
                  key: const ValueKey('custom-theme-noise-intensity'),
                  value: _appearance.background.noiseIntensity * 100,
                  semanticLabel: 'Noise intensity',
                  semanticFormatterCallback: (value) => '${value.round()}%',
                  onChanged: enabled
                      ? (value) => _changeBackground(
                          _appearance.background.copyWith(
                            noiseIntensity: value / 100,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          DField(
            children: [
              DFieldLabel(
                child: Text(
                  'Panel transparency · ${(_appearance.background.transparency * 100).round()}%',
                ),
              ),
              DSlider(
                key: const ValueKey('custom-theme-transparency'),
                value: _appearance.background.transparency * 100,
                max: ForumBackground.maxTransparency * 100,
                semanticLabel: 'Panel transparency',
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChanged: enabled
                    ? (value) => _changeBackground(
                        _appearance.background.copyWith(
                          transparency: value / 100,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _contrast(ForumTheme theme) {
    final a = theme.primary.computeLuminance();
    final b = theme.secondary.computeLuminance();
    return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
  }
}

class _AppearanceDraft {
  _AppearanceDraft(ForumTheme theme, Iterable<String> roles) {
    final values = theme.toJson()['colors'] as Map<String, String>;
    colors = {
      for (final role in roles) role: TextEditingController(text: values[role]),
    };
    lastColors = {
      for (final role in roles) role: ForumTheme.parseHex(values[role]!)!,
    };
    load(theme, baseId: theme.id);
  }

  late final Map<String, TextEditingController> colors;
  late final Map<String, Color> lastColors;
  late ForumBackground background;
  late bool backgroundEdited;
  late bool windowGradient;
  late bool darkerSidebars;
  String? baseId;

  void load(ForumTheme theme, {required String? baseId}) {
    this.baseId = baseId;
    background = theme.background ?? ForumBackground(color: theme.tertiary);
    backgroundEdited = theme.background != null;
    windowGradient = theme.windowGradient;
    darkerSidebars = theme.darkerSidebars;
    final values = theme.toJson()['colors'] as Map<String, String>;
    for (final entry in colors.entries) {
      entry.value.text = values[entry.key]!;
      lastColors[entry.key] = ForumTheme.parseHex(values[entry.key]!)!;
    }
  }

  Map<String, dynamic> toJson(String name, Brightness brightness) => {
    'version': 1,
    'name': name,
    'mode': brightness.name,
    if (backgroundEdited) 'background': background.toJson(),
    'windowGradient': windowGradient,
    'darkerSidebars': darkerSidebars,
    'colors': {for (final entry in colors.entries) entry.key: entry.value.text},
  };

  void dispose() {
    for (final controller in colors.values) {
      controller.dispose();
    }
  }
}
