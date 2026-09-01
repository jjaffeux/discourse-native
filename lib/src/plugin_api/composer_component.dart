import 'dart:async';

import 'package:flutter/widgets.dart';

import 'composer_syntax.dart';

/// Whether a composer component participates in a line or owns its own row.
enum ComposerComponentLayout { inline, block }

/// A typed component proposed by a pure [ComposerComponentFinder].
///
/// Candidates deliberately contain no source copy. The composer validates the
/// range and captures the exact Markdown from its canonical document before
/// rendering or invoking an action.
@immutable
final class ComposerComponentCandidate<T extends Object> {
  const ComposerComponentCandidate({required this.range, required this.value});

  final TextRange range;
  final T value;
}

/// A validated, raw-free component occurrence used by presentation callbacks.
///
/// Renderers and semantic labels receive this shape rather than the captured
/// source. Component conformance tests additionally verify that presentation
/// values do not turn the exact syntax into visual or spoken output.
@immutable
final class ComposerComponentPresentation<T extends Object> {
  const ComposerComponentPresentation({
    required this.range,
    required this.value,
  });

  final TextRange range;
  final T value;

  int get start => range.start;
  int get end => range.end;
}

/// One validated component occurrence in an immutable document snapshot.
///
/// [source] is the exact Markdown captured from [range], not a serialization of
/// [value]. Actions can therefore use it together with [ComposerEditorHost] to
/// make source-verified edits without making Markdown regeneration lossy.
@immutable
final class ComposerComponentInstance<T extends Object> {
  const ComposerComponentInstance({
    required this.range,
    required this.source,
    required this.value,
  });

  final TextRange range;
  final String source;
  final T value;

  int get start => range.start;
  int get end => range.end;
}

/// Immutable, raw-free input used to render one resolved component occurrence.
///
/// The exact Markdown source is deliberately available only to component
/// actions through [ComposerComponentInstance]. A renderer receives no direct
/// source field; each component's conformance test must also verify that its
/// typed presentation value is rendered without exposing authoring syntax.
@immutable
final class ComposerComponentRenderContext<T extends Object> {
  const ComposerComponentRenderContext({
    required this.range,
    required this.value,
    required this.baseStyle,
    required this.selected,
    required this.hovered,
  });

  final TextRange range;
  final T value;
  final TextStyle baseStyle;
  final bool selected;
  final bool hovered;

  int get start => range.start;
  int get end => range.end;
}

/// Finds typed component candidates without mutating [markdown] or app state.
///
/// The private composer resolver immediately materializes and validates the
/// returned iterable. Repeated calls with the same Markdown must return the
/// same ranges and values.
typedef ComposerComponentFinder<T extends Object> =
    Iterable<ComposerComponentCandidate<T>> Function(String markdown);

typedef ComposerComponentBuilder<T extends Object> =
    Widget Function(
      BuildContext context,
      ComposerComponentRenderContext<T> component,
    );

typedef ComposerComponentSemanticLabel<T extends Object> =
    String Function(
      BuildContext context,
      ComposerComponentPresentation<T> component,
    );

/// An optional component action operating against a source-verified host.
typedef ComposerComponentAction<T extends Object> =
    FutureOr<void> Function(
      BuildContext context,
      ComposerEditorHost editor,
      ComposerComponentInstance<T> component,
    );

/// Receives composer components without erasing their payload type.
///
/// A registrar can resolve [ComposerComponent.find], build instances, and call
/// component actions while the same `T` remains in scope. This avoids storing
/// callbacks behind `ComposerComponent<Object>`, which would make invoking a
/// plugin's typed callbacks unsound.
abstract interface class ComposerComponentRegistrar {
  void add<T extends Object>(ComposerComponent<T> component);
}

/// Declares the one atomic composer component owned by a plugin.
///
/// [composerComponentKind] is validated against the contributing site
/// plugin's namespace by the registry. Implementations must call
/// [ComposerComponentRegistrar.add] exactly once for that same kind.
abstract interface class ComposerComponentPlugin {
  ComposerSyntaxKind get composerComponentKind;

  void registerComposerComponent(
    ComposerSyntaxPolicyContext context,
    ComposerComponentRegistrar registrar,
  );
}

/// The complete plugin contract for one atomic inline or block component.
///
/// Higher [precedence] wins when multiple kinds propose the exact same range;
/// equal precedence is resolved by [kind]'s namespaced identifier. Cursor,
/// selection, deletion, and navigation behavior are composer invariants and
/// intentionally cannot be customized by a component.
@immutable
final class ComposerComponent<T extends Object> {
  const ComposerComponent.inline({
    required this.kind,
    this.precedence = 0,
    required this.find,
    required this.builder,
    required this.semanticLabel,
    this.onEdit,
    this.onRemove,
  }) : layout = ComposerComponentLayout.inline;

  const ComposerComponent.block({
    required this.kind,
    this.precedence = 0,
    required this.find,
    required this.builder,
    required this.semanticLabel,
    this.onEdit,
    this.onRemove,
  }) : layout = ComposerComponentLayout.block;

  final ComposerSyntaxKind kind;
  final ComposerComponentLayout layout;
  final int precedence;
  final ComposerComponentFinder<T> find;
  final ComposerComponentBuilder<T> builder;
  final ComposerComponentSemanticLabel<T> semanticLabel;
  final ComposerComponentAction<T>? onEdit;
  final ComposerComponentAction<T>? onRemove;
}
