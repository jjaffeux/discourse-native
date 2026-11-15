import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'topic_read_outbox.dart';

/// Application support is the app's own container on Apple platforms and an
/// owner-only directory on Linux, and the outbox restricts its file as well.
TopicReadOutbox createPlatformTopicReadOutbox() =>
    createTopicReadOutbox(() async {
      final support = await getApplicationSupportDirectory();
      return File('${support.path}/outbox/topic-reads-v1.json');
    });
