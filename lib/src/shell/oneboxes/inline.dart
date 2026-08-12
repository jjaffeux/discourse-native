import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'github/pr/inline.dart';

/// Keeps inline oneboxes in the text flow while adding the few native details
/// the cooked anchor cannot draw by itself.
///
/// A custom widget would replace the complete anchor with one [WidgetSpan].
/// That span is indivisible, so a long title moves to the next line instead of
/// using the room left after the preceding words. Registering a build operation
/// leaves the title as real anchor text and injects only the small PR status
/// glyph as a widget.
class InlineOneboxWidgetFactory extends WidgetFactory {
  @override
  void parse(BuildTree tree) {
    super.parse(tree);

    final element = tree.element;
    if (!element.classes.contains('inline-onebox')) return;

    final status = GithubPullRequestInlineOnebox.status(element);
    if (status == null) return;

    tree.register(
      BuildOp(
        alwaysRenderBlock: false,
        debugLabel: 'inline-onebox-pr-status',
        onRenderInline: (tree) {
          tree.prepend(
            WidgetBit.inline(
              tree,
              GithubPullRequestInlineOnebox.statusIcon(status),
              alignment: PlaceholderAlignment.middle,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget? buildGestureDetector(
    BuildTree tree,
    Widget child,
    GestureRecognizer recognizer,
  ) {
    final detector = super.buildGestureDetector(tree, child, recognizer);
    if (detector == null ||
        !tree.element.classes.contains('inline-onebox') ||
        GithubPullRequestInlineOnebox.status(tree.element) == null) {
      return detector;
    }

    // The title's TextSpan already exposes the named link. The glyph shares
    // its recognizer for pointer input but must not add a second, empty link to
    // the semantics tree.
    return ExcludeSemantics(child: detector);
  }
}
