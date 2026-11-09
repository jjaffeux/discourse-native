import 'package:flutter/widgets.dart';

import '../controller.dart';
import '../editor_scope.dart';
import '../embedded_editor.dart';
import 'document_body_controller.dart';

class ComposerDocumentBodyEditor extends StatefulWidget {
  const ComposerDocumentBodyEditor({
    super.key,
    required this.parent,
    required this.range,
    required this.resolveRange,
    required this.semanticLabel,
  });

  final ComposerController parent;
  final ComposerDocumentBodyRange range;
  final ComposerDocumentBodyRange? Function(String document, int start)
  resolveRange;
  final String semanticLabel;

  @override
  State<ComposerDocumentBodyEditor> createState() =>
      _ComposerDocumentBodyEditorState();
}

class _ComposerDocumentBodyEditorState
    extends State<ComposerDocumentBodyEditor> {
  late ComposerDocumentBodyController _body = ComposerDocumentBodyController(
    widget.parent,
    widget.range,
    resolveRange: widget.resolveRange,
  );

  @override
  void didUpdateWidget(ComposerDocumentBodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_body.parent, widget.parent) || !_body.isCurrent) {
      final previous = _body;
      _body = ComposerDocumentBodyController(
        widget.parent,
        widget.range,
        resolveRange: widget.resolveRange,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    } else {
      _body.updateRange(widget.range);
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.parent,
    scrollController: widget.parent.text.imageScrollController,
    semanticLabel: widget.semanticLabel,
    child: ComposerEditorScope.of(context).richBody(
      composer: _body,
      label: widget.semanticLabel,
      hintText: '',
      onExit: widget.parent.requestFocus,
    ),
  );
}
