import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import 'settings_section.dart';
import 'theme_icons.dart';

/// The window effects every forum shares, drawn over whichever colours it
/// uses. They are chosen here rather than inside a theme so they are found
/// without making one, and so moving between forums never changes them.
class ForumAppearanceEffects extends StatelessWidget {
  const ForumAppearanceEffects({
    super.key,
    required this.effects,
    required this.onChanged,
    this.trailing,
  });

  final ForumBackground effects;
  final ValueChanged<ForumBackground> onChanged;

  /// The section heading's trailing label.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final textureEnabled = effects.effect != ForumBackgroundEffect.normal;
    return SettingsSection(
      title: 'Effects',
      icon: const ThemeIcon(ThemeIcons.background),
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          _RampField(
            label: 'Tint',
            value: effects.strength,
            readout:
                '${(effects.strength * ForumBackground.maxTint * 100).round()}%',
            ramp: DSliderRamp(
              startColor: tokens.background,
              endColor: Color.lerp(
                tokens.background,
                tokens.primary,
                ForumBackground.maxTint,
              ),
            ),
            onChanged: (v) => onChanged(effects.copyWith(strength: v)),
          ),
          _RampField(
            label: 'Opacity',
            value: 1 - effects.transparency / ForumBackground.maxTransparency,
            readout: '${((1 - effects.transparency) * 100).round()}%',
            ramp: DSliderRamp(
              startColor: tokens.background.withValues(
                alpha: 1 - ForumBackground.maxTransparency,
              ),
              endColor: tokens.background,
              pattern: DSliderRampPattern.checkerboard,
            ),
            onChanged: (v) => onChanged(
              effects.copyWith(
                transparency: (1 - v) * ForumBackground.maxTransparency,
              ),
            ),
          ),
          DField(
            children: [
              const DFieldLabel(child: Text('Texture')),
              DToggleGroup<ForumBackgroundEffect>(
                key: const ValueKey('theme-texture'),
                values: [effects.effect],
                allowEmptySelection: false,
                inset: true,
                expanded: true,
                density: DToggleDensity.tile,
                semanticLabel: 'Texture',
                items: const [
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.normal,
                    icon: ThemeIcon(ThemeIcons.none),
                    child: Text('None'),
                  ),
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.paper,
                    icon: ThemeIcon(ThemeIcons.paper),
                    child: Text('Paper'),
                  ),
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.lava,
                    icon: ThemeIcon(ThemeIcons.lava),
                    child: Text('Lava lamp'),
                  ),
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.gradient,
                    icon: ThemeIcon(ThemeIcons.gradient),
                    child: Text('Gradient'),
                  ),
                ],
                onChanged: (values) =>
                    onChanged(effects.copyWith(effect: values.single)),
              ),
            ],
          ),
          _RampField(
            label: 'Intensity',
            value: effects.noiseIntensity,
            ramp: DSliderRamp(
              startColor: Color.lerp(tokens.background, Colors.black, .14),
              pattern: DSliderRampPattern.wave,
            ),
            onChanged: textureEnabled
                ? (v) => onChanged(effects.copyWith(noiseIntensity: v))
                : null,
          ),
        ],
      ),
    );
  }
}

class _RampField extends StatelessWidget {
  const _RampField({
    required this.label,
    required this.value,
    required this.ramp,
    required this.onChanged,
    this.readout,
  });
  final String label;
  final double value;
  final DSliderRamp ramp;
  final ValueChanged<double>? onChanged;
  final String? readout;

  @override
  Widget build(BuildContext context) => DField(
    children: [
      Opacity(
        opacity: onChanged == null ? .4 : 1,
        child: Row(
          children: [
            Expanded(child: DFieldLabel(child: Text(label))),
            Text(
              readout ?? '${(value * 100).round()}%',
              style: TextStyle(
                color: DTokens.of(context).mutedForeground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      DSlider(
        key: ValueKey('theme-${label.toLowerCase()}'),
        value: value * 100,
        variant: DSliderVariant.ramp,
        ramp: ramp,
        semanticLabel: label,
        semanticFormatterCallback: (_) =>
            readout ?? '${(value * 100).round()}%',
        onChanged: onChanged == null ? null : (v) => onChanged!(v / 100),
      ),
    ],
  );
}
