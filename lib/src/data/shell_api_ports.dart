import '../plugin_api/discourse_model_codec.dart';
import 'discourse_api_contracts.dart';
import 'plugin_transport.dart';

/// The shell's explicit composition boundary over the production HTTP client.
///
/// Controllers receive the narrow workflow port they consume. Keeping the
/// assembly here lets production use one HTTP adapter without making tests
/// implement every public method on that concrete class.
final class ShellApiPorts {
  const ShellApiPorts({
    required this.lifecycle,
    required this.models,
    required this.pluginTransport,
    required this.siteLookup,
    required this.site,
    required this.search,
    required this.lookups,
    required this.categories,
    required this.topicComposerQueries,
    required this.topicContent,
    required this.topicMutations,
    required this.postMutations,
    required this.composerPersistence,
    required this.accountActivity,
    required this.bookmarks,
    required this.doNotDisturb,
    required this.drafts,
    required this.userSummaries,
    required this.topicFeeds,
    required this.topicReads,
    required this.userPreferences,
  });

  factory ShellApiPorts.fromCapabilities(ShellApiCapabilities capabilities) {
    return ShellApiPorts(
      lifecycle: capabilities,
      models: capabilities.models,
      pluginTransport: capabilities,
      siteLookup: capabilities,
      site: capabilities,
      search: capabilities,
      lookups: capabilities,
      categories: capabilities,
      topicComposerQueries: capabilities,
      topicContent: capabilities,
      topicMutations: capabilities,
      postMutations: capabilities,
      composerPersistence: capabilities,
      accountActivity: capabilities,
      bookmarks: capabilities,
      doNotDisturb: capabilities,
      drafts: capabilities,
      userSummaries: capabilities,
      topicFeeds: capabilities,
      topicReads: capabilities,
      userPreferences: capabilities,
    );
  }

  final DiscourseApiLifecycle lifecycle;
  final DiscourseModelCodec models;
  final PluginApiTransport pluginTransport;
  final SiteLookupApi siteLookup;
  final ShellSiteApi site;
  final ShellSearchApi search;
  final ShellLookupApi lookups;
  final CategoryQueriesApi categories;
  final TopicComposerQueriesApi topicComposerQueries;
  final TopicContentApi topicContent;
  final TopicMutationsApi topicMutations;
  final PostMutationsApi postMutations;
  final ComposerPersistenceApi composerPersistence;
  final AccountActivityApi accountActivity;
  final BookmarksWriteApi bookmarks;
  final DoNotDisturbApi doNotDisturb;
  final DraftsApi drafts;
  final UserSummariesApi userSummaries;
  final TopicFeedsApi topicFeeds;
  final TopicReadsApi topicReads;
  final UserPreferencesApi userPreferences;

  void close() => lifecycle.close();
}
