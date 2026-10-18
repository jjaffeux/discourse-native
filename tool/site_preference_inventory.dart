import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Returns a cold-start inventory and rejects undeclared persistence adapters.
({Map<String, String> files, Set<String> prefixes}) sitePreferenceInventory(
  Directory root,
) {
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final declarations = <(String, String)>[];
  final prefixes = <String>{};
  final ownedNamespaces = <String>{};
  for (final file in files) {
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    ).unit;
    final inventory = _PreferenceDeclarations();
    unit.accept(inventory);
    final relative = file.path.substring(root.path.length + 1);
    final unowned = inventory.rawAdapters.difference({
      ...inventory.declaredAdapters,
      ...inventory.classifiedAdapters,
    });
    if (unowned.isNotEmpty) {
      throw StateError(
        '$relative ${unowned.join(', ')} opens raw preferences without declared ownership. '
        'Declare a SitePreferenceKey or annotate the adapter with '
        'PreferenceStorage and its device/document retirement contract.',
      );
    }
    for (final declaration in inventory.trackedDeclarations) {
      if (!inventory.trackedReferences.contains(declaration) &&
          !inventory.callbackDeclarations.contains(declaration)) {
        throw StateError(
          '$relative $declaration must register retirement with track or onForget.',
        );
      }
    }
    for (final declaration in inventory.managedDeclarations) {
      if (!inventory.managedReferences.contains(declaration)) {
        throw StateError(
          '$relative $declaration must use OwnedSitePreferences for managed retirement.',
        );
      }
    }
    for (final namespace in inventory.ownedNamespaces) {
      if (!ownedNamespaces.add(namespace)) {
        throw StateError('Duplicate owned preference namespace $namespace.');
      }
    }
    for (final prefix in inventory.prefixes) {
      if (!prefixes.add(prefix)) {
        throw StateError('Duplicate site preference namespace $prefix.');
      }
    }
    for (final declaration in inventory.declarations) {
      declarations.add((relative, declaration));
    }
  }
  final groups = <String, List<(String, String)>>{'': []};
  for (final declaration in declarations) {
    final path = declaration.$1;
    final group = path.startsWith('plugins/')
        ? 'plugins/${path.split('/')[1]}/'
        : '';
    (groups[group] ??= []).add(declaration);
  }
  return (
    prefixes: prefixes,
    files: {
      for (final group in groups.entries)
        '${group.key}site_preference_inventory.g.dart': _renderInventory(
          group.key,
          group.value,
        ),
    },
  );
}

String _renderInventory(String group, List<(String, String)> declarations) {
  final imports = <String, String>{};
  for (final (path, _) in declarations) {
    imports.putIfAbsent(path, () => 'p${imports.length}');
  }
  final directives =
      [
        group.isEmpty
            ? "import 'data/site_preference_keys.dart';"
            : "import 'package:discourse_native/discourse_plugin_sdk.dart';",
        for (final entry in imports.entries)
          "import '${entry.key.substring(group.length)}' as ${entry.value};",
      ]..sort((a, b) {
        final aPackage = a.startsWith("import 'package:");
        final bPackage = b.startsWith("import 'package:");
        return aPackage == bPackage ? a.compareTo(b) : (aPackage ? -1 : 1);
      });
  final out = StringBuffer('${directives.join('\n')}\n');
  out.writeln('\nconst declaredSitePreferenceKeys = <SitePreferenceKey>[');
  for (final (path, declaration) in declarations) {
    out.writeln('  ${imports[path]}.$declaration,');
  }
  out.writeln('];');
  return out.toString();
}

final class _PreferenceDeclarations extends RecursiveAstVisitor<void> {
  final declarations = <String>[];
  final prefixes = <String>{};
  final rawAdapters = <String>{};
  final declaredAdapters = <String>{};
  final classifiedAdapters = <String>{};
  final trackedDeclarations = <String>{};
  final trackedReferences = <String>{};
  final callbackDeclarations = <String>{};
  final managedDeclarations = <String>{};
  final managedReferences = <String>{};
  final ownedNamespaces = <String>{};

  String _adapter(AstNode node) {
    final enclosingClass = node.thisOrAncestorOfType<ClassDeclaration>();
    if (enclosingClass != null) return enclosingClass.namePart.typeName.lexeme;
    final function = node.thisOrAncestorOfType<FunctionDeclaration>();
    return function == null ? '<top-level>' : function.name.lexeme;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target?.toSource().split('.').last == 'SharedPreferences' &&
        node.methodName.name == 'getInstance') {
      rawAdapters.add(_adapter(node));
    }
    if (const {
      'SharedPreferencesAsync',
      'SharedPreferencesWithCache',
    }.contains(node.methodName.name)) {
      rawAdapters.add(_adapter(node));
    }
    if (node.methodName.name == 'track' && node.target != null) {
      final reference = node.target!.toSource();
      trackedReferences.add(
        reference.contains('.') ? reference : '${_adapter(node)}.$reference',
      );
    }
    if (node.methodName.name == 'SitePreferenceKey') {
      _addDeclaration(node, node.argumentList);
    }
    if (node.methodName.name == 'OwnedSitePreferences') {
      _addOwned(node, node.argumentList);
    }
    if (node.methodName.name == 'ScalarPreferenceRepository') {
      rawAdapters.add(_adapter(node));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (const {
      'SharedPreferences',
      'SharedPreferencesAsync',
      'SharedPreferencesWithCache',
    }.contains(node.name.lexeme)) {
      rawAdapters.add(_adapter(node));
    }
    super.visitNamedType(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    if (node.name.toSource() == 'PreferenceStorage' ||
        node.name.toSource().startsWith('PreferenceStorage.')) {
      final args = node.arguments?.arguments;
      if (args == null ||
          args.length != 1 ||
          args.single is! SimpleStringLiteral ||
          (args.single as SimpleStringLiteral).value.trim().isEmpty) {
        throw StateError('PreferenceStorage requires its ownership contract.');
      }
      classifiedAdapters.add(_adapter(node));
    }
    super.visitAnnotation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'SitePreferenceKey') {
      _addDeclaration(node, node.argumentList);
    }
    if (node.constructorName.type.name.lexeme == 'OwnedSitePreferences') {
      _addOwned(node, node.argumentList);
    }
    if (node.constructorName.type.name.lexeme == 'ScalarPreferenceRepository') {
      rawAdapters.add(_adapter(node));
    }
    super.visitInstanceCreationExpression(node);
  }

  void _addOwned(AstNode node, ArgumentList arguments) {
    final options = {
      for (final arg in arguments.arguments.whereType<NamedArgument>())
        arg.name.lexeme: arg.argumentExpression,
    };
    final id = options['id'];
    if (id is! SimpleStringLiteral || id.value.isEmpty) {
      throw StateError('OwnedSitePreferences requires a stable literal id.');
    }
    if (!ownedNamespaces.add(id.value)) {
      throw StateError('Duplicate owned preference namespace ${id.value}.');
    }
    final legacy = options['legacy']?.toSource();
    if (legacy != null) {
      managedReferences.add(
        legacy.contains('.') ? legacy : '${_adapter(node)}.$legacy',
      );
    }
  }

  void _addDeclaration(AstNode node, ArgumentList arguments) {
    final variable = node.parent;
    final list = variable?.parent;
    final field = list?.parent;
    final owner = field?.thisOrAncestorOfType<ClassDeclaration>();
    if (variable is! VariableDeclaration ||
        list is! VariableDeclarationList ||
        !list.isConst ||
        field is! FieldDeclaration ||
        !field.isStatic ||
        owner is! ClassDeclaration ||
        variable.name.lexeme.startsWith('_') ||
        owner.namePart.typeName.lexeme.startsWith('_')) {
      throw StateError(
        'SitePreferenceKey must be a public static const declaration.',
      );
    }
    final reference =
        '${owner.namePart.typeName.lexeme}.${variable.name.lexeme}';
    final options = {
      for (final arg in arguments.arguments.whereType<NamedArgument>())
        arg.name.lexeme: arg.argumentExpression,
    };
    final retirement = options['retirement']?.toSource();
    if (!const {
      'SitePreferenceRetirement.storedOnly',
      'SitePreferenceRetirement.tracked',
      'SitePreferenceRetirement.managed',
    }.contains(retirement)) {
      throw StateError('$reference must declare retirement.');
    }
    if (retirement == 'SitePreferenceRetirement.managed') {
      managedDeclarations.add(reference);
    }
    if (retirement == 'SitePreferenceRetirement.tracked') {
      trackedDeclarations.add(reference);
      if (options['onForget'] case final callback?) {
        if (callback is! NullLiteral) callbackDeclarations.add(reference);
      }
    }
    final namespace = arguments.arguments.first;
    if (namespace is! SimpleStringLiteral || namespace.value.isEmpty) {
      throw StateError('$reference requires a stable literal namespace.');
    }
    if (!prefixes.add(namespace.value)) {
      throw StateError(
        'Duplicate site preference namespace ${namespace.value}.',
      );
    }
    declaredAdapters.add(owner.namePart.typeName.lexeme);
    declarations.add(reference);
  }
}

void main(List<String> args) {
  final generated = sitePreferenceInventory(Directory('lib/src'));
  for (final entry in generated.files.entries) {
    final output = File('lib/src/${entry.key}');
    if (args.contains('--check')) {
      if (!output.existsSync() || output.readAsStringSync() != entry.value) {
        stderr.writeln('Run dart run tool/site_preference_inventory.dart.');
        exitCode = 1;
      }
    } else {
      output.writeAsStringSync(entry.value);
    }
  }
}
