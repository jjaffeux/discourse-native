import 'dart:async';

import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plugin_data.dart';

/// Stable, plugin-owned identity for one composer syntax language.
@immutable
final class ComposerSyntaxKind {
  const ComposerSyntaxKind({required this.owner, required this.name});

  final PluginId owner;
  final String name;

  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is ComposerSyntaxKind && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

/// Opaque plugin-owned record state available to one composer.
///
/// Core deliberately exposes only namespaced plugin data plus the two neutral
/// account facts needed by authoring features. A syntax plugin cannot inspect
/// unrelated core account, route, post, or site-configuration fields through
/// the generic composer boundary.
@immutable
final class ComposerPluginState {
  const ComposerPluginState({
    this.siteSettings = PluginData.none,
    this.currentUser = PluginData.none,
    this.freshCurrentUser = PluginData.none,
    this.editingPost = PluginData.none,
    this.accountTimezone,
    this.freshCurrentUserIsStaff = false,
  });

  final PluginData siteSettings;
  final PluginData currentUser;
  final PluginData freshCurrentUser;
  final PluginData editingPost;
  final String? accountTimezone;
  final bool freshCurrentUserIsStaff;
}

typedef ComposerPluginStateReader = ComposerPluginState Function();

/// Immutable target facts and state reader used to create one syntax policy.
@immutable
final class ComposerSyntaxPolicyContext {
  const ComposerSyntaxPolicyContext({
    required this.siteUrl,
    required this.isPluginTarget,
    required this.isEdit,
    required this.initialState,
    required this.readState,
  });

  final String siteUrl;
  final bool isPluginTarget;
  final bool isEdit;
  final ComposerPluginState initialState;
  final ComposerPluginStateReader readState;
}

/// The feature-neutral artwork inputs for one collapsed source projection.
@immutable
final class ComposerSyntaxRenderContext {
  const ComposerSyntaxRenderContext({
    required this.baseStyle,
    required this.locale,
    required this.pillKey,
    required this.highlighted,
    required this.hovered,
    required this.followedByLineBreak,
  });

  final TextStyle baseStyle;
  final Locale locale;
  final GlobalKey pillKey;
  final bool highlighted;
  final bool hovered;
  final bool followedByLineBreak;
}

/// One plugin-owned, losslessly recognised source range in a composer.
final class ComposerSyntaxOccurrence {
  const ComposerSyntaxOccurrence(this.policy, this.projection);

  final ComposerSyntaxPolicy policy;
  final ComposerSyntaxProjection projection;

  ComposerSyntaxKind get kind => policy.kind;
  int get start => projection.start;
  int get end => projection.end;
  String get source => projection.source;

  bool sameAs(ComposerSyntaxOccurrence? other) =>
      other != null &&
      kind == other.kind &&
      start == other.start &&
      end == other.end &&
      source == other.source;
}

/// Creates one stable parser/projector policy for each open composer.
abstract interface class ComposerSyntaxPlugin {
  ComposerSyntaxKind get composerSyntaxKind;

  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  );
}

/// A plugin-owned parser and projection configuration for one composer.
abstract interface class ComposerSyntaxPolicy {
  ComposerSyntaxKind get kind;

  List<ComposerSyntaxProjection> parse(String source);

  /// Immutable equality token for configuration which changes projection
  /// artwork without changing source, such as a formatter setting.
  Object? get projectionState;

  TextInputFormatter? get inputFormatter;
}

/// One typed plugin-owned source projection.
///
/// Core owns only ordering and source offsets. The plugin retains its parsed
/// value, validation rules, artwork, caret behavior, and editing semantics.
abstract interface class ComposerSyntaxProjection {
  int get start;
  int get end;
  String get source;

  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  });

  int caretAfter(String document);

  TextEditingValue moveCaretAfter(TextEditingValue document);

  bool get supportsHover;

  bool get protectsAdjacentDelete;

  bool get hidesCursorWhenSelected;

  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context);

  FutureOr<void> edit(BuildContext context, ComposerEditorHost editor);

  FutureOr<void> remove(BuildContext context, ComposerEditorHost editor);
}

/// The least authority a plugin needs to inspect and safely edit one composer.
abstract interface class ComposerEditorHost {
  String get siteUrl;
  bool get isPluginTarget;
  TextEditingValue get value;
  String? get originalRaw;
  bool get loadingBody;
  bool get isCurrent;
  bool get isEdit;
  PluginData get siteSettings;

  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind);

  /// Replaces the document only while this remains the current composer and
  /// its complete editing value still equals [expectedValue].
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  });

  /// Inserts a source block only while the complete document still equals
  /// [expectedValue]. The comparison and insertion are one synchronous edit.
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  });

  void requestFocus();
}

/// Adds keyboard commands whose availability is owned by a plugin.
abstract interface class ComposerShortcutPlugin {
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerEditorHost editor,
  );
}
