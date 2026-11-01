import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../chat/chat_preview_contract.dart';
import 'math_composer.dart';
import 'math_services.dart';
import 'math_settings.dart';
import 'math_source.dart';

final class DiscourseMathPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<MathSettings>,
        CookingPlugin,
        CookedElementPlugin,
        ComposerToolbarPlugin,
        ComposerShortcutPlugin,
        ComposerSyntaxPlugin,
        ChatPreviewContribution {
  const DiscourseMathPlugin();
  @override
  String get name => 'discourse-math';
  @override
  PluginDataPersistenceCodec<MathSettings> get siteSettingsCodec =>
      const MathSettingsCodec();
  @override
  MathSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      MathSettings.fromWire(json);
  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: name,
      owner: name,
      version: '1',
      enabledSetting: 'discourse_math_enabled',
    ),
  ];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) => {
    'settings': (data.read(mathSettingsKey) ?? const MathSettings()).toWire(),
  };
  @override
  ComposerSyntaxKind get composerSyntaxKind => mathSyntaxKind;
  @override
  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) => MathComposerPolicy(context);
  bool _enabled(ComposerEditorHost editor) =>
      editor.isCurrent &&
      editor.isEditing &&
      !editor.loadingBody &&
      editor.siteSettings.get(mathSettingsKey)?.configuration != null;
  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) => !_enabled(editor)
      ? const []
      : [
          ComposerToolbarContribution(
            icon: DIcons.squareRootVariable,
            label: context.l10n.insertMath,
            onInvoke: () => insertMath(context, editor),
          ),
        ];
  @override
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerEditorHost editor,
  ) => !_enabled(editor)
      ? const {}
      : {
          const SingleActivator(LogicalKeyboardKey.keyM, shift: true): () =>
              insertMath(context, editor),
        };
  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    final expression = readMathElement(element);
    if (expression == null) return null;
    final child = _CookedMath(
      siteUrl: siteUrl,
      expression: expression,
      element: element,
    );
    return expression.display ? child : InlineCustomWidget(child: child);
  }

  @override
  String get previewFeatureId => name;
  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final settings =
        request.siteConfig.plugins.get(mathSettingsKey) ?? const MathSettings();
    final occurrences = scanMath(request.raw, settings);
    return ChatPreviewInspection(
      claims: [
        for (final item in occurrences)
          ChatPreviewClaim(
            range: SourceRange(item.start, item.end),
            node: PluginPreviewNode(
              range: SourceRange(item.start, item.end),
              featureId: name,
              kind: item.expression.input.name,
              fallbackText: item.original,
              attributes: {
                'source': item.expression.source,
                'display': '${item.expression.display}',
                'settings': jsonEncode(settings.toWire()),
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node) {
    if (node.featureId != name || !['tex', 'ascii'].contains(node.kind)) {
      return null;
    }
    final source = node.attributes['source'];
    if (source == null) return null;
    final stored = node.attributes['settings'];
    if (stored == null) return null;
    final settings = const MathSettingsCodec().decode(jsonDecode(stored));
    final config = settings?.configuration;
    if (config == null) return null;
    return DMath(
      expression: DMathExpression(
        source,
        input: node.kind == 'ascii' ? DMathInput.ascii : DMathInput.tex,
        display: node.attributes['display'] == 'true',
      ),
      configuration: config,
    );
  }
}

class _CookedMath extends StatelessWidget {
  const _CookedMath({required this.expression, this.siteUrl, this.element});
  final DMathExpression expression;
  final String? siteUrl;
  final dom.Element? element;
  @override
  Widget build(BuildContext context) {
    final service = PluginUiScope.maybe(context, mathServiceKey);
    if (service == null || siteUrl == null) return Text(expression.source);
    final changes = service.sites.siteConfigListenableFor?.call(siteUrl!);
    Widget render() {
      final settings = service.sites
          .siteConfigFor(siteUrl!)
          .plugins
          .get(mathSettingsKey);
      final configuration = settings?.configuration;
      if (configuration == null ||
          expression.input == DMathInput.ascii &&
              settings?.supportsAscii != true) {
        return Text(expression.source);
      }
      var root = element?.parentNode;
      while (root?.parentNode != null) {
        root = root!.parentNode;
      }
      final document = root == null
          ? null
          : _mathDocuments[root] ??= _MathDocument(root);
      final index = document?.elements.indexOf(element!);
      return KeyedSubtree(
        key: document?.keys[element],
        child: DMath(
          key: ObjectKey(service),
          expression: expression,
          configuration: configuration,
          context: document?.expressions ?? const [],
          contextIndex: index,
          onLink: (url) {
            if (url.startsWith('#')) {
              String fragment;
              try {
                fragment = Uri.decodeComponent(url.substring(1));
              } on FormatException {
                return;
              }
              final target = document
                  ?.labels[fragment.startsWith('mjx-eqn:')
                      ? fragment.substring(8)
                      : fragment]
                  ?.currentContext;
              if (target != null) unawaited(Scrollable.ensureVisible(target));
            } else {
              final parsed = Uri.tryParse(url);
              if (parsed != null &&
                  (!parsed.hasScheme ||
                      ['http', 'https', 'mailto'].contains(parsed.scheme)) &&
                  !url.startsWith('//')) {
                unawaited(openLink(context, url, siteUrl: siteUrl));
              }
            }
          },
        ),
      );
    }

    return changes == null
        ? render()
        : ListenableBuilder(listenable: changes, builder: (_, _) => render());
  }
}

Iterable<dom.Element> _elements(dom.Node root) sync* {
  for (final child in root.nodes) {
    if (child is dom.Element && readMathElement(child) != null) yield child;
    yield* _elements(child);
  }
}

final _mathDocuments = Expando<_MathDocument>();

final class _MathDocument {
  _MathDocument(dom.Node root) {
    for (final element in _elements(root)) {
      elements.add(element);
      final expression = readMathElement(element)!;
      expressions.add(expression);
      final key = keys[element] = GlobalKey();
      for (final label in RegExp(
        r'\\label\{([A-Za-z_][A-Za-z0-9_.:-]*)\}',
      ).allMatches(expression.source)) {
        labels.putIfAbsent(label.group(1)!, () => key);
      }
    }
  }
  final elements = <dom.Element>[];
  final expressions = <DMathExpression>[];
  final keys = <dom.Element, GlobalKey>{};
  final labels = <String, GlobalKey>{};
}
