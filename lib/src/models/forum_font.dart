import 'package:discourse_native/l10n/strings.dart';

/// Bundled reading fonts, available without network access on every platform.
enum ForumFont {
  system(null),
  openSans('Open Sans'),
  lato('Lato'),
  jetBrainsMono('JetBrains Mono');

  const ForumFont(this.family);

  String get label => switch (this) {
    system => appL10n.systemDefault,
    openSans => appL10n.openSans,
    lato => appL10n.lato,
    jetBrainsMono => appL10n.jetBrainsMono,
  };
  final String? family;

  static ForumFont fromName(Object? name) =>
      values.firstWhere((font) => font.name == name, orElse: () => system);
}

/// Release runners register this app's fonts as dependency fonts, so support
/// their package-qualified names as well as the root application's families.
List<String>? forumFontFamilyFallback(String? family) =>
    family == null ? null : ['packages/discourse_native/$family'];
