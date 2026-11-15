import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'content_snapshot_store.dart';

/// Application support rather than the cache directory: the snapshot holds
/// private messages, and the cache directory is the one the OS and cleaning
/// tools treat as public scratch space. `PrivateFileDocument` keeps both the
/// directory and its files owner-only.
ContentSnapshotStore createPlatformContentSnapshotStore() =>
    ContentSnapshotStore(
      directory: () async => Directory(
        '${(await getApplicationSupportDirectory()).path}/'
        '${ContentSnapshotStore.directoryName}',
      ),
    );
