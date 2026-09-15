import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../../plugin_api/site_plugin_api.dart';
import '../../theme/d_icons.dart';

/// Reader support follows Discourse's cooked marker, not theme installation.
final class DiscourseMermaidPlugin
    implements SitePlugin, CookedElementPlugin, ComposerToolbarPlugin {
  const DiscourseMermaidPlugin();

  @override
  String get name => 'discourse-mermaid';

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    if (element.localName != 'pre' ||
        element.attributes['data-code-wrap'] != 'mermaid') {
      return null;
    }
    final source = element.querySelector('code')?.text;
    if (source == null || source.trim().isEmpty) return null;
    final height = double.tryParse(
      element.attributes['data-code-height'] ?? '',
    );
    return DMermaid(
      source: source,
      height: height != null && height.isFinite && height > 0
          ? height.clamp(80, 1200)
          : null,
    );
  }

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) {
    if (!editor.isCurrent || !editor.isEditing || editor.loadingBody) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.code,
        label: 'Mermaid chart',
        onInvoke: () {
          if (!editor.isCurrent || !editor.isEditing || editor.loadingBody) {
            return;
          }
          if (editor.insertBlock(
            expectedValue: editor.value,
            markdown: '```mermaid\nflowchart TD\n    A --> B\n```',
          )) {
            editor.requestFocus();
          }
        },
      ),
    ];
  }
}
