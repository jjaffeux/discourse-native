import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _composerController = 'lib/src/shell/composer/controller.dart';
const _markdownController =
    'lib/src/shell/composer/markdown_editing_controller.dart';
const _kitBarrel = 'lib/discourse_ui.dart';

/// The widget libraries the composer controllers still compile. The global
/// cycle check prevents a dependency from reaching back to the controllers.
/// Adding one here is a reviewed decision; the component editors, pills,
/// previews, panel and UI kit stay out of the artwork seam.
const _leafWidgetLibraries = {
  'lib/src/plugin_api/plugin_ui_scope.dart',
  'lib/src/shell/composer/components/blockquote.dart',
  'lib/src/shell/emoji.dart',
  'lib/src/shell/quote_panel.dart',
};

void main() {
  final graph = LibraryGraph.load();

  group('composer controllers and widgets', () {
    test('the composer controllers compile without the widget kit', () {
      final controllerReach = graph.closureOf(_composerController);
      final markdownReach = graph.closureOf(_markdownController);
      final widgets = graph.widgetLibrariesReachedBy(_composerController);
      // ignore: avoid_print
      print(
        'PERF_PROOF composer-off-kit '
        'controller_reach=${controllerReach.length} '
        'widget_libraries=${widgets.length} '
        'markdown_reach=${markdownReach.length}',
      );
      expect(controllerReach, isNot(contains(_kitBarrel)));
      expect(markdownReach, isNot(contains(_kitBarrel)));
    });

    test('the composer controller reaches only leaf widget libraries', () {
      expect(
        graph.widgetLibrariesReachedBy(_composerController),
        _leafWidgetLibraries,
      );
    });

    test('the pure link parser is what inline formatting compiles', () {
      expect(
        graph.edges['lib/src/shell/composer/inline_formatting.dart'],
        isNot(contains('lib/src/shell/composer/components/link.dart')),
      );
      expect(
        graph.edges['lib/src/shell/composer/inline_formatting.dart'],
        contains('lib/src/shell/composer/components/link_source.dart'),
      );
    });
  });
}
