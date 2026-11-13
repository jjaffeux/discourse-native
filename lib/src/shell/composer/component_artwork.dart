import 'package:flutter/widgets.dart';

import 'artwork.dart';
import 'components/code_source.dart';
import 'components/details_source.dart';
import 'components/document_body_range.dart';
import 'components/list_source.dart';
import 'components/table_source.dart';
import 'controller.dart';

export 'component_editor.dart';

/// [ComposerArtwork] plus the core syntax components, whose widgets embed an
/// editor bound to their [ComposerController]. The core policies read it
/// through [ComposerController.artwork].
abstract interface class ComposerComponentArtwork implements ComposerArtwork {
  Widget codeBlock({
    required Key key,
    required ComposerController composer,
    required ComposerCodeBlock block,
    required bool highlighted,
    required VoidCallback? onSelect,
  });

  Widget details({
    required Key key,
    required ComposerController composer,
    required ComposerDetailsBlock block,
    required bool highlighted,
  });

  Widget table({
    required Key key,
    required ComposerController composer,
    required ComposerTableBlock table,
    required bool highlighted,
  });

  Widget listItem({
    required Key key,
    required ComposerController composer,
    required ComposerListItem item,
    required bool highlighted,
    required ScrollController? scrollController,
  });

  Widget upload({
    required Key key,
    required ComposerController composer,
    required int id,
    required bool highlighted,
  });

  Widget video({
    required Key key,
    required String? url,
    required String title,
    required String? siteUrl,
    required bool highlighted,
  });

  Widget embeddedDocument({
    required Key key,
    required ComposerController parent,
    required ComposerDocumentBodyRange range,
    required ComposerDocumentBodyRange? Function(String document, int start)
    resolveRange,
    required String semanticLabel,
  });
}
