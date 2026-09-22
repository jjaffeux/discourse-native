import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:html/dom.dart' as dom;

const localDatesPluginId = PluginId('discourse-local-dates');

abstract interface class CookedTimeParser {
  DateTime? parseDescendant(dom.Element scope);
}

const localDatesCookedTimeParserService = PluginServiceKey<CookedTimeParser>(
  owner: localDatesPluginId,
  name: 'cooked-time-parser',
);
