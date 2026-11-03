import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _before = 'Start with enough words to wrap onto several lines before ';
const _between = ' and continue across several more lines with ';
const _after = ' to the very ending';
const _body = '$_before@alex$_between@staff$_after';
const _html =
    '<aside class="quote" data-username="sam">'
    '<div class="title">sam:</div><blockquote><p>$_before'
    '<a class="mention" href="/u/alex">@alex</a>$_between'
    '<a class="mention-group" href="/g/staff">@staff</a>$_after'
    '</p></blockquote></aside>';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final backward in [false, true]) {
      testWidgets('${platform.name} selects a multiline quote across mentions '
          'by dragging the ${backward ? 'start' : 'end'} handle', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: DPageSurface(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectionArea(
                  onSelectionChanged: (content) =>
                      selected = content?.plainText,
                  child: const CookedHtml(html: _html),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith('Start with'),
          ),
        );
        final length = paragraph.text.toPlainText().length;
        TextBox character(int offset) => paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: offset + 1),
            )
            .single;
        final first = character(0).toRect();
        final last = character(length - 1).toRect();
        expect(last.top, greaterThan(first.bottom));

        final gesture = await tester.startGesture(
          paragraph.localToGlobal((backward ? last : first).center),
        );
        addTearDown(gesture.removePointer);
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected, backward ? 'ending' : 'Start');

        final boxes = paragraph.getBoxesForSelection(
          backward ? paragraph.selections.last : paragraph.selections.first,
        );
        final handle = backward
            ? boxes.first.toRect().bottomLeft
            : boxes.last.toRect().bottomRight;
        final target = backward ? first.bottomLeft : last.bottomRight;
        final grip = platform == TargetPlatform.android
            ? Offset(backward ? -10 : 10, 10)
            : Offset.zero;
        await gesture.down(paragraph.localToGlobal(handle + grip));
        await gesture.moveTo(paragraph.localToGlobal(target + grip));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected, _body);

        tester
            .state<SelectionAreaState>(find.byType(SelectionArea))
            .selectableRegion
            .selectAll(SelectionChangedCause.toolbar);
        await tester.pump();
        expect(selected, 'sam$_body');
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({platform}));
    }
  }
}
