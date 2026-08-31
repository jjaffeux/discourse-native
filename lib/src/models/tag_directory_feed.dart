import 'package:flutter/foundation.dart';

import 'sidebar_tag.dart';

@immutable
class TagDirectoryFeed {
  const TagDirectoryFeed({
    this.tags = const [],
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  final List<SidebarTag> tags;
  final bool loading;
  final bool loaded;
  final String? error;

  bool get isEmpty => loaded && error == null && tags.isEmpty;

  TagDirectoryFeed refreshing() =>
      TagDirectoryFeed(tags: tags, loading: true, loaded: loaded);

  TagDirectoryFeed withTags(Iterable<SidebarTag> values) => TagDirectoryFeed(
    tags: List<SidebarTag>.unmodifiable(values),
    loaded: true,
  );

  TagDirectoryFeed withError(String message) =>
      TagDirectoryFeed(tags: tags, loaded: loaded, error: message);
}
