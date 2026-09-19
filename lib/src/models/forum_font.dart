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
