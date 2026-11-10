import 'data/bookmark_reminder_store.dart' as p0;
import 'data/emoji_picker_store.dart' as p1;
import 'data/forum_settings_store.dart' as p2;
import 'data/recent_search_store.dart' as p3;
import 'data/retired_user_directory_column_widths.dart' as p4;
import 'data/sidebar_section_store.dart' as p5;
import 'data/site_preference_keys.dart';
import 'data/topic_recommendations_tab_store.dart' as p6;
import 'data/topic_sidebar_store.dart' as p7;
import 'shell/header_preferences_controller.dart' as p8;
import 'shell/mobile_place_order_controller.dart' as p9;

const declaredSitePreferenceKeys = <SitePreferenceKey>[
  p0.BookmarkReminderStore.keys,
  p1.SharedPreferencesEmojiPickerPersistence.keys,
  p2.ForumSettingsStore.themeModeKeys,
  p2.ForumSettingsStore.themesKeys,
  p3.RecentSearchStore.keys,
  p4.RetiredUserDirectoryColumnWidths.keys,
  p5.SharedPreferencesSidebarSectionPersistence.keys,
  p6.SharedPreferencesTopicRecommendationsTabPersistence.keys,
  p7.SharedPreferencesTopicSidebarPersistence.keys,
  p8.HeaderPreferencesController.keys,
  p9.MobilePlaceOrderController.keys,
];
