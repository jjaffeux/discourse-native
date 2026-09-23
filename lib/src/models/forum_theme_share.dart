import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pointycastle/digests/sha256.dart';

import 'forum_theme.dart';

/// A self-contained theme carried by a Markdown fence in posts and chat.
/// The standard code fence survives server cooking without a server extension.
abstract final class ForumThemeShare {
  static const language = 'discourse-theme';
  static const maxLength = 65536;

  static String encode(ForumTheme theme) =>
      '```$language\n${jsonEncode(_data(theme))}\n```';

  // Both editor tabs must share the same identity. Legacy single-mode themes
  // include the derived second palette that the app already displays.
  static Map<String, dynamic> _data(ForumTheme theme) => {
    ...theme.forBrightness(Brightness.light).toJson(),
    'alternate': theme.forBrightness(Brightness.dark).toJson(),
  };

  /// Validates the portable data and assigns an identity based on its contents.
  /// Sender-supplied IDs cannot overwrite an existing local custom theme.
  static ForumTheme? decode(String source) {
    if (source.length > maxLength) return null;
    try {
      final value = jsonDecode(source);
      if (value is! Map<String, dynamic>) return null;
      final theme = ForumTheme.fromJson(value, id: 'shared');
      final data = _data(theme);
      final digest = SHA256Digest().process(
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
      );
      final id = digest
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      return ForumTheme.fromJson(data, id: 'custom-shared-$id');
    } on FormatException {
      return null;
    }
  }

  static bool matches(ForumTheme? first, ForumTheme second) =>
      first != null && jsonEncode(_data(first)) == jsonEncode(_data(second));
}
