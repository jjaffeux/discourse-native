import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:flutter/services.dart';

final class FakeComposerEditorHost implements ComposerEditorHost {
  FakeComposerEditorHost(this.value);

  @override
  TextEditingValue value;

  bool current = true;
  bool focusRequested = false;
  int commitCalls = 0;
  int commitTextCalls = 0;

  @override
  String get siteUrl => 'https://meta.example.com';

  @override
  bool get isPluginTarget => false;

  @override
  String? get originalRaw => null;

  @override
  bool get loadingBody => false;

  @override
  bool get isCurrent => current;

  @override
  bool get isEdit => false;

  @override
  PluginData get siteSettings => PluginData.none;

  @override
  T? syntaxPolicy<T extends ComposerSyntaxPolicy>(ComposerSyntaxKind kind) =>
      null;

  @override
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) {
    commitCalls += 1;
    if (this.value != expectedValue) return false;
    this.value = value;
    return true;
  }

  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) {
    commitTextCalls += 1;
    if (this.value.text != expectedText) return false;
    this.value = value;
    return true;
  }

  @override
  bool insertBlock({
    required TextEditingValue expectedValue,
    required String markdown,
  }) => false;

  @override
  void requestFocus() {
    focusRequested = true;
  }
}
