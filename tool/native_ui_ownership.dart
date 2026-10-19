import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

enum NativeUiFindingKind {
  rawControl,
  internalImport,
  gestureReview,
  parseError,
}

final class NativeUiFinding {
  const NativeUiFinding({
    required this.path,
    required this.line,
    required this.column,
    required this.kind,
    required this.symbol,
  });

  final String path;
  final int line;
  final int column;
  final NativeUiFindingKind kind;
  final String symbol;

  bool get isError => kind != NativeUiFindingKind.gestureReview;

  @override
  String toString() => '$path:$line:$column: ${kind.name}: $symbol';
}

const _rawControls = {
  'AlertDialog',
  'Dialog',
  'SimpleDialog',
  'SimpleDialogOption',
  'CupertinoAlertDialog',
  'CupertinoDialogAction',
  'CupertinoPopupSurface',
  'CupertinoActionSheet',
  'CupertinoActionSheetAction',
  'ListTile',
  'CheckboxListTile',
  'RadioListTile',
  'SwitchListTile',
  'AboutListTile',
  'AboutDialog',
  'CupertinoListTile',
  'CupertinoListSection',
  'InputDecoration',
  'InputDecorator',
  'TextField',
  'TextFormField',
  'CupertinoTextField',
  'CupertinoTextFormFieldRow',
  'EditableText',
  'IconButton',
  'TextButton',
  'ElevatedButton',
  'OutlinedButton',
  'FilledButton',
  'MaterialButton',
  'RawMaterialButton',
  'FloatingActionButton',
  'BackButton',
  'CloseButton',
  'CupertinoButton',
  'Checkbox',
  'Radio',
  'RadioGroup',
  'Switch',
  'CupertinoCheckbox',
  'CupertinoRadio',
  'CupertinoSwitch',
  'ToggleButtons',
  'SegmentedButton',
  'CupertinoSegmentedControl',
  'CupertinoSlidingSegmentedControl',
  'DropdownButton',
  'DropdownButtonFormField',
  'DropdownMenu',
  'DropdownMenuItem',
  'PopupMenuButton',
  'PopupMenuItem',
  'CheckedPopupMenuItem',
  'MenuAnchor',
  'MenuBar',
  'MenuItemButton',
  'SubmenuButton',
  'CheckboxMenuButton',
  'RadioMenuButton',
  'Autocomplete',
  'RawAutocomplete',
  'Slider',
  'RangeSlider',
  'CupertinoSlider',
  'CircularProgressIndicator',
  'LinearProgressIndicator',
  'CupertinoActivityIndicator',
  'Tooltip',
  'Chip',
  'ActionChip',
  'ChoiceChip',
  'FilterChip',
  'InputChip',
  'RawChip',
  'SearchBar',
  'SearchAnchor',
  'DatePickerDialog',
  'TimePickerDialog',
  'CalendarDatePicker',
  'InputDatePickerFormField',
  'CupertinoDatePicker',
  'CupertinoTimerPicker',
  'CupertinoPicker',
  'InkWell',
  'InkResponse',
};

const _rawOverlays = {
  'showDialog',
  'showGeneralDialog',
  'showAdaptiveDialog',
  'showCupertinoDialog',
  'showModalBottomSheet',
  'showBottomSheet',
  'showCupertinoModalPopup',
  'showMenu',
  'showDatePicker',
  'showDateRangePicker',
  'showTimePicker',
};

const _constructorMembers = {
  'new',
  'adaptive',
  'fullscreen',
  'collapsed',
  'extended',
  'small',
  'large',
  'filled',
  'filledTonal',
  'outlined',
  'icon',
  'tonal',
  'tonalIcon',
  'filledIcon',
  'elevated',
  'bar',
  'insetGrouped',
  'notched',
  'borderless',
  'formRow',
  'partiallyRevealed',
};

Set<String> _frameworkSymbols(String? uri) {
  if (uri == null || !uri.startsWith('package:flutter/')) return {};
  const widgets = {
    'EditableText',
    'RawAutocomplete',
    'GestureDetector',
    'showGeneralDialog',
  };
  if (uri == 'package:flutter/material.dart' ||
      uri.startsWith('package:flutter/src/material/')) {
    return {
      ..._rawControls.where((name) => !name.startsWith('Cupertino')),
      ..._rawOverlays.where((name) => !name.contains('Cupertino')),
      ...widgets,
    };
  }
  if (uri == 'package:flutter/cupertino.dart' ||
      uri.startsWith('package:flutter/src/cupertino/')) {
    return {
      ..._rawControls.where((name) => name.startsWith('Cupertino')),
      ..._rawOverlays.where((name) => name.contains('Cupertino')),
      ...widgets,
    };
  }
  return uri == 'package:flutter/widgets.dart' ||
          uri.startsWith('package:flutter/src/widgets/')
      ? {...widgets}
      : {};
}

/// Parses application source without resolving Flutter or starting an engine.
/// Import prefixes, show/hide clauses, and declarations in this file determine
/// the known names. The repository scanner supplies direct local import aliases.
List<NativeUiFinding> inspectNativeUiSource(
  String source, {
  required String path,
  Map<String, String> importedTypeAliases = const {},
  Iterable<ImportDirective> inheritedImports = const [],
}) {
  path = path.replaceAll('\\', '/');
  if (path.startsWith('lib/src/ui/')) return const [];
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final findings = <NativeUiFinding>[];
  final emitted = <(int, NativeUiFindingKind)>{};
  void report(AstNode node, NativeUiFindingKind kind, String symbol) {
    if (!emitted.add((node.offset, kind))) return;
    final location = parsed.lineInfo.getLocation(node.offset);
    findings.add(
      NativeUiFinding(
        path: path,
        line: location.lineNumber,
        column: location.columnNumber,
        kind: kind,
        symbol: symbol,
      ),
    );
  }

  for (final error in parsed.errors) {
    final location = parsed.lineInfo.getLocation(error.offset);
    findings.add(
      NativeUiFinding(
        path: path,
        line: location.lineNumber,
        column: location.columnNumber,
        kind: NativeUiFindingKind.parseError,
        symbol: error.message,
      ),
    );
  }
  final visitor = _NativeUiVisitor(
    parsed.unit,
    report,
    importedTypeAliases,
    inheritedImports,
  );
  for (final directive in parsed.unit.directives) {
    if (directive is! NamespaceDirective) continue;
    for (final uri in [
      directive.uri,
      ...directive.configurations.map((c) => c.uri),
    ]) {
      final value = uri.stringValue;
      if (value == null) continue;
      final destination = Uri.parse(
        'package:discourse_native/${path.substring(4)}',
      ).resolve(value).toString();
      if (destination.startsWith('package:discourse_native/src/ui/') &&
          !(path == 'lib/discourse_ui.dart' && directive is ExportDirective)) {
        report(directive, NativeUiFindingKind.internalImport, value);
      }
    }
  }
  parsed.unit.accept(visitor);
  findings.sort((a, b) {
    final line = a.line.compareTo(b.line);
    return line != 0 ? line : a.column.compareTo(b.column);
  });
  return findings;
}

final class _NativeUiVisitor extends RecursiveAstVisitor<void> {
  _NativeUiVisitor(
    this.unit,
    this.report,
    this.importedTypeAliases, [
    Iterable<ImportDirective> inheritedImports = const [],
  ]) {
    for (final directive in [
      ...unit.directives.whereType<ImportDirective>(),
      ...inheritedImports,
    ]) {
      final uris = [
        directive.uri,
        ...directive.configurations.map((c) => c.uri),
      ];
      final symbols = {
        for (final uri in uris) ..._frameworkSymbols(uri.stringValue),
      };
      if (symbols.isEmpty) continue;
      for (final combinator in directive.combinators) {
        if (combinator is ShowCombinator) {
          symbols.retainAll(combinator.shownNames.map((name) => name.name));
        } else if (combinator is HideCombinator) {
          symbols.removeAll(combinator.hiddenNames.map((name) => name.name));
        }
      }
      imported
          .putIfAbsent(directive.prefix?.name ?? '', () => {})
          .addAll(symbols);
    }
    final declarations = _Declarations();
    unit.accept(declarations);
    shadows.addAll(declarations.shadows);
    aliases.addAll(declarations.aliases);
  }

  final CompilationUnit unit;
  final void Function(AstNode, NativeUiFindingKind, String) report;
  final Map<String, String> importedTypeAliases;
  final imported = <String, Set<String>>{};
  final shadows = <String, List<AstNode>>{};
  final aliases = <String, NamedType>{};

  bool _shadowed(String name, AstNode use) =>
      shadows[name]?.any(
        (scope) => use.offset >= scope.offset && use.end <= scope.end,
      ) ??
      false;

  String? _symbol(String source, AstNode use, [Set<String>? visiting]) {
    final name = source.replaceAll(RegExp(r'<.*>'), '').trim();
    final parts = name.split('.');
    if (_shadowed(parts.first, use)) return null;
    if (importedTypeAliases.containsKey(name)) return importedTypeAliases[name];
    if (parts.length == 1 && aliases.containsKey(name)) {
      final seen = visiting ?? <String>{};
      if (!seen.add(name)) return null;
      return _symbol(aliases[name]!.toSource(), aliases[name]!, seen);
    }
    final prefix = parts.length == 2 ? parts.first : '';
    final symbol = parts.last;
    if (parts.length > 2 || _shadowed(prefix.isEmpty ? symbol : prefix, use)) {
      return null;
    }
    return imported[prefix]?.contains(symbol) == true ? symbol : null;
  }

  String? _explicitConstructorSymbol(String name, AstNode node) {
    final symbol = _symbol(name, node);
    if (symbol != null) return symbol;
    final separator = name.lastIndexOf('.');
    return separator < 0 ? null : _symbol(name.substring(0, separator), node);
  }

  void _creation(
    AstNode node,
    String name,
    ArgumentList arguments, {
    bool explicitConstructor = false,
  }) {
    final symbol = explicitConstructor
        ? _explicitConstructorSymbol(name, node)
        : _symbol(name, node);
    if (symbol == null) return;
    if (_rawControls.contains(symbol) || _rawOverlays.contains(symbol)) {
      report(node, NativeUiFindingKind.rawControl, symbol);
    } else if (symbol == 'GestureDetector') {
      for (final argument in arguments.arguments.whereType<NamedArgument>()) {
        if (const {
              'onTap',
              'onTapDown',
              'onTapUp',
            }.contains(argument.name.lexeme) &&
            argument.argumentExpression is! NullLiteral) {
          report(
            node,
            NativeUiFindingKind.gestureReview,
            'GestureDetector.${argument.name.lexeme}',
          );
          break;
        }
      }
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _creation(
      node,
      node.constructorName.type.toSource(),
      node.argumentList,
      explicitConstructor: true,
    );
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final member = node.methodName.name;
    final name = target == null ? member : '$target.$member';
    if (_constructorMembers.contains(member) &&
        target != null &&
        _symbol(target, node) != null) {
      _creation(node, target, node.argumentList);
    } else {
      _creation(node, name, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _reference(AstNode node, String target, String member) {
    if (!_constructorMembers.contains(member)) return;
    final symbol = _symbol(target, node);
    if (symbol != null && _rawControls.contains(symbol)) {
      report(node, NativeUiFindingKind.rawControl, symbol);
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _reference(node, node.prefix.name, node.identifier.name);
    final symbol = _symbol(node.toSource(), node);
    if (symbol != null && _rawOverlays.contains(symbol)) {
      report(node, NativeUiFindingKind.rawControl, symbol);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    if (!node.inDeclarationContext() &&
        parent is! PrefixedIdentifier &&
        parent is! PropertyAccess &&
        parent is! MethodInvocation &&
        parent is! Combinator) {
      final symbol = _symbol(node.name, node);
      if (symbol != null && _rawOverlays.contains(symbol)) {
        report(node, NativeUiFindingKind.rawControl, symbol);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target != null) {
      _reference(node, target.toSource(), node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    final symbol = _explicitConstructorSymbol(
      node.constructorName.type.toSource(),
      node,
    );
    if (symbol != null && _rawControls.contains(symbol)) {
      report(node, NativeUiFindingKind.rawControl, symbol);
    }
    super.visitConstructorReference(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.parent is ExtendsClause ||
        node.parent is ClassTypeAlias ||
        node.parent is ImplementsClause ||
        node.parent is WithClause) {
      final symbol = _symbol(node.toSource(), node);
      if (symbol != null && _rawControls.contains(symbol)) {
        report(node, NativeUiFindingKind.rawControl, symbol);
      }
    }
    super.visitNamedType(node);
  }
}

final class _Declarations extends GeneralizingAstVisitor<void> {
  final shadows = <String, List<AstNode>>{};
  final aliases = <String, NamedType>{};

  void _add(String name, AstNode node) {
    AstNode? scope = node.parent;
    while (scope != null &&
        scope is! Block &&
        scope is! ClassDeclaration &&
        scope is! CompilationUnit &&
        scope is! FunctionExpression &&
        scope is! MethodDeclaration) {
      scope = scope.parent;
    }
    if (scope != null) shadows.putIfAbsent(name, () => []).add(scope);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _add(node.namePart.typeName.lexeme, node);
    super.visitClassDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(node.name.lexeme, node);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _add(node.name.lexeme, node);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFormalParameter(FormalParameter node) {
    final name = node.name;
    if (name != null) _add(name.lexeme, node);
    super.visitFormalParameter(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    final type = node.type;
    if (type is NamedType) aliases[node.name.lexeme] = type;
    super.visitGenericTypeAlias(node);
  }
}

List<NativeUiFinding> scanNativeUiOwnership(Directory root) {
  final lib = Directory('${root.path}/lib');
  final files =
      lib
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final sources = {
    for (final file in files)
      'lib/${file.path.substring(lib.path.length + 1)}': file
          .readAsStringSync(),
  };
  final units = {
    for (final entry in sources.entries)
      entry.key: parseString(
        content: entry.value,
        throwIfDiagnostics: false,
      ).unit,
  };
  final partImports = <String, List<ImportDirective>>{};
  for (final entry in units.entries) {
    final base = Uri.parse(
      'package:discourse_native/${entry.key.substring(4)}',
    );
    for (final part in entry.value.directives.whereType<PartDirective>()) {
      final reference = part.uri.stringValue;
      if (reference == null) continue;
      final uri = base.resolve(reference);
      if (uri.scheme != 'package' ||
          !uri.path.startsWith('discourse_native/')) {
        continue;
      }
      final path = 'lib/${uri.path.substring('discourse_native/'.length)}';
      partImports[path] = entry.value.directives
          .whereType<ImportDirective>()
          .toList();
    }
  }
  final libraryAliases = <String, Map<String, String>>{};
  for (final entry in units.entries) {
    final visitor = _NativeUiVisitor(entry.value, (_, _, _) {}, const {});
    libraryAliases['package:discourse_native/${entry.key.substring(4)}'] = {
      for (final alias in visitor.aliases.entries)
        alias.key: ?visitor._symbol(alias.value.toSource(), alias.value),
    };
  }
  return [
    for (final entry in sources.entries)
      ...inspectNativeUiSource(
        entry.value,
        path: entry.key,
        inheritedImports: partImports[entry.key] ?? const [],
        importedTypeAliases: _importedAliases(
          entry.key,
          units[entry.key]!,
          libraryAliases,
        ),
      ),
  ];
}

Map<String, String> _importedAliases(
  String path,
  CompilationUnit unit,
  Map<String, Map<String, String>> libraries,
) {
  final result = <String, String>{};
  final base = Uri.parse('package:discourse_native/${path.substring(4)}');
  for (final directive in unit.directives.whereType<ImportDirective>()) {
    for (final uri in [
      directive.uri,
      ...directive.configurations.map((c) => c.uri),
    ]) {
      if (uri.stringValue case final source?) {
        final aliases = libraries[base.resolve(source).toString()];
        if (aliases == null) continue;
        final names = aliases.keys.toSet()
          ..removeWhere((name) => name.startsWith('_'));
        for (final combinator in directive.combinators) {
          if (combinator is ShowCombinator) {
            names.retainAll(combinator.shownNames.map((name) => name.name));
          } else if (combinator is HideCombinator) {
            names.removeAll(combinator.hiddenNames.map((name) => name.name));
          }
        }
        for (final name in names) {
          final prefix = directive.prefix?.name;
          result[prefix == null ? name : '$prefix.$name'] = aliases[name]!;
        }
      }
    }
  }
  return result;
}

void main(List<String> arguments) {
  final findings = scanNativeUiOwnership(
    Directory(arguments.isEmpty ? '.' : arguments.single),
  );
  for (final finding in findings) {
    stdout.writeln(finding);
  }
  final errors = findings.where((finding) => finding.isError).length;
  final reviews = findings.length - errors;
  stdout.writeln(
    '$errors Native ownership violations; $reviews gesture reviews.',
  );
  exitCode = errors == 0 ? 0 : 1;
}
