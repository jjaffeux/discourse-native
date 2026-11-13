import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Core limits a topic title to 255 characters. Its fancy-title fallback is
/// the HTML-escaped raw title, whose longest entity (`&quot;`) is six UTF-16
/// code units, so even that worst case fits in 255 * 6. Bounding the fallback
/// before DOM parsing keeps a malformed response from allocating an arbitrary
/// HTML tree without changing any conforming title.
const int maximumFancyTitleSourceCodeUnits = 1530;

/// Server IDs and counts are signed 64-bit values: 19 digits, plus an optional
/// minus sign. Reject longer strings before `int.tryParse`; a malformed JSON
/// response is otherwise able to spend CPU and temporary memory parsing a
/// multi-megabyte decimal field at every model boundary that uses these
/// helpers.
const int maximumJsonIntegerCodeUnits = 20;

/// Normal wire values are around 24–35 code units. Sixty-four leaves room for
/// fractional precision and a numeric timezone while refusing corrupted
/// multi-megabyte strings before `DateTime.tryParse` scans them.
const int maximumJsonDateCodeUnits = 64;

int jsonInt(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s when s.length <= maximumJsonIntegerCodeUnits =>
    int.tryParse(s) ?? 0,
  _ => 0,
};

int? jsonIntOrNull(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s when s.length <= maximumJsonIntegerCodeUnits => int.tryParse(
    s,
  ),
  _ => null,
};

String jsonString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

Map<String, dynamic> jsonObject(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// Plugin codecs read values back from this app's own storage, where a map
/// may have been decoded with untyped keys. A codec answers null for a value
/// that is not an object or carries a non-string key, because a value it
/// cannot read is one it must not claim to hold; [jsonObject]'s empty
/// fallback would turn that into a default record.
Map<String, Object?>? jsonObjectFields(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<dynamic> jsonArray(Object? value) =>
    value is List<dynamic> ? value : const [];

Iterable<Map<String, dynamic>> jsonObjects(Object? value) sync* {
  for (final entry in jsonArray(value)) {
    if (entry is Map<String, dynamic>) yield entry;
  }
}

String? jsonText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// An emoji image stands as its shortcode, which is what core's own plain
/// excerpt writes in its place. Cooked HTML and `keep_emoji_images` excerpts
/// (PostItemExcerpt) carry the `<img>` instead, and an image has no text:
/// dropping it would split a sentence around a double space and leave an
/// emoji-only post blank.
String? jsonHtmlText(Object? value) {
  final source = jsonText(value);
  if (source == null) return null;
  if (!source.contains('<') &&
      !source.contains('&') &&
      !source.contains('\r') &&
      !source.contains('\u0000')) {
    return jsonText(source.replaceAll(_htmlWhitespace, ' '));
  }
  final fragment = html.parseFragment(source);
  final text = StringBuffer();
  _appendExcerptText(fragment, text);
  return jsonText(text.toString().replaceAll(_htmlWhitespace, ' '));
}

void _appendExcerptText(dom.Node parent, StringBuffer text) {
  for (final node in parent.nodes) {
    if (node is dom.Text) {
      text.write(node.data);
    } else if (node is dom.Element) {
      final name = node.localName;
      if (name == 'br') {
        text.write(' ');
        continue;
      }
      if (name == 'img' && node.classes.contains('emoji')) {
        text.write(
          jsonText(node.attributes['alt']) ??
              jsonText(node.attributes['title']) ??
              '',
        );
        continue;
      }
      final separates = switch (name) {
        'p' ||
        'div' ||
        'li' ||
        'blockquote' ||
        'h1' ||
        'h2' ||
        'h3' ||
        'h4' ||
        'h5' ||
        'h6' ||
        'tr' ||
        'th' ||
        'td' => true,
        _ => false,
      };
      if (separates) text.write(' ');
      _appendExcerptText(node, text);
      if (separates) text.write(' ');
    }
  }
}

final _htmlWhitespace = RegExp(r'\s+');

DateTime? jsonDate(Object? value) => switch (value) {
  final String s when s.length <= maximumJsonDateCodeUnits => DateTime.tryParse(
    s,
  ),
  _ => null,
};

/// [plain] is preferred: it is the same text as unicode, which is what a
/// native Text widget wants. [fancy] is HTML — smart quotes as entities,
/// ampersands escaped — and only means anything once unescaped, which is why
/// it is the fallback, unless [localized] says it is a translation (see
/// [jsonLocalizedTitle]).
String jsonTitle(Object? plain, Object? fancy, {Object? localized}) {
  if (jsonLocalizedTitle(fancy, localized) case final translation?) {
    return translation;
  }
  if (plain case final String title when title.isNotEmpty) return title;
  return _fancyTitleText(fancy) ?? '';
}

/// With content localization on, core translates only `fancy_title` into the
/// viewer's language and flags it with `fancy_title_localized`; `title` stays
/// in the language the topic was written in. Upstream's topic-title-token
/// shows the translation then, but editing and every write's `original_title`
/// work on `title`, which is why a record that is written back keeps both.
String? jsonLocalizedTitle(Object? fancy, Object? localized) {
  if (localized != true) return null;
  final text = _fancyTitleText(fancy);
  return text == null || text.trim().isEmpty ? null : text;
}

String? _fancyTitleText(Object? fancy) {
  if (fancy case final String fancy when fancy.isNotEmpty) {
    final source = _boundedFancyTitleSource(fancy);
    if (!source.contains('<') &&
        !source.contains('&') &&
        !source.contains('\r') &&
        !source.contains('\u0000')) {
      return source;
    }
    return html.parseFragment(source).text ?? source;
  }
  return null;
}

String _boundedFancyTitleSource(String source) {
  if (source.length <= maximumFancyTitleSourceCodeUnits) return source;

  var end = maximumFancyTitleSourceCodeUnits;
  final before = source.codeUnitAt(end - 1);
  final after = source.codeUnitAt(end);
  if (_isHighSurrogate(before) && _isLowSurrogate(after)) end--;
  return source.substring(0, end);
}

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

/// Category colors are hex digits normally sent without a leading `#`, but
/// sites also produce `#`-prefixed and CSS three-digit shorthand forms. Every
/// serializer that carries a category color must resolve it through this
/// helper or [categoryColorValueOrNull]; anything unrecognized becomes
/// Discourse's default category gray.
int categoryColorValue(String color) =>
    categoryColorValueOrNull(color) ?? 0xFF888888;

/// [categoryColorValue]'s recognition, for a reader that draws its own
/// fallback rather than Discourse's gray when the color is unrecognized.
int? categoryColorValueOrNull(String color) {
  final hex = color.trim();
  final start = hex.startsWith('#') ? 1 : 0;
  final length = hex.length - start;
  if (length != 3 && length != 6) return null;
  var rgb = 0;
  for (var i = start; i < hex.length; i++) {
    final code = hex.codeUnitAt(i);
    final digit = switch (code) {
      >= 0x30 && <= 0x39 => code - 0x30,
      >= 0x41 && <= 0x46 => code - 0x41 + 10,
      >= 0x61 && <= 0x66 => code - 0x61 + 10,
      _ => -1,
    };
    if (digit < 0) return null;
    rgb = length == 3 ? (rgb << 8) | digit * 17 : (rgb << 4) | digit;
  }
  return 0xff000000 | rgb;
}

/// Root-relative templates already include the forum's subfolder, while
/// relative paths belong under that folder. CDN URLs bypass the forum URL.
String? resolveAvatarUrl(String? template, String siteUrl, {int size = 90}) {
  if (template == null || template.isEmpty) return null;
  final sized = template.replaceAll('{size}', '$size');
  if (sized.startsWith('//')) return 'https:$sized';
  if (_avatarHttpPrefix.hasMatch(sized) &&
      (Uri.tryParse(sized)?.hasScheme ?? true)) {
    return sized;
  }
  if (sized.startsWith('/')) {
    final site = Uri.tryParse(siteUrl);
    if (site != null &&
        (site.scheme == 'https' || site.scheme == 'http') &&
        site.host.isNotEmpty &&
        site.userInfo.isEmpty) {
      return '${site.origin}$sized';
    }
    // Keep malformed URLs non-throwing and credentials visible to the
    // transport policy; taking the origin would silently strip user info.
    return '$siteUrl$sized';
  }
  return '$siteUrl${siteUrl.endsWith('/') ? '' : '/'}$sized';
}

final _avatarHttpPrefix = RegExp(r'^http', caseSensitive: false);
