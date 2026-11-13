import 'package:discourse_native/discourse_math_types.dart';
import 'package:discourse_native/discourse_plugin_contracts.dart';

const mathSettingsKey = PluginDataKey<MathSettings>(
  owner: 'discourse-math',
  name: 'site-settings',
);

final class MathSettings {
  const MathSettings({
    this.enabled = false,
    this.provider = 'mathjax',
    this.output = 'html',
    this.latexDelimiters = true,
    this.menu = true,
    this.zoom = false,
    this.accessibility = false,
    this.asciiMath = false,
  });

  factory MathSettings.fromWire(Map<String, dynamic> json) => MathSettings(
    enabled: json['discourse_math_enabled'] == true,
    provider: json.containsKey('discourse_math_provider')
        ? jsonText(json['discourse_math_provider']) ?? ''
        : 'mathjax',
    output: json.containsKey('discourse_math_mathjax_output')
        ? jsonText(json['discourse_math_mathjax_output']) ?? ''
        : 'html',
    latexDelimiters: json['discourse_math_enable_latex_delimiters'] != false,
    menu: json['discourse_math_enable_menu'] != false,
    zoom: json['discourse_math_zoom_on_click'] == true,
    accessibility: json['discourse_math_enable_accessibility'] == true,
    asciiMath: json['discourse_math_enable_asciimath'] == true,
  );

  final bool enabled, latexDelimiters, menu, zoom, accessibility, asciiMath;
  final String provider, output;

  DMathConfiguration? get configuration {
    if (!enabled) return null;
    return switch (provider) {
      'katex' => const DMathKatex(),
      'mathjax' => switch (output) {
        'html' => DMathJax(
          output: DMathJaxOutput.html,
          menu: menu,
          zoom: zoom,
          accessibility: accessibility,
        ),
        'svg' => DMathJax(
          output: DMathJaxOutput.svg,
          menu: menu,
          zoom: zoom,
          accessibility: accessibility,
        ),
        _ => null,
      },
      _ => null,
    };
  }

  bool get supportsAscii => enabled && provider == 'mathjax' && asciiMath;

  Map<String, Object?> toWire() => {
    'discourse_math_enabled': enabled,
    'discourse_math_provider': provider,
    'discourse_math_mathjax_output': output,
    'discourse_math_enable_latex_delimiters': latexDelimiters,
    'discourse_math_enable_menu': menu,
    'discourse_math_zoom_on_click': zoom,
    'discourse_math_enable_accessibility': accessibility,
    'discourse_math_enable_asciimath': asciiMath,
  };

  @override
  bool operator ==(Object other) =>
      other is MathSettings &&
      enabled == other.enabled &&
      provider == other.provider &&
      output == other.output &&
      latexDelimiters == other.latexDelimiters &&
      menu == other.menu &&
      zoom == other.zoom &&
      accessibility == other.accessibility &&
      asciiMath == other.asciiMath;
  @override
  int get hashCode => Object.hash(
    enabled,
    provider,
    output,
    latexDelimiters,
    menu,
    zoom,
    accessibility,
    asciiMath,
  );
}

final class MathSettingsCodec extends PluginDataPersistenceCodec<MathSettings> {
  const MathSettingsCodec();
  @override
  PluginDataKey<MathSettings> get key => mathSettingsKey;
  @override
  MathSettings? decode(Object? value) {
    final fields = jsonObjectFields(value);
    return fields == null ? null : MathSettings.fromWire(fields);
  }

  @override
  Object encode(MathSettings value) => value.toWire();
}
