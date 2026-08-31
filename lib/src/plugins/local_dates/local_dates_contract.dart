import 'package:html/dom.dart' as dom;

import '../../plugin_api/plugin_manifest.dart';

const localDatesPluginId = PluginId('discourse-local-dates');

abstract interface class CookedTimeParser {
  DateTime? parseDescendant(dom.Element scope);
}

const localDatesCookedTimeParserService = PluginServiceKey<CookedTimeParser>(
  owner: localDatesPluginId,
  name: 'cooked-time-parser',
);
