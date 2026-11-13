import '../models/notification.dart';
import '../models/post_flag.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';

/// A category-list response plus whether its page-one site metadata also
/// arrived. A partial list is still useful for badges/navigation, but callers
/// should leave it retryable so lazy-loaded navigation choices can be filled
/// in.
final class CategoryLoadResult {
  factory CategoryLoadResult(
    Iterable<TopicCategory> categories, {
    bool complete = true,
    Iterable<int>? rootCategoryIds,
    bool canCreateTopic = false,
    SitePostActionCatalog? postActionCatalog,
    TopicComposerCapabilities? composerCapabilities,
    Iterable<NotificationWireType> notificationTypes = const [],
    Iterable<SidebarTag>? siteTopTags,
    Iterable<SidebarTag>? anonymousDefaultTags,
    bool? anonymousSearchAllowed,
  }) {
    final immutableCategories = List<TopicCategory>.unmodifiable(categories);
    return CategoryLoadResult._(
      immutableCategories,
      List<int>.unmodifiable(
        rootCategoryIds ??
            immutableCategories
                .where((category) => category.parentCategoryId == null)
                .map((category) => category.id),
      ),
      complete,
      canCreateTopic,
      postActionCatalog,
      composerCapabilities,
      List<NotificationWireType>.unmodifiable(notificationTypes),
      siteTopTags == null ? null : List<SidebarTag>.unmodifiable(siteTopTags),
      anonymousDefaultTags == null
          ? null
          : List<SidebarTag>.unmodifiable(anonymousDefaultTags),
      anonymousSearchAllowed,
    );
  }

  CategoryLoadResult._(
    this.categories,
    this.rootCategoryIds,
    this.complete,
    this.canCreateTopic,
    this.postActionCatalog,
    this.composerCapabilities,
    this.notificationTypes,
    this.siteTopTags,
    this.anonymousDefaultTags,
    this.anonymousSearchAllowed,
  );

  final List<TopicCategory> categories;

  /// Category ids represented as roots by this page's category-list response.
  ///
  /// Nested categories and the page-one `site.json` supplement remain in
  /// [categories] for identity lookup, but must not become category cards.
  final List<int> rootCategoryIds;
  final bool complete;
  final bool canCreateTopic;

  /// Navigation metadata carried by the page-one `/site.json` supplement.
  ///
  /// Null means that optional request failed or was not made (later pages),
  /// while an empty list is the server-confirmed absence of fallback tags.
  final List<SidebarTag>? siteTopTags;
  final List<SidebarTag>? anonymousDefaultTags;

  /// Authenticated post-action metadata from the page-one `/site.json` read.
  /// Null means that metadata was not requested or did not arrive.
  final SitePostActionCatalog? postActionCatalog;

  /// What the signed-in user may do in the composer, from the authenticated
  /// page-one `/site.json` read. Null means that read was not made or did not
  /// arrive; an anonymous document would understate the account's permissions.
  final TopicComposerCapabilities? composerCapabilities;

  /// The site's notification catalog from the authenticated page-one
  /// `/site.json` read. Empty when that read was not made, failed, or named no
  /// types, which settles nothing about the catalog.
  final List<NotificationWireType> notificationTypes;

  /// Core's `allow_anonymous_search`, as the anonymous page-one `/site.json`
  /// read reports it through `can_search`. Null means that read was
  /// authenticated, failed, or was not made.
  final bool? anonymousSearchAllowed;
}
