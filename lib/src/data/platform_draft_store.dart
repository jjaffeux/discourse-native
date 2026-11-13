import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'draft_store.dart';
import 'platform_private_storage.dart';

DraftStore createPlatformDraftStore() =>
    DraftStore(persistence: _platformDraftPersistence);

final DraftPersistence _platformDraftPersistence = _createDraftPersistence();

DraftPersistence _createDraftPersistence() {
  if (Platform.isLinux) {
    return PrivateDraftPersistence(storage: platformEnumerablePrivateStorage);
  }
  if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
    return ApplicationSupportDraftPersistence(
      file: () async {
        final support = await getApplicationSupportDirectory();
        return File(
          '${support.path}/${ApplicationSupportDraftPersistence.directoryName}/'
          '${ApplicationSupportDraftPersistence.fileName}',
        );
      },
      legacyStorage: platformLegacyAppleStorage,
    );
  }
  throw UnsupportedError('Draft persistence is unavailable on this platform');
}
