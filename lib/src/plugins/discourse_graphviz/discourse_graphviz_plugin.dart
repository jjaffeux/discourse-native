import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'graphviz_diagram.dart';

const _pluginEngines = {'dot', 'neato', 'circo', 'fdp', 'osage', 'twopi'};
const _themeEngines = {
  ..._pluginEngines,
  'nop',
  'nop1',
  'nop2',
  'patchwork',
  'sfdp',
};

final class DiscourseGraphvizPlugin implements SitePlugin, CookedElementPlugin {
  const DiscourseGraphvizPlugin();

  @override
  String get name => 'discourse-graphviz';

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
    // Older posts may already contain an image rendered by Discourse; leave
    // image and SVG children in the normal cooked pipeline.
    if (element.localName != 'div' ||
        !element.classes.contains('graphviz') ||
        element.children.isNotEmpty ||
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
