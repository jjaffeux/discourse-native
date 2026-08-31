import '../../plugin_api/plugin_manifest.dart';
import '../local_dates/local_dates_contract.dart';

const discourseGithubPluginId = PluginId('discourse-github');

const discourseGithubCookedTimeParserService =
    PluginServiceKey<CookedTimeParser>(
      owner: discourseGithubPluginId,
      name: 'cooked-time-parser',
    );
