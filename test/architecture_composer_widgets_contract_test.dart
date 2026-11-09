import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _composerController = 'lib/src/shell/composer/controller.dart';
const _markdownController =
    'lib/src/shell/composer/markdown_editing_controller.dart';
const _kitBarrel = 'lib/discourse_ui.dart';
const _panel = 'lib/src/shell/composer/panel.dart';
const _shellController = 'lib/src/shell/shell_controller.dart';

/// The widget libraries the composer controllers still compile. Each is a
/// leaf: it imports nothing that reaches the controllers or the shell back,
/// which the second test proves. Adding one here is a reviewed decision; the
/// component editors, pills, previews, the panel and the UI kit must stay out,
/// because they are what the artwork seam exists to remove.
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

    test(
      'no widget library the composer controller reaches imports it back',
      () {
        final reached = graph.widgetLibrariesReachedBy(_composerController);
        expect({
          for (final library in reached)
            if (graph.closureOf(library).contains(_composerController)) library,
        }, isEmpty);
      },
    );

    test('the controllers share no import cycle with the panel', () {
      final cycles = graph.cycles();
      for (final cycle in cycles.where((cycle) => cycle.contains(_panel))) {
        expect(cycle, isNot(contains(_composerController)));
        expect(cycle, isNot(contains(_markdownController)));
        expect(cycle, isNot(contains(_shellController)));
      }
    });

    test('ShellController shares no import cycle with the composer', () {
      final cycles = graph.cycles();
      for (final cycle in cycles.where(
        (cycle) => cycle.contains(_shellController),
      )) {
        expect(
          cycle.where(
            (library) => library.startsWith('lib/src/shell/composer/'),
          ),
          isEmpty,
        );
      }
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
