import 'package:discourse_native/src/shell/oneboxes/markup.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

dom.Element element(String source) =>
    html.parseFragment(source).children.single;

void main() {
  group('hexColorIn', () {
    test('reads the colour out of either form the templates write', () {
      expect(hexColorIn('background-color: #0088CC'), const Color(0xFF0088CC));
      expect(
        hexColorIn('box-shadow: -5px 0px #ab9364'),
        const Color(0xFFAB9364),
      );
    });

    test('is opaque whatever the site wrote', () {
      expect(hexColorIn('#000000')!.a, 1.0);
    });

    test('declines anything that is not six hex digits', () {
      expect(hexColorIn(null), isNull);
      expect(hexColorIn(''), isNull);
      expect(hexColorIn('background-color: red'), isNull);
      expect(hexColorIn('background-color: #abc'), isNull);
    });

    test('reads an element\'s own style attribute', () {
      expect(
        hexColorOf(element('<span style="background-color: #FF0000"></span>')),
        const Color(0xFFFF0000),
      );
      expect(hexColorOf(element('<span></span>')), isNull);
      expect(hexColorOf(null), isNull);
    });
  });

  group('oneLineText', () {
    test('collapses the indentation the templates write', () {
      expect(
        oneLineText(element('<p>\n  one\n  two\t three  \n</p>')),
        'one two three',
      );
    });

    test('has nothing to say about an element with no text', () {
      expect(oneLineText(element('<p>   \n  </p>')), isNull);
      expect(oneLineText(element('<p></p>')), isNull);
      expect(oneLineText(null), isNull);
    });
  });

  group('digitsIn', () {
    test('reads a count out of the label around it', () {
      expect(digitsIn(element('<span class="added">+123</span>')), 123);
      expect(digitsIn(element('<span class="removed">-45</span>')), 45);
      expect(digitsIn(element('<span>4 files changed</span>')), 4);
    });

    test('has nothing to say when there are no digits', () {
      expect(digitsIn(element('<span>none</span>')), isNull);
      expect(digitsIn(null), isNull);
    });
  });
}
