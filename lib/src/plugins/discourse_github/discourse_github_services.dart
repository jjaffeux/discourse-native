import '../../plugin_api/plugin_manifest.dart';
import '../local_dates/local_dates_contract.dart';

const discourseGithubPluginId = PluginId('discourse-github');

/// The optional Local Dates parser republished under GitHub's own namespace.
///
/// UI code therefore never reaches into another plugin's service graph.
const discourseGithubCookedTimeParserService =
    PluginServiceKey<CookedTimeParser>(
      owner: discourseGithubPluginId,
      name: 'cooked-time-parser',
    );
