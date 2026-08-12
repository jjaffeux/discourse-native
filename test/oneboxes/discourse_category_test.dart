import 'package:discourse_native/src/shell/oneboxes/discourse/category/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

/// Shaped after `discourse_category_onebox.mustache`, the markup
/// `Oneboxer.local_category_html` renders for a category link that sits alone
/// on its line. The color arrives in the aside's `box-shadow`.
const String categoryOnebox = '''
<aside class="onebox category-onebox" style="box-shadow: -5px 0px #0088CC;" data-onebox-src="https://meta.discourse.org/c/feature/60">
  <article class="onebox-body category-onebox-body">
    <h3>
      <a class="badge-category__wrapper" href="https://meta.discourse.org/c/feature/60">
         <span class="badge-category__name">feature</span>
       </a>
    </h3>
    <div>
      <span class="description">
        <p>Things we want to build.</p>
      </span>
    </div>
    <div class="subcategories">
      <span class="subcategory">
        <a class="badge-category__wrapper" href="https://meta.discourse.org/c/feature/design/61">
          <span class="badge-category-bg" style="background-color: #9900CC"></span>
          <span class="badge-category clear-badge"><span class="category-name">design</span></span>
        </a>
      </span>
      <span class="subcategory">
        <a class="badge-category__wrapper" href="https://meta.discourse.org/c/feature/docs/62">
          <span class="badge-category-bg" style="background-color: #00AA66"></span>
          <span class="badge-category clear-badge"><span class="category-name">docs</span></span>
        </a>
      </span>
    </div>
    <div class="clearfix"></div>
  </article>
  <div class="clearfix"></div>
</aside>
''';

DiscourseCategoryData parse(String source) => DiscourseCategoryData.from(
  html.parse(source).querySelector('aside.onebox')!,
);

void main() {
  test('deep category markup parses without recursive DOM traversal', () {
    const depth = 1000;
    final nested =
        '${List.filled(depth, '<div>').join()}'
        '<span class="category-name">Deep child</span>'
        '${List.filled(depth, '</div>').join()}';

    final parsed = parse(
      '<aside class="onebox category-onebox"><article class="onebox-body">'
      '<span class="subcategory">$nested</span></article></aside>',
    );

    expect(parsed.subcategories.single.name, 'Deep child');
  });

  group('DiscourseCategoryData', () {
    test('reads the name, the color and the subcategories', () {
      final data = parse(categoryOnebox);

      expect(data.name, 'feature');
      expect(data.color, const Color(0xFF0088CC));
      expect(data.description, 'Things we want to build.');
      expect(data.subcategories, hasLength(2));
      expect(data.subcategories[0].name, 'design');
      expect(data.subcategories[0].color, const Color(0xFF9900CC));
      expect(data.subcategories[1].name, 'docs');
      expect(data.subcategories[1].color, const Color(0xFF00AA66));
    });
  });

  group('DiscourseCategoryOnebox', () {
    testWidgets('draws the category card', (tester) async {
      final aside = html.parse(categoryOnebox).querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: oneboxWidgetBuilder(aside)!),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('feature'), findsOneWidget);
      expect(find.text('Things we want to build.'), findsOneWidget);
      expect(find.text('design'), findsOneWidget);
      expect(find.text('docs'), findsOneWidget);
    });
  });
}
