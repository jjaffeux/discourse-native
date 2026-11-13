import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _composerController = 'lib/src/shell/composer/controller.dart';
const _markdownController =
    'lib/src/shell/composer/markdown_editing_controller.dart';
const _shellScope = 'lib/src/shell/shell_scope.dart';
const _accountHosts = [
  'lib/src/shell/header_preferences.dart',
  'lib/src/shell/mobile_place_order.dart',
];
const _userCard = 'lib/src/shell/user_card.dart';
const _cookedHtml = 'lib/src/shell/cooked_html.dart';
const _titleBar = 'lib/src/shell/title_bar.dart';
const _composerPanel = 'lib/src/shell/composer/panel.dart';
const _composerPresentation = 'lib/src/shell/composer/presentation.dart';
const _adaptiveShell = 'lib/src/shell/adaptive_shell.dart';
const _desktopPanels = 'lib/src/shell/desktop_panels.dart';
const _mainContent = 'lib/src/shell/main_content.dart';

/// Cooked HTML is a recursive grammar: a quote, an image-grid item, and a
/// onebox each hold cooked HTML, so these libraries render one another.
const _cookedRecursion = [
  _cookedHtml,
  'lib/src/shell/image_grid.dart',
  'lib/src/shell/oneboxes/onebox.dart',
  'lib/src/shell/oneboxes/twitter.dart',
  'lib/src/shell/quote.dart',
];

/// The controller constructs its core syntax policies, and each policy and
/// the artwork that draws it are written against that controller.
const _composerControllerCycle = [
  'lib/src/shell/composer/component_artwork.dart',
  'lib/src/shell/composer/components/code.dart',
  'lib/src/shell/composer/components/core.dart',
  'lib/src/shell/composer/components/details.dart',
  'lib/src/shell/composer/components/document_body_controller.dart',
  'lib/src/shell/composer/components/list.dart',
  _composerController,
];

void main() {
  final graph = LibraryGraph.load();

  group('shell widget cycles', () {
    test('cooked rendering is the only widget cycle in the shell', () {
      expect(
        graph.cycles().where((cycle) => !cycle.contains(_composerController)),
        [_cookedRecursion],
      );
    });

    test('drawing an emoji or a bookmark item does not compile the shell', () {
      for (final library in const [
        'lib/src/shell/site_emoji_image.dart',
        'lib/src/shell/site_emoji_text.dart',
        'lib/src/shell/topic_title.dart',
        'lib/src/shell/destination_bookmark_menu_item.dart',
      ]) {
        expect(
          graph.closureOf(library),
          isNot(contains('lib/src/shell/shell_controller.dart')),
          reason: library,
        );
      }
    });

    test('naming a user or following a link does not compile the card', () {
      for (final library in const [
        'lib/src/shell/open_link.dart',
        'lib/src/shell/user_card_target.dart',
        'lib/src/shell/site_image.dart',
        'lib/src/shell/mention.dart',
        'lib/src/shell/topic_list_view.dart',
      ]) {
        expect(
          graph.closureOf(library).intersection(const {_userCard, _cookedHtml}),
          isEmpty,
          reason: library,
        );
      }
    });

    test('the lightbox does not compile the title bar', () {
      expect(
        graph.closureOf('lib/src/shell/lightbox.dart'),
        isNot(contains(_titleBar)),
      );
    });

    test('shell chrome asks about the composer without compiling it', () {
      for (final library in const [
        'lib/src/shell/composer/presentation_scope.dart',
        'lib/src/shell/composer/draft_tabs.dart',
        'lib/src/shell/composer/placement_icon.dart',
        'lib/src/shell/shell_panel.dart',
        'lib/src/shell/reader_content_bounds.dart',
        'lib/src/shell/topic_corner_controls.dart',
      ]) {
        expect(
          graph.closureOf(library).intersection(const {
            _composerPanel,
            _composerPresentation,
          }),
          isEmpty,
          reason: library,
        );
      }
    });

    test('component editors embed a body without compiling the editor', () {
      for (final library in const [
        'lib/src/shell/composer/components/details_editor.dart',
        'lib/src/shell/composer/components/document_body_editor.dart',
        'lib/src/shell/composer/components/list_item_editor.dart',
      ]) {
        expect(
          graph.closureOf(library),
          isNot(contains(_composerPanel)),
          reason: library,
        );
      }
    });

    test('the shell scope mounts its account hosts one way', () {
      for (final host in _accountHosts) {
        expect(
          graph.closureOf(host),
          isNot(contains(_shellScope)),
          reason: host,
        );
      }
    });

    test('page composition depends downward', () {
      for (final library in const [_desktopPanels, _mainContent]) {
        expect(
          graph.closureOf(library),
          isNot(contains(_adaptiveShell)),
          reason: library,
        );
      }
      expect(graph.closureOf(_mainContent), isNot(contains(_desktopPanels)));
      expect(graph.closureOf(_titleBar), isNot(contains(_mainContent)));
    });
  });

  group('composer controller cycle', () {
    test(
      'the markdown controller compiles without the composer controller',
      () {
        expect(
          graph.closureOf(_markdownController),
          isNot(contains(_composerController)),
        );
      },
    );

    test('independent syntax policies compile without the composer controller', () {
      for (final name in const ['table', 'upload', 'video']) {
        final library = 'lib/src/shell/composer/components/$name.dart';
        expect(graph.edges, contains(library));
        expect(graph.closureOf(library), isNot(contains(_composerController)));
      }
    });

    test('the cycle holds only the controller and its core policies', () {
      expect(
        graph.cycles().where((cycle) => cycle.contains(_composerController)),
        [_composerControllerCycle],
      );
    });
  });
}
