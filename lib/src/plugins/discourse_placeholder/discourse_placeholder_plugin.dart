import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/cooked_html.dart';
import 'placeholder_document.dart';
import 'placeholder_session.dart';

final class DiscoursePlaceholderPlugin
    implements SitePlugin, PostBodyTransformPlugin, CookedElementPlugin {
  const DiscoursePlaceholderPlugin();

  @override
  String get name => placeholderPluginId.value;

  @override
  Widget? transformPostBody(
    PluginPostBodyContext context,
    String cooked,
    PluginPostBodyBuilder builder,
  ) {
    if (context.topic == null ||
        !cooked.contains('data-wrap') ||
        !cooked.contains('placeholder')) {
      return null;
    }
    return _PlaceholderPostBody(
      postContext: context,
      cooked: cooked,
      builder: builder,
    );
  }

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    if (!element.classes.contains('d-wrap') ||
        element.attributes['data-wrap'] != 'placeholder') {
      return null;
    }
    final index = int.tryParse(
      element.attributes[placeholderFieldAttribute] ?? '',
    );
    if (index == null) return null;
    return Builder(
      builder: (context) {
        final scope = context
            .dependOnInheritedWidgetOfExactType<_PlaceholderScope>();
        final field = scope?.field(index, element.attributes['data-key']);
        if (field == null || siteUrl != scope!.siteUrl) {
          return CookedHtml(html: element.innerHtml, siteUrl: siteUrl);
        }
        return _PlaceholderField(
          key: field.widgetKey,
          field: field,
          description: element.attributes['data-description'],
          descriptionHtml: element.innerHtml,
          siteUrl: siteUrl,
          definition: scope.document.definitions[field.name]!,
          values: scope.values,
        );
      },
    );
  }
}

class _PlaceholderPostBody extends StatefulWidget {
  const _PlaceholderPostBody({
    required this.postContext,
    required this.cooked,
    required this.builder,
  });
  final PluginPostBodyContext postContext;
  final String cooked;
  final PluginPostBodyBuilder builder;

  @override
  State<_PlaceholderPostBody> createState() => _PlaceholderPostBodyState();
}

class _PlaceholderPostBodyState extends State<_PlaceholderPostBody> {
  late PlaceholderDocument _document;
  PlaceholderSession? _session;
  PlaceholderValues? _values;
  final _fields = <_FieldEditing>[];
  Timer? _debounce;
  late String _displayed;

  @override
  void initState() {
    super.initState();
    _document = PlaceholderDocument.parse(widget.cooked);
    _displayed = widget.cooked;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(_PlaceholderPostBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cooked != widget.cooked) {
      _document = PlaceholderDocument.parse(widget.cooked);
    }
    _bind();
  }

  void _bind() {
    final session = PluginUiScope.optional(context, placeholderSessionService);
    final post = widget.postContext;
    final previous = _values;
    if (_document.definitions.isEmpty || session == null) {
      _detach();
      _displayed = widget.cooked;
      return;
    }
    if (session != _session ||
        previous == null ||
        !previous.isCurrent ||
        previous.id.siteUrl != post.siteUrl ||
        previous.id.topicId != post.topic!.id ||
        previous.id.postId != post.post.id) {
      _detach();
      _session = session;
      _values = session.acquire(post.siteUrl, post.topic!.id, post.post.id)
        ..addListener(_changed);
    }
    _syncFields();
    _displayed = _document.render(_values!.overrides);
  }

  void _syncFields() {
    for (var index = 0; index < _document.fields.length; index++) {
      final key = _document.fields[index];
      if (index < _fields.length && _fields[index].name != key) {
        _retire(_fields[index]);
        _fields[index] = _FieldEditing(key);
      } else if (index == _fields.length) {
        _fields.add(_FieldEditing(key));
      }
      final field = _fields[index];
      final value =
          _values!.overrides[key] ??
          _document.definitions[key]!.defaultValue ??
          '';
      if (!field.focus.hasFocus && field.text.text != value) {
        field.text.text = value;
      }
    }
    while (_fields.length > _document.fields.length) {
      _retire(_fields.removeLast());
    }
  }

  void _changed() {
    _syncFields();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _displayed = _document.render(_values!.overrides));
    });
  }

  void _retire(_FieldEditing field) {
    // Old HTML may retain an editor until the replacement frame is committed.
    WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());
  }

  void _detach() {
    _debounce?.cancel();
    final values = _values;
    _values = null;
    if (values != null) {
      values.removeListener(_changed);
      _session!.release(values);
    }
    for (final field in _fields) {
      _retire(field);
    }
    _fields.clear();
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    if (values == null) return widget.builder(context, widget.cooked);
    return _PlaceholderScope(
      siteUrl: widget.postContext.siteUrl,
      document: _document,
      fields: _fields,
      values: values,
      child: Builder(builder: (context) => widget.builder(context, _displayed)),
    );
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

class _FieldEditing {
  _FieldEditing(this.name);
  final String name;
  final widgetKey = GlobalKey();
  final text = TextEditingController();
  final focus = FocusNode();
  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

class _PlaceholderScope extends InheritedWidget {
  const _PlaceholderScope({
    required this.siteUrl,
    required this.document,
    required this.fields,
    required this.values,
    required super.child,
  });
  final String siteUrl;
  final PlaceholderDocument document;
  final List<_FieldEditing> fields;
  final PlaceholderValues values;

  _FieldEditing? field(int index, String? name) =>
      index >= 0 && index < fields.length && fields[index].name == name
      ? fields[index]
      : null;

  @override
  bool updateShouldNotify(_PlaceholderScope oldWidget) => true;
}

class _PlaceholderField extends StatelessWidget {
  const _PlaceholderField({
    super.key,
    required this.field,
    required this.description,
    required this.descriptionHtml,
    required this.siteUrl,
    required this.definition,
    required this.values,
  });
  final _FieldEditing field;
  final String? description;
  final String descriptionHtml;
  final String? siteUrl;
  final PlaceholderDefinition definition;
  final PlaceholderValues values;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final options = definition.defaults.toSet();
    final value = values.overrides[definition.key] ?? definition.defaultValue;
    void change(String value) => values.change(
      definition.key,
      value,
      defaultValue: definition.defaultValue,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 528),
          child: Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                tokens.primary.withValues(alpha: dark ? .10 : .05),
                tokens.background,
              ),
              borderRadius: const BorderRadiusDirectional.only(
                topEnd: Radius.circular(DSpacing.sm),
                bottomEnd: Radius.circular(DSpacing.sm),
              ),
            ),
            foregroundDecoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: tokens.primary, width: DSpacing.xs),
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(22, 16, 18, 16),
            child: DField(
              children: [
                DFieldLabel(
                  focusNode: field.focus,
                  excludeSemantics: true,
                  child: Text(definition.key),
                ),
                DFieldControl(
                  // Text editors expose their label at the editor's native boundary.
                  label: options.isEmpty ? '' : definition.key,
                  description: description,
                  child: options.isEmpty
                      ? DInput(
                          controller: field.text,
                          focusNode: field.focus,
                          semanticLabel: definition.key,
                          hintText: description,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: change,
                        )
                      : DSelect<String>.controlled(
                          focusNode: field.focus,
                          isExpanded: true,
                          value: options.contains(value) || value == 'none'
                              ? value
                              : null,
                          placeholder: description ?? 'Select a value',
                          entries: [
                            if (description != null &&
                                description!.isNotEmpty &&
                                !options.contains('none'))
                              DSelectOption(
                                value: 'none',
                                label: description!,
                                child: Text(description!),
                              ),
                            for (final option in options)
                              DSelectOption(
                                value: option,
                                label: option,
                                child: Text(option),
                              ),
                          ],
                          onChanged: (value) => change(value ?? 'none'),
                        ),
                ),
                if (descriptionHtml.trim().isNotEmpty)
                  DFieldDescription(
                    child: Builder(
                      builder: (context) => CookedHtml(
                        html: descriptionHtml,
                        textStyle: DefaultTextStyle.of(context).style,
                        siteUrl: siteUrl,
                        compactParagraphs: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
