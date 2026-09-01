import 'dart:async';

import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plugin_data.dart';

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

abstract interface class ComposerSyntaxPlugin {
  ComposerSyntaxKind get composerSyntaxKind;

  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  );
}

abstract interface class ComposerSyntaxPolicy {
  ComposerSyntaxKind get kind;

  List<ComposerSyntaxProjection> parse(String source);

  /// Immutable equality token for configuration which changes projection
  /// artwork without changing source, such as a formatter setting.
  Object? get projectionState;

  TextInputFormatter? get inputFormatter;
}

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

  /// Replaces the document while its text still equals [expectedText]. This
  /// permits modal focus changes to update selection metadata without making
  /// a verified text replacement stale.
  bool commitText({
    required String expectedText,
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

abstract interface class ComposerShortcutPlugin {
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerEditorHost editor,
  );
}
