import 'package:xml/xml.dart';

import '../models/json.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_icon_catalog.dart';
import '../theme/d_icon.dart';
import 'discourse_transport.dart';

/// Supplements bundled icons with the forum's complete SVG catalogue.
final class SidebarIconLoader {
  SidebarIconLoader(this._transport, this._bundled);

  final DiscourseTransport _transport;
  final IconNameDecoder _bundled;
  final _cache = <Uri, (DateTime, String)>{};
  int _cachedCharacters = 0;
  static const _maximumCachedCharacters = 2 * 1024 * 1024;

  Future<List<SidebarSection>> load(Object? values, String siteUrl) async {
    final json = jsonObjects(values).toList();
    final icons = _SidebarIcons(_bundled);

    List<SidebarSection> decode() => List.unmodifiable([
      for (var index = 0; index < json.length; index++)
        ?SidebarSection.customFromJson(json[index], index: index, icons: icons),
    ]);

    // Let the model select valid, visible links before requesting any artwork.
    final sections = decode();
    final missing = icons.missing.toList();
    if (missing.isEmpty) return sections;

    // Leave headroom in the shared request queue even for many custom sections.
    for (var start = 0; start < missing.length; start += 4) {
      await Future.wait(
        missing.skip(start).take(4).map((name) async {
          final icon = await _loadIcon(siteUrl, name);
          if (icon != null) icons.loaded[name] = icon;
        }),
      );
    }
    return decode();
  }

  Future<DIconData?> _loadIcon(String siteUrl, String name) async {
    try {
      final root = await _symbol(siteUrl, name);
      if (root == null) return null;
      final symbols = <String, XmlElement>{name: root};
      final definitions = XmlElement.tag('defs');

      // Some Discourse icons use sibling symbols (for example a plus badge).
      // Include those definitions so the standalone SVG renders like the sprite.
      Future<bool> includeReferences(
        XmlElement element,
        Set<String> ancestors,
      ) async {
        final localIds = {
          for (final node in element.descendantElements)
            ?node.getAttribute('id'),
        };
        for (final use in element.findAllElements('use')) {
          final href =
              use.getAttribute('href') ??
              use.getAttribute(
                'href',
                namespaceUri: 'http://www.w3.org/1999/xlink',
              );
          if (href == null || !href.startsWith('#')) continue;
          final reference = href.substring(1);
          if (localIds.contains(reference)) continue;
          if (ancestors.contains(reference)) return false;
          if (symbols.containsKey(reference)) continue;
          if (symbols.length >= 32) return false;
          final dependency = await _symbol(siteUrl, reference);
          if (dependency == null) return false;
          final symbol = XmlElement.tag(
            'symbol',
            attributes: dependency.attributes.map(
              (attribute) => attribute.copy(),
            ),
            children: dependency.children.map((child) => child.copy()),
          )..setAttribute('id', reference);
          symbols[reference] = symbol;
          definitions.children.add(symbol);
          if (!await includeReferences(symbol, {...ancestors, reference})) {
            return false;
          }
        }
        return true;
      }

      if (!await includeReferences(root, {name})) return null;
      if (definitions.children.isNotEmpty) root.children.insert(0, definitions);
      return DIconData(name, root.toXmlString(), preserveColors: true);
    } on Exception {
      // Artwork is optional; an offline/missing icon must not hide navigation.
      return null;
    }
  }

  Future<XmlElement?> _symbol(String siteUrl, String name) async {
    final site = Uri.parse(siteUrl);
    final url = site.replace(
      pathSegments: [
        ...site.pathSegments.where((part) => part.isNotEmpty),
        'svg-sprite',
        site.host,
        'icon',
        '$name.svg',
      ],
      query: null,
      fragment: null,
    );
    final cached = _cache[url];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(days: 1)) {
      return XmlDocument.parse(cached.$2).rootElement;
    }
    // This endpoint is public, including on login-required forums.
    final response = await _transport.get(
      url,
      siteUrl: siteUrl,
      accept: 'image/svg+xml',
    );
    final source = response.body;
    final root = XmlDocument.parse(source).childElements.singleOrNull;
    if (root == null ||
        root.name.local != 'svg' ||
        root.childElements.isEmpty) {
      return null;
    }
    if (source.length <= _maximumCachedCharacters) {
      _cachedCharacters -= _cache.remove(url)?.$2.length ?? 0;
      while (_cache.length >= 256 ||
          _cachedCharacters + source.length > _maximumCachedCharacters) {
        _cachedCharacters -= _cache.remove(_cache.keys.first)!.$2.length;
      }
      _cache[url] = (DateTime.now(), source);
      _cachedCharacters += source.length;
    }
    return root;
  }
}

final class _SidebarIcons implements IconNameDecoder {
  _SidebarIcons(this.bundled);

  static const _missing = DIconData('', '');
  final IconNameDecoder bundled;
  final missing = <String>{};
  final loaded = <String, DIconData>{};

  @override
  DIconData iconNamed(String? name, {required DIconData fallback}) {
    if (name == null || name.isEmpty) return fallback;
    final icon = bundled.iconNamed(name, fallback: _missing);
    if (!identical(icon, _missing)) return icon;
    missing.add(name);
    return loaded[name] ?? fallback;
  }
}
