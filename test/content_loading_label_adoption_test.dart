import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

final _busyCopy = RegExp(
  r'^(Loading(?:[ .…]|$)|Searching(?:[ .…]|$)|Finding tags|'
  r'Generating summary|Regenerating summary|Refreshing preferences|'
  r'Opening conversation|Still finding out|Rendering diagram)',
);

Set<String> _loadingKeys() {
  final strings =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final entry in strings.entries)
      if (entry.value is String && _busyCopy.hasMatch(entry.value as String))
        entry.key,
  };
}

void main() {
  test('the loading-copy check catches text and conditional input hints', () {
    final keys = _loadingKeys();
    final visitor = _LoadingTextVisitor(keys);
    parseString(
      content: '''
void build() {
  Text(context.l10n.loadingPreferences);
  DText(appL10n.searching);
  ComposerEditor(hintText: loading ? context.l10n.loadingThatPost : 'Reply');
  Text(context.l10n.loadingDembed('Video'));
  Text(appL10n.loadingPreferencesFrom('example.com'));
  DSkeletonRegion(semanticsLabel: context.l10n.loadingPreferences);
}
''',
    ).unit.accept(visitor);
    expect(visitor.offenders, hasLength(5));
  });

  test('content-loading copy stays out of painted text and input hints', () {
    final keys = _loadingKeys();
    expect(
      keys,
      containsAll(['loadingPreferences', 'findingTags', 'searching']),
    );
    final offenders = <String>[];
    for (final file in Directory('lib/src').listSync(recursive: true)) {
      if (file is! File ||
          !file.path.endsWith('.dart') ||
          file.path.startsWith('lib/src/styleguide/')) {
        continue;
      }
      final parsed = parseString(content: file.readAsStringSync());
      final visitor = _LoadingTextVisitor(keys);
      parsed.unit.accept(visitor);
      for (final node in visitor.offenders) {
        offenders.add(
          '${file.path}:${parsed.lineInfo.getLocation(node.offset).lineNumber}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use Native skeletons for pending content. Keep localized loading '
          'copy in accessibility labels.\n${offenders.join('\n')}',
    );
  });
}

class _LoadingTextVisitor extends RecursiveAstVisitor<void> {
  _LoadingTextVisitor(this.keys);

  final Set<String> keys;
  final offenders = <AstNode>[];

  bool _hasLoadingCopy(AstNode node) {
    final references = _LoadingReferences(keys);
    node.accept(references);
    return references.found;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (const {
          'Text',
          'DText',
          'TextSpan',
        }.contains(node.constructorName.type.name.lexeme) &&
        _hasLoadingCopy(node.argumentList)) {
      offenders.add(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'hintText' &&
        _hasLoadingCopy(node.argumentExpression)) {
      offenders.add(node);
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (const {'Text', 'DText', 'TextSpan'}.contains(node.methodName.name) &&
        _hasLoadingCopy(node.argumentList)) {
      offenders.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

class _LoadingReferences extends RecursiveAstVisitor<void> {
  _LoadingReferences(this.keys);

  final Set<String> keys;
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    if ((target == 'appL10n' || target?.endsWith('.l10n') == true) &&
        keys.contains(node.methodName.name)) {
      found = true;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.target?.toSource().endsWith('.l10n') == true &&
        keys.contains(node.propertyName.name)) {
      found = true;
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'appL10n' && keys.contains(node.identifier.name)) {
      found = true;
    }
    super.visitPrefixedIdentifier(node);
  }
}
