import 'package:discourse_native/discourse_plugin_sdk.dart';
import '../local_dates/local_dates_contract.dart';

const discourseGithubPluginId = PluginId('discourse-github');

const discourseGithubCookedTimeParserService =
    PluginServiceKey<CookedTimeParser>(
      owner: discourseGithubPluginId,
      name: 'cooked-time-parser',
    );
