import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/chat_message_blocks_test.dart' as blocks;
import '../test/chat_transcript_test.dart' as transcripts;
import '../test/composer_upload_attachment_test.dart' as attachments;
import '../test/dsa_notice_presentation_test.dart' as reporting;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const workspace = String.fromEnvironment('NATIVE_TEST_WORKSPACE');
  if (workspace.isNotEmpty) Directory.current = workspace;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('Chat action blocks', blocks.main);
  group('Chat transcripts', transcripts.main);
  group('Composer media previews', attachments.main);
  group('Illegal-content reporting', reporting.main);
}
