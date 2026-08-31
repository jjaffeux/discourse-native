/// Plugin compatibility boundary; plugins must not import the package's `src`.
library;

export 'src/data/app_release.dart';
export 'src/data/discourse_api_contracts.dart'
    hide
        CategoryLoadResult,
        CategoryQueriesApi,
        ComposerPersistenceApi,
        DiscourseApiConfiguration,
        DiscourseApiLifecycle,
        DiscourseApiModels,
        PostMutationsApi,
        ShellApiCapabilities,
        ShellLookupApi,
        ShellSearchApi,
        ShellSiteApi,
        SiteLookupApi,
        TagQueriesApi,
        TopicComposerQueriesApi,
        TopicContentApi,
        TopicMutationsApi,
        defaultDiscourseHashtagOrder,
        maximumDiscourseHashtagsPerRequest,
        maximumDiscourseSearchTermLength;
export 'src/data/plugin_transport.dart';
export 'src/data/serial_operation_queue.dart';
export 'src/diagnostics/diagnostic_event.dart';
export 'src/diagnostics/diagnostics_controller.dart';
export 'src/diagnostics/diagnostics_persistence.dart';
export 'src/diagnostics/topic_scroll_capture.dart';
export 'src/foundation/loopback_host.dart';
export 'src/foundation/private_file_permissions.dart';
export 'src/models/content_route.dart';
export 'src/models/json.dart';
export 'src/models/sidebar.dart';
export 'src/models/site_config.dart';
export 'src/plugin_api/background_retention.dart';
export 'src/plugin_api/core_plugin_host.dart';
export 'src/plugin_api/hashtag_kind.dart';
export 'src/plugin_api/live_channels.dart';
export 'src/plugin_api/plugin_data.dart';
export 'src/plugin_api/plugin_manifest.dart';
export 'src/plugin_api/plugin_runtime.dart';
export 'src/plugin_api/plugin_scope.dart';
export 'src/plugin_api/shell_extensions.dart';
export 'src/plugin_api/site_plugin_api.dart';
export 'src/plugins/chat/chat_contract.dart';
export 'src/shell/adaptive_dialog_action.dart';
export 'src/shell/avatar_image.dart';
export 'src/shell/content_reading_lane.dart'
    show
        ContentReadingLane,
        ContentReadingLaneBox,
        ContentReadingLaneBuilder,
        ContentReadingLaneGeometry;
export 'src/shell/diagnostics_text.dart';
export 'src/shell/select.dart';
export 'src/shell/site_url.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/d_icon.dart';
export 'src/theme/d_icons.dart';
