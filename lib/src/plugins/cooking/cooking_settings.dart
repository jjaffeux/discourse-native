import 'package:discourse_native/discourse_plugin_sdk.dart';

const cookingSettingsKey = PluginDataKey<CookingSettings>(
  owner: 'cooking',
  name: 'site-settings',
);

final class CookingSettings {
  const CookingSettings({this.checklistEnabled = true});
  final bool checklistEnabled;

  @override
  bool operator ==(Object other) =>
      other is CookingSettings && other.checklistEnabled == checklistEnabled;

  @override
  int get hashCode => checklistEnabled.hashCode;
}

final class CookingSettingsCodec
    extends PluginDataPersistenceCodec<CookingSettings> {
  const CookingSettingsCodec();
  @override
  PluginDataKey<CookingSettings> get key => cookingSettingsKey;
  @override
  CookingSettings? decode(Object? value) {
    final json = jsonObjectFields(value);
    return json == null
        ? null
        : CookingSettings(checklistEnabled: json['checklistEnabled'] != false);
  }

  @override
  Object encode(CookingSettings value) => {
    'checklistEnabled': value.checklistEnabled,
  };
}
