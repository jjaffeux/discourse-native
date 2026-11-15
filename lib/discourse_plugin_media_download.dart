/// The platform save and share implementation for a plugin that exports a
/// file. It is kept out of the contracts barrel because it loads native
/// plugins, which pure-Dart consumers of the contracts cannot.
library;

export 'src/foundation/native_media_download_environment.dart';
