import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/plugin_api/hashtag_kind.dart';
import 'package:discourse_native/src/shell/composer/component_artwork.dart';
import 'package:discourse_native/src/shell/composer/components/code_source.dart';
import 'package:discourse_native/src/shell/composer/components/details_source.dart';
import 'package:discourse_native/src/shell/composer/components/document_body_controller.dart';
import 'package:discourse_native/src/shell/composer/components/gallery_source.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/components/link_source.dart';
import 'package:discourse_native/src/shell/composer/components/list_source.dart';
import 'package:discourse_native/src/shell/composer/components/quote_source.dart';
import 'package:discourse_native/src/shell/composer/components/table_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);

const _source =
    '| a | b |\n| - | - |\n| 1 | 2 |\n\n'
    '```dart\nmain();\n```\n\n'
    '[details="Summary"]\nhidden\n[/details]\n\n'
    '- an item\n\n'
    '![photo](https://example.test/p.png)\n\n'
    '![clip|video](https://example.test/clip.mp4)\n\n'
    'see [Docs](https://example.test/docs) now\n';

ComposerController _composer() {
  final composer = ComposerController(_target);
  composer.text.value = const TextEditingValue(
    text: _source,
    selection: TextSelection.collapsed(offset: 0),
  );
  addTearDown(composer.dispose);
  return composer;
}

Future<void> _pump(WidgetTester tester, ComposerController composer) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: TextField(controller: composer.text, maxLines: null),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'drawing a component with no artwork installed is a wiring error',
    (tester) async {
      await _pump(tester, _composer());
      final error = tester.takeException();
      expect(error, isA<StateError>());
      expect('$error', contains('ComposerEditor'));
    },
  );

  testWidgets(
    'every core projection hands its parsed component to the artwork',
    (tester) async {
      final composer = _composer();
      final artwork = _RecordingArtwork();
      composer.artwork = artwork;
      await _pump(tester, composer);
      expect(tester.takeException(), isNull);
      expect(
        artwork.drawn,
        containsAll([
          'table 1x2',
          'code dart main();',
          'details Summary',
          'list an item',
          'image https://example.test/p.png',
          'video https://example.test/clip.mp4',
          'link Docs https://example.test/docs',
        ]),
      );
      expect(find.byType(_Drawn), findsNWidgets(artwork.drawn.length));
    },
  );

  testWidgets('keycaps and task checkboxes are drawn by the artwork', (
    tester,
  ) async {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);
    composer.text.value = const TextEditingValue(
      text: 'press <kbd>K</kbd> now\n\n[ ] task\n\nend',
      selection: TextSelection.collapsed(offset: 0),
    );
    final artwork = _RecordingArtwork();
    composer.artwork = artwork;
    await _pump(tester, composer);
    expect(tester.takeException(), isNull);
    expect(artwork.drawn, containsAll(['key K', 'todo task unchecked']));
  });

  testWidgets('editing a projection reaches its component through the key', (
    tester,
  ) async {
    final composer = _composer();
    final artwork = _RecordingArtwork();
    composer.artwork = artwork;
    await _pump(tester, composer);
    final context = tester.element(find.byType(TextField));
    for (final occurrence in composer.text.syntaxBlocks) {
      occurrence.projection.edit(context, composer);
    }
    expect(
      artwork.edited,
      containsAll(['table', 'code', 'details', 'list', 'link Docs']),
    );
  });

  test('the document controller shares the artwork the composer receives', () {
    final composer = _composer();
    final artwork = _RecordingArtwork();
    composer.artwork = artwork;
    expect(composer.text.artwork, same(artwork));
    expect(composer.artwork, same(artwork));
  });
}

/// Records what each projection asks for and draws a box in its place.
final class _RecordingArtwork
    implements ComposerComponentArtwork<ComposerController> {
  final drawn = <String>[];
  final edited = <String>[];

  Widget _draw(String what, {Key? key, String? editName}) {
    drawn.add(what);
    return _Drawn(
      key: key,
      onEdit: editName == null ? null : () => edited.add(editName),
    );
  }

  @override
  Widget codeBlock({
    required Key key,
    required ComposerController composer,
    required ComposerCodeBlock block,
    required bool highlighted,
    required VoidCallback? onSelect,
  }) => _draw(
    'code ${block.language} ${block.body.trim()}',
    key: key,
    editName: 'code',
  );

  @override
  Widget details({
    required Key key,
    required ComposerController composer,
    required ComposerDetailsBlock block,
    required bool highlighted,
  }) => _draw('details ${block.summary}', key: key, editName: 'details');

  @override
  Widget table({
    required Key key,
    required ComposerController composer,
    required ComposerTableBlock table,
    required bool highlighted,
  }) => _draw(
    'table ${table.rowCount}x${table.columnCount}',
    key: key,
    editName: 'table',
  );

  @override
  Widget listItem({
    required Key key,
    required ComposerController composer,
    required ComposerListItem item,
    required bool highlighted,
    required ScrollController? scrollController,
  }) => _draw('list ${item.body.text}', key: key, editName: 'list');

  @override
  Widget upload({
    required Key key,
    required ComposerController composer,
    required int id,
    required bool highlighted,
  }) => _draw('upload $id', key: key);

  @override
  Widget video({
    required Key key,
    required String? url,
    required String title,
    required String? siteUrl,
    required bool highlighted,
  }) => _draw('video $url', key: key);

  @override
  Widget embeddedDocument({
    required Key key,
    required ComposerController parent,
    required ComposerDocumentBodyRange range,
    required ComposerDocumentBodyRange? Function(String document, int start)
    resolveRange,
    required String semanticLabel,
  }) => _draw('body $semanticLabel', key: key);

  @override
  Widget image({
    required ComposerImageBlock image,
    required String? url,
    required String? siteUrl,
    required bool highlighted,
    required ValueChanged<Size> onNaturalSize,
    required VoidCallback? onDragStarted,
    required VoidCallback onDragEnded,
  }) => _draw('image $url');

  @override
  Widget gallery({
    required ComposerImageGalleryBlock gallery,
    required String? siteUrl,
    required bool highlighted,
    required String? Function(ComposerImageBlock image) resolveUrl,
    required Key Function(ComposerImageBlock image) imageKey,
    required bool Function(ComposerImageBlock image) imageHighlighted,
    required void Function(ComposerImageBlock image, Size size) onNaturalSize,
    required VoidCallback? onEdit,
    required void Function(ComposerImageBlock image, int index)? onReorder,
    required ValueChanged<ComposerImageBlock> onReorderStarted,
    required ValueChanged<ComposerImageBlock> onReorderEnded,
  }) => _draw('gallery ${gallery.images.length}');

  @override
  Widget quote({
    required ComposerQuoteBlock block,
    required String contents,
    required String? siteUrl,
    required TextStyle baseStyle,
    required GlobalKey removeKey,
    required bool selected,
    required VoidCallback? onRemove,
  }) => _draw('quote $contents');

  @override
  Widget mention({required String label, required TextStyle baseStyle}) =>
      _draw('mention $label');

  @override
  Widget hashtag({
    required String label,
    required FoundHashtag hashtag,
    required TextStyle baseStyle,
    required String? siteUrl,
    required PluginHashtagPresentationResolver? pluginPresentation,
  }) => _draw('hashtag $label');

  @override
  Widget link({
    required Key key,
    required String anchor,
    required String url,
    required TextStyle baseStyle,
    required bool highlighted,
    required bool hovered,
    required String? siteUrl,
    required String? Function(String url)? resolveUploadUrl,
  }) => _draw('link $anchor $url', key: key);

  @override
  Future<void> editLink(
    BuildContext context,
    ComposerEditorHost editor,
    ComposerLinkBlock link,
  ) async {
    edited.add('link ${link.anchor}');
  }

  @override
  Widget keyboardKey({required String semanticLabel, required Widget child}) =>
      _draw('key $semanticLabel');

  @override
  Widget todoMarker({
    required bool checked,
    required String label,
    required TextStyle style,
    required VoidCallback? onChanged,
  }) => _draw('todo $label ${checked ? 'checked' : 'unchecked'}');
}

class _Drawn extends StatefulWidget {
  const _Drawn({super.key, required this.onEdit});

  final VoidCallback? onEdit;

  @override
  State<_Drawn> createState() => _DrawnState();
}

class _DrawnState extends State<_Drawn> implements ComposerComponentEditor {
  @override
  void edit() => widget.onEdit?.call();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 40, height: 20);
}
