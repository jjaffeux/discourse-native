import 'package:flutter/widgets.dart';

import '../../models/found_hashtag.dart';
import '../../plugin_api/composer_syntax.dart';
import '../../plugin_api/hashtag_kind.dart';
import 'components/gallery_source.dart';
import 'components/image_source.dart';
import 'components/link_source.dart';
import 'components/quote_source.dart';

/// How a rendered composer draws the components its document controller
/// projects: media, quotes, pills, links, keycaps and task checkboxes. The
/// controller owns every source offset, span, key and caret rule around a
/// component; the editor that renders the controller supplies these widgets,
/// so the controllers compile without the shell's widget libraries or the UI
/// kit.
///
/// Each method returns the widget placed inside the component's span, with
/// the same tree the component drew before the split, so hit regions,
/// selection and keyed lookups are unchanged.
abstract interface class ComposerArtwork {
  Widget image({
    required ComposerImageBlock image,
    required String? url,
    required String? siteUrl,
    required bool highlighted,
    required ValueChanged<Size> onNaturalSize,
    required VoidCallback? onDragStarted,
    required VoidCallback onDragEnded,
  });

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
  });

  Widget quote({
    required ComposerQuoteBlock block,
    required String contents,
    required String? siteUrl,
    required TextStyle baseStyle,
    required GlobalKey removeKey,
    required bool selected,
    required VoidCallback? onRemove,
  });

  Widget mention({required String label, required TextStyle baseStyle});

  Widget hashtag({
    required String label,
    required FoundHashtag hashtag,
    required TextStyle baseStyle,
    required String? siteUrl,
    required PluginHashtagPresentationResolver? pluginPresentation,
  });

  /// [key] identifies the pill for the controller's geometry lookups.
  /// [resolveUploadUrl] answers the preview for an attachment link.
  Widget link({
    required Key key,
    required String anchor,
    required String url,
    required TextStyle baseStyle,
    required bool highlighted,
    required bool hovered,
    required String? siteUrl,
    required String? Function(String url)? resolveUploadUrl,
  });

  Future<void> editLink(
    BuildContext context,
    ComposerEditorHost editor,
    ComposerLinkBlock link,
  );

  /// [child] is the styled text of a `<kbd>` run. [semanticLabel] names the
  /// whole key, which can span several styled runs.
  Widget keyboardKey({required String semanticLabel, required Widget child});

  /// [label] is the task's text and is empty for a task with none written
  /// yet. A null [onChanged] draws the marker read-only.
  Widget todoMarker({
    required bool checked,
    required String label,
    required TextStyle style,
    required VoidCallback? onChanged,
  });
}

/// The editor rendering a controller installs its artwork before the first
/// frame. Drawing a component with none installed is a wiring error, not a
/// state to render around.
Never composerArtworkMissing() => throw StateError(
  'This composer is rendered outside a ComposerEditor. Install a '
  'ComposerArtwork on its document controller before drawing components.',
);
