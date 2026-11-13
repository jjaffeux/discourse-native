import '../models/discourse_model_codec.dart';
import 'account_activity_api.dart';
import 'bookmarks_write_api.dart';
import 'category_api_contracts.dart';
import 'composer_persistence_api.dart';
import 'discourse_search_contract.dart';
import 'do_not_disturb_api.dart';
import 'drafts_api.dart';
import 'dsa_notice_contracts.dart';
import 'plugin_transport.dart';
import 'post_mutations_api.dart';
import 'shell_lookup_api.dart';
import 'shell_site_api.dart';
import 'site_lookup_api.dart';
import 'tag_api_contracts.dart';
import 'topic_composer_queries_api.dart';
import 'topic_content_api.dart';
import 'topic_feeds_api.dart';
import 'topic_mutations_api.dart';
import 'topic_reads_api.dart';
import 'user_preferences_api.dart';
import 'user_summaries_api.dart';

export 'account_activity_api.dart';
export 'bookmarks_write_api.dart';
export 'category_api_contracts.dart';
export 'category_load_result.dart';
export 'composer_persistence_api.dart';
export 'discourse_search_contract.dart';
export 'do_not_disturb_api.dart';
export 'drafts_api.dart';
export 'dsa_notice_contracts.dart';
export 'failure_text.dart';
export 'post_mutations_api.dart';
export 'shell_lookup_api.dart';
export 'shell_site_api.dart';
export 'site_lookup_api.dart';
export 'site_lookup_failure.dart';
export 'tag_api_contracts.dart';
export 'topic_composer_queries_api.dart';
export 'topic_content_api.dart';
export 'topic_feeds_api.dart';
export 'topic_mutations_api.dart';
export 'topic_reads_api.dart';
export 'user_preferences_api.dart';
export 'user_summaries_api.dart';
export 'write_failure.dart';

/// Compile-time aggregate accepted only at the shell composition boundary.
///
/// Consumers below that boundary receive one workflow port. Adding an
/// unrelated public method to the production HTTP adapter therefore cannot
/// widen this contract or its test doubles.
abstract interface class ShellApiCapabilities
    implements
        DiscourseApiLifecycle,
        DiscourseApiModels,
        DsaNoticesApi,
        SiteLookupApi,
        PluginApiTransport,
        PluginJsonListTransport,
        ShellSiteApi,
        ShellSearchApi,
        ShellLookupApi,
        CategoryQueriesApi,
        CategoryMutationsApi,
        TagQueriesApi,
        TagNotificationsApi,
        TopicComposerQueriesApi,
        TopicContentApi,
        TopicMutationsApi,
        PostMutationsApi,
        ComposerPersistenceApi,
        AccountActivityApi,
        BookmarksWriteApi,
        DoNotDisturbApi,
        DraftsApi,
        UserSummariesApi,
        TopicFeedsApi,
        TopicReadsApi,
        UserPreferencesApi {}

abstract interface class DiscourseApiLifecycle {
  void close();
}

abstract interface class DiscourseApiModels {
  DiscourseModelCodec get models;
}

abstract interface class DiscourseApiConfiguration {
  Duration get timeout;
}
