/// Bundled reading fonts, available without network access on every platform.
enum ForumFont {
  system('System default', null),
  openSans('Open Sans', 'Open Sans'),
  lato('Lato', 'Lato'),
  jetBrainsMono('JetBrains Mono', 'JetBrains Mono');

  const ForumFont(this.label, this.family);

  final String label;
  final String? family;

  static ForumFont fromName(Object? name) =>
      values.firstWhere((font) => font.name == name, orElse: () => system);
}

/// Release runners register this app's fonts as dependency fonts, so support
/// their package-qualified names as well as the root application's families.
List<String>? forumFontFamilyFallback(String? family) =>
    family == null ? null : ['packages/discourse_native/$family'];
