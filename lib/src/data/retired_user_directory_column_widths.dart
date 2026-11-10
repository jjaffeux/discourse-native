import 'site_preference_keys.dart';

/// The column widths the Users directory kept per forum while its columns
/// could be resized. Nothing reads or writes them any more; the key stays
/// declared so forgetting a forum still removes what was stored for it.
abstract final class RetiredUserDirectoryColumnWidths {
  static const keys = SitePreferenceKey(
    'discourse_native.user_directory_column_widths',
    retirement: SitePreferenceRetirement.storedOnly,
  );
}
