import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../plugin_api/composer_component.dart' as plugin;
import '../../plugin_api/composer_syntax.dart';
import '../../plugin_api/plugin_scope.dart';
import '../composer_document/component.dart' as document;
import '../composer_document/source.dart';

/// A type-erased registration whose implementation still owns its original T.
///
/// Call [from] before placing differently typed components in one collection.
/// This keeps the unavoidable type erasure behind a checked adapter instead of
/// invoking a covariantly upcast component callback with the wrong context.
sealed class ComposerHybridComponentRegistration {
  const ComposerHybridComponentRegistration();

  static ComposerHybridComponentRegistration from<T extends Object>(
    plugin.ComposerComponent<T> component,
  ) {
    return _TypedComposerHybridComponentRegistration<T>(component);
  }

  ComposerSyntaxKind get syntaxKind;
  document.ComposerComponentKind get documentKind;
  document.ComposerComponentDefinition<Object> createDefinition();
  ComposerHybridComponentRenderer get renderer;
  ComposerHybridComponentActions get actions;
}

/// Builds and labels validated component matches for the projected surface.
abstract interface class ComposerHybridComponentRenderer {
  ComposerSyntaxKind get syntaxKind;
  plugin.ComposerComponentLayout get layout;

  Widget build(
    BuildContext context, {
    required document.ComposerComponentMatch<Object> match,
    required TextStyle baseStyle,
    required bool selected,
    required bool hovered,
  });

  String semanticLabel(
    BuildContext context,
    document.ComposerComponentMatch<Object> match,
  );
}

/// Invokes optional component actions with a source-captured typed instance.
abstract interface class ComposerHybridComponentActions {
  bool get canEdit;
  bool get canRemove;

  FutureOr<void> edit(
    BuildContext context,
    ComposerEditorHost editor,
    document.ComposerComponentMatch<Object> match,
  );

  FutureOr<void> remove(
    BuildContext context,
    ComposerEditorHost editor,
    document.ComposerComponentMatch<Object> match,
  );
}

final class _TypedComposerHybridComponentRegistration<T extends Object>
    extends ComposerHybridComponentRegistration
    implements ComposerHybridComponentRenderer, ComposerHybridComponentActions {
  _TypedComposerHybridComponentRegistration(this._component)
    : _documentKind = document.ComposerComponentKind(_component.kind.id);

  final plugin.ComposerComponent<T> _component;
  final document.ComposerComponentKind _documentKind;

  bool get _isCore => syntaxKind.owner.value == 'core';

  BuildContext _callbackContext(BuildContext context) =>
      _isCore ? context : PluginUiScope.contextFor(context, syntaxKind.owner);

  Widget _own(Widget child) =>
      _isCore ? child : PluginUiScope.own(syntaxKind.owner, child);

  @override
  ComposerSyntaxKind get syntaxKind => _component.kind;

  @override
  document.ComposerComponentKind get documentKind => _documentKind;

  @override
  plugin.ComposerComponentLayout get layout => _component.layout;

  @override
  ComposerHybridComponentRenderer get renderer => this;

  @override
  ComposerHybridComponentActions get actions => this;

  @override
  document.ComposerComponentDefinition<Object> createDefinition() {
    return document.ComposerComponentDefinition<Object>(
      kind: _documentKind,
      layout: switch (_component.layout) {
        plugin.ComposerComponentLayout.inline =>
          document.ComposerComponentLayout.inline,
        plugin.ComposerComponentLayout.block =>
          document.ComposerComponentLayout.block,
      },
      precedence: _component.precedence,
      parse: (input) {
        final candidates = List<plugin.ComposerComponentCandidate<T>>.of(
          _component.find(input.source),
          growable: false,
        );
        return candidates
            .map(
              (candidate) => document.ComposerComponentCandidate<Object>(
                range: ComposerSourceRange(
                  candidate.range.start,
                  candidate.range.end,
                ),
                value: candidate.value,
              ),
            )
            .toList(growable: false);
      },
    );
  }

  @override
  Widget build(
    BuildContext context, {
    required document.ComposerComponentMatch<Object> match,
    required TextStyle baseStyle,
    required bool selected,
    required bool hovered,
  }) {
    return _own(
      _component.builder(
        _callbackContext(context),
        plugin.ComposerComponentRenderContext<T>(
          range: TextRange(start: match.range.start, end: match.range.end),
          value: _valueFor(match),
          baseStyle: baseStyle,
          selected: selected,
          hovered: hovered,
        ),
      ),
    );
  }

  @override
  String semanticLabel(
    BuildContext context,
    document.ComposerComponentMatch<Object> match,
  ) {
    return _component.semanticLabel(
      _callbackContext(context),
      _presentationFor(match),
    );
  }

  @override
  bool get canEdit => _component.onEdit != null;

  @override
  bool get canRemove => _component.onRemove != null;

  @override
  FutureOr<void> edit(
    BuildContext context,
    ComposerEditorHost editor,
    document.ComposerComponentMatch<Object> match,
  ) {
    final action = _component.onEdit;
    if (action == null) {
      throw UnsupportedError('Component ${syntaxKind.id} has no edit action');
    }
    return action(_callbackContext(context), editor, _instanceFor(match));
  }

  @override
  FutureOr<void> remove(
    BuildContext context,
    ComposerEditorHost editor,
    document.ComposerComponentMatch<Object> match,
  ) {
    final action = _component.onRemove;
    if (action == null) {
      throw UnsupportedError('Component ${syntaxKind.id} has no remove action');
    }
    return action(_callbackContext(context), editor, _instanceFor(match));
  }

  plugin.ComposerComponentInstance<T> _instanceFor(
    document.ComposerComponentMatch<Object> match,
  ) {
    final value = _valueFor(match);
    return plugin.ComposerComponentInstance<T>(
      range: TextRange(start: match.range.start, end: match.range.end),
      source: match.source,
      value: value,
    );
  }

  plugin.ComposerComponentPresentation<T> _presentationFor(
    document.ComposerComponentMatch<Object> match,
  ) {
    return plugin.ComposerComponentPresentation<T>(
      range: TextRange(start: match.range.start, end: match.range.end),
      value: _valueFor(match),
    );
  }

  T _valueFor(document.ComposerComponentMatch<Object> match) {
    if (match.kind != _documentKind ||
        match.layout != _definitionLayout ||
        match.value is! T) {
      throw StateError(
        'Resolved match does not belong to component ${syntaxKind.id}',
      );
    }
    return match.value as T;
  }

  document.ComposerComponentLayout get _definitionLayout {
    return switch (_component.layout) {
      plugin.ComposerComponentLayout.inline =>
        document.ComposerComponentLayout.inline,
      plugin.ComposerComponentLayout.block =>
        document.ComposerComponentLayout.block,
    };
  }
}
