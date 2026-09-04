import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../plugin_api/composer_syntax.dart';
import '../../plugin_api/plugin_data.dart';
import '../composer_document/component.dart';
import '../composer_document/document.dart';
import '../composer_document/interaction.dart';
import '../composer_document/projection.dart';
import '../composer_document/selection.dart';
import '../composer_document/source.dart';
import 'component_registration.dart';

sealed class ComposerHybridDispatchResult {
  const ComposerHybridDispatchResult();

  bool get handled;
  bool get changed;
}

final class ComposerHybridPassThrough extends ComposerHybridDispatchResult {
  const ComposerHybridPassThrough();

  @override
  bool get handled => false;

  @override
  bool get changed => false;
}

final class ComposerHybridSelectionHandled
    extends ComposerHybridDispatchResult {
  const ComposerHybridSelectionHandled({
    required this.before,
    required this.after,
  });

  final ComposerSelection before;
  final ComposerSelection after;

  @override
  bool get handled => true;

  @override
  bool get changed => before != after;
}

final class ComposerHybridTransactionHandled
    extends ComposerHybridDispatchResult {
  const ComposerHybridTransactionHandled(this.result);

  final ComposerCommitResult result;

  @override
  bool get handled => true;

  @override
  bool get changed => result is ComposerCommitApplied;
}

/// The single project-owned editing session behind a projected composer.
///
/// Markdown remains canonical. Editor surfaces translate gestures and keys to
/// semantic intents, while this session owns resolution, verified edits,
/// selection normalization, and history without exposing a widget package.
final class ComposerHybridEditingSession extends ChangeNotifier {
  factory ComposerHybridEditingSession({
    required String markdown,
    required Iterable<ComposerHybridComponentRegistration> registrations,
    ComposerSelection? selection,
    ComposerProjectionResolver resolver = const ComposerProjectionResolver(),
    ComposerSelectionNormalizer selectionNormalizer =
        const ComposerSelectionNormalizer(),
    ComposerInteractionReducer interactionReducer =
        const ComposerInteractionReducer(),
  }) {
    final frozenRegistrations =
        List<ComposerHybridComponentRegistration>.unmodifiable(registrations);
    final registrationsByKind =
        <ComposerComponentKind, ComposerHybridComponentRegistration>{};
    for (final registration in frozenRegistrations) {
      if (registrationsByKind.containsKey(registration.documentKind)) {
        throw ArgumentError.value(
          registration.syntaxKind.id,
          'registrations',
          'contains a duplicate component kind',
        );
      }
      registrationsByKind[registration.documentKind] = registration;
    }
    final document = ComposerDocument(
      source: markdown,
      definitions: frozenRegistrations.map(
        (registration) => registration.createDefinition(),
      ),
      selection: selection,
      resolver: resolver,
      selectionNormalizer: selectionNormalizer,
    );
    return ComposerHybridEditingSession._(
      document: document,
      registrationsByKind: Map.unmodifiable(registrationsByKind),
      interactionReducer: interactionReducer,
    );
  }

  ComposerHybridEditingSession._({
    required this._document,
    required this._registrationsByKind,
    required this._interactionReducer,
  });

  final ComposerDocument _document;
  final Map<ComposerComponentKind, ComposerHybridComponentRegistration>
  _registrationsByKind;
  final ComposerInteractionReducer _interactionReducer;

  String get markdown => _document.snapshot.source;
  ComposerRevision get revision => _document.snapshot.revision;
  ComposerDocumentSnapshot get snapshot => _document.snapshot;
  ComposerSelection get selection => _document.snapshot.selection;
  bool get canUndo => _document.canUndo;
  bool get canRedo => _document.canRedo;

  ComposerHybridComponentRenderer? rendererFor(ComposerComponentKind kind) {
    return _registrationsByKind[kind]?.renderer;
  }

  ComposerHybridComponentActions? actionsFor(ComposerComponentKind kind) {
    final registration = _registrationsByKind[kind];
    if (registration == null) return null;
    return _SessionBoundComposerComponentActions(
      this,
      kind,
      registration.actions,
      revision,
    );
  }

  ComposerHybridComponentRenderer? rendererForSyntaxKind(
    ComposerSyntaxKind kind,
  ) {
    return rendererFor(ComposerComponentKind(kind.id));
  }

  ComposerHybridComponentActions? actionsForSyntaxKind(
    ComposerSyntaxKind kind,
  ) {
    return actionsFor(ComposerComponentKind(kind.id));
  }

  ComposerHybridDispatchResult dispatch(ComposerInteractionIntent intent) {
    final decision = _interactionReducer.reduce(snapshot, intent);
    return switch (decision) {
      ComposerInteractionPassThrough() => const ComposerHybridPassThrough(),
      ComposerInteractionSelection() => _applySelection(decision.selection),
      ComposerInteractionTransaction() => ComposerHybridTransactionHandled(
        commit(decision.transaction),
      ),
    };
  }

  ComposerCommitResult commit(ComposerTransaction transaction) {
    final result = _document.commit(transaction);
    if (result is ComposerCommitApplied) notifyListeners();
    return result;
  }

  ComposerDocumentSnapshot? undo() {
    final restored = _document.undo();
    if (restored != null) notifyListeners();
    return restored;
  }

  ComposerDocumentSnapshot? redo() {
    final restored = _document.redo();
    if (restored != null) notifyListeners();
    return restored;
  }

  ComposerHybridSelectionHandled _applySelection(ComposerSelection requested) {
    final before = selection;
    final after = _document.setSelection(requested).selection;
    if (before != after) notifyListeners();
    return ComposerHybridSelectionHandled(before: before, after: after);
  }
}

final class _SessionBoundComposerComponentActions
    implements ComposerHybridComponentActions {
  const _SessionBoundComposerComponentActions(
    this._session,
    this._kind,
    this._delegate,
    this._revision,
  );

  final ComposerHybridEditingSession _session;
  final ComposerComponentKind _kind;
  final ComposerHybridComponentActions _delegate;
  final ComposerRevision _revision;

  @override
  bool get canEdit => _session.revision == _revision && _delegate.canEdit;

  @override
  bool get canRemove => _session.revision == _revision && _delegate.canRemove;

  @override
  FutureOr<void> edit(
    BuildContext context,
    ComposerEditorHost editor,
    ComposerComponentMatch<Object> match,
  ) {
    final currentMatch = _currentMatch(match);
    if (currentMatch == null) return Future<void>.value();
    return _delegate.edit(
      context,
      _RevisionLeasedComposerEditorHost(_session, editor, _revision),
      currentMatch,
    );
  }

  @override
  FutureOr<void> remove(
    BuildContext context,
    ComposerEditorHost editor,
    ComposerComponentMatch<Object> match,
  ) {
    final currentMatch = _currentMatch(match);
    if (currentMatch == null) return Future<void>.value();
    return _delegate.remove(
      context,
      _RevisionLeasedComposerEditorHost(_session, editor, _revision),
      currentMatch,
    );
  }

  ComposerComponentMatch<Object>? _currentMatch(
    ComposerComponentMatch<Object> requested,
  ) {
    if (_session.revision != _revision || requested.kind != _kind) return null;
    final current = _session.snapshot.projection.componentForToken(
      requested.token,
    );
    return current;
  }
}

/// Grants one mutation while both the host and hybrid snapshot remain current.
final class _RevisionLeasedComposerEditorHost implements ComposerEditorHost {
  _RevisionLeasedComposerEditorHost(
    this._session,
    this._delegate,
    this._revision,
  );

  final ComposerHybridEditingSession _session;
  final ComposerEditorHost _delegate;
  final ComposerRevision _revision;
  bool _consumed = false;
  ComposerRevision? _focusRevision;

  bool get _revisionIsCurrent =>
      _session.revision == _revision && _delegate.isCurrent;

  bool get _canMutate => !_consumed && _revisionIsCurrent;

  @override
  bool get isCurrent => _canMutate;

  @override
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) {
    if (!_canMutate) return false;
    final committed = _delegate.commit(
      expectedValue: expectedValue,
      value: value,
    );
    if (committed) _consumeMutationLease();
    return committed;
  }

  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) {
    if (!_canMutate) return false;
    final committed = _delegate.commitText(
      expectedText: expectedText,
      value: value,
    );
    if (committed) _consumeMutationLease();
    return committed;
  }

  @override
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  }) {
    if (!_canMutate) return false;
    final committed = _delegate.insertBlock(
      expectedValue: expectedValue,
      markdown: markdown,
    );
    if (committed) _consumeMutationLease();
    return committed;
  }

  void _consumeMutationLease() {
    _consumed = true;
    // A session-backed delegate can synchronously advance the canonical
    // revision while committing. Preserve only that resulting revision for
    // the conventional commit-then-focus handoff.
    _focusRevision = _session.revision;
  }

  @override
  bool get isEdit => _delegate.isEdit;

  @override
  bool get isNewTopic => _delegate.isNewTopic;

  @override
  bool get isReply => _delegate.isReply;

  @override
  bool get isEditing => _delegate.isEditing;

  @override
  bool get isPluginTarget => _delegate.isPluginTarget;

  @override
  bool get loadingBody => _delegate.loadingBody;

  @override
  String? get originalRaw => _delegate.originalRaw;

  @override
  PluginData get siteSettings => _delegate.siteSettings;

  @override
  String get siteUrl => _delegate.siteUrl;

  @override
  TextEditingValue get value => _delegate.value;

  @override
  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind) {
    return _delegate.syntaxPolicy<T>(kind);
  }

  @override
  void requestFocus() {
    // Existing component actions commit first and restore focus afterwards.
    // Consumption prevents a second mutation, but the successful delegate can
    // have advanced the canonical session by one revision before this call.
    final permittedRevision = _focusRevision ?? _revision;
    if (_session.revision == permittedRevision && _delegate.isCurrent) {
      _delegate.requestFocus();
    }
  }
}
