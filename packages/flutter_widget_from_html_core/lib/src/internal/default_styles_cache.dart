import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;

import '../external/csslib.dart';

/// Reuses parsed default declarations within one body while giving each element
/// its own mutable syntax tree for custom build operations.
class DefaultStylesCache {
  final _templates = <String, List<css.Declaration>>{};

  List<css.Declaration> parse(String styles) {
    final existing = _templates[styles];
    if (existing != null) {
      return existing.map(_clone).toList();
    }
    final declarations = css.parse('*{$styles}').collectDeclarations();
    if (_templates.length < 64 &&
        styles.length <= 4096 &&
        declarations.every((d) =>
            d.runtimeType == css.Declaration &&
            !d.isIE7 &&
            (d.dartStyle == null ||
                d.dartStyle is css.MarginExpression ||
                d.dartStyle is css.PaddingExpression ||
                d.dartStyle is css.WidthExpression ||
                d.dartStyle is css.HeightExpression) &&
            _canClone(d.expression))) {
      _templates[styles] = declarations;
      return declarations.map(_clone).toList();
    }
    return declarations;
  }

  // csslib's clone implementations for some compound expressions are lossy.
  // Cache only independent literal values; preserve the parser for the rest.
  static bool _canClone(css.Expression? expression) =>
      expression is css.Expressions &&
      expression.expressions.every((e) =>
          e is css.LiteralTerm &&
          e is! css.FunctionTerm &&
          e is! css.CalcTerm &&
          (e.value is String || e.value is num || e.value is css.Identifier));

  static css.Declaration _clone(css.Declaration declaration) {
    final cloned = declaration.clone();
    for (final expression
        in (cloned.expression! as css.Expressions).expressions) {
      final literal = expression as css.LiteralTerm;
      if (literal.value is css.Identifier) {
        literal.value = (literal.value as css.Identifier).clone();
      }
    }
    final dartStyle = declaration.dartStyle;
    if (dartStyle != null) {
      cloned.dartStyle = (dartStyle.clone() as css.DartStyleExpression)
        ..priority = dartStyle.priority;
    }
    return cloned;
  }
}
