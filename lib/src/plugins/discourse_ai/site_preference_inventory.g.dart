import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'ai_proofreading_preferences.dart' as p0;

const declaredSitePreferenceKeys = <SitePreferenceKey>[
  p0.SharedPreferencesAiProofreadingPreferencePersistence.keys,
  p0.SharedPreferencesAiProofreadingPreferencePersistence.siteWideKeys,
];
