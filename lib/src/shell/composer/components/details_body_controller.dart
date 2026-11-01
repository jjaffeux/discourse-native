import '../controller.dart';
import 'details_source.dart';
import 'document_body_controller.dart';

/// Binds the generic host range editor to the built-in details source format.
class ComposerDetailsBodyController extends ComposerDocumentBodyController {
  ComposerDetailsBodyController(
    ComposerController parent,
    ComposerDetailsBlock block,
  ) : _block = block,
      super(
        parent,
        _range(block),
        resolveRange: (document, start) {
          final next = parseComposerDetails(
            document,
          ).where((block) => block.start == start).firstOrNull;
          return next == null ? null : _range(next);
        },
      );
  ComposerDetailsBlock _block;
  ComposerDetailsBlock get block =>
      parseComposerDetails(
        parent.text.text,
      ).where((block) => block.start == range.start).firstOrNull ??
      _block;
  void updateBlock(ComposerDetailsBlock block) {
    _block = block;
    updateRange(_range(block));
  }

  static ComposerDocumentBodyRange _range(ComposerDetailsBlock block) =>
      ComposerDocumentBodyRange(
        start: block.start,
        source: block.source,
        bodyStart: block.bodyStart,
        bodyEnd: block.bodyEnd,
        serialize: block.withBody,
      );
}
