import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Checks literal text at UI boundaries. Server content, protocol identifiers,
/// developer diagnostics, and executable styleguide sample documents are data.
List<String> unlocalizedUiText(Directory directory) {
  final findings = <String>[];
  for (final file in directory.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') ||
        file.path.contains('/l10n/') ||
        file.path.contains('/styleguide/') ||
        file.path.endsWith('_review_main.dart')) {
      continue;
    }
    final result = parseString(content: file.readAsStringSync());
    final visitor = _UiTextVisitor((node) {
      findings.add(
        '${file.path}:${result.lineInfo.getLocation(node.offset).lineNumber}: '
        '${node.toSource()}',
      );
    });
    result.unit.accept(visitor);
  }
  return findings;
}

void main() {
  final findings = unlocalizedUiText(Directory('lib'));
  if (findings.isNotEmpty) {
    stderr.writeln(findings.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln('UI text localization audit passed.');
  }
}

class _UiTextVisitor extends RecursiveAstVisitor<void> {
  _UiTextVisitor(this.report);
  final void Function(StringLiteral) report;

  static const _textArguments = {
    'label',
    'title',
    'subtitle',
    'text',
    'description',
    'emptyTitle',
    'emptyDescription',
    'tooltip',
    'semanticLabel',
    'semanticsLabel',
    'hintText',
    'labelText',
    'helperText',
    'errorText',
    'placeholder',
    'barrierLabel',
    'emptyMessage',
    'loadingSemanticLabel',
    'closeSemanticLabel',
  };

  void check(StringLiteral node) {
    if (node.parent is AdjacentStrings) return;
    final source = node.toSource();
    // A displayed link is content, not an application message.
    if (source.startsWith("'/chat/c/")) return;
    if (!RegExp(r'[A-Za-z]{2}').hasMatch(source)) return;
    AstNode child = node;
    for (AstNode? p = node.parent; p != null; child = p, p = p.parent) {
      if (p is ConditionalExpression && identical(p.condition, child)) return;
      if (p is BinaryExpression && !['??', '+'].contains(p.operator.lexeme)) {
        return;
      }
      if (p is ConditionalExpression ||
          p is ParenthesizedExpression ||
          p is StringInterpolation ||
          p is InterpolationExpression ||
          p is AdjacentStrings ||
          p is BinaryExpression) {
        continue;
      }
      if (p is FormalParameterDefaultClause) {
        final parameter = p.parent;
        if (parameter is FormalParameter &&
            _textArguments.contains(parameter.name?.lexeme)) {
          report(node);
        }
        return;
      }
      if (p is ExpressionFunctionBody && p.parent is MethodDeclaration) {
        final method = p.parent as MethodDeclaration;
        if (method.isGetter && _textArguments.contains(method.name.lexeme)) {
          report(node);
        }
        return;
      }
      if (p is NamedArgument) {
        if (_textArguments.contains(p.name.lexeme)) report(node);
        return;
      }
      if (p is ArgumentList) {
        final parent = p.parent;
        final name = switch (parent) {
          MethodInvocation() => parent.methodName.name,
          InstanceCreationExpression() =>
            parent.constructorName.type.name.lexeme,
          _ => '',
        };
        if (name == 'Text' &&
            !(parent is MethodInvocation &&
                parent.target?.toSource() == 'dom') &&
            p.arguments.first == child) {
          report(node);
        }
        return;
      }
      return;
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    check(node);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    check(node);
    super.visitAdjacentStrings(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    // An interpolation with only dynamic content has no English to translate.
    if (node.elements.whereType<InterpolationString>().any(
      (part) => RegExp(r'[A-Za-z]{2}').hasMatch(part.value),
    )) {
      check(node);
    }
    super.visitStringInterpolation(node);
  }
}
