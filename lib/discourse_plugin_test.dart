/// Test-only host utilities for repository-owned Discourse plugins.
///
/// This is a deliberately separate entrypoint from [discourse_plugin_sdk.dart]:
/// application code should depend on the SDK contracts, while plugin tests can
/// opt into deterministic host and transport adapters without copying core's
/// own test doubles.
library;

export 'package:discourse_plugin_api/testing.dart'
    show
        PluginTransportRequest,
        PluginTransportResponder,
        RecordingPluginTransport;

export 'src/plugin_testing/plugin_host_harness.dart'
    show PluginHostHarness, PluginHostSite, PluginHostUser;
export 'src/plugin_testing/plugin_test_ports.dart'
    show PluginTestRequestHost, RecordingPluginLiveChannels;
