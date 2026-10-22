import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter_widget_from_html_core/src/internal/core_build_tree.dart';
import 'package:flutter_widget_from_html_core/src/internal/flattener.dart';
import 'package:html/dom.dart' as dom;

class _RecordingFactory extends WidgetFactory {
  final texts = <String>[];

  @override
  InlineSpan? buildTextSpan({
    List<InlineSpan>? children,
    GestureRecognizer? recognizer,
    TextStyle? style,
    String? text,
  }) {
    if (text != null) {
      texts.add(text);
    }
    return super.buildTextSpan(
      children: children,
      recognizer: recognizer,
      style: style,
      text: text,
    );
  }
}

class _MutatingBit extends TextBit {
  final BuildTree target;

  const _MutatingBit(BuildTree parent, this.target) : super(parent, 'changed');

  @override
  void flatten(Flattened f) {
    target.prepend(TextBit(target, 'inserted '));
    super.flatten(f);
  }
}

class _AncestorResolvers extends InheritanceResolvers {
  VoidCallback? onParentRead;

  @override
  InheritanceResolvers? get parent {
    onParentRead?.call();
    return super.parent;
  }
}

class _EqualTextBit extends TextBit {
  const _EqualTextBit(super.parent, super.data);

  @override
  bool operator ==(Object other) => other is _EqualTextBit;

  @override
  int get hashCode => 0;
}

class _ReverseTree extends BuildTree {
  @override
  final BuildTree parent;

  _ReverseTree(this.parent)
      : super(
          element: dom.Element.tag('custom'),
          inheritanceResolvers: parent.inheritanceResolvers.sub(),
        );

  @override
  Iterable<BuildBit> get bits => children.toList().reversed;

  @override
  get styles => parent.styles;

  @override
  void operator []=(String key, String value) => throw UnimplementedError();

  @override
  WidgetPlaceholder? build() => throw UnimplementedError();

  @override
  BuildBit copyWith({BuildTree? parent}) => throw UnimplementedError();

  @override
  void flatten(Flattened f) {}

  @override
  getStyle(String property) => parent.getStyle(property);

  @override
  void register(BuildOp op) => throw UnimplementedError();

  @override
  BuildTree sub({dom.Element? element}) => throw UnimplementedError();
}

CoreBuildTree _root(WidgetFactory factory) => CoreBuildTree.root(
      inheritanceResolvers: InheritanceResolvers(),
      wf: factory,
    );

String _wide(BuildTree tree) {
  for (var i = 0; i < 80; i++) {
    tree.addText('word$i');
    tree.addWhitespace(' ');
  }
  return List.generate(80, (i) => 'word$i').join(' ');
}

Widget _host(Widget child) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

Future<InlineSpan> _render(
  WidgetTester tester,
  WidgetFactory factory,
  BuildTree tree,
) async {
  final widgets = Flattener(factory, tree).widgets.toList();
  await tester.pumpWidget(_host(Column(children: widgets)));
  expect(tester.takeException(), isNull);
  return tester.widget<RichText>(find.byType(RichText)).text;
}

List<TextSpan> _runs(InlineSpan span) => [
      if (span is TextSpan) ...[
        if (span.text?.isNotEmpty == true) span,
        for (final child in span.children ?? const <InlineSpan>[])
          ..._runs(child),
      ],
    ];

void main() {
  testWidgets('broad HTML preserves whitespace, empty styles and span order',
      (tester) async {
    final factory = _RecordingFactory();
    final html = List.generate(
      80,
      (i) => '<span style="color: ${i.isEven ? 'red' : 'blue'}">'
          'word$i <b><i></i></b></span>',
    ).join();
    await tester.pumpWidget(_host(HtmlWidget(
      '<p>$html</p>',
      buildAsync: false,
      factoryBuilder: () => factory,
    )));
    final span = tester.widget<RichText>(find.byType(RichText)).text;
    expect(span.toPlainText(), List.generate(80, (i) => 'word$i').join(' '));
    final runs = _runs(span);
    expect(runs, hasLength(80));
    for (var i = 0; i < 80; i++) {
      expect(runs[i].text, i == 79 ? 'word$i' : 'word$i ');
      expect(runs[i].style?.color,
          i.isEven ? const Color(0xffff0000) : const Color(0xff0000ff));
    }
    expect(factory.texts.where((text) => text.isNotEmpty),
        List.generate(80, (i) => i == 0 ? 'word79' : 'word${79 - i} '));
    expect(tester.takeException(), isNull);
  });

  testWidgets('trailing whitespace keeps inheritance outside the current tree',
      (tester) async {
    final factory = _RecordingFactory();
    final outer = _root(factory)
      ..inherit<CssWhitespace>(
          (resolving, value) => resolving.copyWith(value: value),
          CssWhitespace.pre);
    final tree = outer.sub()
      ..inherit<CssWhitespace>(
          (resolving, value) => resolving.copyWith(value: value),
          CssWhitespace.normal);
    outer.append(tree);
    final expected = _wide(tree);
    tree.addText('last');
    final trailing = tree.addWhitespace('\t\n');
    final outside = outer.addText('outside');
    expect(trailing.next, same(outside));
    expect(outside.prev, same(trailing));
    final span = await _render(tester, factory, tree);
    expect(span.toPlainText(), '$expected last\t\n');
    expect(factory.texts, ['\t\n', '$expected last']);
  });

  testWidgets('inline callbacks finish before broad text is flattened',
      (tester) async {
    final factory = _RecordingFactory();
    final tree = _root(factory);
    final events = <String>[];
    for (var i = 0; i < 80; i++) {
      final child = tree.sub();
      final nested = child.sub()..addText('word$i');
      nested.register(BuildOp(onRenderInline: (_) => events.add('nested$i')));
      child.append(nested);
      child.register(BuildOp(onRenderInline: (current) {
        events.add('child$i');
        current.prepend(TextBit(current, '['));
        current.addText(']');
        current.addWhitespace(' ');
      }));
      tree.append(child);
    }
    final span = await _render(tester, factory, tree);
    expect(span.toPlainText(), List.generate(80, (i) => '[word$i]').join(' '));
    expect(events, [
      for (var i = 0; i < 80; i++) ...['nested$i', 'child$i']
    ]);
  });

  testWidgets('custom leaf mutation keeps the later tree live', (tester) async {
    final factory = _RecordingFactory();
    final tree = _root(factory);
    final prefix = _wide(tree);
    final target = tree.sub()..addText('original');
    tree.append(_MutatingBit(tree, target));
    tree.addWhitespace(' ');
    tree.append(target);
    final span = await _render(tester, factory, tree);
    expect(span.toPlainText(), '$prefix changed inserted original');
  });

  for (final mutation in [
    (parentReads: 0, prepend: false),
    (parentReads: 16, prepend: true),
  ]) {
    testWidgets(
        'custom resolver ancestor mutation stays live after '
        '${mutation.parentReads} parent reads', (tester) async {
      final factory = _RecordingFactory();
      final ancestor = _AncestorResolvers();
      final tree = CoreBuildTree.root(
        inheritanceResolvers: ancestor.sub(),
        wf: factory,
      );
      final prefix = _wide(tree);
      final pre = tree.sub()
        ..inherit<CssWhitespace>(
          (resolved, value) => resolved.copyWith(value: value),
          CssWhitespace.pre,
        )
        ..addText('before')
        ..addWhitespace('\t\n');
      tree.append(pre);
      final target = tree.sub();
      tree.append(target);
      tree.addText('end');
      var parentReads = 0;
      ancestor.onParentRead = () {
        if (parentReads++ < mutation.parentReads) {
          return;
        }
        ancestor.onParentRead = null;
        if (mutation.prepend) {
          target.prepend(TextBit(target, 'inserted'));
        } else {
          target.addText('inserted');
        }
      };
      final span = await _render(tester, factory, tree);
      expect(span.toPlainText(), '$prefix before\t\ninsertedend');
      expect(parentReads, mutation.parentReads + 1);
    });
  }

  testWidgets('custom traversal keeps its own leaf order', (tester) async {
    final factory = _RecordingFactory();
    final tree = _root(factory);
    final prefix = _wide(tree);
    final custom = _ReverseTree(tree)
      ..addText('last')
      ..addText('first');
    tree.append(custom);
    final span = await _render(tester, factory, tree);
    expect(span.toPlainText(), '$prefix firstlast');
  });

  testWidgets('equal custom bits retain first-equal next and prev semantics',
      (tester) async {
    final factory = _RecordingFactory();
    final tree = _root(factory);
    final prefix = _wide(tree);
    final first = _EqualTextBit(tree, 'first');
    final second = _EqualTextBit(tree, 'second');
    tree.append(first);
    final middle = tree.addText('|');
    tree.append(second);
    tree.addText('end');
    expect(second.next, same(middle));
    expect(middle.prev, same(first));
    final span = await _render(tester, factory, tree);
    expect(span.toPlainText(), '$prefix first|secondend');
  });

  testWidgets(
      'duplicate core leaves retain their repeated output and traversal',
      (tester) async {
    final factory = _RecordingFactory();
    final tree = _root(factory);
    final prefix = _wide(tree);
    final repeated = tree.addText('repeat');
    final middle = tree.addText('|');
    tree.append(repeated);
    tree.addText('end');
    expect(repeated.next, same(middle));
    expect(middle.prev, same(repeated));
    final span = await _render(tester, factory, tree);
    expect(span.toPlainText(), '$prefix repeat|repeatend');
  });
}
