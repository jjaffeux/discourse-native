import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'graphviz_diagram.dart';

const _pluginEngines = {'dot', 'neato', 'circo', 'fdp', 'osage', 'twopi'};
const _id = 'discourse-graphviz';
const _enabledSetting = 'discourse_graphviz_enabled';
const _enabledKey = PluginDataKey<bool>(owner: _id, name: 'enabled');
const _themeEngines = {
  ..._pluginEngines,
  'nop',
  'nop1',
  'nop2',
  'patchwork',
  'sfdp',
};

final class DiscourseGraphvizPlugin
    implements
        SitePlugin,
        CookedElementPlugin,
        SiteSettingsPlugin<bool>,
        CookingPlugin {
  const DiscourseGraphvizPlugin();

  @override
  String get name => _id;

  @override
  PluginDataPersistenceCodec<bool> get siteSettingsCodec =>
      const _EnabledCodec();

  @override
  bool? readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      switch (json[_enabledSetting]) {
        final bool enabled => enabled,
        _ => null,
      };

  @override
  List<CookingProfile> get cookingProfiles => const [];

  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: _id,
      owner: _id,
      version: '1',
      profiles: const ['post'],
      enabledSetting: _enabledSetting,
    ),
  ];

  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) => {
    'settings': {_enabledSetting: data.read(_enabledKey) ?? false},
  };

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    final attributes = element.attributes;
    if (element.localName == 'pre' &&
        attributes['data-code-wrap'] == 'graphviz') {
      final source = element.querySelector('code')?.text;
      if (source == null || source.trim().isEmpty) return null;
      final engine = attributes['data-code-engine'];
      final height = double.tryParse(attributes['data-code-height'] ?? '');
      return GraphvizDiagram(
        source: source,
        engine: _themeEngines.contains(engine) ? engine! : 'dot',
        height: height != null && height.isFinite && height > 0
            ? height.clamp(80, 1200)
            : null,
      );
    }
    // Search highlighting can wrap parts of the DOT source in marks. Keep
    // previously rendered images and SVG in the standard cooked pipeline.
    if (element.localName != 'div' ||
        !element.classes.contains('graphviz') ||
        element.children.any(
          (child) =>
              child.localName != 'mark' ||
              !child.classes.contains('native-search-hit') ||
              child.children.isNotEmpty,
        ) ||
        element.text.trim().isEmpty) {
      return null;
    }
    final engine = attributes['data-engine'];
    return GraphvizDiagram(
      source: element.text,
      engine: _pluginEngines.contains(engine) ? engine! : 'dot',
    );
  }
}

final class _EnabledCodec extends PluginDataPersistenceCodec<bool> {
  const _EnabledCodec();

  @override
  PluginDataKey<bool> get key => _enabledKey;

  @override
  bool? decode(Object? value) => value is bool ? value : null;

  @override
  Object encode(bool value) => value;
}
