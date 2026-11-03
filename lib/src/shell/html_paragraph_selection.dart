import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps a paragraph's text and inline widgets in logical selection order.
class HtmlParagraphSelection extends StatefulWidget {
  const HtmlParagraphSelection({super.key, required this.child});

  final Widget child;

  @override
  State<HtmlParagraphSelection> createState() => _HtmlParagraphSelectionState();
}

class _HtmlParagraphSelectionState extends State<HtmlParagraphSelection> {
  final _paragraphKey = GlobalKey();
  late final _delegate = _ParagraphSelectionDelegate(_paragraph);

  RenderParagraph _paragraph() {
    RenderParagraph? paragraph;
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        paragraph = object;
      } else if (paragraph == null) {
        object.visitChildren(visit);
      }
    }

    visit(_paragraphKey.currentContext!.findRenderObject()!);
    return paragraph!;
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer(
    delegate: _delegate,
    child: KeyedSubtree(key: _paragraphKey, child: widget.child),
  );
}

class _ParagraphSelectionDelegate extends StaticSelectionContainerDelegate {
  _ParagraphSelectionDelegate(this.paragraph);

  final RenderParagraph Function() paragraph;

  @override
  Comparator<Selectable> get compareOrder => (a, b) {
    final text = paragraph();
    int offset(Selectable selectable) {
      final global = MatrixUtils.transformPoint(
        selectable.getTransformTo(null),
        selectable.boundingBoxes.first.center,
      );
      return text.getPositionForOffset(text.globalToLocal(global)).offset;
    }

    // A wrapped fragment's union rectangle can surround an inline badge.
    // Compare positions in the owning paragraph instead of screen rectangles.
    final order = offset(a).compareTo(offset(b));
    return order != 0 ? order : super.compareOrder(a, b);
  };
}
